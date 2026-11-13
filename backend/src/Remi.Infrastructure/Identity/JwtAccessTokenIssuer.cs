using System.Security.Claims;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Remi.Application.Abstractions;
using Remi.Domain.Accounts;

namespace Remi.Infrastructure.Identity;

/// <summary>15 dakikalık, HMAC-SHA256 imzalı erişim anahtarı. İçinde yalnız hesap kimliği vardır (kişisel bilgi yok).</summary>
internal sealed class JwtAccessTokenIssuer(IOptions<AuthOptions> options) : IAccessTokenIssuer
{
    private readonly AuthOptions _options = options.Value;
    private static readonly JsonWebTokenHandler Handler = new();

    public AccessToken Issue(AccountId account, DateTimeOffset now)
    {
        var lifetime = TimeSpan.FromMinutes(_options.AccessTokenMinutes);
        var token = Handler.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = _options.Issuer,
            Audience = _options.Audience,
            Subject = new ClaimsIdentity([
                new Claim(JwtRegisteredClaimNames.Sub, account.Value.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            ]),
            IssuedAt = now.UtcDateTime,
            NotBefore = now.UtcDateTime,
            Expires = now.Add(lifetime).UtcDateTime,
            SigningCredentials = new SigningCredentials(SigningKey(_options), SecurityAlgorithms.HmacSha256),
        });
        return new AccessToken(token, (int)lifetime.TotalSeconds);
    }

    public static SymmetricSecurityKey SigningKey(AuthOptions options) => new(options.SigningKeyBytes());
}
