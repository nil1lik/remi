import Foundation

/// Bir günün dersi: hangi grup, o gün tatilde mi.
struct Lesson: Identifiable, Hashable {
    var group: StudyGroup
    var day: Date
    var isPaused: Bool

    var id: String { "\(group.id)-\(Int(day.timeIntervalSince1970))" }
    var start: Date { day.addingTimeInterval(TimeInterval(group.startMinute * 60)) }
    var end: Date { day.addingTimeInterval(TimeInterval(group.endMinute * 60)) }
}

/// Seçilen günün dersleri, özeti ve "güzel haber"i.
struct DayPlan {
    let day: Date
    let lessons: [Lesson]

    init(day: Date, groups: [StudyGroup], profile: Profile, calendar: Calendar = .remi) {
        let start = calendar.startOfDay(for: day)
        self.day = start
        let teacherAway = profile.isOnVacation(on: start)
        lessons = groups
            .filter { $0.meets(on: start, calendar: calendar) }
            .map { Lesson(group: $0, day: start, isPaused: teacherAway || $0.isOnHoliday(on: start)) }
            .sorted { ($0.group.startMinute, $0.group.name) < ($1.group.startMinute, $1.group.name) }
    }

    /// Tatilde olmayan, gerçekten yapılacak dersler.
    var active: [Lesson] { lessons.filter { !$0.isPaused } }
    var totalMinutes: Int { active.reduce(0) { $0 + $1.group.durationMinutes } }
    var firstStart: Int? { active.map(\.group.startMinute).min() }
    var lastEnd: Int? { active.map(\.group.endMinute).max() }

    enum GoodNews { case morningFree, eveningFree, bothFree }

    /// Sabah = 12:00 öncesi, akşam = 18:00 sonrası. Hiç ders yoksa haber yok (boş gün ayrı gösterilir).
    var goodNews: GoodNews? {
        guard !active.isEmpty else { return nil }
        let morningFree = !active.contains { $0.group.startMinute < 12 * 60 }
        let eveningFree = !active.contains { $0.group.endMinute > 18 * 60 }
        switch (morningFree, eveningFree) {
        case (true, true): return .bothFree
        case (true, false): return .morningFree
        case (false, true): return .eveningFree
        default: return nil
        }
    }

    /// Şu an süren ya da sıradaki ders (yalnız bugün için anlamlı).
    func current(at now: Date) -> (lesson: Lesson, isLive: Bool)? {
        if let live = active.first(where: { now >= $0.start && now < $0.end }) { return (live, true) }
        if let next = active.first(where: { $0.start > now }) { return (next, false) }
        return nil
    }
}
