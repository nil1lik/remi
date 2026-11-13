import Foundation

// Remi çekirdek testleri (Xcode'suz): kurallar, günlük plan, metinler ve Excel çıktısı.
// Çalıştırma: ./Tests/run.sh

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition { failures += 1; print("  ✗ satır \(line): \(message)") }
}

let cal = Calendar.remi
func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

// MARK: Sohbet bağlantısı (backend'deki ChatLink ile aynı kurallar)

print("Sohbet bağlantısı")
for (input, url, app) in [
    ("chat.whatsapp.com/AbC123", "https://chat.whatsapp.com/AbC123", ChatApp.whatsapp),
    ("https://T.ME/+AbC", "https://t.me/+AbC", .telegram),
    (" https://telegram.me/remi_grup/ ", "https://telegram.me/remi_grup", .telegram),
] {
    let parsed = ChatLinkRule.parse(input)
    check(parsed?.url.absoluteString == url && parsed?.app == app, "\(input) → \(String(describing: parsed))")
}
for bad in ["javascript:alert(1)", "http://chat.whatsapp.com/AbC", "https://chat.whatsapp.com.evil.example/AbC",
            "https://user@t.me/AbC", "https://t.me:444/AbC", "https://t.me/AbC#x", "https://t.me/AbC?start=x",
            "https://t.me/", "https://t.me/a%2Fb", "whatsapp://send?text=hi"] {
    check(ChatLinkRule.parse(bad) == nil, "reddedilmeli: \(bad)")
}

// MARK: Hatırlatma tekerleği

print("Hatırlatma")
for (m, ok) in [(0, true), (5, true), (60, true), (120, true), (720, true), (3, false), (65, false), (90, false), (780, false), (-5, false)] {
    check(ReminderSetting.isAllowed(m) == ok, "\(m) dk → \(ok)")
}

// MARK: Grup kuralları

print("Grup kuralları")
let ok = StudyGroup(name: "A1-20 sınıfı", days: [.thursday], startMinute: 540)
check(GroupRules.problems(of: ok).isEmpty, "geçerli grup")
check(GroupRules.problems(of: StudyGroup(name: "  ", days: [.monday], startMinute: 540)) == [.nameRequired], "boş ad")
check(GroupRules.problems(of: StudyGroup(name: String(repeating: "x", count: 61), days: [.monday], startMinute: 540)) == [.nameTooLong], "uzun ad")
check(GroupRules.problems(of: StudyGroup(name: "A1\u{202E}gnp.exe", days: [.monday], startMinute: 540)) == [.nameInvalid], "bidi karakter")
check(GroupRules.problems(of: StudyGroup(name: "X", days: [], startMinute: 540)) == [.noDays], "gün yok")
check(GroupRules.problems(of: StudyGroup(name: "X", days: [.monday], startMinute: 23 * 60, durationMinutes: 90)) == [.endsAfterMidnight], "gece yarısı")
check(GroupRules.problems(of: StudyGroup(name: "X", chatLink: "https://evil.example/x", days: [.monday], startMinute: 540)) == [.badLink], "kötü bağlantı")

// MARK: Günlük plan, özet ve "güzel haber"

print("Günlük plan")
let thursday = day(2026, 11, 12)
let friday = day(2026, 11, 13)
let groups = [
    StudyGroup(name: "A1-20", days: [.thursday, .saturday], startMinute: 9 * 60),
    StudyGroup(name: "Elif", days: [.thursday, .friday], startMinute: 14 * 60),
    StudyGroup(name: "B1-07", days: [.thursday], startMinute: 18 * 60, durationMinutes: 90,
               holiday: DayRange(start: day(2026, 11, 10), end: day(2026, 11, 20))),
]
let plan = DayPlan(day: thursday, groups: groups, profile: Profile())
check(plan.lessons.map(\.group.name) == ["A1-20", "Elif", "B1-07"], "saat sırası: \(plan.lessons.map(\.group.name))")
check(plan.active.count == 2, "tatildeki grup sayılmaz")
check(plan.totalMinutes == 120, "toplam 2 saat: \(plan.totalMinutes)")
check(plan.firstStart == 540 && plan.lastEnd == 15 * 60, "ilk–son: \(String(describing: plan.firstStart))–\(String(describing: plan.lastEnd))")
check(plan.goodNews == .eveningFree, "akşam boş (B1-07 tatilde): \(String(describing: plan.goodNews))")

let fridayPlan = DayPlan(day: friday, groups: groups, profile: Profile())
check(fridayPlan.goodNews == .bothFree, "cuma: sabah da akşam da boş")
let busy = DayPlan(day: thursday, groups: groups.map { var g = $0; g.holiday = nil; return g }, profile: Profile())
check(busy.goodNews == nil, "sabah ve akşam dolu: haber yok")
check(DayPlan(day: day(2026, 11, 15), groups: groups, profile: Profile()).goodNews == nil, "boş gün: haber yok")

var away = Profile()
away.vacation = DayRange(start: thursday, end: friday)
let vacationPlan = DayPlan(day: thursday, groups: groups, profile: away)
check(vacationPlan.active.isEmpty && vacationPlan.lessons.count == 3, "hoca tatilde: hepsi susar ama görünür")

let now = thursday.addingTimeInterval(TimeInterval(13 * 3600 + 42 * 60))
let current = plan.current(at: now)
check(current?.lesson.group.name == "Elif" && current?.isLive == false, "13:42'de sıradaki Elif")

// MARK: Metinler

print("Metinler")
let tr = Strings(language: .tr), en = Strings(language: .en), ar = Strings(language: .ar)
check(tr.lessonCount(3) == "3 ders" && en.lessonCount(1) == "1 lesson" && ar.lessonCount(2) == "درسان", "çoğul")
check(ar.clock(14 * 60) == "١٤:٠٠", "Arapça saat: \(ar.clock(14 * 60))")
check(ar.number(13) == "١٣", "Arapça sayı: \(ar.number(13))")
check(tr.reminderShort(ReminderSetting(minutesBefore: 120)) == "2 sa önce", "hatırlatma metni")
check(tr.days([.monday, .tuesday, .wednesday, .thursday, .friday]) == "Hafta içi", "hafta içi")
check(tr.greeting(at: thursday.addingTimeInterval(9 * 3600), name: "Hocam") == "Günaydın, Hocam", "selam")

// MARK: Excel

print("Excel")
let rows = ScheduleExport.rows(groups: groups, strings: tr, includeLinks: true, markHolidays: true)
check(rows.first?.day == .thursday && rows.count == 5, "satırlar (Per 3 + Cum 1 + Cmt 1): \(rows.count)")
check(ScheduleExport.xml("a<b & \"c\"\u{0001}") == "a&lt;b &amp; &quot;c&quot;", "XML kaçışı")
check(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF43926, "CRC-32 test vektörü")
let file = try ScheduleExport.excelFile(rows: rows, strings: tr, includeLinks: true, markHolidays: true)
let out = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : file
if out != file {
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.copyItem(at: file, to: out)
}
print("  Excel: \(out.path)")

if failures == 0 { print("✓ çekirdek testleri geçti") } else { print("✗ \(failures) test başarısız"); exit(1) }
