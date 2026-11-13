namespace Remi.Domain.Common;

/// <summary>
/// Enum'ları istemciyle küçük harfli adlarıyla konuşur ("notification", "dark").
/// Sayısal değerler ve bilinmeyen adlar reddedilir ("1" ya da "Dark" kabul edilmez).
/// </summary>
public static class EnumText
{
    public static string ToText<T>(this T value) where T : struct, Enum => value.ToString().ToLowerInvariant();

    public static Result<T> Parse<T>(string? text) where T : struct, Enum
    {
        foreach (var value in Enum.GetValues<T>())
            if (string.Equals(value.ToText(), text, StringComparison.Ordinal)) return value;
        return Error.Invalid("", "invalid_value");
    }
}
