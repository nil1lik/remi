namespace Remi.Domain.Common;

public enum ErrorKind
{
    /// <summary>Girdi bir iş kuralına uymuyor (alan bazlı).</summary>
    Validation,
    /// <summary>Kayıt bulunamadı ya da isteyene ait değil.</summary>
    NotFound,
    /// <summary>Eşzamanlı değişiklik ya da çakışan kimlik.</summary>
    Conflict,
    /// <summary>İşlem kurala aykırı (ör. grup sınırı).</summary>
    Rule,
    /// <summary>Kimlik doğrulanamadı.</summary>
    Unauthorized,
}

/// <param name="Code">İstemcinin anlayacağı sabit kod (ör. "too_long").</param>
/// <param name="Field">Hatanın ait olduğu alan (doğrulama hatalarında).</param>
/// <param name="Details">İsteğe bağlı ek bilgi (ör. çakışmada güncel kayıt).</param>
public sealed record Error(ErrorKind Kind, string Code, string? Field = null, object? Details = null)
{
    public static Error Invalid(string field, string code) => new(ErrorKind.Validation, code, field);
    public static Error NotFound(string code = "not_found") => new(ErrorKind.NotFound, code);
    public static Error Conflict(string code, object? details = null) => new(ErrorKind.Conflict, code, Details: details);
    public static Error Rule(string code) => new(ErrorKind.Rule, code);
    public static Error Unauthorized(string code) => new(ErrorKind.Unauthorized, code);

    public Error At(string field) => this with { Field = field };
}

/// <summary>Başarı ya da bir/çok hata. İş kuralı ihlalleri istisna (exception) yerine bununla döner.</summary>
public class Result
{
    private static readonly Result SuccessInstance = new([]);
    public IReadOnlyList<Error> Errors { get; }
    public bool IsSuccess => Errors.Count == 0;

    protected Result(IReadOnlyList<Error> errors) => Errors = errors;

    public static Result Success() => SuccessInstance;
    public static Result Failure(params Error[] errors) => new(errors);
    public static Result<T> Success<T>(T value) => new(value, []);
    public static Result<T> Failure<T>(params Error[] errors) => new(default, errors);

    public static implicit operator Result(Error error) => new([error]);
}

public sealed class Result<T> : Result
{
    private readonly T? _value;

    internal Result(T? value, IReadOnlyList<Error> errors) : base(errors) => _value = value;

    public T Value => IsSuccess ? _value! : throw new InvalidOperationException("Başarısız sonucun değeri okunamaz.");

    public static implicit operator Result<T>(T value) => new(value, []);
    public static implicit operator Result<T>(Error error) => new(default, [error]);

    public Result<TOut> Map<TOut>(Func<T, TOut> map) => IsSuccess ? map(Value) : new Result<TOut>(default, Errors);
}

/// <summary>Birden çok value object oluştururken hataları toplar; hepsi birden istemciye döner.</summary>
public sealed class ErrorCollector
{
    private readonly List<Error> _errors = [];
    public bool HasErrors => _errors.Count > 0;
    public IReadOnlyList<Error> Errors => _errors;

    /// <summary>Sonuç başarılıysa değeri verir; değilse hataları alan adıyla kaydeder.</summary>
    public T? Take<T>(Result<T> result, string field)
    {
        if (result.IsSuccess) return result.Value;
        _errors.AddRange(result.Errors.Select(e => string.IsNullOrEmpty(e.Field) ? e.At(field) : e));
        return default;
    }

    public void Add(Error error) => _errors.Add(error);
}
