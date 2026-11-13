using Remi.Domain.Common;

namespace Remi.Domain.Groups;

public readonly record struct GroupId(Guid Value)
{
    public static GroupId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}

/// <summary>Grup adı ("A1-20 sınıfı"): 1–60 karakter, görünmez/yön değiştiren karakter yok.</summary>
public sealed record GroupName
{
    public const int MaxLength = 60;

    public string Value { get; }
    private GroupName(string value) => Value = value;

    public static Result<GroupName> Create(string? value) => Text.Clean(value, MaxLength, required: true).Map(v => new GroupName(v));
    public static GroupName Restore(string value) => new(value);
    public override string ToString() => Value;
}

/// <summary>Uygulamadaki grup renkleri; serbest renk kodu kabul edilmez.</summary>
public enum GroupColor { Blue, Green, Coral, Rose, Amber, Violet }

public enum ChatApp { WhatsApp, Telegram }

/// <summary>
/// Grubun sohbet bağlantısı. Yalnız https ve yalnız WhatsApp/Telegram grup adresleri kabul edilir;
/// kullanıcı adı/şifre, port, parça (#) ve sorgu (?) içeren adresler reddedilir. Böylece bağlantı
/// başka bir siteye ya da uygulamaya yönlendiremez.
/// </summary>
public sealed record ChatLink
{
    public const int MaxLength = 200;

    private static readonly Dictionary<string, ChatApp> Hosts = new(StringComparer.OrdinalIgnoreCase)
    {
        ["chat.whatsapp.com"] = ChatApp.WhatsApp,
        ["t.me"] = ChatApp.Telegram,
        ["telegram.me"] = ChatApp.Telegram,
    };

    public string Url { get; }
    public ChatApp App { get; }

    private ChatLink(string url, ChatApp app) => (Url, App) = (url, app);

    public static Result<ChatLink?> CreateOptional(string? input) =>
        string.IsNullOrWhiteSpace(input) ? Result.Success<ChatLink?>(null) : Create(input).Map<ChatLink?>(l => l);

    public static Result<ChatLink> Create(string input)
    {
        var unsupported = Error.Invalid("", "unsupported_link");
        var text = input.Trim();
        if (text.Length is 0 or > MaxLength) return unsupported;
        if (!text.Contains("://", StringComparison.Ordinal)) text = "https://" + text;
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri)) return unsupported;
        if (uri.Scheme != Uri.UriSchemeHttps) return unsupported;
        if (uri.UserInfo.Length > 0 || !uri.IsDefaultPort || uri.Fragment.Length > 0 || uri.Query.Length > 0) return unsupported;
        if (!Hosts.TryGetValue(uri.Host, out var app)) return unsupported;

        var path = uri.AbsolutePath.Trim('/');
        if (path.Length is 0 or > 120) return unsupported;
        if (!path.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-' or '+' or '/')) return unsupported;

        return new ChatLink($"https://{uri.Host.ToLowerInvariant()}/{path}", app);
    }

    /// <summary>Yalnız veritabanından okurken. Kayıtlı adres yazılırken denetlendi.</summary>
    public static ChatLink Restore(string url)
    {
        var link = Create(url);
        return link.IsSuccess ? link.Value : throw new InvalidOperationException("Kayıtlı sohbet bağlantısı geçersiz.");
    }

    public override string ToString() => Url;
}

[Flags]
public enum Weekdays
{
    None = 0,
    Monday = 1, Tuesday = 2, Wednesday = 4, Thursday = 8, Friday = 16, Saturday = 32, Sunday = 64,
    All = 127,
}

/// <summary>Haftalık ders saati: hangi günler, kaçta, kaç dakika. Ders gece yarısını geçemez.</summary>
public sealed record WeeklySchedule
{
    public const int MinDuration = 15;
    public const int MaxDuration = 600;
    private const int MinutesPerDay = 24 * 60;

    public Weekdays Days { get; }
    public int StartMinute { get; }
    public int DurationMinutes { get; }

    private WeeklySchedule(Weekdays days, int startMinute, int durationMinutes) =>
        (Days, StartMinute, DurationMinutes) = (days, startMinute, durationMinutes);

    /// <param name="isoDays">1 = Pazartesi … 7 = Pazar.</param>
    public static Result<WeeklySchedule> Create(IReadOnlyCollection<int>? isoDays, int? startMinute, int? durationMinutes)
    {
        var errors = new List<Error>();
        var days = Weekdays.None;
        if (isoDays is null || isoDays.Count == 0) errors.Add(Error.Invalid("days", "required"));
        else if (isoDays.Count > 7 || isoDays.Any(d => d is < 1 or > 7)) errors.Add(Error.Invalid("days", "invalid_value"));
        else days = isoDays.Aggregate(Weekdays.None, (mask, d) => mask | (Weekdays)(1 << (d - 1)));

        var start = startMinute ?? -1;
        if (start is < 0 or >= MinutesPerDay) errors.Add(Error.Invalid("startMinute", "out_of_range"));

        var duration = durationMinutes ?? 60;
        if (duration is < MinDuration or > MaxDuration) errors.Add(Error.Invalid("durationMinutes", "out_of_range"));
        else if (start >= 0 && start + duration > MinutesPerDay) errors.Add(Error.Invalid("durationMinutes", "ends_after_midnight"));

        return errors.Count > 0 ? Result.Failure<WeeklySchedule>([.. errors]) : new WeeklySchedule(days, start, duration);
    }

    public static WeeklySchedule Restore(Weekdays days, int startMinute, int durationMinutes) => new(days, startMinute, durationMinutes);

    /// <summary>1 = Pazartesi … 7 = Pazar.</summary>
    public int[] IsoDays() => Enumerable.Range(1, 7).Where(d => Days.HasFlag((Weekdays)(1 << (d - 1)))).ToArray();
}

/// <summary>Grubun düzenlenebilir bilgileri; hepsi önceden doğrulanmış value object'lerdir.</summary>
public sealed record GroupDetails(
    GroupName Name, GroupColor Color, ChatLink? ChatLink, WeeklySchedule Schedule, Reminder Reminder, DateRange? Holiday);
