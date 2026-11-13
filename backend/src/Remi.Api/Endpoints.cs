using Remi.Api.Http;
using Remi.Application;
using Remi.Application.Accounts;
using Remi.Application.Auth;
using Remi.Application.Groups;

namespace Remi.Api;

/// <summary>HTTP uçları: yalnız isteği kullanım senaryosuna iletir ve sonucu yanıta çevirir.</summary>
public static class Endpoints
{
    public sealed record RefreshRequest(string? RefreshToken);

    public static void MapRemiEndpoints(this WebApplication app)
    {
        app.MapGet("/health", () => Results.Ok(new { status = "ok" })).AllowAnonymous();

        // Giriş: anonim, IP başına sıkı hız sınırı.
        var auth = app.MapGroup("/v1/auth").AllowAnonymous().RequireRateLimiting(RateLimits.Auth);
        auth.MapPost("/refresh", async (RefreshRequest body, AuthService service, CancellationToken ct) =>
            (await service.RefreshAsync(body.RefreshToken, ct)).ToHttp(Results.Ok));
        auth.MapPost("/logout", async (RefreshRequest body, AuthService service, CancellationToken ct) =>
        {
            await service.LogoutAsync(body.RefreshToken, ct);
            return Results.NoContent();
        });
        auth.MapPost("/{provider}", async (string provider, SignInCommand body, AuthService service, CancellationToken ct) =>
            (await service.SignInAsync(provider, body, ct)).ToHttp(Results.Ok));

        // Hesaba ait uçlar: geçerli erişim anahtarı ve var olan hesap gerekir.
        var api = app.MapGroup("/v1")
            .RequireAuthorization()
            .RequireRateLimiting(RateLimits.Api)
            .AddEndpointFilter(CurrentAccount.RequireExisting);

        api.MapGet("/me", async (HttpContext http, AccountService service, CancellationToken ct) =>
            (await service.GetAsync(CurrentAccount.Of(http), ct)).ToHttp(Results.Ok));
        api.MapPatch("/me", async (PersonalizeCommand body, HttpContext http, AccountService service, CancellationToken ct) =>
            (await service.PersonalizeAsync(CurrentAccount.Of(http), body, ct)).ToHttp(Results.Ok));
        api.MapPut("/me/vacation", async (DateRangeCommand body, HttpContext http, AccountService service, CancellationToken ct) =>
            (await service.StartVacationAsync(CurrentAccount.Of(http), body, ct)).ToHttp(Results.Ok));
        api.MapDelete("/me/vacation", async (HttpContext http, AccountService service, CancellationToken ct) =>
            (await service.EndVacationAsync(CurrentAccount.Of(http), ct)).ToHttp(Results.Ok));
        api.MapDelete("/me", async (HttpContext http, AccountService service, CancellationToken ct) =>
        {
            await service.DeleteAsync(CurrentAccount.Of(http), ct);
            return Results.NoContent();
        });

        api.MapGet("/groups", async (HttpContext http, GroupService service, CancellationToken ct) =>
            Results.Ok(await service.ListAsync(CurrentAccount.Of(http), ct)));
        api.MapPost("/groups", async (GroupCommand body, HttpContext http, GroupService service, CancellationToken ct) =>
            (await service.CreateAsync(CurrentAccount.Of(http), body, ct)).ToHttp(g => Results.Created($"/v1/groups/{g.Id}", g)));
        api.MapPut("/groups/{id:guid}", async (Guid id, GroupCommand body, HttpContext http, GroupService service, CancellationToken ct) =>
            (await service.UpdateAsync(CurrentAccount.Of(http), id, body, ct)).ToHttp(Results.Ok));
        api.MapDelete("/groups/{id:guid}", async (Guid id, int? version, HttpContext http, GroupService service, CancellationToken ct) =>
            (await service.DeleteAsync(CurrentAccount.Of(http), id, version, ct)).ToHttp(_ => Results.NoContent()));
        api.MapGet("/sync", async (long? since, HttpContext http, GroupService service, CancellationToken ct) =>
            (await service.SyncAsync(CurrentAccount.Of(http), since ?? 0, ct)).ToHttp(Results.Ok));
    }
}
