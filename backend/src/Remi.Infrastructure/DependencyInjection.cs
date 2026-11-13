using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Remi.Application.Abstractions;
using Remi.Infrastructure.Identity;
using Remi.Infrastructure.Persistence;

namespace Remi.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        // Gizli anahtar eksik ya da kısaysa uygulama hiç açılmaz.
        services.AddOptions<AuthOptions>()
            .Bind(configuration.GetSection(AuthOptions.Section))
            .Validate(o => { o.SigningKeyBytes(); return true; })
            .ValidateOnStart();

        services.AddDbContext<RemiDbContext>(o => o.UseNpgsql(configuration.GetConnectionString("Remi")));
        services.AddScoped<IAccountRepository, AccountRepository>();
        services.AddScoped<IGroupRepository, GroupRepository>();
        services.AddScoped<IRefreshTokenRepository, RefreshTokenRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        services.AddSingleton<IIdentityTokenVerifier, OidcIdentityTokenVerifier>();
        services.AddSingleton<IAccessTokenIssuer, JwtAccessTokenIssuer>();
        services.AddSingleton(sp => new SessionSettings(
            TimeSpan.FromDays(sp.GetRequiredService<IOptions<AuthOptions>>().Value.RefreshTokenDays)));
        services.AddSingleton(TimeProvider.System);
        return services;
    }

    /// <summary>API'nin erişim anahtarlarını doğrularken kullandığı anahtar ve kimlik değerleri.</summary>
    public static (SymmetricSecurityKey Key, string Issuer, string Audience) AccessTokenValidation(IOptions<AuthOptions> options) =>
        (JwtAccessTokenIssuer.SigningKey(options.Value), options.Value.Issuer, options.Value.Audience);

    public static Task MigrateDatabaseAsync(IServiceProvider services, CancellationToken ct = default)
    {
        using var scope = services.CreateScope();
        return scope.ServiceProvider.GetRequiredService<RemiDbContext>().Database.MigrateAsync(ct);
    }
}
