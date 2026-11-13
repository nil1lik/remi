# Remi API

Remi'nin backend'i: Apple/Google ile giriş, profil ve tercihler, ders gruplarının yedeklenmesi ve
cihazlar arası eşitleme. Hatırlatmalar telefonda kurulur; sunucu yalnız veriyi saklar.

.NET 10 · ASP.NET Core Minimal API · EF Core 10 · PostgreSQL 17

## Mimari (DDD, katmanlı)

```
src/
  Remi.Domain           İş modeli. Hiçbir pakete bağımlı değil.
    Accounts/           Account (aggregate): giriş kimlikleri, tercihler, "Ben tatildeyim", revizyon sayacı
    Groups/             Group (aggregate): ad, renk, sohbet bağlantısı, haftalık saat, hatırlatma, tatil, sürüm
    Sessions/           RefreshToken: döndürme ve çalınma tespiti
    Common/             Result/Error, DateRange, Reminder, ortak kurallar
  Remi.Application      Kullanım senaryoları ve port arayüzleri
    Auth/AuthService           giriş, anahtar yenileme, çıkış
    Accounts/AccountService    profil, kişiselleştirme, tatil, hesap silme
    Groups/GroupService        grup işlemleri, eşitleme
    Abstractions/Ports.cs      repository, unit of work, kimlik doğrulayıcı, anahtar üretici
  Remi.Infrastructure   Portların gerçekleri
    Persistence/        EF Core eşlemeleri, repository'ler, göçler
    Identity/           Apple/Google id_token doğrulama (OIDC/JWKS), JWT üretimi
  Remi.Api              Yalnız HTTP: güvenlik ayarları, uçlar, Result → HTTP yanıtı
tests/
  Remi.Domain.Tests     Value object ve aggregate kuralları (veritabanısız)
  Remi.Api.Tests        Uçtan uca HTTP testleri (bellek içi SQLite, sahte kimlik sağlayıcı)
```

Bağımlılık yönü: `Api → Application → Domain`, `Infrastructure → Application → Domain`.
Kurallar value object'lerin içindedir ve her yerde aynıdır:

| Value object | Kural |
|---|---|
| `GroupName` | 1–60 karakter, kontrol ve yön değiştiren (bidi) karakter yok |
| `ChatLink` | Yalnız `https://chat.whatsapp.com/…`, `https://t.me/…`, `https://telegram.me/…`; kullanıcı adı, port, `?`, `#` yok |
| `WeeklySchedule` | En az bir gün, 00:00–23:59 başlangıç, 15–600 dk, gece yarısını geçmez |
| `Reminder` | 0–60 dk (5'er) ya da 1–12 saat önce; bildirim ya da alarm |
| `DateRange` | Başlangıç ≤ bitiş, en fazla 366 gün (grup tatili, hocanın tatili) |
| `DisplayName` | En fazla 40 karakter |

## Uçlar

| Yöntem | Yol | Açıklama |
|---|---|---|
| POST | `/v1/auth/apple`, `/v1/auth/google` | `{ idToken, nonce, displayName?, locale? }` → erişim + yenileme anahtarı + profil |
| POST | `/v1/auth/refresh` | `{ refreshToken }` → yeni anahtar çifti (eski anahtar geçersizleşir) |
| POST | `/v1/auth/logout` | `{ refreshToken }` → oturumu kapatır |
| GET / PATCH | `/v1/me` | Profil; dil, tema, renk, varsayılan hatırlatma |
| PUT / DELETE | `/v1/me/vacation` | "Ben tatildeyim" `{ start, end }` / "Tatilden geldim" |
| DELETE | `/v1/me` | Hesabı ve tüm verisini kalıcı siler (App Store şartı) |
| GET / POST | `/v1/groups` | Grupları listele / ekle (istemci kendi kimliğini gönderebilir) |
| PUT / DELETE | `/v1/groups/{id}` | Güncelle (`version` zorunlu) / sil (`?version=` isteğe bağlı) |
| GET | `/v1/sync?since=N` | `N` revizyonundan sonraki değişiklikler (silinenler dahil) ve yeni `cursor` |

Hatalar `application/problem+json`: doğrulamada alan → kod listesi (`{"chatLink":["unsupported_link"]}`),
diğerlerinde `title` sabit kod (`version_mismatch`, `id_unavailable`, `group_limit_reached`…). Sürüm
çakışmasında güncel kayıt `current` alanında döner.

## Güvenlik

- **Giriş:** Apple/Google `id_token` imzası sağlayıcının yayımladığı anahtarlarla (JWKS) doğrulanır; yalnız RS256,
  `iss`, `aud` (paket kimliği / iOS istemci kimliği), süre ve Apple'da zorunlu `nonce` (tekrar oynatmaya karşı)
  kontrol edilir. Şifre tutulmaz.
- **Erişim anahtarı:** 15 dakika, HMAC-SHA256, yalnız hesap kimliği içerir. `alg: none`, başka anahtarla imzalı
  ya da süresi geçmiş belge reddedilir. Hesap silinmişse geçerli anahtar da işe yaramaz.
- **Yenileme anahtarı:** 256 bit rastgele; veritabanında yalnız SHA-256 özeti. Her kullanımda yenilenir; kullanılmış
  anahtar tekrar gelirse ya da iki istek aynı anahtarla yarışırsa oturumun tüm anahtarları iptal edilir.
- **Veri ayrımı:** Her işlem hesabın kendi verisine bakar; başkasının grubu "yok" (404) görünür, kime ait olduğu sızmaz.
- **Girdi:** Tüm alanlar sunucuda value object'lerle doğrulanır; istemci kontrolüne güvenilmez.
- **Kötüye kullanım:** Giriş uçlarında IP başına dakikada 10, diğerlerinde hesap başına dakikada 300 istek;
  istek gövdesi en fazla 32 KB; hesap başına en fazla 200 grup.
- **Yanıtlar:** `nosniff`, `X-Frame-Options: DENY`, `no-referrer`, `Cache-Control: no-store`, katı CSP, üretimde
  HSTS; sunucu adı gizli, hata yanıtlarında iç ayrıntı yok, kimlik belgeleri loglanmaz.
- **Gizli değerler:** İmza anahtarı ve veritabanı şifresi depoda değil, ortam değişkeninde. İmza anahtarı yoksa
  ya da 32 bayttan kısaysa uygulama açılmaz.
- **Konteyner:** Yetkisiz kullanıcı, salt okunur dosya sistemi, tüm Linux yetkileri kapalı; veritabanı ve API
  yalnız `127.0.0.1`'e açık (dışarıya bir HTTPS vekil sunucusu üzerinden açılır).

## Çalıştırma

```sh
# Testler (Docker gerekmez)
dotnet test

# Yerel PostgreSQL + API (Docker)
cp .env.example .env          # POSTGRES_PASSWORD ve AUTH_SIGNING_KEY doldur
docker compose up -d --build
curl http://127.0.0.1:8080/health

# Şema değişikliği sonrası yeni göç
dotnet tool restore
dotnet ef migrations add <Ad> --project src/Remi.Infrastructure --startup-project src/Remi.Infrastructure --output-dir Persistence/Migrations
```

Üretimde API bir HTTPS vekil sunucusunun (Caddy/nginx) arkasında çalışır; vekilin IP'si
`Network__KnownProxies__0` ile verilir ki hız sınırı gerçek istemci IP'sine göre işlesin.

## Açık işler

- Hesap silmede Apple oturumunun da iptali (`appleid.apple.com/auth/revoke`): Apple Developer anahtarı gerekiyor.
- Silinmiş grup izlerinin 90 gün sonra temizlenmesi (zamanlanmış görev).
- iOS uygulamasının bu API'ye bağlanması (giriş ekranı, eşitleme, anahtarların Keychain'de saklanması).
