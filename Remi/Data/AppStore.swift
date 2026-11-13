import Foundation
import Observation

/// Uygulamanın tek veri kaynağı: gruplar, profil ve eşitleme durumu.
/// Her değişiklik diske yazılır, hatırlatmalar yeniden kurulur ve (giriş yapılmışsa) sunucuya gönderilir.
@MainActor
@Observable
final class AppStore {
    private(set) var groups: [StudyGroup] = []
    private(set) var profile = Profile()
    private(set) var onboarded = false
    private(set) var account: AccountInfo?
    var syncStatus: SyncStatus = .idle
    /// "Tatilden geldim" sonrası Bugün ekranındaki karşılama mesajı.
    var showWelcomeBack = false

    struct AccountInfo: Codable, Hashable {
        var id: UUID
        var provider: String
    }

    enum SyncStatus: Equatable { case idle, syncing, synced(Date), failed }

    /// Sunucuya henüz gitmemiş değişiklikler (çevrimdışı çalışma).
    enum PendingChange: Codable, Hashable { case upsert, delete(version: Int) }
    private(set) var pending: [UUID: PendingChange] = [:]
    private(set) var profileDirty = false
    private(set) var cursor: Int64 = 0

    @ObservationIgnored let scheduler = ReminderScheduler()
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    var strings: Strings { Strings(language: profile.language) }

    /// Demo modunda (yalnız Debug) hiçbir şey diske yazılmaz.
    @ObservationIgnored private var ephemeral = false

    init() {
        #if DEBUG
        if DebugDemo.isActive {
            ephemeral = true
            seedDemo()
            return
        }
        #endif
        load()
        endVacationIfOver()
    }

    // MARK: Profil

    func completeOnboarding(_ profile: Profile) {
        self.profile = profile
        onboarded = true
        profileDirty = true
        commit()
        Task { await scheduler.requestPermissions(for: profile.defaultReminder.kind) }
    }

    func updateProfile(_ change: (inout Profile) -> Void) {
        var copy = profile
        change(&copy)
        if copy.displayName.count > 40 { copy.displayName = String(copy.displayName.prefix(40)) }
        guard copy != profile else { return }
        profile = copy
        profileDirty = true
        commit()
    }

    /// "Ben tatildeyim": aralık boyunca tüm hatırlatmalar susar.
    func startVacation(_ range: DayRange) {
        updateProfile { $0.vacation = range }
    }

    /// "Tatilden geldim".
    func endVacation() {
        updateProfile { $0.vacation = nil }
        showWelcomeBack = true
    }

    var isOnVacationToday: Bool { profile.isOnVacation(on: .now) }

    /// Tatil bitişi geçtiyse Remi kendiliğinden uyanır.
    func endVacationIfOver() {
        if let vacation = profile.vacation, Calendar.remi.startOfDay(for: vacation.end) < Calendar.remi.startOfDay(for: .now) {
            updateProfile { $0.vacation = nil }
        }
    }

    // MARK: Gruplar

    var canAddGroup: Bool { groups.count < GroupRules.maxGroups }

    func group(_ id: UUID) -> StudyGroup? { groups.first { $0.id == id } }

    @discardableResult
    func save(_ group: StudyGroup) -> Bool {
        guard GroupRules.problems(of: group).isEmpty else { return false }
        var clean = group
        clean.name = GroupRules.clean(group.name)
        clean.chatLink = group.chatLink.flatMap { $0.isEmpty ? nil : ChatLinkRule.normalized($0) }
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = clean
        } else {
            guard canAddGroup else { return false }
            groups.append(clean)
            if groups.count == 1 { Task { await scheduler.requestPermissions(for: clean.reminder.kind) } }
        }
        markPending(clean.id, .upsert)
        commit()
        return true
    }

    func delete(_ id: UUID) {
        guard let group = group(id) else { return }
        groups.removeAll { $0.id == id }
        // Sunucuya hiç gitmemiş grubu silmek için istek gerekmez.
        if group.version == 0, pending[id] == .upsert { pending[id] = nil } else { markPending(id, .delete(version: group.version)) }
        commit()
    }

    /// Seçilen grupları tatile alır (ya da tatilini bitirir).
    func setHoliday(_ range: DayRange?, for ids: Set<UUID>) {
        for index in groups.indices where ids.contains(groups[index].id) {
            groups[index].holiday = range
            markPending(groups[index].id, .upsert)
        }
        commit()
    }

    func plan(for day: Date) -> DayPlan { DayPlan(day: day, groups: groups, profile: profile) }

    // MARK: Hesap ve eşitleme (SyncService kullanır)

    var isSignedIn: Bool { account != nil }

    func signedIn(_ info: AccountInfo, serverProfile: Profile?) {
        account = info
        // İlk kurulumda (yeni telefon) hesaptaki ayarlar gelir; uygulama zaten kullanılıyorsa
        // telefondaki ayarlar hesaba yazılır. Telefondaki gruplar her durumda sunucuya gönderilir.
        if !onboarded, let serverProfile {
            profile.merge(server: serverProfile)
            profileDirty = false
        } else {
            profileDirty = true
        }
        for group in groups where pending[group.id] == nil { pending[group.id] = .upsert }
        cursor = 0
        commit()
    }

    func signedOut() {
        account = nil
        cursor = 0
        syncStatus = .idle
        // Telefondaki program kalır; yeniden girişte tekrar gönderilir.
        for index in groups.indices { groups[index].version = 0 }
        pending = [:]
        persist()
    }

    func markSynced(_ id: UUID, version: Int) {
        if let index = groups.firstIndex(where: { $0.id == id }) { groups[index].version = version }
        pending[id] = nil
        persist()
    }

    func markDeletedOnServer(_ id: UUID) {
        pending[id] = nil
        persist()
    }

    func markProfileSynced() {
        profileDirty = false
        persist()
    }

    /// Sunucudan gelen değişiklikler. Telefonda gönderilmeyi bekleyen değişiklik varsa o kazanır.
    func applyRemote(groups remote: [StudyGroup], deleted: [UUID], profile remoteProfile: Profile?, cursor newCursor: Int64) {
        for id in deleted where pending[id] == nil { groups.removeAll { $0.id == id } }
        for group in remote where pending[group.id] == nil {
            if let index = groups.firstIndex(where: { $0.id == group.id }) { groups[index] = group } else { groups.append(group) }
        }
        if let remoteProfile, !profileDirty { profile.merge(server: remoteProfile) }
        cursor = newCursor
        persist()
        reschedule()
    }

    /// Sürüm çakışmasında sunucudaki güncel hal alınır.
    func replaceWithServer(_ group: StudyGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) { groups[index] = group }
        pending[group.id] = nil
        persist()
        reschedule()
    }

    // MARK: Kayıt

    private func markPending(_ id: UUID, _ change: PendingChange) {
        guard isSignedIn else { return }
        pending[id] = change
    }

    private func commit() {
        persist()
        reschedule()
        onChange?()
    }

    func reschedule() {
        rescheduleTask?.cancel()
        let groups = groups, profile = profile
        rescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await scheduler.sync(groups: groups, profile: profile)
        }
    }

    private struct Snapshot: Codable {
        var groups: [StudyGroup]
        var profile: Profile
        var onboarded: Bool
        var account: AccountInfo?
        var pending: [UUID: PendingChange]
        var profileDirty: Bool
        var cursor: Int64
    }

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("remi.json")
    }

    private func persist() {
        guard !ephemeral else { return }
        let snapshot = Snapshot(groups: groups, profile: profile, onboarded: onboarded, account: account,
                                pending: pending, profileDirty: profileDirty, cursor: cursor)
        do {
            // Telefon kilitliyken dosya şifreli kalır.
            try JSONEncoder().encode(snapshot).write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Kaydedilemedi: \(error)")
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: Self.fileURL), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            (groups, profile, onboarded, account, pending, profileDirty, cursor) =
                (s.groups, s.profile, s.onboarded, s.account, s.pending, s.profileDirty, s.cursor)
        } else if let migrated = LegacyImport.groups() {
            groups = migrated
        }
    }
}

#if DEBUG
extension AppStore {
    /// Ekran görüntüsü ve deneme için örnek program (REMI_DEMO=1).
    fileprivate func seedDemo() {
        let today = Calendar.remi.startOfDay(for: .now)
        groups = [
            StudyGroup(name: "A1-20 sınıfı", color: .blue, chatLink: "https://chat.whatsapp.com/AbC123xyz", days: [.thursday, .saturday], startMinute: 9 * 60),
            StudyGroup(name: "A2-14", color: .green, chatLink: "https://t.me/+AbCdEf", days: [.monday, .wednesday], startMinute: 17 * 60 + 30, durationMinutes: 90),
            StudyGroup(name: "B1-07", color: .coral, chatLink: "https://chat.whatsapp.com/Xyz987", days: [.tuesday, .thursday, .friday], startMinute: 18 * 60, durationMinutes: 90,
                       holiday: DayRange(start: today, end: Calendar.remi.date(byAdding: .day, value: 7, to: today)!)),
            StudyGroup(name: "Özel ders · Elif", color: .rose, chatLink: "https://chat.whatsapp.com/Elif2026", days: [.thursday, .friday], startMinute: 14 * 60,
                       reminder: ReminderSetting(minutesBefore: 120, kind: .alarm)),
        ]
        profile = Profile(displayName: "Hocam", language: DebugDemo.language, theme: DebugDemo.theme, accent: DebugDemo.accent)
        if DebugDemo.screen == "sleep" {
            profile.vacation = DayRange(start: today, end: Calendar.remi.date(byAdding: .day, value: 10, to: today)!)
        }
        onboarded = !["login", "personalize"].contains(DebugDemo.screen)
        if DebugDemo.screen == "empty" { groups = [] }
    }
}
#endif

extension Profile {
    /// Sunucudaki tercihleri alır; bu telefona ait olmayan bir şey yok.
    mutating func merge(server: Profile) {
        displayName = server.displayName
        language = server.language
        theme = server.theme
        accent = server.accent
        defaultReminder = server.defaultReminder
        vacation = server.vacation
    }
}

/// Önceki sürümün (ders listesi) verisini gruplara çevirir: aynı ad ve saatteki dersler tek grup olur.
enum LegacyImport {
    private struct OldFile: Decodable { var lessons: [OldLesson] }
    private struct OldLesson: Decodable {
        var title: String
        var weekday: Int?
        var start: Int
        var end: Int?
    }

    static func groups() -> [StudyGroup]? {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("schedule.json")),
              let file = try? JSONDecoder().decode(OldFile.self, from: data)
        else { return nil }

        var result: [StudyGroup] = []
        let weekly = file.lessons.filter { $0.weekday != nil }
        for (key, lessons) in Dictionary(grouping: weekly, by: { "\($0.title)|\($0.start)|\($0.end ?? $0.start + 60)" }) {
            guard let first = lessons.first else { continue }
            let duration = min(max((first.end ?? first.start + 60) - first.start, GroupRules.minDuration), GroupRules.maxDuration)
            var group = StudyGroup(name: String(first.title.prefix(GroupRules.maxNameLength)),
                                   color: GroupColor.next(after: result),
                                   days: Set(lessons.compactMap { $0.weekday.flatMap(Weekday.init(rawValue:)) }),
                                   startMinute: first.start, durationMinutes: duration)
            if group.startMinute + group.durationMinutes > 24 * 60 { group.durationMinutes = 24 * 60 - group.startMinute }
            if GroupRules.problems(of: group).isEmpty { result.append(group) }
            _ = key
        }
        return result.isEmpty ? nil : result.sorted { $0.startMinute < $1.startMinute }
    }
}
