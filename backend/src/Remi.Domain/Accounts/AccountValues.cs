using Remi.Domain.Common;

namespace Remi.Domain.Accounts;

public readonly record struct AccountId(Guid Value)
{
    public static AccountId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}

/// <summary>Kullanıcıya nasıl seslenileceği ("Hocam"). Boş olabilir.</summary>
public sealed record DisplayName
{
    public const int MaxLength = 40;
    public static readonly DisplayName Empty = new("");

    public string Value { get; }
    private DisplayName(string value) => Value = value;

    public static Result<DisplayName> Create(string? value) => Text.Clean(value, MaxLength, required: false).Map(v => new DisplayName(v));
    public static DisplayName Restore(string value) => new(value);
    public override string ToString() => Value;
}

public enum Locale { Tr, En, Ar }
public enum Theme { System, Light, Dark }
public enum Accent { Violet, Mint, Coral, Rose, Amber, Ocean }

/// <summary>Kişiselleştirme: dil, tema, uygulama rengi ve yeni gruplar için varsayılan hatırlatma.</summary>
public sealed record Preferences(Locale Locale, Theme Theme, Accent Accent, Reminder DefaultReminder)
{
    /// <summary>Yalnız veritabanından okurken (gömülü tip kurucuya parametre olarak verilemiyor).</summary>
    private Preferences() : this(Locale.Tr, Theme.System, Accent.Violet, Reminder.Default) { }

    public static Preferences Default(Locale locale) => new(locale, Theme.System, Accent.Violet, Reminder.Default);
}

public enum IdentityProvider { Apple, Google }

/// <summary>Dış sağlayıcıdaki kalıcı kimlik (id_token "sub"). Aynı "sub" farklı sağlayıcıda farklı kişidir.</summary>
public sealed record ExternalIdentity
{
    public const int MaxSubjectLength = 255;

    public IdentityProvider Provider { get; }
    public string Subject { get; }

    private ExternalIdentity(IdentityProvider provider, string subject) => (Provider, Subject) = (provider, subject);

    public static Result<ExternalIdentity> Create(IdentityProvider provider, string? subject) =>
        string.IsNullOrEmpty(subject) || subject.Length > MaxSubjectLength || Text.HasUnsafeCharacters(subject)
            ? Error.Unauthorized("invalid_identity_token")
            : new ExternalIdentity(provider, subject);
}
