import Foundation
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Ders hatırlatmalarını bildirim ya da alarm olarak kurar. Her senkronda
/// uygulamanın kurduğu tüm hatırlatmalar silinip programdan yeniden oluşturulur.
@MainActor
final class ReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private static let identifierPrefix = "lesson."
    /// iOS bir uygulama için en fazla 64 bekleyen bildirim tutar; deneme bildirimine yer bırak.
    private static let notificationLimit = 60

    // MARK: İzinler

    var alarmsSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    func notificationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestNotificationPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// nil: bu iOS sürümünde alarm yok.
    func alarmAuthorized() -> Bool? {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return nil
    }

    func alarmPermissionDenied() -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .denied
        }
        #endif
        return false
    }

    @discardableResult
    func requestAlarmPermission() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let state = try? await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        }
        #endif
        return false
    }

    func requestPermissions(for kind: ReminderKind) async {
        if await notificationStatus() == .notDetermined {
            await requestNotificationPermission()
        }
        if kind == .alarm, alarmsSupported, alarmAuthorized() == false, !alarmPermissionDenied() {
            await requestAlarmPermission()
        }
    }

    // MARK: Senkron

    private struct Plan {
        var lesson: Lesson
        var settings: ReminderSettings
        /// Haftalık ders için hatırlatmanın günü ve saati (ders gece yarısına yakınsa önceki güne kayar).
        var weekday: Weekday?
        var minuteOfDay: Int
        /// Tek seferlik ders için hatırlatma anı.
        var fireDate: Date?
    }

    func sync(lessons: [Lesson], defaults: ReminderSettings) async {
        let plans = makePlans(lessons: lessons, defaults: defaults)
        let canAlarm = alarmAuthorized() == true

        let alarmPlans = canAlarm ? plans.filter { $0.settings.kind == .alarm } : []
        let notificationPlans = canAlarm ? plans.filter { $0.settings.kind == .notification } : plans

        await syncNotifications(notificationPlans)
        await syncAlarms(alarmPlans)
    }

    private func makePlans(lessons: [Lesson], defaults: ReminderSettings, now: Date = .now) -> [Plan] {
        let calendar = Calendar.schedule
        var plans: [Plan] = []
        for lesson in lessons {
            let settings = lesson.customReminder ?? defaults
            guard settings.isEnabled else { continue }

            if let date = lesson.date {
                let fire = lesson.startDate(on: date, calendar: calendar).addingTimeInterval(TimeInterval(-settings.minutesBefore * 60))
                guard fire > now else { continue }
                plans.append(Plan(lesson: lesson, settings: settings, weekday: nil, minuteOfDay: 0, fireDate: fire))
            } else if let weekday = lesson.weekday {
                let week = 7 * 1440
                let minuteOfWeek = ((weekday.rawValue - 1) * 1440 + lesson.start - settings.minutesBefore + week) % week
                plans.append(Plan(lesson: lesson, settings: settings,
                                  weekday: Weekday(rawValue: minuteOfWeek / 1440 + 1),
                                  minuteOfDay: minuteOfWeek % 1440, fireDate: nil))
            }
        }
        return plans
    }

    private func syncNotifications(_ plans: [Plan]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let requests: [UNNotificationRequest]
        if plans.count <= Self.notificationLimit {
            requests = plans.map { plan in
                let trigger: UNNotificationTrigger
                if let fireDate = plan.fireDate {
                    let components = Calendar.schedule.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                } else {
                    var components = DateComponents()
                    components.weekday = plan.weekday!.calendarWeekday
                    components.hour = plan.minuteOfDay / 60
                    components.minute = plan.minuteOfDay % 60
                    trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                }
                return UNNotificationRequest(identifier: Self.identifierPrefix + plan.lesson.id.uuidString,
                                             content: content(for: plan), trigger: trigger)
            }
        } else {
            // Çok kalabalık program: önümüzdeki 7 günün en yakın hatırlatmalarını kur.
            // Uygulama her açıldığında liste yenilenir.
            requests = upcomingOccurrences(plans, days: 7).prefix(Self.notificationLimit).map { plan, fire in
                let components = Calendar.schedule.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                return UNNotificationRequest(
                    identifier: Self.identifierPrefix + plan.lesson.id.uuidString + "." + String(Int(fire.timeIntervalSince1970)),
                    content: content(for: plan),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            }
        }

        for request in requests {
            do {
                try await center.add(request)
            } catch {
                print("Bildirim kurulamadı: \(error)")
            }
        }
    }

    private func upcomingOccurrences(_ plans: [Plan], days: Int, now: Date = .now) -> [(Plan, Date)] {
        let calendar = Calendar.schedule
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: days, to: today)!
        var result: [(Plan, Date)] = []
        for plan in plans {
            if let fire = plan.fireDate {
                if fire < horizon { result.append((plan, fire)) }
                continue
            }
            for offset in 0...days {
                let day = calendar.date(byAdding: .day, value: offset, to: today)!
                guard Weekday(date: day, calendar: calendar) == plan.weekday else { continue }
                let fire = day.addingTimeInterval(TimeInterval(plan.minuteOfDay * 60))
                if fire > now { result.append((plan, fire)) }
            }
        }
        return result.sorted { $0.1 < $1.1 }
    }

    private func content(for plan: Plan) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = plan.lesson.title
        content.body = Self.message(for: plan.lesson, minutesBefore: plan.settings.minutesBefore)
        content.sound = .default
        content.threadIdentifier = "lessons"
        content.userInfo = ["lessonID": plan.lesson.id.uuidString]
        return content
    }

    static func message(for lesson: Lesson, minutesBefore: Int) -> String {
        var parts: [String] = []
        parts.append(minutesBefore == 0 ? "Ders başlıyor" : "\(ReminderSettings.label(forMinutes: minutesBefore).replacingOccurrences(of: " önce", with: "")) sonra başlıyor")
        parts.append(lesson.timeText)
        if let location = lesson.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    // MARK: Alarm

    private func syncAlarms(_ plans: [Plan]) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        let manager = AlarmManager.shared
        for alarm in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: alarm.id)
        }
        for plan in plans {
            let schedule: Alarm.Schedule
            if let fireDate = plan.fireDate {
                schedule = .fixed(fireDate)
            } else {
                let time = Alarm.Schedule.Relative.Time(hour: plan.minuteOfDay / 60, minute: plan.minuteOfDay % 60)
                schedule = .relative(.init(time: time, repeats: .weekly([plan.weekday!.localeWeekday])))
            }
            await scheduleAlarm(title: Self.alarmTitle(for: plan.lesson, minutesBefore: plan.settings.minutesBefore),
                                schedule: schedule, color: LessonPalette.color(for: plan.lesson.title))
        }
        #endif
    }

    static func alarmTitle(for lesson: Lesson, minutesBefore: Int) -> String {
        minutesBefore == 0 ? "\(lesson.title) başlıyor" : "\(lesson.title) · \(minutesBefore) dk sonra"
    }

    // MARK: Deneme

    /// Ayarlar ekranındaki "Dene" düğmesi: birkaç saniye sonra seçilen türde hatırlatma.
    func sendTest(kind: ReminderKind, minutesBefore: Int) async {
        let sample = Lesson(title: "A1-20 sınıfı", weekday: nil, date: nil, start: 9 * 60, end: 10 * 60, location: "Deneme")
        #if canImport(AlarmKit)
        if kind == .alarm {
            if #available(iOS 26.0, *) {
                if alarmAuthorized() != true { await requestAlarmPermission() }
                if alarmAuthorized() == true {
                    await scheduleAlarm(title: Self.alarmTitle(for: sample, minutesBefore: minutesBefore),
                                        schedule: .fixed(.now.addingTimeInterval(10)), color: .indigo)
                    return
                }
            }
        }
        #endif
        if await notificationStatus() == .notDetermined { await requestNotificationPermission() }
        let content = UNMutableNotificationContent()
        content.title = sample.title
        content.body = Self.message(for: sample, minutesBefore: minutesBefore)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try? await center.add(request)
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarm(title: String, schedule: Alarm.Schedule, color: Color) async {
        let stop = AlarmButton(text: "Kapat", textColor: .white, systemImageName: "stop.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                                            secondaryButton: nil, secondaryButtonBehavior: nil)
        } else {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), stopButton: stop,
                                            secondaryButton: nil, secondaryButtonBehavior: nil)
        }
        let attributes = AlarmAttributes<LessonAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                              metadata: LessonAlarmMetadata(), tintColor: color)
        let configuration = AlarmManager.AlarmConfiguration<LessonAlarmMetadata>(
            countdownDuration: nil, schedule: schedule, attributes: attributes,
            stopIntent: nil, secondaryIntent: nil
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
        } catch {
            print("Alarm kurulamadı: \(error)")
        }
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct LessonAlarmMetadata: AlarmMetadata {}

extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }
}
#endif
