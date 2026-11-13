namespace Remi.Domain.Common;

/// <summary>Başlangıç ve bitişi dahil gün aralığı (tatil). En fazla bir yıl.</summary>
public sealed record DateRange
{
    public const int MaxDays = 366;

    public DateOnly Start { get; }
    public DateOnly End { get; }

    private DateRange(DateOnly start, DateOnly end) => (Start, End) = (start, end);

    public static Result<DateRange> Create(DateOnly start, DateOnly end)
    {
        if (end < start) return Error.Invalid("", "end_before_start");
        if (end.DayNumber - start.DayNumber > MaxDays) return Error.Invalid("", "too_long");
        return new DateRange(start, end);
    }

    /// <summary>İkisi de boşsa aralık yok demektir; yalnız biri doluysa hata.</summary>
    public static Result<DateRange?> CreateOptional(DateOnly? start, DateOnly? end)
    {
        if (start is null && end is null) return Result.Success<DateRange?>(null);
        if (start is null || end is null) return Error.Invalid("", "both_dates_required");
        var range = Create(start.Value, end.Value);
        return range.IsSuccess ? Result.Success<DateRange?>(range.Value) : Result.Failure<DateRange?>([.. range.Errors]);
    }

    public bool Contains(DateOnly day) => day >= Start && day <= End;

    /// <summary>Yalnız veritabanından okurken: kurallar yazarken denetlendi.</summary>
    public static DateRange? Restore(DateOnly? start, DateOnly? end) =>
        start is { } s && end is { } e ? new DateRange(s, e) : null;
}
