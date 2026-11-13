using Microsoft.EntityFrameworkCore;
using Remi.Application.Abstractions;
using Remi.Domain.Accounts;
using Remi.Domain.Groups;
using Remi.Domain.Sessions;

namespace Remi.Infrastructure.Persistence;

internal sealed class AccountRepository(RemiDbContext db) : IAccountRepository
{
    public Task<Account?> FindAsync(AccountId id, CancellationToken ct) =>
        db.Accounts.SingleOrDefaultAsync(a => a.Id == id, ct);

    public Task<Account?> FindByIdentityAsync(ExternalIdentity identity, CancellationToken ct) =>
        db.Accounts.SingleOrDefaultAsync(
            a => a.Logins.Any(l => l.Provider == identity.Provider && l.Subject == identity.Subject), ct);

    public Task<bool> ExistsAsync(AccountId id, CancellationToken ct) => db.Accounts.AnyAsync(a => a.Id == id, ct);

    public void Add(Account account) => db.Accounts.Add(account);

    // Gruplar, oturumlar ve giriş kayıtları veritabanında ON DELETE CASCADE ile birlikte silinir.
    public Task DeleteAsync(AccountId id, CancellationToken ct) =>
        db.Accounts.Where(a => a.Id == id).ExecuteDeleteAsync(ct);
}

internal sealed class GroupRepository(RemiDbContext db) : IGroupRepository
{
    public Task<Group?> FindAsync(GroupId id, CancellationToken ct) => db.Groups.SingleOrDefaultAsync(g => g.Id == id, ct);

    public Task<bool> ExistsAsync(GroupId id, CancellationToken ct) => db.Groups.AnyAsync(g => g.Id == id, ct);

    public Task<int> CountActiveAsync(AccountId owner, CancellationToken ct) =>
        db.Groups.CountAsync(g => g.OwnerId == owner && !g.IsDeleted, ct);

    public async Task<IReadOnlyList<Group>> ListActiveAsync(AccountId owner, CancellationToken ct) =>
        await db.Groups.AsNoTracking()
            .Where(g => g.OwnerId == owner && !g.IsDeleted)
            .OrderBy(g => g.Schedule.StartMinute).ThenBy(g => g.Revision)
            .ToListAsync(ct);

    public async Task<IReadOnlyList<Group>> ListChangedSinceAsync(AccountId owner, long revision, CancellationToken ct) =>
        await db.Groups.AsNoTracking()
            .Where(g => g.OwnerId == owner && g.Revision > revision)
            .OrderBy(g => g.Revision)
            .ToListAsync(ct);

    public void Add(Group group) => db.Groups.Add(group);
}

internal sealed class RefreshTokenRepository(RemiDbContext db) : IRefreshTokenRepository
{
    public Task<RefreshToken?> FindByHashAsync(string tokenHash, CancellationToken ct) =>
        db.RefreshTokens.SingleOrDefaultAsync(t => t.TokenHash == tokenHash, ct);

    public async Task<IReadOnlyList<RefreshToken>> ListActiveInFamilyAsync(Guid familyId, CancellationToken ct) =>
        await db.RefreshTokens.Where(t => t.FamilyId == familyId && t.RevokedAt == null).ToListAsync(ct);

    public void Add(RefreshToken token) => db.RefreshTokens.Add(token);
}

internal sealed class UnitOfWork(RemiDbContext db) : IUnitOfWork
{
    public async Task SaveChangesAsync(CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException ex)
        {
            throw new ConcurrencyConflictException(ex);
        }
        catch (DbUpdateException ex) when (IsUniqueViolation(ex))
        {
            throw new DuplicateKeyException(ex);
        }
    }

    public void Reset() => db.ChangeTracker.Clear();

    private static bool IsUniqueViolation(DbUpdateException ex) => ex.InnerException switch
    {
        Npgsql.PostgresException pg => pg.SqlState == Npgsql.PostgresErrorCodes.UniqueViolation,
        // Testlerde kullanılan SQLite (bu katman ona bağımlı değil).
        { } inner when inner.GetType().Name == "SqliteException" => inner.Message.Contains("UNIQUE", StringComparison.Ordinal),
        _ => false,
    };
}
