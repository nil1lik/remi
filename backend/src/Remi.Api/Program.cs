using System.Net;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Remi.Api;
using Remi.Api.Http;
using Remi.Application.Accounts;
using Remi.Application.Auth;
using Remi.Application.Groups;
using Remi.Infrastructure;
using Remi.Infrastructure.Identity;

var builder = WebApplication.CreateBuilder(args);

// Kestrel: sunucu adı gizli, istek gövdesi küçük (en büyük istek tek bir grup kaydı).
builder.WebHost.ConfigureKestrel(k =>
{
    k.AddServerHeader = false;
    k.Limits.MaxRequestBodySize = 32 * 1024;
    k.Limits.MaxRequestHeadersTotalSize = 16 * 1024;
});

builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<AccountService>();
builder.Services.AddScoped<GroupService>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
// Erişim anahtarı doğrulaması, doğrulanmış ayarlardan kurulur (anahtar yoksa uygulama açılmaz).
builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IOptions<AuthOptions>, IHostEnvironment>((o, auth, env) =>
    {
        var (key, issuer, audience) = DependencyInjection.AccessTokenValidation(auth);
        o.MapInboundClaims = false;
        o.RequireHttpsMetadata = !env.IsDevelopment();
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = issuer,
            ValidAudience = audience,
            IssuerSigningKey = key,
            ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
            RequireSignedTokens = true,
            RequireExpirationTime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromSeconds(30),
        };
    });
builder.Services.AddAuthorization();

var authPerMinute = builder.Configuration.GetValue("RateLimits:AuthPerMinute", 10);
var apiPerMinute = builder.Configuration.GetValue("RateLimits:ApiPerMinute", 300);
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    // Giriş: IP başına dakikada 10 deneme (anahtar tahmini ve kaba kuvvete karşı).
    o.AddPolicy(RateLimits.Auth, ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = authPerMinute, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
    // Diğer istekler: hesap başına dakikada 300.
    o.AddPolicy(RateLimits.Api, ctx => RateLimitPartition.GetFixedWindowLimiter(
        CurrentAccount.FromClaims(ctx.User)?.ToString() ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = apiPerMinute, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});

// Vekil sunucu (Caddy/nginx) arkasında gerçek istemci IP'si: yalnız tanımlı vekillere güvenilir.
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownIPNetworks.Clear();
    o.KnownProxies.Clear();
    foreach (var proxy in builder.Configuration.GetSection("Network:KnownProxies").Get<string[]>() ?? [])
        if (IPAddress.TryParse(proxy, out var ip)) o.KnownProxies.Add(ip);
});

// Hatalarda iç ayrıntı (yığın izi, SQL) istemciye gitmez.
builder.Services.AddProblemDetails();
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.MaxDepth = 16);

var app = builder.Build();

app.UseForwardedHeaders();
app.UseExceptionHandler();
app.UseStatusCodePages();
if (!app.Environment.IsDevelopment()) app.UseHsts();

app.Use(async (context, next) =>
{
    var h = context.Response.Headers;
    h.XContentTypeOptions = "nosniff";
    h.XFrameOptions = "DENY";
    h["Referrer-Policy"] = "no-referrer";
    h.ContentSecurityPolicy = "default-src 'none'; frame-ancestors 'none'";
    h.CacheControl = "no-store";
    await next();
});

app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

app.MapRemiEndpoints();

if (app.Configuration.GetValue<bool>("Database:MigrateOnStartup"))
    await DependencyInjection.MigrateDatabaseAsync(app.Services);

app.Run();

public partial class Program;
