using Remi.Application.Abstractions;
using Remi.Domain.Accounts;
using Remi.Domain.Common;
using Remi.Domain.Groups;

namespace Remi.Application.Groups;

/// <summary>Grup ekleme, düzenleme, silme ve cihazlar arası eşitleme.</summary>
public sealed class GroupService(IAccountRepository accounts, IGroupRepository groups, IUnitOfWork uow, TimeProvider clock)
{
    public async Task<IReadOnlyList<GroupDto>> ListAsync(AccountId owner, CancellationToken ct) =>
        (await groups.ListActiveAsync(owner, ct)).Select(GroupDto.From).ToList();

    public Task<Result<GroupDto>> CreateAsync(AccountId ownerId, GroupCommand command, CancellationToken ct)
    {
        var details = BuildDetails(command);
        if (!details.IsSuccess) return Task.FromResult(Result.Failure<GroupDto>([.. details.Errors]));

        return Retry.OnConflictAsync<GroupDto>(uow, async () =>
        {
            if (await accounts.FindAsync(ownerId, ct) is not { } owner) return Error.NotFound();
            if (await groups.CountActiveAsync(ownerId, ct) >= Group.MaxPerAccount) return Error.Rule("group_limit_reached");

            // İstemci çevrimdışıyken kimliği kendisi üretebilir. Başkasına ait kimlik kullanılamaz,
            // ama kime ait olduğu da söylenmez.
            var id = command.Id is { } given ? new GroupId(given) : GroupId.New();
            if (await groups.FindAsync(id, ct) is { } taken)
                return taken.OwnerId == ownerId && !taken.IsDeleted
                    ? Error.Conflict("already_exists", GroupDto.From(taken))
                    : Error.Conflict("id_unavailable");

            var group = Group.Create(id, owner, details.Value, clock.GetUtcNow());
            groups.Add(group);
            await uow.SaveChangesAsync(ct);
            return GroupDto.From(group);
        });
    }

    public Task<Result<GroupDto>> UpdateAsync(AccountId ownerId, Guid id, GroupCommand command, CancellationToken ct)
    {
        var details = BuildDetails(command);
        var errors = details.Errors.ToList();
        if (command.Version is null) errors.Add(Error.Invalid("version", "required"));
        if (errors.Count > 0) return Task.FromResult(Result.Failure<GroupDto>([.. errors]));

        return Retry.OnConflictAsync<GroupDto>(uow, async () =>
        {
            if (await accounts.FindAsync(ownerId, ct) is not { } owner) return Error.NotFound();
            if (await groups.FindAsync(new GroupId(id), ct) is not { } group) return Error.NotFound();

            var result = group.Update(owner, command.Version!.Value, details.Value, clock.GetUtcNow());
            if (!result.IsSuccess) return WithCurrent(result, group);
            await uow.SaveChangesAsync(ct);
            return GroupDto.From(group);
        });
    }

    public Task<Result<GroupDto>> DeleteAsync(AccountId ownerId, Guid id, int? expectedVersion, CancellationToken ct) =>
        Retry.OnConflictAsync<GroupDto>(uow, async () =>
        {
            if (await accounts.FindAsync(ownerId, ct) is not { } owner) return Error.NotFound();
            if (await groups.FindAsync(new GroupId(id), ct) is not { } group) return Error.NotFound();

            var result = group.Delete(owner, expectedVersion, clock.GetUtcNow());
            if (!result.IsSuccess) return WithCurrent(result, group);
            await uow.SaveChangesAsync(ct);
            return GroupDto.From(group);
        });

    /// <summary>
    /// Cihaz son gördüğü revizyonu gönderir, yalnız ondan sonraki değişiklikleri alır.
    /// since = 0 tam yüklemedir (silinmiş izler gönderilmez).
    /// </summary>
    public async Task<Result<SyncResult>> SyncAsync(AccountId ownerId, long since, CancellationToken ct)
    {
        if (since < 0) return Error.Invalid("since", "out_of_range");
        if (await accounts.FindAsync(ownerId, ct) is not { } owner) return Error.NotFound();
        if (since > owner.Revision) since = 0; // Sunucudan ileri bir sayaç: cihaz tam yükleme yapsın.

        var changed = since == 0
            ? await groups.ListActiveAsync(ownerId, ct)
            : await groups.ListChangedSinceAsync(ownerId, since, ct);

        return new SyncResult(
            owner.Revision,
            since == 0 || owner.ProfileRevision > since ? ProfileDto.From(owner) : null,
            changed.Select(GroupDto.From).ToList());
    }

    /// <summary>İstemcinin gönderdiği ham alanları domain value object'lerine çevirir; tüm hataları birlikte döner.</summary>
    private static Result<GroupDetails> BuildDetails(GroupCommand c)
    {
        var errors = new ErrorCollector();
        var name = errors.Take(GroupName.Create(c.Name), "name");
        var color = errors.Take(EnumText.Parse<GroupColor>(c.Color ?? "blue"), "color");
        var link = errors.Take(ChatLink.CreateOptional(c.ChatLink), "chatLink");
        var schedule = errors.Take(WeeklySchedule.Create(c.Days, c.StartMinute, c.DurationMinutes), "schedule");
        var kind = errors.Take(EnumText.Parse<ReminderKind>(c.ReminderKind ?? "notification"), "reminderKind");
        var reminder = errors.Take(Reminder.Create(c.ReminderMinutes ?? Reminder.Default.MinutesBefore, kind), "reminderMinutes");
        var holiday = errors.Take(DateRange.CreateOptional(c.HolidayStart, c.HolidayEnd), "holiday");

        return errors.HasErrors
            ? Result.Failure<GroupDetails>([.. errors.Errors])
            : new GroupDetails(name!, color, link, schedule!, reminder!, holiday);
    }

    /// <summary>Sürüm çakışmasında istemci yeniden deneyebilsin diye güncel kayıt da döner.</summary>
    private static Result<GroupDto> WithCurrent(Result result, Group group)
    {
        var error = result.Errors[0];
        return error.Kind == ErrorKind.Conflict ? error with { Details = GroupDto.From(group) } : error;
    }
}
