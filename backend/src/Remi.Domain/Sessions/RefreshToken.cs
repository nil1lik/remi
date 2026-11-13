using Remi.Domain.Accounts;

namespace Remi.Domain.Sessions;

/// <summary>
/// Oturum yenileme anahtarı. Anahtarın kendisi değil yalnız özeti saklanır. Her kullanımda yenisiyle
/// değiştirilir (rotation); aynı oturum ailesinden kullanılmış bir anahtar tekrar gelirse anahtar
/// çalınmış sayılır ve aile tümden iptal edilir.
/// </summary>
public sealed class RefreshToken
{
    public Guid Id { get; private init; }
    public AccountId AccountId { get; private init; }
    public Guid FamilyId { get; private init; }
    public string TokenHash { get; private init; } = "";
    public DateTimeOffset CreatedAt { get; private init; }
    public DateTimeOffset ExpiresAt { get; private init; }
    public DateTimeOffset? RevokedAt { get; private set; }
    public Guid? ReplacedById { get; private set; }

    private RefreshToken() { }

    public static RefreshToken Issue(AccountId account, Guid familyId, string tokenHash, DateTimeOffset now, TimeSpan lifetime) => new()
    {
        Id = Guid.NewGuid(),
        AccountId = account,
        FamilyId = familyId,
        TokenHash = tokenHash,
        CreatedAt = now,
        ExpiresAt = now + lifetime,
    };

    /// <summary>Daha önce kullanılmış ya da iptal edilmiş: tekrar gelmesi çalınma belirtisidir.</summary>
    public bool WasUsedOrRevoked => RevokedAt is not null || ReplacedById is not null;
    public bool IsExpired(DateTimeOffset now) => ExpiresAt <= now;

    public RefreshToken Rotate(string newTokenHash, DateTimeOffset now, TimeSpan lifetime)
    {
        if (WasUsedOrRevoked || IsExpired(now)) throw new InvalidOperationException("Kullanılamaz anahtar yenilenemez.");
        var next = Issue(AccountId, FamilyId, newTokenHash, now, lifetime);
        ReplacedById = next.Id;
        RevokedAt = now;
        return next;
    }

    public void Revoke(DateTimeOffset now) => RevokedAt ??= now;
}
