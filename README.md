# Remi

Önemli şeyleri zamanında hatırlatan iOS uygulaması. İlk özelliği **ders programı**: program Excel'de
hazırlanır, uygulamaya yüklenir; Remi günün derslerini gösterir ve her dersten önce bildirim ya da alarm kurar.
Yapı yeni hatırlatma kaynaklarına (tek seferlik hatırlatmalar, rutinler, başka tablo türleri) açık tutuldu.

## Özellikler

- **Bugün ekranı:** haftalık gün şeridi (sola/sağa kaydırınca hafta değişir), "Şu an / Sıradaki" kartı, renkli kartlar.
- **Açılış animasyonu:** çalan zil, dalgalanan halkalar, harf harf gelen "Remi" (Hareketi Azalt açıksa kısa geçiş).
- **Elle program:** "+" ile ders ekle (grup adı, birden çok gün ya da tek seferlik tarih, saat, süre kısayolları,
  yer, not); yazdıkça güncellenen önizleme kartı, kayıtlı grup önerileri, çakışma uyarısı. "Haftalık program"
  ekranında gün gün düzenleme ve kaydırarak silme; ders detayında "Düzenle".
- **Excel ile içe aktarma:** "Örnek Excel'i indir" → doldur → "Excel'den içe aktar". Dosya WhatsApp, Mail ya da
  Dosyalar'dan "Paylaş → Remi" ile de açılabilir. Önce önizleme gösterilir, okunamayan satırlar satır numarasıyla listelenir.
  Program doluysa "Mevcut programa ekle" (elle girilenler kalır, aynı kayıt tekrar eklenmez) ya da "Programın yerine geçsin".
- **Hatırlatma:** kaç dakika önce (0–120 dk) ve tür (Bildirim / Alarm) Ayarlar'dan; istenirse tek bir kayda özel ayar.
  - *Bildirim:* kilit ekranında bildirim ve ses.
  - *Alarm:* iOS 26+ AlarmKit; Saat uygulamasındaki alarm gibi tam ekran, sessiz modda da çalar. Eski iOS'ta bildirim gönderilir.
- Hesap, sunucu, internet yok; veriler telefonda kalır.

## Ders programı Excel biçimi

| Grup / Sınıf | Günler | Saat | Yer | Not | Tarih (tek seferlik) |
|---|---|---|---|---|---|
| A1-20 sınıfı | Perşembe Cmt | 09.00-10.00 | Salon 2 | | |
| A2-14 | Pazartesi, Çarşamba | 17.30-19.00 | Online | Zoom linki grupta | |
| Seviye sınavı | | 10.00-11.30 | Salon 1 | | 07.11.2026 |

- Başlıklar esnek ("Sınıf", "Grup", "Gün", "Başlangıç", "Bitiş" de tanınır), sütun sırası serbest.
- Günler: "Perşembe Cmt", "Pzt, Çar", "Pazartesi-Cuma", "Salı ve Perşembe". Saat: "09.00-10.00", "09:00", Excel saat hücresi.
- Tarih dolu satır yalnız o gün geçerli; tarihi boş satırlar her hafta tekrarlanır. CSV de okunur.

## TestFlight ile telefona kurulum

Remi App Store'da herkese açık yayınlanmaz; TestFlight ile yalnız davet edilen kişiler kurar.
Her yüklenen sürüm 90 gün çalışır; süre dolmadan yeni sürüm yüklenir.

1. **Apple Developer üyeliği** (yıllık ücretli): iPhone'da App Store'dan *Apple Developer* uygulaması →
   Hesap → Şimdi Kaydol → Birey. Onay e-postası gelince devam.
2. **Xcode'a hesabı ekle:** Xcode → Settings → Accounts → **+** → Apple Account.
3. **Paket kimliğini kaydettir:** `com.niloya.remi` imzalı bir derlemeyle Apple'a kaydedilir.
4. **App Store Connect kaydı:** appstoreconnect.apple.com → Uygulamalar → **+** → Yeni Uygulama →
   iOS, ad "Remi" (alınmışsa "Remi: Smart Reminders"), dil Türkçe, paket kimliği `com.niloya.remi`, SKU `remi`.
5. **Yükleme:** Xcode → Product → Archive → Distribute App → App Store Connect.
6. **Test kullanıcısı:** App Store Connect → Kullanıcılar ve Erişim → kişiyi davet et → uygulamanın TestFlight
   sekmesi → İç Test → grup aç → kişiyi ekle.
7. **Telefonda:** davet e-postasını kabul et → App Store'dan *TestFlight*'ı kur → Remi → Yükle.

## Geliştirme

```
Remi/
  App/         Uygulama girişi, bildirim delegesi
  Models/      Lesson, ReminderSettings, ScheduleStore (JSON ile kalıcı)
  Services/    XLSXReader (bağımlılıksız .xlsx okuyucu), ScheduleImporter, ReminderScheduler
  Views/       Bugün, kayıt detayı, ayarlar, içe aktarma önizlemesi
  Resources/   Assets, Ders-Programi-Sablon.xlsx
Config/Info.plist  Alarm izni metni, xlsx/csv dosya türü kaydı, şifreleme beyanı
tools/             Şablon ve ikon üreticiler
Tests/             Xcode'suz içe aktarma testleri
```

- Şablon: `python3 tools/make_template.py`. İçe aktarma testleri: `./Tests/run.sh`.
- iOS en fazla 64 bekleyen bildirim tutar. 60 haftalık kaydı geçen programda önümüzdeki 7 günün hatırlatmaları
  kurulur ve uygulama her açıldığında yenilenir; daha küçük programlarda haftalık tekrarlıdır.
