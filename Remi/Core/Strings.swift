import SwiftUI

/// Uygulama içi metinler (TR / EN / AR). Dil uygulamanın içinden seçildiği için sistem diline bağlı değildir.
struct Strings {
    let language: AppLanguage

    private func t(_ tr: String, _ en: String, _ ar: String) -> String {
        switch language {
        case .tr: tr
        case .en: en
        case .ar: ar
        }
    }

    var locale: Locale { language.locale }

    // MARK: Biçimlendirme

    /// Sayılar Arapçada Arapça rakamla yazılır.
    func number(_ value: Int) -> String {
        let f = NumberFormatter()
        f.locale = locale
        return f.string(from: value as NSNumber) ?? "\(value)"
    }

    func decimal(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.maximumFractionDigits = 1
        return f.string(from: value as NSNumber) ?? "\(value)"
    }

    func clock(_ minuteOfDay: Int) -> String { digits(minuteOfDay.clock) }

    /// Metindeki 0–9 rakamlarını dilin rakamlarına çevirir (Arapçada ٠–٩).
    func digits(_ text: String) -> String {
        guard language == .ar else { return text }
        let arabic = Array("٠١٢٣٤٥٦٧٨٩")
        return String(text.map { c in c.wholeNumberValue.map { arabic[$0] } ?? c })
    }

    func timeRange(_ start: Int, _ end: Int) -> String { "\(clock(start)) – \(clock(end))" }

    func date(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = .remi
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    func duration(_ minutes: Int) -> String {
        if minutes < 60 { return t("\(number(minutes)) dk", "\(number(minutes)) min", "\(number(minutes)) د") }
        let hours = Double(minutes) / 60
        return t("\(decimal(hours)) sa", "\(decimal(hours)) h", "\(decimal(hours)) س")
    }

    func reminderShort(_ r: ReminderSetting) -> String {
        let m = r.minutesBefore
        if m == 0 { return t("Ders başlarken", "When it starts", "عند البدء") }
        if m < 60 { return t("\(number(m)) dk önce", "\(number(m)) min before", "قبل \(number(m)) دقيقة") }
        if m == 60 { return t("1 sa önce", "1 h before", "قبل ساعة") }
        return t("\(number(m / 60)) sa önce", "\(number(m / 60)) h before", "قبل \(number(m / 60)) ساعات")
    }

    func kind(_ k: ReminderKind) -> String { k == .notification ? notification : alarm }

    // MARK: Günler

    func weekdayName(_ d: Weekday) -> String {
        switch d {
        case .monday: t("Pazartesi", "Monday", "الاثنين")
        case .tuesday: t("Salı", "Tuesday", "الثلاثاء")
        case .wednesday: t("Çarşamba", "Wednesday", "الأربعاء")
        case .thursday: t("Perşembe", "Thursday", "الخميس")
        case .friday: t("Cuma", "Friday", "الجمعة")
        case .saturday: t("Cumartesi", "Saturday", "السبت")
        case .sunday: t("Pazar", "Sunday", "الأحد")
        }
    }

    func weekdayShort(_ d: Weekday) -> String {
        switch d {
        case .monday: t("Pzt", "Mon", "ن")
        case .tuesday: t("Sal", "Tue", "ث")
        case .wednesday: t("Çar", "Wed", "ر")
        case .thursday: t("Per", "Thu", "خ")
        case .friday: t("Cum", "Fri", "ج")
        case .saturday: t("Cmt", "Sat", "س")
        case .sunday: t("Paz", "Sun", "ح")
        }
    }

    func weekdayLetter(_ d: Weekday) -> String {
        switch d {
        case .monday: t("P", "M", "ن")
        case .tuesday: t("S", "T", "ث")
        case .wednesday: t("Ç", "W", "ر")
        case .thursday: t("P", "T", "خ")
        case .friday: t("C", "F", "ج")
        case .saturday: t("C", "S", "س")
        case .sunday: t("P", "S", "ح")
        }
    }

    func days(_ days: Set<Weekday>) -> String {
        let sorted = days.sorted()
        if sorted.count == 7 { return t("Her gün", "Every day", "كل يوم") }
        if sorted == [.monday, .tuesday, .wednesday, .thursday, .friday] { return t("Hafta içi", "Weekdays", "أيام الأسبوع") }
        if sorted == [.saturday, .sunday] { return t("Hafta sonu", "Weekends", "عطلة نهاية الأسبوع") }
        let separator = language == .ar ? "، " : ", "
        return sorted.map { sorted.count > 2 ? weekdayShort($0) : weekdayName($0) }.joined(separator: separator)
    }

    // MARK: Genel

    var cancel: String { t("Vazgeç", "Cancel", "إلغاء") }
    var close: String { t("Kapat", "Close", "إغلاق") }
    var save: String { t("Kaydet", "Save", "حفظ") }
    var edit: String { t("Düzenle", "Edit", "تعديل") }
    var delete: String { t("Sil", "Delete", "حذف") }
    var done: String { t("Bitti", "Done", "تم") }
    var all: String { t("Tümü", "All", "الكل") }
    var none: String { t("Hiçbiri", "None", "لا شيء") }
    var notification: String { t("Bildirim", "Notification", "إشعار") }
    var alarm: String { t("Alarm", "Alarm", "منبّه") }

    // MARK: Giriş ve kişiselleştirme

    var tagline: String { t("Derslerin zamanında, grupların tek yerde.", "Your lessons on time, your groups in one place.", "دروسك في وقتها، ومجموعاتك في مكان واحد.") }
    var continueApple: String { t("Apple ile devam et", "Continue with Apple", "المتابعة باستخدام Apple") }
    var continueGoogle: String { t("Google ile devam et", "Continue with Google", "المتابعة باستخدام Google") }
    var continueWithout: String { t("Giriş yapmadan devam et", "Continue without signing in", "المتابعة دون تسجيل الدخول") }
    var signInFailed: String { t("Giriş yapılamadı. Biraz sonra yeniden dene ya da giriş yapmadan devam et.", "Couldn't sign in. Try again later or continue without signing in.", "تعذّر تسجيل الدخول. حاول لاحقًا أو تابع دون تسجيل الدخول.") }
    var lastStep: String { t("Son adım", "Last step", "الخطوة الأخيرة") }
    var personalizeTitle: String { t("Remi senin\ngibi olsun.", "Make Remi\nyour own.", "اجعل ريمي\nيشبهك.") }
    var languageLabel: String { t("Dil", "Language", "اللغة") }
    var howToCall: String { t("Sana nasıl seslenelim?", "What should we call you?", "بماذا نناديك؟") }
    var namePlaceholder: String { t("ör. Hocam", "e.g. Ms. Ayşe", "مثلًا: أستاذة") }
    var yourColor: String { t("Rengin", "Your colour", "لونك") }
    var appearance: String { t("Görünüm", "Appearance", "المظهر") }
    func theme(_ m: ThemeMode) -> String {
        switch m {
        case .system: t("Otomatik", "Automatic", "تلقائي")
        case .light: t("Açık", "Light", "فاتح")
        case .dark: t("Koyu", "Dark", "داكن")
        }
    }
    func letsStart(_ name: String) -> String {
        name.isEmpty ? t("Başlayalım", "Let's start", "لنبدأ") : t("Başlayalım, \(name)", "Let's start, \(name)", "لنبدأ يا \(name)")
    }

    func accentName(_ a: AccentChoice) -> String {
        switch a {
        case .violet: t("Remi moru", "Remi violet", "بنفسجي ريمي")
        case .mint: t("Nane", "Mint", "نعناعي")
        case .coral: t("Mercan", "Coral", "مرجاني")
        case .rose: t("Gül", "Rose", "وردي")
        case .amber: t("Kehribar", "Amber", "كهرماني")
        case .ocean: t("Okyanus", "Ocean", "محيطي")
        }
    }

    func colorName(_ c: GroupColor) -> String {
        switch c {
        case .blue: t("Mavi", "Blue", "أزرق")
        case .green: t("Yeşil", "Green", "أخضر")
        case .coral: t("Mercan", "Coral", "مرجاني")
        case .rose: t("Gül", "Rose", "وردي")
        case .amber: t("Kehribar", "Amber", "كهرماني")
        case .violet: t("Mor", "Violet", "بنفسجي")
        }
    }

    // MARK: Sekmeler

    var tabToday: String { t("Bugün", "Today", "اليوم") }
    var tabProgram: String { t("Program", "Schedule", "الجدول") }
    var tabProfile: String { t("Profil", "Profile", "حسابي") }
    var quickActions: String { t("Hızlı işlem", "Quick actions", "إجراءات سريعة") }

    // MARK: Bugün

    func greeting(at date: Date, name: String) -> String {
        let hour = Calendar.remi.component(.hour, from: date)
        let base: String
        switch hour {
        case 5..<12: base = t("Günaydın", "Good morning", "صباح الخير")
        case 12..<18: base = t("İyi günler", "Good afternoon", "نهارك سعيد")
        case 18..<23: base = t("İyi akşamlar", "Good evening", "مساء الخير")
        default: base = t("İyi geceler", "Good night", "تصبح على خير")
        }
        return name.isEmpty ? base : (language == .ar ? "\(base) يا \(name)" : "\(base), \(name)")
    }

    var upNext: String { t("SIRADAKİ", "UP NEXT", "التالي") }
    var happeningNow: String { t("ŞU AN", "NOW", "الآن") }
    func startsIn(_ minutes: Int) -> String { t("\(duration(minutes)) sonra", "in \(duration(minutes))", "بعد \(duration(minutes))") }
    func endsIn(_ minutes: Int) -> String { t("Bitmesine \(duration(minutes))", "\(duration(minutes)) left", "متبقٍ \(duration(minutes))") }
    var openGroup: String { t("Grubu aç", "Open group", "افتح المجموعة") }
    func openGroup(named name: String) -> String { t("\(name) grubunu aç", "Open \(name) group", "افتح مجموعة \(name)") }
    var onHoliday: String { t("Tatilde", "On holiday", "في عطلة") }
    func holidayUntil(_ date: Date) -> String {
        let d = self.date(date, "d MMM")
        return t("Tatil bitişi: \(d)", "Holiday until \(d)", "في عطلة حتى \(d)")
    }

    func lessonCount(_ n: Int) -> String {
        switch language {
        case .tr: return n == 0 ? "Ders yok" : "\(n) ders"
        case .en: return n == 0 ? "No lessons" : n == 1 ? "1 lesson" : "\(n) lessons"
        case .ar:
            switch n {
            case 0: return "لا دروس"
            case 1: return "درس واحد"
            case 2: return "درسان"
            case 3...10: return "\(number(n)) دروس"
            default: return "\(number(n)) درسًا"
            }
        }
    }

    var statLessons: String { t("ders", "lessons", "دروس") }
    var statHours: String { t("saat", "hours", "ساعات") }
    var statRange: String { t("ilk – son ders", "first – last", "الأول – الأخير") }
    var goodNews: String { t("GÜZEL HABER", "GOOD NEWS", "خبر سار") }

    func goodNews(_ news: DayPlan.GoodNews) -> (title: String, detail: String) {
        switch news {
        case .morningFree: (t("Bu sabah boşsun", "Your morning is free", "صباحك فارغ"),
                            t("Öğlene kadar ders yok.", "No lessons before noon.", "لا دروس قبل الظهر."))
        case .eveningFree: (t("Bu akşam boşsun", "Your evening is free", "مساؤك فارغ"),
                            t("Saat 18:00'den sonra ders yok.", "No lessons after 18:00.", "لا دروس بعد \(clock(18 * 60))."))
        case .bothFree: (t("Sabah da akşam da boşsun", "Morning and evening are free", "الصباح والمساء فارغان"),
                         t("Derslerin gün ortasında.", "Your lessons are midday only.", "دروسك في منتصف اليوم فقط."))
        }
    }

    var emptyDay: String { t("Bu gün ders yok", "No lessons today", "لا دروس اليوم") }
    var emptyDayDetail: String { t("Gününün tadını çıkar.", "Enjoy your day.", "استمتع بيومك.") }
    var noGroupsTitle: String { t("Programını kur", "Set up your schedule", "أنشئ جدولك") }
    var noGroupsDetail: String { t("İlk grubunu ekle; Remi her dersten önce sana haber versin.", "Add your first group and Remi will remind you before every lesson.", "أضف مجموعتك الأولى وسيذكّرك ريمي قبل كل درس.") }
    var addFirstGroup: String { t("İlk grubu ekle", "Add first group", "أضف المجموعة الأولى") }
    var today: String { t("Bugün", "Today", "اليوم") }

    // MARK: Uyku modu

    func sleepTitle(_ name: String) -> String {
        name.isEmpty ? t("İyi tatiller", "Enjoy your holiday", "عطلة سعيدة") : t("İyi tatiller, \(name)", "Enjoy your holiday, \(name)", "عطلة سعيدة يا \(name)")
    }
    func sleepDetail(until date: Date) -> String {
        let d = self.date(date, "d MMMM")
        return t("Remi uyuyor. \(d) tarihine kadar hiçbir hatırlatma gelmeyecek.", "Remi is asleep. No reminders until \(d).", "ريمي نائم. لن تصلك أي تذكيرات حتى \(d).")
    }
    func remindersOnHold(_ n: Int) -> String { t("\(number(n)) hatırlatma bekliyor", "\(number(n)) reminders on hold", "\(number(n)) تذكيرات معلّقة") }
    var backFromVacation: String { t("Tatilden geldim", "I'm back", "عدت من العطلة") }
    var welcomeBack: String { t("Hoş geldin! Hatırlatmalar yeniden açık.", "Welcome back! Reminders are on again.", "أهلًا بعودتك! التذكيرات تعمل من جديد.") }

    // MARK: Hızlı işlem

    var quickGroup: String { t("Hızlı grup", "Quick group", "مجموعة سريعة") }
    var quickGroupDetail: String { t("Yalnız ad, günler ve saat. Gerisi otomatik.", "Just name, days and time. The rest is automatic.", "الاسم والأيام والوقت فقط. والباقي تلقائي.") }
    var newGroup: String { t("Yeni grup", "New group", "مجموعة جديدة") }
    var newGroupDetail: String { t("Tüm ayarlar: renk, bağlantı, süre, hatırlatma.", "All settings: colour, link, length, reminder.", "كل الإعدادات: اللون والرابط والمدة والتذكير.") }
    var enterVacation: String { t("Tatil gir", "Go on holiday", "بدء عطلة") }
    var enterVacationDetail: String { t("Sen ya da gruplar. Hatırlatmalar susar.", "You or some groups. Reminders go quiet.", "أنت أو بعض المجموعات. تتوقف التذكيرات.") }

    // MARK: Grup formu

    var editGroup: String { t("Grubu düzenle", "Edit group", "تعديل المجموعة") }
    var groupName: String { t("Grup adı", "Group name", "اسم المجموعة") }
    var groupNamePlaceholder: String { t("ör. A1-20 sınıfı", "e.g. A1-20 class", "مثلًا: صف A1-20") }
    var chatLinkLabel: String { t("WhatsApp ya da Telegram grup bağlantısı", "WhatsApp or Telegram group link", "رابط مجموعة واتساب أو تيليغرام") }
    var paste: String { t("Yapıştır", "Paste", "لصق") }
    func linkRecognized(_ app: ChatApp) -> String { t("\(app.title) grubu tanındı. Dokununca uygulamada açılır.", "\(app.title) group recognised. Tapping opens it in the app.", "تم التعرّف على مجموعة \(app.title). تُفتح في التطبيق عند النقر.") }
    var linkInvalid: String { t("Bu bir WhatsApp ya da Telegram grup bağlantısına benzemiyor.", "This doesn't look like a WhatsApp or Telegram group link.", "لا يبدو هذا رابط مجموعة واتساب أو تيليغرام.") }
    var pasteLinkOptional: String { t("Grup bağlantısını yapıştır (isteğe bağlı)", "Paste group link (optional)", "الصق رابط المجموعة (اختياري)") }
    func linkAdded(_ app: ChatApp) -> String { t("\(app.title) bağlantısı eklendi", "\(app.title) link added", "تمت إضافة رابط \(app.title)") }
    var whichDays: String { t("Hangi günler?", "Which days?", "أي أيام؟") }
    var time: String { t("Saat", "Time", "الوقت") }
    var earlier: String { t("15 dakika erken", "15 minutes earlier", "أبكر بـ ١٥ دقيقة") }
    var later: String { t("15 dakika geç", "15 minutes later", "أتأخر بـ ١٥ دقيقة") }
    var remindWhen: String { t("Ne zaman hatırlatayım?", "When should I remind you?", "متى أذكّرك؟") }
    var minutesBefore: String { t("dakika önce", "minutes before", "دقيقة قبل") }
    var hoursBefore: String { t("saat önce", "hours before", "ساعة قبل") }
    var color: String { t("Renk", "Colour", "اللون") }
    var createGroup: String { t("Grubu oluştur", "Create group", "إنشاء المجموعة") }
    var addGroup: String { t("Grubu ekle", "Add group", "إضافة المجموعة") }
    var quickNote: String { t("Süre 1 saat, hatırlatma 10 dk önce. Sonra gruptan değiştirebilirsin.", "1 hour long, reminder 10 min before. You can change it later.", "المدة ساعة والتذكير قبل ١٠ دقائق. يمكنك تغييرها لاحقًا.") }
    var groupLimit: String { t("En fazla 200 grup eklenebilir.", "You can add up to 200 groups.", "يمكن إضافة ٢٠٠ مجموعة كحد أقصى.") }

    func problem(_ p: GroupRules.Problem) -> String {
        switch p {
        case .nameRequired: t("Grup adını yaz.", "Enter a group name.", "اكتب اسم المجموعة.")
        case .nameTooLong: t("Ad en fazla 60 karakter olabilir.", "Name can be at most 60 characters.", "الاسم ٦٠ حرفًا كحد أقصى.")
        case .nameInvalid: t("Adda kullanılamayan bir karakter var.", "The name has a character that can't be used.", "يحتوي الاسم على حرف غير مسموح.")
        case .noDays: t("En az bir gün seç.", "Pick at least one day.", "اختر يومًا واحدًا على الأقل.")
        case .endsAfterMidnight: t("Ders gece yarısını geçemez.", "A lesson can't go past midnight.", "لا يمكن أن يتجاوز الدرس منتصف الليل.")
        case .badLink: linkInvalid
        case .badReminder: t("Hatırlatma süresi geçersiz.", "Invalid reminder time.", "وقت التذكير غير صالح.")
        case .badHoliday: t("Tatil tarihleri geçersiz.", "Holiday dates are invalid.", "تواريخ العطلة غير صالحة.")
        }
    }

    // MARK: Tatil

    var meOnVacation: String { t("Ben tatildeyim", "I'm on holiday", "أنا في عطلة") }
    var meOnVacationDetail: String { t("Tüm gruplar, tüm hatırlatmalar susar.", "All groups, all reminders go quiet.", "تتوقف كل التذكيرات لكل المجموعات.") }
    var someGroups: String { t("Ya da yalnız bazı gruplar", "Or only some groups", "أو بعض المجموعات فقط") }
    var howLong: String { t("Ne kadar?", "How long?", "إلى متى؟") }
    var oneWeek: String { t("1 hafta", "1 week", "أسبوع") }
    var twoWeeks: String { t("2 hafta", "2 weeks", "أسبوعان") }
    var oneMonth: String { t("1 ay", "1 month", "شهر") }
    var pickDate: String { t("Tarih", "Date", "تاريخ") }
    var startDate: String { t("Başlangıç", "Start", "البداية") }
    var endDate: String { t("Bitiş", "End", "النهاية") }
    func vacationSummary(_ n: Int) -> String {
        t("Bu sürede \(number(n)) dersin hatırlatması susar. Tatil bitince kendiliğinden devam eder.",
          "Reminders for \(number(n)) lessons go quiet. They resume on their own afterwards.",
          "ستتوقف تذكيرات \(number(n)) دروس، وتعود تلقائيًا بعد العطلة.")
    }
    var pickAGroup: String { t("En az bir grup seç.", "Pick at least one group.", "اختر مجموعة واحدة على الأقل.") }
    var startVacation: String { t("Tatili başlat", "Start holiday", "بدء العطلة") }

    // MARK: Grup detayı

    func openIn(_ app: ChatApp) -> String { t("\(app.title) grubunu aç", "Open in \(app.title)", "افتح في \(app.title)") }
    var daysLabel: String { t("Günler", "Days", "الأيام") }
    var linkLabel: String { t("Bağlantı", "Link", "الرابط") }
    var remindLabel: String { t("Hatırlat", "Remind", "التذكير") }
    var noLink: String { t("Yok", "None", "لا يوجد") }
    var endHoliday: String { t("Bitir", "End", "إنهاء") }
    var remindersSilent: String { t("Hatırlatmalar susuyor.", "Reminders are quiet.", "التذكيرات متوقفة.") }
    var upcomingLessons: String { t("Sıradaki dersler", "Upcoming lessons", "الدروس القادمة") }
    var deleteGroup: String { t("Grubu sil", "Delete group", "حذف المجموعة") }
    func deleteGroupConfirm(_ name: String) -> String { t("\(name) silinsin mi?", "Delete \(name)?", "حذف \(name)؟") }
    func reminderAt(_ minuteOfDay: Int) -> String { t("\(clock(minuteOfDay)) hatırlatma", "Reminder \(clock(minuteOfDay))", "تذكير \(clock(minuteOfDay))") }
    func everyDays(_ d: Set<Weekday>) -> String { t("Her \(days(d))", "Every \(days(d))", "كل \(days(d))") }

    // MARK: Program

    var program: String { t("Program", "Schedule", "الجدول") }
    func programSummary(groups: Int, lessons: Int) -> String {
        t("\(number(groups)) grup · haftada \(number(lessons)) ders", "\(number(groups)) groups · \(number(lessons)) lessons a week", "\(number(groups)) مجموعات · \(number(lessons)) دروس أسبوعيًا")
    }
    var groupsTab: String { t("Gruplar", "Groups", "المجموعات") }
    var weekTab: String { t("Hafta", "Week", "الأسبوع") }
    var exportPrint: String { t("Excel · Yazdır", "Excel · Print", "إكسل · طباعة") }
    var free: String { t("Boş", "Free", "فارغ") }

    // MARK: Dışa aktarma

    var preview: String { t("Önizleme", "Preview", "معاينة") }
    var weeklySchedule: String { t("Haftalık ders programı", "Weekly lesson schedule", "جدول الدروس الأسبوعي") }
    func takenOn(_ date: Date) -> String { t("\(self.date(date, "d MMMM yyyy")) tarihinde alındı", "Exported \(self.date(date, "d MMMM yyyy"))", "تم التصدير \(self.date(date, "d MMMM yyyy"))") }
    var dayColumn: String { t("Gün", "Day", "اليوم") }
    var timeColumn: String { t("Saat", "Time", "الوقت") }
    var groupColumn: String { t("Grup", "Group", "المجموعة") }
    var linkColumn: String { t("Bağlantı", "Link", "الرابط") }
    var noteColumn: String { t("Not", "Note", "ملاحظة") }
    var includeLinks: String { t("Grup bağlantılarını ekle", "Include group links", "تضمين روابط المجموعات") }
    var markHolidays: String { t("Tatilleri işaretle", "Mark holidays", "تمييز العطل") }
    var downloadExcel: String { t("Excel indir", "Download Excel", "تنزيل إكسل") }
    var print: String { t("Yazdır", "Print", "طباعة") }
    var fileName: String { t("Ders programı", "Lesson schedule", "جدول الدروس") }

    // MARK: Profil

    var profile: String { t("Profil", "Profile", "حسابي") }
    func signedIn(with provider: String) -> String { t("\(provider) ile giriş yapıldı", "Signed in with \(provider)", "تم تسجيل الدخول عبر \(provider)") }
    var notSignedIn: String { t("Giriş yapılmadı · veriler yalnız bu telefonda", "Not signed in · data stays on this phone", "لم يتم تسجيل الدخول · البيانات على هذا الهاتف فقط") }
    var signIn: String { t("Giriş yap ve yedekle", "Sign in and back up", "سجّل الدخول للنسخ الاحتياطي") }
    var backedUp: String { t("Yedeklendi", "Backed up", "تم النسخ الاحتياطي") }
    var syncFailed: String { t("Eşitlenemedi, sonra yeniden denenecek", "Couldn't sync, will retry", "تعذّرت المزامنة، ستتم إعادة المحاولة") }
    var appColor: String { t("Uygulama rengi", "App colour", "لون التطبيق") }
    var newGroupReminder: String { t("Yeni gruplar için hatırlatma", "Reminder for new groups", "التذكير للمجموعات الجديدة") }
    func vacationOn(until date: Date) -> String { t("Tatildesin · bitiş \(self.date(date, "d MMM"))", "On holiday · until \(self.date(date, "d MMM"))", "في عطلة · حتى \(self.date(date, "d MMM"))") }
    var turnOnSilences: String { t("Açınca tüm hatırlatmalar 1 hafta susar.", "Turning on silences all reminders for a week.", "عند التفعيل تتوقف كل التذكيرات لمدة أسبوع.") }
    var testNotification: String { t("Deneme bildirimi gönder", "Send a test reminder", "إرسال تذكير تجريبي") }
    var testSent: String { t("Gönderildi, birkaç saniye içinde gelir.", "Sent, it'll arrive in a few seconds.", "تم الإرسال، سيصل خلال ثوانٍ.") }
    var exportLink: String { t("Programı Excel olarak indir ya da yazdır", "Download or print the schedule", "تنزيل الجدول أو طباعته") }
    var signOut: String { t("Çıkış yap", "Sign out", "تسجيل الخروج") }
    var deleteAccount: String { t("Hesabı sil", "Delete account", "حذف الحساب") }
    var deleteAccountConfirm: String { t("Hesabın ve sunucudaki tüm verilerin kalıcı olarak silinir. Bu telefondaki program kalır.", "Your account and all server data are permanently deleted. The schedule on this phone stays.", "سيُحذف حسابك وكل بياناتك على الخادم نهائيًا. يبقى الجدول على هذا الهاتف.") }
    var notificationsOff: String { t("Bildirimler kapalı. Hatırlatma gelmesi için Ayarlar'dan aç.", "Notifications are off. Turn them on in Settings to get reminders.", "الإشعارات متوقفة. فعّلها من الإعدادات لتصلك التذكيرات.") }
    var openSettings: String { t("Ayarları aç", "Open Settings", "فتح الإعدادات") }

    // MARK: Bildirim metni

    func reminderBody(group: StudyGroup, minutesBefore: Int) -> String {
        let range = timeRange(group.startMinute, group.endMinute)
        if minutesBefore == 0 { return t("Ders başlıyor · \(range)", "Starting now · \(range)", "يبدأ الآن · \(range)") }
        return t("\(duration(minutesBefore)) sonra başlıyor · \(range)", "Starts in \(duration(minutesBefore)) · \(range)", "يبدأ بعد \(duration(minutesBefore)) · \(range)")
    }
}

private struct StringsKey: EnvironmentKey {
    static let defaultValue = Strings(language: .tr)
}

extension EnvironmentValues {
    var strings: Strings {
        get { self[StringsKey.self] }
        set { self[StringsKey.self] = newValue }
    }
}
