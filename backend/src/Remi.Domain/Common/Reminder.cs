namespace Remi.Domain.Common;

public enum ReminderKind
{
    Notification,
    Alarm,
}

/// <summary>
/// Dersten ne kadar önce, hangi yolla hatırlatılacağı. Uygulamadaki tekerlekle aynı değerler:
/// 0–60 dakika (5'er) ya da 1–12 saat.
/// </summary>
public sealed record Reminder
{
    public static readonly Reminder Default = new(10, ReminderKind.Notification);

    public int MinutesBefore { get; }
    public ReminderKind Kind { get; }

    private Reminder(int minutesBefore, ReminderKind kind) => (MinutesBefore, Kind) = (minutesBefore, kind);

    public static bool IsAllowed(int minutes) =>
        minutes is >= 0 and <= 60 && minutes % 5 == 0 ||
        minutes is > 60 and <= 720 && minutes % 60 == 0;

    public static Result<Reminder> Create(int minutesBefore, ReminderKind kind) =>
        IsAllowed(minutesBefore) ? new Reminder(minutesBefore, kind) : Error.Invalid("", "invalid_reminder");

    public static Reminder Restore(int minutesBefore, ReminderKind kind) => new(minutesBefore, kind);
}
