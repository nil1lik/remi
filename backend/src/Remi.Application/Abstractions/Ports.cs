using Remi.Domain.Accounts;
using Remi.Domain.Groups;
using Remi.Domain.Sessions;

namespace Remi.Application.Abstractions;

// Uygulama katmanının dış dünyadan beklediği yetenekler. Gerçekleri Infrastructure'dadır.

public interface IAccountRepository
{
    Task<Account?> FindAsync(AccountId id, CancellationToken ct);
    Task<Account?> FindByIdentityAsync(ExternalIdentity identity, CancellationToken ct);
    Task<bool> ExistsAsync(AccountId id, CancellationToken ct);
    void Add(Account account);
    /// <summary>Hesabı ve ona bağlı her şeyi (gruplar, oturumlar, girişler) kalıcı olarak siler.</summary>
    Task DeleteAsync(AccountId id, CancellationToken ct);
}

public interface IGroupRepository
{
    /// <summary>Sahibine bakmadan bulur; sahiplik kontrolünü aggregate yapar.</summary>
    Task<Group?> FindAsync(GroupId id, CancellationToken ct);
    Task<bool> ExistsAsync(GroupId id, CancellationToken ct);
    Task<int> CountActiveAsync(AccountId owner, CancellationToken ct);
    Task<IReadOnlyList<Group>> ListActiveAsync(AccountId owner, CancellationToken ct);
    /// <summary>Verilen revizyondan sonra değişen gruplar (silinmiş izler dahil), revizyon sırasıyla.</summary>
    Task<IReadOnlyList<Group>> ListChangedSinceAsync(AccountId owner, long revision, CancellationToken ct);
    void Add(Group group);
}

public interface IRefreshTokenRepository
{
    Task<RefreshToken?> FindByHashAsync(string tokenHash, CancellationToken ct);
    Task<IReadOnlyList<RefreshToken>> ListActiveInFamilyAsync(Guid familyId, CancellationToken ct);
    void Add(RefreshToken token);
}

public interface IUnitOfWork
{
    /// <exception cref="ConcurrencyConflictException">Kayıt bu arada başka bir istekle değişti.</exception>
    /// <exception cref="DuplicateKeyException">Benzersiz olması gereken bir değer zaten var.</exception>
    Task SaveChangesAsync(CancellationToken ct);
    /// <summary>Bekleyen değişiklikleri unutur (yeniden denemeden önce).</summary>
    void Reset();
}

public sealed class ConcurrencyConflictException(Exception inner) : Exception("Eşzamanlı değişiklik.", inner);
public sealed class DuplicateKeyException(Exception inner) : Exception("Benzersizlik ihlali.", inner);

/// <summary>Apple/Google kimlik belgesini (id_token) doğrular.</summary>
public interface IIdentityTokenVerifier
{
    /// <returns>Belge geçerliyse kalıcı kimlik; değilse null.</returns>
    Task<ExternalIdentity?> VerifyAsync(IdentityProvider provider, string idToken, string? nonce, CancellationToken ct);
}

public sealed record AccessToken(string Value, int ExpiresInSeconds);

/// <summary>Kısa ömürlü erişim anahtarı (JWT) üretir.</summary>
public interface IAccessTokenIssuer
{
    AccessToken Issue(AccountId account, DateTimeOffset now);
}

public sealed record SessionSettings(TimeSpan RefreshTokenLifetime);
