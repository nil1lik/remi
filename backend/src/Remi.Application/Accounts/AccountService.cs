using Remi.Application.Abstractions;
using Remi.Domain.Accounts;
using Remi.Domain.Common;

namespace Remi.Application.Accounts;

/// <summary>Profil, kişiselleştirme, hocanın tatili ve hesap silme.</summary>
public sealed class AccountService(IAccountRepository accounts, IUnitOfWork uow)
{
    public async Task<Result<ProfileDto>> GetAsync(AccountId id, CancellationToken ct) =>
        await accounts.FindAsync(id, ct) is { } account ? ProfileDto.From(account) : Error.NotFound();

    public Task<Result<ProfileDto>> PersonalizeAsync(AccountId id, PersonalizeCommand command, CancellationToken ct) =>
        Retry.OnConflictAsync<ProfileDto>(uow, async () =>
        {
            if (await accounts.FindAsync(id, ct) is not { } account) return Error.NotFound();

            var errors = new ErrorCollector();
            var current = account.Preferences;
            var name = command.DisplayName is null ? null : errors.Take(DisplayName.Create(command.DisplayName), "displayName");
            var locale = command.Locale is null ? current.Locale : errors.Take(EnumText.Parse<Locale>(command.Locale), "locale");
            var theme = command.Theme is null ? current.Theme : errors.Take(EnumText.Parse<Theme>(command.Theme), "theme");
            var accent = command.Accent is null ? current.Accent : errors.Take(EnumText.Parse<Accent>(command.Accent), "accent");
            var kind = command.DefaultReminderKind is null
                ? current.DefaultReminder.Kind
                : errors.Take(EnumText.Parse<ReminderKind>(command.DefaultReminderKind), "defaultReminderKind");
            var reminder = errors.Take(
                Reminder.Create(command.DefaultReminderMinutes ?? current.DefaultReminder.MinutesBefore, kind),
                "defaultReminderMinutes");
            if (errors.HasErrors) return Result.Failure<ProfileDto>([.. errors.Errors]);

            account.Personalize(name, new Preferences(locale, theme, accent, reminder!));
            await uow.SaveChangesAsync(ct);
            return ProfileDto.From(account);
        });

    /// <summary>"Ben tatildeyim": tüm hatırlatmalar aralık boyunca susar.</summary>
    public Task<Result<ProfileDto>> StartVacationAsync(AccountId id, DateRangeCommand command, CancellationToken ct)
    {
        if (command.Start is null || command.End is null)
            return Task.FromResult<Result<ProfileDto>>(Error.Invalid("vacation", "both_dates_required"));
        var range = DateRange.Create(command.Start.Value, command.End.Value);
        if (!range.IsSuccess) return Task.FromResult(Result.Failure<ProfileDto>([.. range.Errors.Select(e => e.At("vacation"))]));

        return Retry.OnConflictAsync<ProfileDto>(uow, async () =>
        {
            if (await accounts.FindAsync(id, ct) is not { } account) return Error.NotFound();
            account.StartVacation(range.Value);
            await uow.SaveChangesAsync(ct);
            return ProfileDto.From(account);
        });
    }

    /// <summary>"Tatilden geldim".</summary>
    public Task<Result<ProfileDto>> EndVacationAsync(AccountId id, CancellationToken ct) =>
        Retry.OnConflictAsync<ProfileDto>(uow, async () =>
        {
            if (await accounts.FindAsync(id, ct) is not { } account) return Error.NotFound();
            account.EndVacation();
            await uow.SaveChangesAsync(ct);
            return ProfileDto.From(account);
        });

    public Task DeleteAsync(AccountId id, CancellationToken ct) => accounts.DeleteAsync(id, ct);
}
