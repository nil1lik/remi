import Foundation
import Observation

/// Programın ve ayarların tek kaynağı. Değişiklikler diske yazılır ve hatırlatmalar yeniden kurulur.
@MainActor
@Observable
final class ScheduleStore {
    private(set) var lessons: [Lesson] = []
    private(set) var lastImport: Date?

    var reminder = ReminderSettings() {
        didSet {
            guard reminder != oldValue else { return }
            save()
            rescheduleReminders()
        }
    }

    /// Önizlemesi gösterilen, henüz uygulanmamış içe aktarma.
    var pendingImport: PendingImport?
    var importError: String?
    /// Ayarlar ekranından dosya seçici istendiğinde ana ekran açar.
    var importRequestID = 0

    @ObservationIgnored let scheduler = ReminderScheduler()
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    struct PendingImport: Identifiable {
        let id = UUID()
        var fileName: String
        var result: ScheduleImporter.Result
    }

    private struct Snapshot: Codable {
        var lessons: [Lesson]
        var reminder: ReminderSettings
        var lastImport: Date?
    }

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("schedule.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            lessons = snapshot.lessons
            reminder = snapshot.reminder
            lastImport = snapshot.lastImport
        }
    }

    // MARK: Sorgular

    func lessons(on day: Date) -> [Lesson] {
        lessons.filter { $0.occurs(on: day) }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    func hasLessons(on day: Date) -> Bool {
        lessons.contains { $0.occurs(on: day) }
    }

    func effectiveReminder(for lesson: Lesson) -> ReminderSettings {
        lesson.customReminder ?? reminder
    }

    // MARK: Değişiklikler

    func update(_ lesson: Lesson) {
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }), lessons[index] != lesson else { return }
        lessons[index] = lesson
        save()
        rescheduleReminders()
    }

    func delete(_ lesson: Lesson) {
        lessons.removeAll { $0.id == lesson.id }
        save()
        rescheduleReminders()
    }

    func clearSchedule() {
        lessons = []
        lastImport = nil
        save()
        rescheduleReminders()
    }

    // MARK: İçe aktarma

    func requestFilePicker() {
        importRequestID += 1
    }

    /// Dosya seçiciden ya da başka bir uygulamadan ("Paylaş → Remi") gelen dosya.
    func prepareImport(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try ScheduleImporter.importFile(at: url)
            pendingImport = PendingImport(fileName: url.lastPathComponent, result: result)
        } catch {
            importError = error.localizedDescription
        }
    }

    func applyPendingImport() {
        guard let pending = pendingImport else { return }
        lessons = pending.result.lessons
        lastImport = .now
        pendingImport = nil
        save()
        Task {
            await scheduler.requestPermissions(for: reminder.kind)
            rescheduleReminders()
        }
    }

    // MARK: Hatırlatmalar

    /// Arka arkaya gelen değişiklikleri tek bir yeniden kurulumda toplar.
    func rescheduleReminders() {
        rescheduleTask?.cancel()
        let lessons = lessons
        let defaults = reminder
        rescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await scheduler.sync(lessons: lessons, defaults: defaults)
        }
    }

    private func save() {
        let snapshot = Snapshot(lessons: lessons, reminder: reminder, lastImport: lastImport)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("Program kaydedilemedi: \(error)")
        }
    }
}
