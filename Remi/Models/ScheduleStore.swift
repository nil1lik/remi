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

    /// Kayıtlı grup adları, en çok kullanılandan aza (elle eklerken öneri olarak).
    var groupTitles: [String] {
        var counts: [String: Int] = [:]
        for lesson in lessons { counts[lesson.title, default: 0] += 1 }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
    }

    /// Aynı adlı son kayıt; yeni derse yer ve süreyi önermek için.
    func template(forTitle title: String) -> Lesson? {
        let key = ScheduleImporter.normalize(title)
        return lessons.last { ScheduleImporter.normalize($0.title) == key }
    }

    /// Verilen derslerle aynı gün ve saatte çakışan kayıtlar.
    func conflicts(with candidates: [Lesson], excluding excluded: Set<Lesson.ID> = []) -> [Lesson] {
        lessons.filter { existing in
            !excluded.contains(existing.id) && candidates.contains { $0.overlaps(existing) }
        }
        .sorted { ($0.weekday?.rawValue ?? 8, $0.start) < ($1.weekday?.rawValue ?? 8, $1.start) }
    }

    // MARK: Değişiklikler

    func update(_ lesson: Lesson) {
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }), lessons[index] != lesson else { return }
        lessons[index] = lesson
        save()
        rescheduleReminders()
    }

    /// Elle eklenen dersler. İlk eklemede hatırlatma izni istenir.
    func add(_ newLessons: [Lesson]) {
        guard !newLessons.isEmpty else { return }
        let wasEmpty = lessons.isEmpty
        lessons.append(contentsOf: newLessons)
        save()
        if wasEmpty {
            Task {
                await scheduler.requestPermissions(for: reminder.kind)
                rescheduleReminders()
            }
        } else {
            rescheduleReminders()
        }
    }

    /// Düzenlenen dersi ilk kayıtla değiştirir, kalanları (yeni seçilen günler) ekler.
    func replace(_ id: Lesson.ID, with edited: [Lesson]) {
        guard let index = lessons.firstIndex(where: { $0.id == id }), let first = edited.first else { return }
        lessons[index] = first
        lessons.append(contentsOf: edited.dropFirst())
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

    /// `merge` doğruysa dosyadaki dersler mevcut programa eklenir (aynısı zaten varsa atlanır),
    /// değilse programın yerine geçer.
    func applyPendingImport(merge: Bool = false) {
        guard let pending = pendingImport else { return }
        if merge {
            let existing = Set(lessons.map(\.identityKey))
            lessons += pending.result.lessons.filter { !existing.contains($0.identityKey) }
        } else {
            lessons = pending.result.lessons
        }
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
