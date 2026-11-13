namespace Remi.Domain.Common;

internal static class Text
{
    /// <summary>
    /// Kontrol karakterleri ve yazı yönünü gizlice çeviren (bidi) karakterler, adı olduğundan farklı
    /// gösterebilir ("A1‮gnp.exe"). Bunlar hiçbir metin alanında kabul edilmez.
    /// </summary>
    public static bool HasUnsafeCharacters(string text) =>
        text.Any(c => char.IsControl(c) || c is >= '‪' and <= '‮' or >= '⁦' and <= '⁩');

    /// <summary>Kırpılmış, güvenli ve sınır içinde bir metin; değilse hata.</summary>
    public static Result<string> Clean(string? value, int max, bool required)
    {
        var text = value?.Trim() ?? "";
        if (text.Length == 0) return required ? Error.Invalid("", "required") : "";
        if (text.Length > max) return Error.Invalid("", "too_long");
        if (HasUnsafeCharacters(text)) return Error.Invalid("", "invalid_characters");
        return text;
    }
}
