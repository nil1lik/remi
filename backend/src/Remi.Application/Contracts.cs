using Remi.Domain.Accounts;
using Remi.Domain.Common;
using Remi.Domain.Groups;

namespace Remi.Application;

// Komutlar (istemciden gelen ham veri; domain value object'lerine çevrilirken doğrulanır)

public sealed record SignInCommand(string? IdToken, string? Nonce, string? DisplayName, string? Locale);

public sealed record PersonalizeCommand(
    string? DisplayName, string? Locale, string? Theme, string? Accent,
    int? DefaultReminderMinutes, string? DefaultReminderKind);

public sealed record DateRangeCommand(DateOnly? Start, DateOnly? End);

public sealed record GroupCommand(
    Guid? Id, string? Name, string? Color, string? ChatLink, int[]? Days,
    int? StartMinute, int? DurationMinutes, int? ReminderMinutes, string? ReminderKind,
    DateOnly? HolidayStart, DateOnly? HolidayEnd,
    /// <summary>Güncellemede istemcinin son gördüğü sürüm.</summary>
    int? Version);

// Sonuçlar

public sealed record TokenResult(string AccessToken, int ExpiresIn, string RefreshToken);
public sealed record AuthResult(string AccessToken, int ExpiresIn, string RefreshToken, ProfileDto Profile);

public sealed record ProfileDto(
    Guid Id, string DisplayName, string Locale, string Theme, string Accent,
    int DefaultReminderMinutes, string DefaultReminderKind,
    DateOnly? VacationStart, DateOnly? VacationEnd)
{
    public static ProfileDto From(Account a) => new(
        a.Id.Value, a.DisplayName.Value, a.Preferences.Locale.ToText(), a.Preferences.Theme.ToText(),
        a.Preferences.Accent.ToText(), a.Preferences.DefaultReminder.MinutesBefore,
        a.Preferences.DefaultReminder.Kind.ToText(), a.Vacation?.Start, a.Vacation?.End);
}

public sealed record GroupDto(
    Guid Id, string Name, string Color, string? ChatLink, string? ChatApp,
    int[] Days, int StartMinute, int DurationMinutes,
    int ReminderMinutes, string ReminderKind,
    DateOnly? HolidayStart, DateOnly? HolidayEnd,
    int Version, bool Deleted)
{
    public static GroupDto From(Group g) => g.IsDeleted
        ? new(g.Id.Value, "", g.Color.ToText(), null, null, [], 0, 0, 0, g.Reminder.Kind.ToText(), null, null, g.Version, true)
        : new(g.Id.Value, g.Name.Value, g.Color.ToText(), g.ChatLink?.Url, g.ChatLink?.App.ToText(),
            g.Schedule.IsoDays(), g.Schedule.StartMinute, g.Schedule.DurationMinutes,
            g.Reminder.MinutesBefore, g.Reminder.Kind.ToText(), g.Holiday?.Start, g.Holiday?.End, g.Version, false);
}

public sealed record SyncResult(long Cursor, ProfileDto? Profile, IReadOnlyList<GroupDto> Groups);
