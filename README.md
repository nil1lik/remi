# Ders Programı (iOS)

Öğretmen için haftalık grup/ders programı. Program Excel'de hazırlanır, uygulamaya yüklenir;
uygulama günün derslerini gösterir ve her dersten önce bildirim ya da alarm kurar.

## Özellikler

- **Bugün ekranı:** haftalık gün şeridi (sola/sağa kaydırınca hafta değişir), "Şu an / Sıradaki" kartı, renkli grup kartları.
- **Excel ile içe aktarma:** uygulamadaki "Örnek Excel'i indir" ile şablon alınır, doldurulur, "Excel'den içe aktar" ile geri yüklenir.
  Dosya WhatsApp, Mail ya da Dosyalar'dan "Paylaş → Ders Programı" ile de açılabilir. Yüklemeden önce önizleme gösterilir, okunamayan satırlar satır numarasıyla listelenir.
- **Hatırlatma:** kaç dakika önce (0–120 dk) ve tür (Bildirim / Alarm) Ayarlar'dan seçilir; istenirse tek bir gruba özel ayar yapılabilir.
  - *Bildirim:* kilit ekranında bildirim ve ses.
  - *Alarm:* iOS 26'daki AlarmKit ile Saat uygulamasındaki alarm gibi tam ekran çalar, sessiz modda da duyulur. iOS 26'dan eski telefonlarda bildirim gönderilir.
- İnternet, hesap ya da sunucu yok; her şey telefonda kalır.

## Excel biçimi

| Grup / Sınıf | Günler | Saat | Yer | Not | Tarih (tek seferlik) |
|---|---|---|---|---|---|
| A1-20 sınıfı | Perşembe Cmt | 09.00-10.00 | Salon 2 | | |
| A2-14 | Pazartesi, Çarşamba | 17.30-19.00 | Online | Zoom linki grupta | |
| Seviye sınavı | | 10.00-11.30 | Salon 1 | | 07.11.2026 |

- Sütun sırası ve başlıkların tam yazımı esnek: "Sınıf", "Grup", "Gün", "Başlangıç", "Bitiş" gibi başlıklar da tanınır.
- Günler: "Perşembe Cmt", "Pzt, Çar", "Pazartesi-Cuma", "Salı ve Perşembe" biçimleri olur.
- Saat: "09.00-10.00", "09:00", "9.30" ya da Excel'in saat hücresi olur. Ayrı "Bitiş" sütunu da olabilir.
- Tarih dolu satır yalnız o gün için geçerlidir; tarihi boş satırlar her hafta tekrarlanır.
- CSV (Türkçe Excel'in `;` ayraçlı CSV'si dahil) de okunur.

## Telefona kurulum

1. Mac'e App Store'dan **Xcode 26** kur, bir kez açıp ek bileşenleri (iOS) indir.
2. `DersProgrami.xcodeproj` dosyasını aç.
3. Sol üstte **DersProgrami** projesi → **Signing & Capabilities** → *Team* olarak Apple ID'ni seç
   (Xcode → Settings → Accounts'tan eklenir). Bundle ID çakışırsa `com.niloya.dersprogrami` değerini değiştir.
4. iPhone'u kabloyla bağla; telefonda **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu**'nu aç.
5. Xcode'da üstten cihaz olarak iPhone'u seç, **▶︎ Run**.
6. İlk açılışta telefonda **Ayarlar → Genel → VPN ve Cihaz Yönetimi**'nden geliştiriciye güven.

> Ücretsiz Apple ID ile yüklenen uygulama 7 gün sonra açılmaz olur; Xcode'dan tekrar Run yapmak yeter.
> Kalıcı kurulum ya da kardeşinin kendi telefonuna uzaktan dağıtım için Apple Developer Program (yıllık ücretli) + TestFlight gerekir.

## Geliştirme

```
DersProgrami/
  App/         Uygulama girişi, bildirim delegesi
  Models/      Lesson, ReminderSettings, ScheduleStore (JSON ile kalıcı)
  Services/    XLSXReader (bağımlılıksız .xlsx okuyucu), ScheduleImporter, ReminderScheduler
  Views/       Bugün, grup detayı, ayarlar, içe aktarma önizlemesi
  Resources/   Assets, Ders-Programi-Sablon.xlsx
Config/Info.plist  Alarm izni metni, xlsx/csv dosya türü kaydı
tools/             Şablon ve ikon üreticiler
Tests/             Xcode'suz içe aktarma testleri
```

- Şablonu değiştirmek için `tools/make_template.py` düzenlenir, `python3 tools/make_template.py` çalıştırılır.
- İçe aktarma testleri (Xcode gerekmez): `./Tests/run.sh` (openpyxl kuruluysa gerçek Excel benzeri dosyayla da dener).
- iOS 64 bekleyen bildirimle sınırlıdır. 60 haftalık dersi geçen programda önümüzdeki 7 günün hatırlatmaları kurulur
  ve uygulama her açıldığında yenilenir. Daha küçük programlarda hatırlatmalar haftalık tekrarlıdır, uygulamayı açmak gerekmez.
