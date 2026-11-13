using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using Remi.Application.Abstractions;
using Remi.Application.Auth;
using Remi.Domain.Accounts;

namespace Remi.Infrastructure.Identity;

/// <summary>
/// Apple/Google kimlik belgesini sağlayıcının yayımladığı anahtarlarla (JWKS) doğrular: imza (yalnız RS256),
/// issuer, audience (bizim uygulamamız), süre ve nonce. Anahtarlar önbelleğe alınır; tanınmayan anahtarla
/// gelen belgede önbellek bir kez yenilenir.
/// </summary>
internal sealed class OidcIdentityTokenVerifier : IIdentityTokenVerifier
{
    private const int MaxTokenLength = 8 * 1024;
    private readonly AuthOptions _options;
    private readonly ILogger<OidcIdentityTokenVerifier> _logger;
    private readonly Dictionary<IdentityProvider, ConfigurationManager<OpenIdConnectConfiguration>> _configs;
    private readonly JsonWebTokenHandler _handler = new() { MapInboundClaims = false };

    public OidcIdentityTokenVerifier(IOptions<AuthOptions> options, ILogger<OidcIdentityTokenVerifier> logger)
    {
        _options = options.Value;
        _logger = logger;
        _configs = new()
        {
            [IdentityProvider.Apple] = Manager(_options.Apple.Authority),
            [IdentityProvider.Google] = Manager(_options.Google.Authority),
        };
    }

    private static ConfigurationManager<OpenIdConnectConfiguration> Manager(string authority) =>
        new($"{authority.TrimEnd('/')}/.well-known/openid-configuration",
            new OpenIdConnectConfigurationRetriever(),
            new HttpDocumentRetriever { RequireHttps = true });

    public async Task<ExternalIdentity?> VerifyAsync(IdentityProvider provider, string idToken, string? nonce, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(idToken) || idToken.Length > MaxTokenLength) return null;

        var settings = provider == IdentityProvider.Apple ? _options.Apple : _options.Google;
        if (settings.ClientIds.Length == 0)
        {
            _logger.LogWarning("{Provider} girişi yapılandırılmamış (ClientIds boş).", provider);
            return null;
        }

        // Apple'da nonce zorunlu: belgenin bu giriş isteği için üretildiğini kanıtlar (tekrar oynatmaya karşı).
        if (provider == IdentityProvider.Apple && string.IsNullOrEmpty(nonce)) return null;

        var manager = _configs[provider];
        var result = await ValidateAsync(manager, settings, idToken, ct);
        if (result is { IsValid: false, Exception: SecurityTokenSignatureKeyNotFoundException })
        {
            manager.RequestRefresh(); // Sağlayıcı anahtarlarını döndürmüş olabilir.
            result = await ValidateAsync(manager, settings, idToken, ct);
        }

        if (!result.IsValid || result.SecurityToken is not JsonWebToken jwt)
        {
            // Belgenin kendisi loglanmaz; yalnız reddetme nedeni.
            _logger.LogInformation("{Provider} kimlik belgesi reddedildi: {Reason}", provider, result.Exception?.GetType().Name);
            return null;
        }

        if (!string.IsNullOrEmpty(nonce))
        {
            // Apple: istemci isteğe SHA-256(nonce) koyar, belgede o özet döner. Google: nonce olduğu gibi döner.
            var expected = provider == IdentityProvider.Apple ? AuthService.Hash(nonce) : nonce;
            if (!jwt.TryGetPayloadValue<string>("nonce", out var actual) || !FixedEquals(expected, actual)) return null;
        }

        var identity = ExternalIdentity.Create(provider, jwt.Subject);
        return identity.IsSuccess ? identity.Value : null;
    }

    private async Task<TokenValidationResult> ValidateAsync(
        ConfigurationManager<OpenIdConnectConfiguration> manager, ProviderOptions settings, string idToken, CancellationToken ct)
    {
        OpenIdConnectConfiguration config;
        try
        {
            config = await manager.GetConfigurationAsync(ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogError(ex, "Kimlik sağlayıcısının anahtarları alınamadı.");
            return new TokenValidationResult { IsValid = false, Exception = ex };
        }

        return await _handler.ValidateTokenAsync(idToken, new TokenValidationParameters
        {
            ValidIssuers = settings.Issuers,
            ValidAudiences = settings.ClientIds,
            IssuerSigningKeys = config.SigningKeys,
            ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
            RequireSignedTokens = true,
            RequireExpirationTime = true,
            ValidateIssuerSigningKey = true,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1),
        });
    }

    private static bool FixedEquals(string a, string b) =>
        CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));
}
