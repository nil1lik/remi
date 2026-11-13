using Remi.Application.Abstractions;
using Remi.Domain.Common;

namespace Remi.Application;

internal static class Retry
{
    /// <summary>
    /// Hesabın revizyon sayacı eşzamanlı isteklerde çakışabilir; işlem veriyi baştan okuyarak
    /// en fazla 3 kez denenir. İşlem her denemede kendi okumasını yapmalıdır.
    /// </summary>
    public static async Task<Result<T>> OnConflictAsync<T>(IUnitOfWork uow, Func<Task<Result<T>>> action)
    {
        for (var attempt = 1; ; attempt++)
        {
            try { return await action(); }
            catch (ConcurrencyConflictException) when (attempt < 3) { uow.Reset(); }
            catch (ConcurrencyConflictException) { uow.Reset(); return Error.Conflict("concurrent_update"); }
        }
    }
}
