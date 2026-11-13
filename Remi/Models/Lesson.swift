import Foundation

/// Haftanın günü. Ham değerler Pazartesi = 1 … Pazar = 7 (Türkiye takvimi).
enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .monday: "Pazartesi"
        case .tuesday: "Salı"
        case .wednesday: "Çarşamba"
        case .thursday: "Perşembe"
        case .friday: "Cuma"
        case .saturday: "Cumartesi"
        case .sunday: "Pazar"
        }
    }

    var shortName: String {
        switch self {
        case .monday: "Pzt"
        case .tuesday: "Sal"
        case .wednesday: "Çar"
        case .thursday: "Per"
        case .friday: "Cum"
        case .saturday: "Cmt"
        case .sunday: "Paz"
        }
    }

    /// `Calendar` gün numarası (Pazar = 1 … Cumartesi = 7).
    var calendarWeekday: Int { rawValue % 7 + 1 }

    init?(calendarWeekday: Int) {
        self.init(rawValue: (calendarWeekday + 5) % 7 + 1)
    }

    init(date: Date, calendar: Calendar = .schedule) {
        self.init(calendarWeekday: calendar.component(.weekday, from: date))!
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case notification
    case alarm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notification: "Bildirim"
        case .alarm: "Alarm"
        }
    }
}

struct ReminderSettings: Codable, Hashable {
    var isEnabled: Bool = true
    var minutesBefore: Int = 10
    var kind: ReminderKind = .notification

    static let minuteOptions = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    static func label(forMinutes minutes: Int) -> String {
        switch minutes {
        case 0: "Ders başlarken"
        case let m where m < 60: "\(m) dakika önce"
        case let m where m % 60 == 0: "\(m / 60) saat önce"
        default: "\(minutes / 60) sa \(minutes % 60) dk önce"
        }
    }
}

struct Lesson: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// Her hafta tekrarlanan ders için gün. `date` doluysa kullanılmaz.
    var weekday: Weekday?
    /// Tek seferlik ders için tarih (günün başlangıcı).
    var date: Date?
    /// Gece yarısından itibaren dakika.
    var start: Int
    var end: Int?
    var location: String?
    var note: String?
    /// Bu derse özel hatırlatma; boşsa genel ayar geçerli.
    var customReminder: ReminderSettings?

    var isRecurring: Bool { date == nil }

    var timeText: String {
        if let end { return "\(Self.clock(start)) – \(Self.clock(end))" }
        return Self.clock(start)
    }

    func occurs(on day: Date, calendar: Calendar = .schedule) -> Bool {
        if let date { return calendar.isDate(date, inSameDayAs: day) }
        return weekday == Weekday(date: day, calendar: calendar)
    }

    func startDate(on day: Date, calendar: Calendar = .schedule) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(start * 60))
    }

    func endDate(on day: Date, calendar: Calendar = .schedule) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval((end ?? start + 40) * 60))
    }

    /// Gün ve saat aralığı kesişiyorsa (bitiş yoksa 40 dk sayılır).
    func overlaps(_ other: Lesson) -> Bool {
        guard id != other.id else { return false }
        let sameDay: Bool
        switch (date, other.date) {
        case let (a?, b?): sameDay = Calendar.schedule.isDate(a, inSameDayAs: b)
        case let (a?, nil): sameDay = Weekday(date: a) == other.weekday
        case let (nil, b?): sameDay = weekday == Weekday(date: b)
        case (nil, nil): sameDay = weekday == other.weekday
        }
        guard sameDay else { return false }
        return start < (other.end ?? other.start + 40) && other.start < (end ?? start + 40)
    }

    /// İçe aktarırken aynı kaydı iki kez eklememek için.
    var identityKey: String {
        let day = date.map { String(Int($0.timeIntervalSinceReferenceDate / 86_400)) } ?? "w\(weekday?.rawValue ?? 0)"
        return "\(ScheduleImporter.normalize(title))|\(day)|\(start)"
    }

    /// "Perşembe", "Perşembe, Cumartesi", "Hafta içi", "Her gün"
    static func daysText(_ days: Set<Weekday>) -> String {
        let sorted = days.sorted()
        switch sorted {
        case Weekday.allCases: return "Her gün"
        case [.monday, .tuesday, .wednesday, .thursday, .friday]: return "Hafta içi"
        case [.saturday, .sunday]: return "Hafta sonu"
        default: return sorted.map { sorted.count > 2 ? $0.shortName : $0.name }.joined(separator: ", ")
        }
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

extension Calendar {
    /// Pazartesi ile başlayan Türkçe takvim.
    static let schedule: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }()
}
