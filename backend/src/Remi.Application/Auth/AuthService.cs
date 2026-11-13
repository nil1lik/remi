using System.Security.Cryptography;
using System.Text;
using Remi.Application.Abstractions;
using Remi.Domain.Accounts;
using Remi.Domain.Common;
using Remi.Domain.Sessions;

namespace Remi.Application.Auth;

/// <summary>Giriş, oturum yenileme ve çıkış.</summary>
public sealed class AuthService(
    IIdentityTokenVerifier verifier,
    IAccountRepository accounts,
    IRefreshTokenRepository refreshTokens,
    IAccessTokenIssuer accessTokens,
    IUnitOfWork uow,
    SessionSettings settings,
    TimeProvider clock)
{
    private const int MaxRefreshTokenLength = 128;

    public async Task<Result<AuthResult>> SignInAsync(string provider, SignInCommand command, CancellationToken ct)
    {
        var parsed = EnumText.Parse<IdentityProvider>(provider);
        if (!parsed.IsSuccess) return Error.NotFound("unknown_provider");
        if (string.IsNullOrWhiteSpace(command.IdToken)) return Error.Invalid("idToken", "required");

        var identity = await verifier.VerifyAsync(parsed.Value, command.IdToken, command.Nonce, ct);
        if (identity is null) return Error.Unauthorized("invalid_identity_token");

        var now = clock.GetUtcNow();
        var account = await FindOrRegisterAsync(identity, command, now, ct);
        var tokens = await OpenSessionAsync(account.Id, Guid.NewGuid(), previous: null, now, ct);
        return new AuthResult(tokens.AccessToken, tokens.ExpiresIn, tokens.RefreshToken, ProfileDto.From(account));
    }

    /// <summary>
    /// Yenileme anahtarını yenisiyle değiştirir. Kullanılmış bir anahtar tekrar gelirse (ya da iki istek aynı
    /// anahtarla yarışırsa) anahtar çalınmış sayılır ve oturumun tüm anahtarları iptal edilir.
    /// </summary>
    public async Task<Result<TokenResult>> RefreshAsync(string? rawToken, CancellationToken ct)
    {
        var invalid = Error.Unauthorized("invalid_refresh_token");
        var stored = await FindAsync(rawToken, ct);
        if (stored is null) return invalid;

        var now = clock.GetUtcNow();
        if (stored.WasUsedOrRevoked)
        {
            await RevokeFamilyAsync(stored.FamilyId, now, ct);
            return invalid;
        }
        if (stored.IsExpired(now)) return invalid;

        try
        {
            return await OpenSessionAsync(stored.AccountId, stored.FamilyId, stored, now, ct);
        }
        catch (ConcurrencyConflictException)
        {
            uow.Reset();
            await RevokeFamilyAsync(stored.FamilyId, now, ct);
            return invalid;
        }
    }

    /// <summary>Çıkış: anahtarın oturumunu kapatır. Bilinmeyen anahtar sessizce yok sayılır.</summary>
    public async Task LogoutAsync(string? rawToken, CancellationToken ct)
    {
        var stored = await FindAsync(rawToken, ct);
        if (stored is not null) await RevokeFamilyAsync(stored.FamilyId, clock.GetUtcNow(), ct);
    }

    private async Task<Account> FindOrRegisterAsync(ExternalIdentity identity, SignInCommand command, DateTimeOffset now, CancellationToken ct)
    {
        var existing = await accounts.FindByIdentityAsync(identity, ct);
        if (existing is not null)
        {
            existing.RecordSignIn(identity, now);
            await uow.SaveChangesAsync(ct);
            return existing;
        }

        // İlk giriş: hesap açılır. Ad ve dil isteğe bağlı; geçersizse varsayılan kullanılır.
        var name = DisplayName.Create(command.DisplayName);
        var locale = EnumText.Parse<Locale>(command.Locale);
        var account = Account.Register(identity,
            name.IsSuccess ? name.Value : DisplayName.Empty,
            locale.IsSuccess ? locale.Value : Locale.Tr, now);
        accounts.Add(account);
        try
        {
            await uow.SaveChangesAsync(ct);
            return account;
        }
        catch (DuplicateKeyException)
        {
            // Aynı hesapla eşzamanlı iki ilk giriş: diğeri kazandı, onun hesabı kullanılır.
            uow.Reset();
            return await accounts.FindByIdentityAsync(identity, ct)
                ?? throw new InvalidOperationException("Hesap oluşturulamadı.");
        }
    }

    private async Task<TokenResult> OpenSessionAsync(AccountId account, Guid familyId, RefreshToken? previous, DateTimeOffset now, CancellationToken ct)
    {
        var raw = NewRawToken();
        var lifetime = settings.RefreshTokenLifetime;
        var token = previous is null
            ? RefreshToken.Issue(account, familyId, Hash(raw), now, lifetime)
            : previous.Rotate(Hash(raw), now, lifetime);
        refreshTokens.Add(token);
        await uow.SaveChangesAsync(ct);

        var access = accessTokens.Issue(account, now);
        return new TokenResult(access.Value, access.ExpiresInSeconds, raw);
    }

    private async Task<RefreshToken?> FindAsync(string? raw, CancellationToken ct) =>
        string.IsNullOrEmpty(raw) || raw.Length > MaxRefreshTokenLength ? null : await refreshTokens.FindByHashAsync(Hash(raw), ct);

    private async Task RevokeFamilyAsync(Guid familyId, DateTimeOffset now, CancellationToken ct)
    {
        foreach (var token in await refreshTokens.ListActiveInFamilyAsync(familyId, ct)) token.Revoke(now);
        await uow.SaveChangesAsync(ct);
    }

    /// <summary>256 bit rastgele, URL'de güvenli metin.</summary>
    private static string NewRawToken() =>
        Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static string Hash(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
