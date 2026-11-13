using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Remi.Application.Abstractions;
using Remi.Domain.Accounts;
using Remi.Infrastructure.Persistence;

namespace Remi.Api.Tests;

/// <summary>
/// Gerçek API'yi bellekte çalıştırır: PostgreSQL yerine bellek içi SQLite, Apple/Google yerine sahte doğrulayıcı.
/// </summary>
public sealed class RemiFactory : WebApplicationFactory<Program>
{
    private readonly SqliteConnection _connection = new("DataSource=:memory:");
    public string SigningKey { get; } = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
    public int AuthPerMinute { get; init; } = 1000;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("Auth:SigningKey", SigningKey);
        builder.UseSetting("ConnectionStrings:Remi", "Host=unused");
        builder.UseSetting("RateLimits:AuthPerMinute", AuthPerMinute.ToString());
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<DbContextOptions<RemiDbContext>>();
            services.RemoveAll(typeof(IDbContextOptionsConfiguration<RemiDbContext>));
            _connection.Open();
            services.AddDbContext<RemiDbContext>(o => o.UseSqlite(_connection));
            services.RemoveAll<IIdentityTokenVerifier>();
            services.AddSingleton<IIdentityTokenVerifier, FakeValidator>();
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);
        using var scope = host.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<RemiDbContext>().Database.EnsureCreated();
        return host;
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) _connection.Dispose();
    }

    public async Task<Session> SignInAsync(string subject, string provider = "apple")
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync($"/v1/auth/{provider}",
            new { idToken = FakeValidator.Token(subject), nonce = "n0nce", displayName = "Hocam" });
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<AuthBody>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", body!.AccessToken);
        return new Session(client, body);
    }
}

public sealed record Session(HttpClient Client, AuthBody Auth);
public sealed record AuthBody(string AccessToken, int ExpiresIn, string RefreshToken, ProfileBody Profile);
public sealed record ProfileBody(Guid Id, string DisplayName, string Locale, string Theme, string Accent,
    int DefaultReminderMinutes, string DefaultReminderKind, DateOnly? VacationStart, DateOnly? VacationEnd);
public sealed record GroupBody(Guid Id, string Name, string Color, string? ChatLink, string? ChatApp, int[] Days,
    int StartMinute, int DurationMinutes, int ReminderMinutes, string ReminderKind,
    DateOnly? HolidayStart, DateOnly? HolidayEnd, int Version, bool Deleted);
public sealed record SyncBody(long Cursor, ProfileBody? Profile, List<GroupBody> Groups);

/// <summary>"valid:&lt;sub&gt;" biçimindeki belgeleri kabul eder; gerisini reddeder.</summary>
public sealed class FakeValidator : IIdentityTokenVerifier
{
    public static string Token(string subject) => "valid:" + subject;

    public Task<ExternalIdentity?> VerifyAsync(IdentityProvider provider, string idToken, string? nonce, CancellationToken ct) =>
        Task.FromResult(idToken.StartsWith("valid:", StringComparison.Ordinal)
            ? ExternalIdentity.Create(provider, idToken["valid:".Length..]).Value
            : null);
}
