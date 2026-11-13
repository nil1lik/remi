using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace Remi.Api.Tests;

public sealed class AuthTests : IClassFixture<RemiFactory>
{
    private readonly RemiFactory _factory;
    public AuthTests(RemiFactory factory) => _factory = factory;

    [Fact]
    public async Task Health_is_public_and_sends_security_headers()
    {
        var response = await _factory.CreateClient().GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("nosniff", response.Headers.GetValues("X-Content-Type-Options").Single());
        Assert.Equal("DENY", response.Headers.GetValues("X-Frame-Options").Single());
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
    }

    [Theory]
    [InlineData("/v1/me")]
    [InlineData("/v1/groups")]
    [InlineData("/v1/sync")]
    public async Task Protected_endpoints_require_a_token(string path)
    {
        var response = await _factory.CreateClient().GetAsync(path);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task First_sign_in_creates_account_and_second_reuses_it()
    {
        var first = await _factory.SignInAsync("same-person");
        var second = await _factory.SignInAsync("same-person");
        Assert.Equal(first.Auth.Profile.Id, second.Auth.Profile.Id);
        Assert.Equal("Hocam", first.Auth.Profile.DisplayName);
        Assert.Equal(900, first.Auth.ExpiresIn);
    }

    [Fact]
    public async Task Same_subject_from_other_provider_is_a_different_account()
    {
        var apple = await _factory.SignInAsync("shared-sub", "apple");
        var google = await _factory.SignInAsync("shared-sub", "google");
        Assert.NotEqual(apple.Auth.Profile.Id, google.Auth.Profile.Id);
    }

    [Fact]
    public async Task Invalid_identity_token_is_rejected()
    {
        var response = await _factory.CreateClient().PostAsJsonAsync("/v1/auth/apple", new { idToken = "forged", nonce = "x" });
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Unknown_provider_is_not_found()
    {
        var response = await _factory.CreateClient().PostAsJsonAsync("/v1/auth/facebook", new { idToken = FakeValidator.Token("x") });
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Refresh_rotates_and_reuse_revokes_the_whole_session()
    {
        var session = await _factory.SignInAsync("rotator");
        var client = _factory.CreateClient();

        var rotated = await client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = session.Auth.RefreshToken });
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        var next = await rotated.Content.ReadFromJsonAsync<AuthBody>();
        Assert.NotEqual(session.Auth.RefreshToken, next!.RefreshToken);

        // Eski anahtar tekrar kullanılırsa (çalınmış sayılır) reddedilir...
        var reuse = await client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = session.Auth.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, reuse.StatusCode);

        // ...ve aynı oturumun yeni anahtarı da artık çalışmaz.
        var afterReuse = await client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = next.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, afterReuse.StatusCode);
    }

    [Fact]
    public async Task Logout_revokes_refresh_token()
    {
        var session = await _factory.SignInAsync("leaver");
        var client = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.NoContent,
            (await client.PostAsJsonAsync("/v1/auth/logout", new { refreshToken = session.Auth.RefreshToken })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await client.PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = session.Auth.RefreshToken })).StatusCode);
    }

    [Fact]
    public async Task Garbage_refresh_token_is_rejected()
    {
        var response = await _factory.CreateClient().PostAsJsonAsync("/v1/auth/refresh", new { refreshToken = new string('a', 43) });
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Access_token_signed_with_another_key_is_rejected()
    {
        var session = await _factory.SignInAsync("victim");
        var forged = MakeToken(session.Auth.Profile.Id, RandomNumberGenerator.GetBytes(32));
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", forged);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/me")).StatusCode);
    }

    [Fact]
    public async Task Tampered_or_unsigned_access_token_is_rejected()
    {
        var session = await _factory.SignInAsync("tamper");
        var parts = session.Auth.AccessToken.Split('.');
        var client = _factory.CreateClient();

        // İmzasız ("alg": "none") belge.
        var header = Base64UrlEncoder.Encode("""{"alg":"none","typ":"JWT"}""");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", $"{header}.{parts[1]}.");
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/me")).StatusCode);

        // İçeriği değiştirilmiş belge (başka kullanıcı kimliği), imza aynı.
        var payload = Base64UrlEncoder.Encode($$"""{"sub":"{{Guid.NewGuid()}}","iss":"remi-api","aud":"remi-app","exp":{{DateTimeOffset.UtcNow.AddMinutes(5).ToUnixTimeSeconds()}}}""");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", $"{parts[0]}.{payload}.{parts[2]}");
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/me")).StatusCode);
    }

    [Fact]
    public async Task Expired_access_token_is_rejected()
    {
        var session = await _factory.SignInAsync("expired");
        var expired = MakeToken(session.Auth.Profile.Id, Convert.FromBase64String(_factory.SigningKey), DateTime.UtcNow.AddMinutes(-5));
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", expired);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/me")).StatusCode);
    }

    [Fact]
    public async Task Sign_in_is_rate_limited_per_ip()
    {
        await using var limited = new RemiFactory { AuthPerMinute = 3 };
        var client = limited.CreateClient();
        var codes = new List<HttpStatusCode>();
        for (var i = 0; i < 5; i++)
            codes.Add((await client.PostAsJsonAsync("/v1/auth/apple", new { idToken = "forged" })).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, codes[^1]);
        Assert.Equal(3, codes.Count(c => c == HttpStatusCode.Unauthorized));
    }

    private static string MakeToken(Guid userId, byte[] key, DateTime? expires = null)
    {
        var exp = expires ?? DateTime.UtcNow.AddMinutes(10);
        return new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = "remi-api",
            Audience = "remi-app",
            Subject = new ClaimsIdentity([new Claim("sub", userId.ToString())]),
            IssuedAt = exp.AddMinutes(-15),
            NotBefore = exp.AddMinutes(-15),
            Expires = exp,
            SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256),
        });
    }
}
