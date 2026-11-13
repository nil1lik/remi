import Foundation

// MARK: - Temel türler

/// 1 = Pazartesi … 7 = Pazar (ISO). Sunucuyla aynı numaralandırma.
enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }
    /// `Calendar` gün numarası (Pazar = 1 … Cumartesi = 7).
    var calendarWeekday: Int { rawValue % 7 + 1 }

    init(date: Date, calendar: Calendar = .remi) {
        self.init(rawValue: (calendar.component(.weekday, from: date) + 5) % 7 + 1)!
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case notification, alarm
    var id: String { rawValue }
}

enum GroupColor: String, Codable, CaseIterable, Identifiable {
    case blue, green, coral, rose, amber, violet
    var id: String { rawValue }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case tr, en, ar
    var id: String { rawValue }
    var isRightToLeft: Bool { self == .ar }
    /// Arapçada tarih ve sayılar da saatler gibi Arapça rakamla (٠–٩) yazılır.
    var locale: Locale { Locale(identifier: rawValue == "ar" ? "ar@numbers=arab" : rawValue == "en" ? "en_GB" : "tr_TR") }
    /// Dil seçicide her dil kendi adıyla görünür.
    var nativeName: String {
        switch self {
        case .tr: "Türkçe"
        case .en: "English"
        case .ar: "العربية"
        }
    }

    static var deviceDefault: AppLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2) ?? "tr"
        return AppLanguage(rawValue: String(code)) ?? .tr
    }
}

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case violet, mint, coral, rose, amber, ocean
    var id: String { rawValue }
}

/// Dersten ne kadar önce, hangi yolla. Tekerlekteki değerler: 0–60 dk (5'er) ya da 1–12 saat.
struct ReminderSetting: Codable, Hashable {
    var minutesBefore: Int = 10
    var kind: ReminderKind = .notification

    static let `default` = ReminderSetting()
    static let minuteValues = Array(stride(from: 0, through: 60, by: 5))
    static let hourValues = Array(1...12)

    static func isAllowed(_ minutes: Int) -> Bool {
        (0...60).contains(minutes) && minutes % 5 == 0 || (61...720).contains(minutes) && minutes % 60 == 0
    }
}

/// Başlangıç ve bitişi dahil gün aralığı (tatil).
struct DayRange: Codable, Hashable {
    var start: Date
    var end: Date

    static let maxDays = 366

    func contains(_ day: Date, calendar: Calendar = .remi) -> Bool {
        let d = calendar.startOfDay(for: day)
        return d >= calendar.startOfDay(for: start) && d <= calendar.startOfDay(for: end)
    }

    var isValid: Bool {
        end >= start && (Calendar.remi.dateComponents([.day], from: start, to: end).day ?? 0) <= Self.maxDays
    }
}

// MARK: - Grup

/// Ders grubu: hocanın programının temel birimi. Dersler grubun haftalık saatinden üretilir.
struct StudyGroup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var color: GroupColor = .blue
    var chatLink: String?
    var days: Set<Weekday>
    var startMinute: Int
    var durationMinutes: Int = 60
    var reminder: ReminderSetting = .default
    var holiday: DayRange?

    /// Sunucudaki sürüm (eşitlemede çakışma kontrolü için). Hiç gönderilmemişse 0.
    var version: Int = 0

    var endMinute: Int { startMinute + durationMinutes }
    var chatApp: ChatApp? { chatLink.flatMap { ChatLinkRule.parse($0)?.app } }

    func meets(on day: Date, calendar: Calendar = .remi) -> Bool {
        days.contains(Weekday(date: day, calendar: calendar))
    }

    func isOnHoliday(on day: Date) -> Bool { holiday?.contains(day) == true }
}

enum ChatApp: String, Codable {
    case whatsapp, telegram
    var title: String { self == .whatsapp ? "WhatsApp" : "Telegram" }
}

// MARK: - Profil

struct Profile: Codable, Hashable {
    var displayName: String = ""
    var language: AppLanguage = .deviceDefault
    var theme: ThemeMode = .system
    var accent: AccentChoice = .violet
    var defaultReminder: ReminderSetting = .default
    /// "Ben tatildeyim": aralık boyunca tüm hatırlatmalar susar.
    var vacation: DayRange?

    func isOnVacation(on day: Date) -> Bool { vacation?.contains(day) == true }
}

extension Calendar {
    /// Pazartesi ile başlayan takvim; saat dilimi cihazınki.
    static let remi: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }()
}

extension Int {
    /// Gece yarısından dakika → "09:30"
    var clock: String { String(format: "%02d:%02d", self / 60, self % 60) }
}
