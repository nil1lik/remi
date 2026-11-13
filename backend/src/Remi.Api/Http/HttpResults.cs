using System.Security.Claims;
using Remi.Application.Abstractions;
using Remi.Domain.Accounts;
using Remi.Domain.Common;

namespace Remi.Api.Http;

public static class HttpResults
{
    /// <summary>Uygulama sonucunu HTTP yanıtına çevirir. Hata gövdesinde iç ayrıntı yoktur, yalnız sabit kodlar.</summary>
    public static IResult ToHttp<T>(this Result<T> result, Func<T, IResult> onSuccess) =>
        result.IsSuccess ? onSuccess(result.Value) : Failure(result.Errors);

    public static IResult Failure(IReadOnlyList<Error> errors)
    {
        if (errors.All(e => e.Kind == ErrorKind.Validation))
            return Results.ValidationProblem(errors
                .GroupBy(e => e.Field ?? "")
                .ToDictionary(g => g.Key, g => g.Select(e => e.Code).Distinct().ToArray()));

        var error = errors.First(e => e.Kind != ErrorKind.Validation);
        var status = error.Kind switch
        {
            ErrorKind.NotFound => StatusCodes.Status404NotFound,
            ErrorKind.Conflict => StatusCodes.Status409Conflict,
            ErrorKind.Rule => StatusCodes.Status422UnprocessableEntity,
            ErrorKind.Unauthorized => StatusCodes.Status401Unauthorized,
            _ => StatusCodes.Status400BadRequest,
        };
        return Results.Problem(statusCode: status, title: error.Code,
            extensions: error.Details is null ? null : new Dictionary<string, object?> { ["current"] = error.Details });
    }
}

public static class CurrentAccount
{
    private const string ItemKey = "remi.account";

    public static AccountId? FromClaims(ClaimsPrincipal principal) =>
        Guid.TryParse(principal.FindFirstValue("sub"), out var id) ? new AccountId(id) : null;

    /// <summary>Filtreden geçmiş istekte hesabın kimliği (her zaman dolu).</summary>
    public static AccountId Of(HttpContext context) => (AccountId)context.Items[ItemKey]!;

    /// <summary>
    /// Erişim anahtarı geçerli olsa bile hesap bu arada silinmiş olabilir; her istekte hesabın var olduğu doğrulanır.
    /// </summary>
    public static async ValueTask<object?> RequireExisting(EndpointFilterInvocationContext ctx, EndpointFilterDelegate next)
    {
        var http = ctx.HttpContext;
        if (FromClaims(http.User) is not { } id)
            return HttpResults.Failure([Error.Unauthorized("invalid_access_token")]);
        var accounts = http.RequestServices.GetRequiredService<IAccountRepository>();
        if (!await accounts.ExistsAsync(id, http.RequestAborted))
            return HttpResults.Failure([Error.Unauthorized("account_not_found")]);
        http.Items[ItemKey] = id;
        return await next(ctx);
    }
}

public static class RateLimits
{
    public const string Auth = "auth";
    public const string Api = "api";
}
