import Foundation
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Grupların hatırlatmalarını bildirim ya da alarm olarak kurar. Her değişiklikte uygulamanın kurduğu
/// tüm hatırlatmalar silinip programdan yeniden oluşturulur.
///
/// Tatili olmayan gruplar haftalık tekrar eder (uygulama açılmasa da çalışır). Grubun ya da hocanın
/// tatili varsa önümüzdeki günler tek tek kurulur ve tatil günleri atlanır; tatil bitiminde
/// "hatırlatmalar yeniden açık" bildirimi uygulamayı açtırır ve liste yenilenir.
@MainActor
final class ReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private static let prefix = "remi."
    /// iOS bir uygulama için en fazla 64 bekleyen bildirim tutar; deneme ve tatil bildirimine yer bırak.
    private static let notificationLimit = 60
    private static let horizonDays = 21

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

    func alarmAuthorized() -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        #endif
        return false
    }

    func requestPermissions(for kind: ReminderKind) async {
        if await notificationStatus() == .notDetermined { await requestNotificationPermission() }
        #if canImport(AlarmKit)
        if kind == .alarm, #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        #endif
    }

    // MARK: Plan

    private enum When {
        case weekly(Weekday, minuteOfDay: Int)
        case once(Date)
    }

    private struct Plan {
        var group: StudyGroup
        var when: When
    }

    func sync(groups: [StudyGroup], profile: Profile) async {
        let strings = Strings(language: profile.language)
        let plans = makePlans(groups: groups, profile: profile)
        let canAlarm = alarmAuthorized()
        let alarmPlans = canAlarm ? plans.filter { $0.group.reminder.kind == .alarm } : []
        let notificationPlans = canAlarm ? plans.filter { $0.group.reminder.kind == .notification } : plans

        await syncNotifications(notificationPlans, strings: strings, vacationEnd: profile.vacation?.end)
        await syncAlarms(alarmPlans, strings: strings)
    }

    private func makePlans(groups: [StudyGroup], profile: Profile, now: Date = .now) -> [Plan] {
        let calendar = Calendar.remi
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: Self.horizonDays, to: today)!
        var plans: [Plan] = []

        for group in groups {
            let lead = group.reminder.minutesBefore
            let pauses = [group.holiday, profile.vacation].compactMap { $0 }.filter { $0.end >= today }
            if pauses.isEmpty {
                // Haftalık tekrar: hatırlatma gece yarısından önceye düşerse önceki güne kayar.
                for day in group.days {
                    let week = 7 * 1440
                    let minuteOfWeek = ((day.rawValue - 1) * 1440 + group.startMinute - lead + week) % week
                    plans.append(Plan(group: group, when: .weekly(Weekday(rawValue: minuteOfWeek / 1440 + 1)!, minuteOfDay: minuteOfWeek % 1440)))
                }
            } else {
                var day = today
                while day < horizon {
                    if group.meets(on: day, calendar: calendar), !pauses.contains(where: { $0.contains(day, calendar: calendar) }) {
                        let fire = day.addingTimeInterval(TimeInterval((group.startMinute - lead) * 60))
                        if fire > now { plans.append(Plan(group: group, when: .once(fire))) }
                    }
                    day = calendar.date(byAdding: .day, value: 1, to: day)!
                }
            }
        }
        return plans
    }

    // MARK: Bildirim

    private func syncNotifications(_ plans: [Plan], strings: Strings, vacationEnd: Date?) async {
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        var requests: [UNNotificationRequest] = []
        if plans.count <= Self.notificationLimit {
            requests = plans.enumerated().map { index, plan in request(for: plan, index: index, strings: strings) }
        } else {
            // Çok kalabalık program: en yakın hatırlatmalar tek tek kurulur, uygulama açıldıkça yenilenir.
            requests = upcoming(plans, days: 7).prefix(Self.notificationLimit).enumerated().map { index, item in
                request(for: Plan(group: item.0.group, when: .once(item.1)), index: index, strings: strings)
            }
        }

        // Hocanın tatili bitince: "Hatırlatmalar yeniden açık" (uygulamayı açtırıp listeyi yeniler).
        if let vacationEnd, let morning = Calendar.remi.date(byAdding: .day, value: 1, to: Calendar.remi.startOfDay(for: vacationEnd))?
            .addingTimeInterval(8 * 3600), morning > .now {
            let content = UNMutableNotificationContent()
            content.title = "Remi"
            content.body = strings.welcomeBack
            content.sound = .default
            let components = Calendar.remi.dateComponents([.year, .month, .day, .hour, .minute], from: morning)
            requests.append(UNNotificationRequest(identifier: Self.prefix + "vacation-end", content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }

        for request in requests {
            do { try await center.add(request) } catch { print("Bildirim kurulamadı: \(error)") }
        }
    }

    private func request(for plan: Plan, index: Int, strings: Strings) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.group.name
        content.body = strings.reminderBody(group: plan.group, minutesBefore: plan.group.reminder.minutesBefore)
        content.sound = .default
        content.threadIdentifier = "lessons"
        content.userInfo = ["groupID": plan.group.id.uuidString]

        let trigger: UNCalendarNotificationTrigger
        switch plan.when {
        case .weekly(let day, let minute):
            var components = DateComponents()
            components.weekday = day.calendarWeekday
            components.hour = minute / 60
            components.minute = minute % 60
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .once(let date):
            trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.remi.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        }
        return UNNotificationRequest(identifier: "\(Self.prefix)\(plan.group.id.uuidString).\(index)", content: content, trigger: trigger)
    }

    private func upcoming(_ plans: [Plan], days: Int, now: Date = .now) -> [(Plan, Date)] {
        let calendar = Calendar.remi
        let today = calendar.startOfDay(for: now)
        var result: [(Plan, Date)] = []
        for plan in plans {
            switch plan.when {
            case .once(let date):
                if date < calendar.date(byAdding: .day, value: days, to: today)! { result.append((plan, date)) }
            case .weekly(let weekday, let minute):
                for offset in 0...days {
                    let day = calendar.date(byAdding: .day, value: offset, to: today)!
                    let fire = day.addingTimeInterval(TimeInterval(minute * 60))
                    if Weekday(date: day, calendar: calendar) == weekday, fire > now { result.append((plan, fire)) }
                }
            }
        }
        return result.sorted { $0.1 < $1.1 }
    }

    // MARK: Alarm (iOS 26+)

    private func syncAlarms(_ plans: [Plan], strings: Strings) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        let manager = AlarmManager.shared
        for alarm in (try? manager.alarms) ?? [] { try? manager.cancel(id: alarm.id) }
        for plan in plans {
            let schedule: Alarm.Schedule
            switch plan.when {
            case .once(let date):
                schedule = .fixed(date)
            case .weekly(let day, let minute):
                schedule = .relative(.init(time: .init(hour: minute / 60, minute: minute % 60), repeats: .weekly([day.localeWeekday])))
            }
            let title = "\(plan.group.name) · \(strings.reminderBody(group: plan.group, minutesBefore: plan.group.reminder.minutesBefore))"
            await scheduleAlarm(title: title, schedule: schedule, color: plan.group.color.color, stop: strings.close)
        }
        #endif
    }

    // MARK: Deneme

    func sendTest(strings: Strings, kind: ReminderKind) async {
        let sample = StudyGroup(name: "Remi", days: [.monday], startMinute: 9 * 60)
        #if canImport(AlarmKit)
        if kind == .alarm, #available(iOS 26.0, *) {
            await requestPermissions(for: .alarm)
            if alarmAuthorized() {
                await scheduleAlarm(title: strings.reminderBody(group: sample, minutesBefore: 10),
                                    schedule: .fixed(.now.addingTimeInterval(10)), color: Brand.ping, stop: strings.close)
                return
            }
        }
        #endif
        if await notificationStatus() == .notDetermined { await requestNotificationPermission() }
        let content = UNMutableNotificationContent()
        content.title = sample.name
        content.body = strings.reminderBody(group: sample, minutesBefore: 10)
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarm(title: String, schedule: Alarm.Schedule, color: Color, stop: String) async {
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), secondaryButton: nil, secondaryButtonBehavior: nil)
        } else {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title),
                                            stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: stop), textColor: .white, systemImageName: "stop.fill"),
                                            secondaryButton: nil, secondaryButtonBehavior: nil)
        }
        let attributes = AlarmAttributes<RemiAlarmMetadata>(presentation: AlarmPresentation(alert: alert), metadata: RemiAlarmMetadata(), tintColor: color)
        let configuration = AlarmManager.AlarmConfiguration<RemiAlarmMetadata>(
            countdownDuration: nil, schedule: schedule, attributes: attributes, stopIntent: nil, secondaryIntent: nil)
        do { _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration) }
        catch { print("Alarm kurulamadı: \(error)") }
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct RemiAlarmMetadata: AlarmMetadata {}

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
