# Remi

Hocaların ders gruplarını tutan ve her dersten önce hatırlatan iOS uygulaması. Grup merkezli: grup bir kez
girilir (ad, renk, WhatsApp/Telegram bağlantısı, günler, saat, hatırlatma), dersler her hafta kendiliğinden gelir.
Türkçe, İngilizce ve Arapça (sağdan sola). Backend: [`backend/`](backend/README.md).

## Ekranlar

- **Açılış ve giriş:** Remi moru zemin, logo, dil seçici (TR / EN / ع), Apple ile, Google ile ya da girişsiz devam.
  Sunucu adresi yoksa yalnız girişsiz kullanım görünür.
- **Kişiselleştir:** dil, hitap, uygulama rengi (6), görünüm (otomatik / açık / koyu); seçtikçe ekran değişir.
- **Bugün:** minimal hafta şeridi, günün özeti (ders · saat · ilk–son), "Güzel haber: bu sabah/akşam boşsun",
  sıradaki ders (ping noktası, grubu aç), ders listesi, tatil etiketi.
- **Tatil modu:** hoca tatildeyken ana sayfa uyur; "Tatilden geldim" ile uyanır. Bitiş tarihi geçince kendiliğinden uyanır.
- **+ menüsü:** Hızlı grup (ad, gün, saat), Yeni grup (tüm ayarlar), Tatil gir (ben ya da seçili gruplar).
- **Program:** gruplar ya da hafta görünümü; Excel indir ve yazdır.
- **Grup:** WhatsApp/Telegram grubunu aç, yerinde hatırlatma tekerleği ve tatil, sıradaki dersler, sil.
- **Profil:** hesap ve yedek durumu, dil, görünüm, renk, varsayılan hatırlatma, "Ben tatildeyim", deneme bildirimi,
  çıkış, hesabı silme.

Formlar üst üste açılmaz; yatay kaydırma yoktur; hatırlatma süresi tekerlekle seçilir (0–60 dk ya da 1–12 saat).

## Hatırlatmalar

- Tatili olmayan gruplar haftalık tekrar eden bildirimle kurulur; uygulama açılmasa da çalışır.
- Grubun ya da hocanın tatili varsa önümüzdeki 21 gün tek tek kurulur, tatil günleri atlanır; tatil bitiminde
  "Hatırlatmalar yeniden açık" bildirimi gelir.
- Alarm seçilen gruplar iOS 26+ AlarmKit ile tam ekran alarm olarak çalar; eski iOS'ta bildirim gönderilir.
- iOS en fazla 64 bekleyen bildirim tutar; çok kalabalık programda en yakın 7 gün kurulur ve açılışta yenilenir.

## Veri ve güvenlik

- Uygulama çevrimdışı çalışır; veri telefonda şifreli dosya korumasıyla saklanır.
- Giriş yapılırsa değişiklikler sunucuya gönderilir ve diğer cihazlardan gelenler çekilir (sürüm çakışmasında
  sunucudaki hal kazanır). Yenileme anahtarı Keychain'de (yalnız bu cihaz), erişim anahtarı yalnız bellekte.
- Apple girişinde her seferinde yeni nonce; Google girişi SDK'sız, PKCE ve `state` kontrolüyle.
- Grup adı ve bağlantı kuralları sunucudakiyle aynıdır (yalnız https WhatsApp/Telegram grup adresleri).
- Release'te API yalnız https ile çalışır; ATS yalnız yerel ağ için gevşek.

## Yapı

```
Remi/
  App/            Giriş noktası, kök akış, Debug demo modu
  Core/           Modeller, kurallar, günlük plan, TR/EN/AR metinler
  Data/           AppStore (tek veri kaynağı, eşitleme kuyruğu), Keychain
  Services/       Hatırlatmalar, API istemcisi, Apple/Google girişi, eşitleme, Excel, yazdırma
  DesignSystem/   Marka renkleri, logo, ortak bileşenler, hatırlatma tekerleği
  Features/       Ekranlar
  Resources/      Assets, Bricolage Grotesque (OFL)
Config/Info.plist RemiAPIBaseURL, GoogleClientID, yazı tipi, ATS
Tests/            Çekirdek testleri (Xcode'suz) + Excel doğrulaması
tools/make_icon.swift  Uygulama ikonu
```

Ayarlar (`project.pbxproj`): `REMI_API_BASE_URL` (Debug: `http://localhost:8080`, Release: boş) ve
`GOOGLE_CLIENT_ID` (boşsa Google girişi gizli). Sunucu yayına alınınca Release adresi doldurulur.

## Geliştirme

```sh
./Tests/run.sh                    # kurallar, günlük plan, metinler, Excel (openpyxl gerekir)
swift tools/make_icon.swift Remi/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Debug derlemesinde demo modu (örnek veriyle doğrudan bir ekran, veri diske yazılmaz):
`SIMCTL_CHILD_REMI_DEMO=1 SIMCTL_CHILD_REMI_SCREEN=today SIMCTL_CHILD_REMI_LANG=ar SIMCTL_CHILD_REMI_THEME=dark xcrun simctl launch <cihaz> com.niloya.remi`
(ekranlar: today, program, week, group, export, profile, menu, quick, new, edit, vacation, sleep, login, personalize, empty).

## TestFlight

1. Apple Developer üyeliği (yıllık ücretli) ve Xcode → Settings → Accounts'a hesap.
2. Projeye ekip ve **Sign in with Apple** yeteneği eklenir; `com.niloya.remi` kaydedilir.
3. App Store Connect'te uygulama oluşturulur, Xcode → Product → Archive → Distribute App ile yüklenir.
4. TestFlight → İç Test grubuna test kullanıcısı eklenir; telefona TestFlight'tan kurulur.
