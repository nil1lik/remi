namespace Remi.Infrastructure.Identity;

public sealed class AuthOptions
{
    public const string Section = "Auth";

    /// <summary>Erişim anahtarlarını imzalayan gizli anahtar (base64, en az 32 bayt). Ortam değişkeninden gelir: Auth__SigningKey.</summary>
    public string SigningKey { get; set; } = "";
    public string Issuer { get; set; } = "remi-api";
    public string Audience { get; set; } = "remi-app";
    public int AccessTokenMinutes { get; set; } = 15;
    public int RefreshTokenDays { get; set; } = 60;

    public ProviderOptions Apple { get; set; } = new()
    {
        Authority = "https://appleid.apple.com",
        Issuers = ["https://appleid.apple.com"],
        ClientIds = ["com.niloya.remi"],
    };

    public ProviderOptions Google { get; set; } = new()
    {
        Authority = "https://accounts.google.com",
        Issuers = ["https://accounts.google.com", "accounts.google.com"],
        ClientIds = [],
    };

    public byte[] SigningKeyBytes()
    {
        byte[] key;
        try { key = Convert.FromBase64String(SigningKey); }
        catch (FormatException) { throw new InvalidOperationException("Auth:SigningKey base64 olmalı."); }
        if (key.Length < 32) throw new InvalidOperationException("Auth:SigningKey en az 32 bayt (256 bit) olmalı.");
        return key;
    }
}

public sealed class ProviderOptions
{
    /// <summary>OpenID yapılandırmasının ve imza anahtarlarının alındığı adres.</summary>
    public string Authority { get; set; } = "";
    public string[] Issuers { get; set; } = [];
    /// <summary>Kabul edilen "aud" değerleri: Apple için paket kimliği, Google için iOS istemci kimliği.</summary>
    public string[] ClientIds { get; set; } = [];
}
