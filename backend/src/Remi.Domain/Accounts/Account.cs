using Remi.Domain.Common;

namespace Remi.Domain.Accounts;

/// <summary>
/// Hocanın hesabı: giriş kimlikleri, kişiselleştirme ve "Ben tatildeyim".
/// Hesaptaki ve gruplarındaki her değişiklik hesabın revizyon sayacını bir artırır; cihazlar bu sayaçla eşitlenir.
/// </summary>
public sealed class Account : AggregateRoot<AccountId>
{
    private readonly List<AccountLogin> _logins = [];
    private DateOnly? _vacationStart;
    private DateOnly? _vacationEnd;

    public DisplayName DisplayName { get; private set; } = DisplayName.Empty;
    public Preferences Preferences { get; private set; } = Preferences.Default(Locale.Tr);
    public DateRange? Vacation => DateRange.Restore(_vacationStart, _vacationEnd);

    /// <summary>Hesabın ve gruplarının son değişiklik numarası.</summary>
    public long Revision { get; private set; }
    /// <summary>Profilin (ad, tercihler, tatil) son değiştiği revizyon.</summary>
    public long ProfileRevision { get; private set; }
    public DateTimeOffset CreatedAt { get; private init; }

    public IReadOnlyList<AccountLogin> Logins => _logins;

    private Account() { }

    public static Account Register(ExternalIdentity identity, DisplayName name, Locale locale, DateTimeOffset now)
    {
        var account = new Account
        {
            Id = AccountId.New(),
            DisplayName = name,
            Preferences = Preferences.Default(locale),
            CreatedAt = now,
        };
        account._logins.Add(new AccountLogin(identity, now));
        account.ProfileRevision = account.NextRevision();
        return account;
    }

    /// <summary>Her değişiklik yeni bir revizyon alır; grup değişiklikleri de buradan numara çeker.</summary>
    public long NextRevision() => ++Revision;

    public void RecordSignIn(ExternalIdentity identity, DateTimeOffset now) =>
        _logins.Single(l => l.Provider == identity.Provider && l.Subject == identity.Subject).Touch(now);

    public void Personalize(DisplayName? name, Preferences preferences)
    {
        if (name is not null) DisplayName = name;
        Preferences = preferences;
        ProfileRevision = NextRevision();
    }

    /// <summary>"Ben tatildeyim": aralık boyunca tüm grupların hatırlatmaları susar.</summary>
    public void StartVacation(DateRange range)
    {
        (_vacationStart, _vacationEnd) = (range.Start, range.End);
        ProfileRevision = NextRevision();
    }

    /// <summary>"Tatilden geldim".</summary>
    public void EndVacation()
    {
        (_vacationStart, _vacationEnd) = (null, null);
        ProfileRevision = NextRevision();
    }

    public bool IsOnVacation(DateOnly day) => Vacation?.Contains(day) == true;
}

/// <summary>Hesaba bağlı bir giriş yolu (Apple ya da Google).</summary>
public sealed class AccountLogin
{
    public IdentityProvider Provider { get; private init; }
    public string Subject { get; private init; } = "";
    public DateTimeOffset CreatedAt { get; private init; }
    public DateTimeOffset LastUsedAt { get; private set; }

    private AccountLogin() { }

    internal AccountLogin(ExternalIdentity identity, DateTimeOffset now) =>
        (Provider, Subject, CreatedAt, LastUsedAt) = (identity.Provider, identity.Subject, now, now);

    internal void Touch(DateTimeOffset now) => LastUsedAt = now;
}
