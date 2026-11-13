import Foundation
import Observation

/// Giriş, çıkış ve cihazlar arası eşitleme. Uygulama çevrimdışı çalışır: değişiklikler önce telefona
/// yazılır, bağlantı varken sunucuya gönderilir, ardından sunucudaki değişiklikler çekilir.
@MainActor
@Observable
final class SyncService {
    @ObservationIgnored let api = APIClient()
    @ObservationIgnored private let signInService = SignInService()
    @ObservationIgnored private unowned let store: AppStore
    @ObservationIgnored private var running = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var debounce: Task<Void, Never>?

    init(store: AppStore) {
        self.store = store
        store.onChange = { [weak self] in self?.scheduleSync() }
    }

    var canSignIn: Bool { api.isConfigured }
    var googleAvailable: Bool { api.isConfigured && SignInService.googleClientID != nil }

    // MARK: Oturum

    func signIn(provider: String) async throws {
        guard api.isConfigured else { throw SignInService.SignInError.notConfigured }
        let credential = provider == "apple"
            ? try await signInService.signInWithApple()
            : try await signInService.signInWithGoogle()
        let name = store.profile.displayName.isEmpty ? (credential.givenName ?? "") : store.profile.displayName
        let response = try await api.signIn(provider: provider, idToken: credential.idToken, nonce: credential.nonce,
                                            displayName: name, language: store.profile.language)
        store.signedIn(.init(id: response.profile.id, provider: provider == "apple" ? "Apple" : "Google"),
                       serverProfile: response.profile.profile)
        await syncNow()
    }

    func signOut() async {
        await api.signOut()
        store.signedOut()
    }

    func deleteAccount() async throws {
        try await api.deleteAccount()
        store.signedOut()
    }

    // MARK: Eşitleme

    func scheduleSync() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func syncNow() async {
        guard store.isSignedIn, api.isConfigured else { return }
        if running { runAgain = true; return }
        running = true
        store.syncStatus = .syncing
        do {
            try await pushProfile()
            try await pushGroups()
            try await pull()
            store.syncStatus = .synced(.now)
        } catch APIClient.APIError.sessionExpired {
            store.signedOut()
        } catch {
            store.syncStatus = .failed
        }
        running = false
        if runAgain {
            runAgain = false
            await syncNow()
        }
    }

    private func pushProfile() async throws {
        guard store.profileDirty else { return }
        let profile = store.profile
        _ = try await api.updateProfile(ProfilePatch(profile))
        if let vacation = profile.vacation { _ = try await api.startVacation(DateRangeDTO(vacation)) }
        else { _ = try await api.endVacation() }
        store.markProfileSynced()
    }

    private func pushGroups() async throws {
        for (id, change) in store.pending {
            switch change {
            case .upsert:
                guard let group = store.group(id) else { store.markDeletedOnServer(id); continue }
                try await upload(group)
            case .delete(let version):
                do {
                    try await api.deleteGroup(id, version: version > 0 ? version : nil)
                } catch APIClient.APIError.notFound {
                    // Zaten yok.
                } catch APIClient.APIError.conflict {
                    // Başka cihaz değiştirmiş; silme kararı yine de geçerli.
                    try? await api.deleteGroup(id, version: nil)
                }
                store.markDeletedOnServer(id)
            }
        }
    }

    private func upload(_ group: StudyGroup) async throws {
        do {
            let saved = group.version == 0
                ? try await api.createGroup(GroupDTO(group))
                : try await api.updateGroup(GroupDTO(group))
            store.markSynced(group.id, version: saved.version ?? group.version + 1)
        } catch APIClient.APIError.notFound {
            // Başka cihazda silinmiş: telefondaki hali yeniden oluşturulur.
            var fresh = group
            fresh.version = 0
            let saved = try await api.createGroup(GroupDTO(fresh))
            store.markSynced(group.id, version: saved.version ?? 1)
        } catch APIClient.APIError.conflict(let data) {
            // Sürüm çakışması: sunucudaki güncel hal kazanır.
            if let current = (try? JSONDecoder.api.decode(ConflictBody.self, from: data))?.current, current.deleted != true {
                store.replaceWithServer(current.group)
            } else {
                store.markDeletedOnServer(group.id)
            }
        }
    }

    private func pull() async throws {
        let response = try await api.sync(since: store.cursor)
        store.applyRemote(
            groups: response.groups.filter { $0.deleted != true }.map(\.group),
            deleted: response.groups.filter { $0.deleted == true }.map(\.id),
            profile: response.profile?.profile,
            cursor: response.cursor)
    }
}
