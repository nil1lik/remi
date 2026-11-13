using Remi.Domain.Accounts;
using Remi.Domain.Common;

namespace Remi.Domain.Groups;

/// <summary>
/// Ders grubu. İki cihaz aynı grubu aynı anda değiştirirse son yazan diğerini ezmesin diye her değişiklik
/// sürümü artırır ve değişiklik, istemcinin son gördüğü sürümle yapılır.
/// Silinen grup diğer cihazlar öğrenene kadar iz olarak kalır; adı ve bağlantısı hemen silinir.
/// </summary>
public sealed class Group : AggregateRoot<GroupId>
{
    public const int MaxPerAccount = 200;

    private DateOnly? _holidayStart;
    private DateOnly? _holidayEnd;

    public AccountId OwnerId { get; private init; }
    public GroupName Name { get; private set; } = null!;
    public GroupColor Color { get; private set; }
    public ChatLink? ChatLink { get; private set; }
    public WeeklySchedule Schedule { get; private set; } = null!;
    public Reminder Reminder { get; private set; } = null!;
    public DateRange? Holiday => DateRange.Restore(_holidayStart, _holidayEnd);

    public int Version { get; private set; }
    /// <summary>Sahibinin revizyon sayacından aldığı numara; eşitleme buna göre yapılır.</summary>
    public long Revision { get; private set; }
    public bool IsDeleted { get; private set; }
    public DateTimeOffset CreatedAt { get; private init; }
    public DateTimeOffset UpdatedAt { get; private set; }

    private Group() { }

    public static Group Create(GroupId id, Account owner, GroupDetails details, DateTimeOffset now)
    {
        var group = new Group { Id = id, OwnerId = owner.Id, CreatedAt = now, Version = 1 };
        group.Apply(details);
        group.Stamp(owner, now);
        return group;
    }

    public Result Update(Account owner, int expectedVersion, GroupDetails details, DateTimeOffset now)
    {
        if (CheckWritable(owner, expectedVersion) is { } error) return error;
        Apply(details);
        Version++;
        Stamp(owner, now);
        return Result.Success();
    }

    public Result Delete(Account owner, int? expectedVersion, DateTimeOffset now)
    {
        if (CheckWritable(owner, expectedVersion) is { } error) return error;
        IsDeleted = true;
        Name = GroupName.Restore("");
        ChatLink = null;
        (_holidayStart, _holidayEnd) = (null, null);
        Version++;
        Stamp(owner, now);
        return Result.Success();
    }

    /// <summary>Bu grup belirtilen gün tatilde mi (grubun kendi tatili ya da hocanın tatili).</summary>
    public bool IsPausedOn(DateOnly day, Account owner) => Holiday?.Contains(day) == true || owner.IsOnVacation(day);

    private Error? CheckWritable(Account owner, int? expectedVersion)
    {
        if (owner.Id != OwnerId || IsDeleted) return Error.NotFound();
        if (expectedVersion is not null && expectedVersion != Version) return Error.Conflict("version_mismatch");
        return null;
    }

    private void Apply(GroupDetails d)
    {
        Name = d.Name;
        Color = d.Color;
        ChatLink = d.ChatLink;
        Schedule = d.Schedule;
        Reminder = d.Reminder;
        (_holidayStart, _holidayEnd) = (d.Holiday?.Start, d.Holiday?.End);
    }

    private void Stamp(Account owner, DateTimeOffset now)
    {
        Revision = owner.NextRevision();
        UpdatedAt = now;
    }
}
