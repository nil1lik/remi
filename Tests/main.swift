// Mac'te Xcode olmadan çalışan içe aktarma testleri: Tests/run.sh
import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if !condition() {
        failures += 1
        print("✗ satır \(line): \(message)")
    }
}

// Saat
check(ScheduleImporter.parseTime("09:00") == 540, "09:00")
check(ScheduleImporter.parseTime("9.00") == 540, "9.00")
check(ScheduleImporter.parseTime("9,30") == 570, "9,30")
check(ScheduleImporter.parseTime("9") == 540, "9")
check(ScheduleImporter.parseTime("0900") == 540, "0900")
check(ScheduleImporter.parseTime("0.375") == 540, "Excel kesri")
check(ScheduleImporter.parseTime("0.39583333333333331") == 570, "Excel kesri 09:30")
check(ScheduleImporter.parseTime("46333.5625") == 810, "Excel tarih+saat")
check(ScheduleImporter.parseTime("09:00:00") == 540, "09:00:00")
check(ScheduleImporter.parseTime("2:15 PM") == 855, "2:15 PM")
check(ScheduleImporter.parseTime("25:00") == nil, "25:00 geçersiz")
check(ScheduleImporter.parseTime("abc") == nil, "metin geçersiz")
let range = ScheduleImporter.parseTimeRange("09:00 – 09:40")
check(range?.0 == 540 && range?.1 == 580, "saat aralığı")

// Gün
check(ScheduleImporter.parseWeekdays("Pazartesi") == [.monday], "Pazartesi")
check(ScheduleImporter.parseWeekdays("ÇARŞAMBA") == [.wednesday], "ÇARŞAMBA")
check(ScheduleImporter.parseWeekdays("Pzt, Çrş") == [.monday, .wednesday], "kısaltmalar")
check(ScheduleImporter.parseWeekdays("Pazartesi-Cuma") == [.monday, .tuesday, .wednesday, .thursday, .friday], "aralık")
check(ScheduleImporter.parseWeekdays("Salı ve Perşembe") == [.tuesday, .thursday], "ve")
check(ScheduleImporter.parseWeekdays("Cumartesi") == [.saturday], "Cumartesi")
check(ScheduleImporter.parseWeekdays("Cuma") == [.friday], "Cuma")
check(ScheduleImporter.parseWeekdays("Pzt.") == [.monday], "noktalı kısaltma")
check(ScheduleImporter.parseWeekdays("perşembe cmt") == [.thursday, .saturday], "boşlukla ayrılmış")
check(ScheduleImporter.parseWeekdays("Pazartesi - Cuma").map(\.count) == 5, "boşluklu aralık")
check(ScheduleImporter.parseTimeRange("09.00-10.00").map { $0.0 } == 540, "09.00-10.00")
check(ScheduleImporter.parseWeekdays("İkinci gün") == nil, "geçersiz gün")
check(Weekday(calendarWeekday: 1) == .sunday && Weekday.monday.calendarWeekday == 2, "Calendar eşlemesi")

// Tarih
let cal = Calendar.schedule
let nov7 = cal.date(from: DateComponents(year: 2026, month: 11, day: 7))!
check(ScheduleImporter.parseDate("07.11.2026", uses1904Dates: false) == nov7, "07.11.2026")
check(ScheduleImporter.parseDate("2026-11-07", uses1904Dates: false) == nov7, "ISO")
check(ScheduleImporter.parseDate("7/11/26", uses1904Dates: false) == nov7, "7/11/26")
check(ScheduleImporter.parseDate("46333", uses1904Dates: false) == nov7, "Excel seri")
check(ScheduleImporter.parseDate("31.02.2026", uses1904Dates: false) == nil, "geçersiz tarih")

// CSV (Türkçe Excel ; ile kaydeder)
let csv = "\u{FEFF}Gün;Başlangıç;Bitiş;Ders;Yer;Not\r\nPazartesi;09:00;09:40;Matematik;B-204;\"Not; noktalı virgüllü\"\r\nSalı;10:00;;Fizik;;\r\n"
do {
    let result = try ScheduleImporter.importRows(ScheduleImporter.parseCSV(csv), sheetName: nil, uses1904Dates: false)
    check(result.lessons.count == 2, "CSV ders sayısı \(result.lessons.count)")
    check(result.lessons.first?.note == "Not; noktalı virgüllü", "CSV tırnaklı alan")
    check(result.lessons.last?.end == nil, "CSV boş bitiş")
} catch {
    check(false, "CSV hata: \(error)")
}

// Başlıksız tablo
do {
    _ = try ScheduleImporter.importRows([["a", "b"], ["c", "d"]], sheetName: nil, uses1904Dates: false)
    check(false, "başlıksız tablo hata vermeli")
} catch {
    check((error as? ScheduleImporter.ImportError) == .headerNotFound, "headerNotFound")
}

// xlsx dosyaları
for path in CommandLine.arguments.dropFirst() {
    do {
        let result = try ScheduleImporter.importFile(at: URL(fileURLWithPath: path))
        print("• \((path as NSString).lastPathComponent): sayfa \"\(result.sheetName ?? "-")\", \(result.lessons.count) ders, \(result.issues.count) uyarı")
        for lesson in result.lessons {
            let when = lesson.weekday?.name ?? lesson.date.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) } ?? "?"
            print("    \(when.padding(toLength: 10, withPad: " ", startingAt: 0)) \(lesson.timeText.padding(toLength: 14, withPad: " ", startingAt: 0)) \(lesson.title) · \(lesson.location ?? "") · \(lesson.note ?? "")")
        }
        for issue in result.issues { print("    ⚠︎ satır \(issue.row): \(issue.message)") }
        if path.contains("Sablon") {
            check(result.lessons.count == 8, "şablon 8 grup-gün")
            let a1 = result.lessons.filter { $0.title == "A1-20 sınıfı" }
            check(a1.map(\.weekday) == [.thursday, .saturday] && a1.allSatisfy { $0.start == 540 && $0.end == 600 }, "A1-20 Per Cmt 09-10")
            check(result.lessons.last?.date == nov7 && result.lessons.last?.weekday == nil, "şablon tek seferlik")
        }
        if path.contains("openpyxl") {
            check(result.lessons.count == 7, "openpyxl ders sayısı \(result.lessons.count)")
            check(result.issues.count == 2, "openpyxl uyarı sayısı \(result.issues.count)")
        }
    } catch {
        check(false, "\(path): \(error.localizedDescription)")
    }
}

print(failures == 0 ? "✓ tüm testler geçti" : "✗ \(failures) test başarısız")
exit(failures == 0 ? 0 : 1)
