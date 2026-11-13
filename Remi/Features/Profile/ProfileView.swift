import SwiftUI
import UserNotifications

/// Profil: hesap ve yedek, dil, görünüm, renk, varsayılan hatırlatma, "Ben tatildeyim", çıktı ve hesap işlemleri.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWheel = false
    @State private var testSent = false
    @State private var confirmDelete = false
    @State private var signInFailed = false
    @State private var notificationsDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(s.profile).font(Brand.display(32, language: s.language)).tracking(s.language == .ar ? 0 : -1)
                accountCard

                if notificationsDenied {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(s.notificationsOff, systemImage: "bell.slash.fill").font(.subheadline.weight(.semibold))
                        Button(s.openSettings) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(Brand.holidayText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.holidayBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                HStack(spacing: 8) {
                    ForEach(AppLanguage.allCases) { language in
                        let on = store.profile.language == language
                        Button { store.updateProfile { $0.language = language } } label: {
                            Text(language.nativeName).font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .foregroundStyle(Brand.text)
                                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? accent.fill : Brand.line, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .fieldLabel(s.languageLabel)

                SegmentedPills(options: ThemeMode.allCases, selection: binding(\.theme), title: s.theme)
                    .fieldLabel(s.appearance)

                ColorDots(options: AccentChoice.allCases, selection: binding(\.accent), color: \.fill, label: s.accentName, size: 40)
                    .fieldLabel(s.appColor)

                reminderCard.fieldLabel(s.newGroupReminder)

                vacationCard

                VStack(spacing: 0) {
                    Button {
                        Task {
                            await store.scheduler.sendTest(strings: s, kind: store.profile.defaultReminder.kind)
                            testSent = true
                        }
                    } label: {
                        listRow(testSent ? s.testSent : s.testNotification, "bell")
                    }
                    .buttonStyle(.plain)
                    if !store.groups.isEmpty {
                        Divider().overlay(Brand.line)
                        NavigationLink(value: ExportRoute()) { listRow(s.exportLink, "square.and.arrow.down") }.buttonStyle(.plain)
                    }
                    if store.isSignedIn {
                        Divider().overlay(Brand.line)
                        Button { Task { await sync.signOut() } } label: { listRow(s.signOut, "rectangle.portrait.and.arrow.right", color: Brand.danger) }
                            .buttonStyle(.plain)
                        Divider().overlay(Brand.line)
                        Button { confirmDelete = true } label: { listRow(s.deleteAccount, "trash", color: Brand.danger) }
                            .buttonStyle(.plain)
                    }
                }
                .card(radius: 22)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Brand.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(s.deleteAccount, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(s.deleteAccount, role: .destructive) { Task { try? await sync.deleteAccount() } }
        } message: {
            Text(s.deleteAccountConfirm)
        }
        .alert(s.signInFailed, isPresented: $signInFailed) { Button(s.close, role: .cancel) {} }
        .task(id: scenePhase) {
            notificationsDenied = await store.scheduler.notificationStatus() == .denied
        }
        .task(id: testSent) {
            guard testSent else { return }
            try? await Task.sleep(for: .seconds(6))
            testSent = false
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { store.profile[keyPath: keyPath] }, set: { value in store.updateProfile { $0[keyPath: keyPath] = value } })
    }

    // MARK: Hesap

    private var accountCard: some View {
        HStack(spacing: 14) {
            Text(String(store.profile.displayName.first.map(String.init) ?? "R").uppercased())
                .font(Brand.display(24, language: s.language))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(accent.fill, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                TextField(s.namePlaceholder, text: binding(\.displayName))
                    .font(.headline)
                    .submitLabel(.done)
                if let account = store.account {
                    Text(s.signedIn(with: account.provider)).font(.footnote).foregroundStyle(Brand.secondary)
                    syncLine
                } else {
                    Text(s.notSignedIn).font(.footnote).foregroundStyle(Brand.secondary)
                    if sync.canSignIn {
                        Button(s.signIn) {
                            Task {
                                do { try await sync.signIn(provider: "apple") }
                                catch SignInService.SignInError.cancelled {}
                                catch { signInFailed = true }
                            }
                        }
                        .font(.footnote.weight(.bold))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var syncLine: some View {
        switch store.syncStatus {
        case .synced(let date):
            Label("\(s.backedUp) · \(date.formatted(.relative(presentation: .named).locale(s.locale)))", systemImage: "checkmark")
                .font(.caption.weight(.bold)).foregroundStyle(Brand.newsText)
        case .failed:
            Label(s.syncFailed, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.caption.weight(.bold)).foregroundStyle(Brand.holidayText)
        case .syncing:
            ProgressView().controlSize(.mini)
        case .idle:
            EmptyView()
        }
    }

    // MARK: Hatırlatma ve tatil

    private var reminderCard: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy) { showWheel.toggle() } } label: {
                HStack {
                    Text(s.reminderShort(store.profile.defaultReminder)).font(.body.weight(.semibold)).foregroundStyle(Brand.text)
                    Spacer()
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Brand.secondary)
                        .rotationEffect(.degrees(showWheel ? 180 : 0))
                }
                .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showWheel {
                ReminderWheel(minutes: binding(\.defaultReminder.minutesBefore)).padding(.horizontal, 8)
            }
            SegmentedPills(options: ReminderKind.allCases, selection: binding(\.defaultReminder.kind), title: s.kind)
                .padding([.horizontal, .bottom], 12)
        }
        .card(radius: 22)
        .onChange(of: store.profile.defaultReminder.kind) { _, kind in
            Task { await store.scheduler.requestPermissions(for: kind) }
        }
    }

    private var vacationCard: some View {
        let on = store.profile.vacation != nil
        return SwitchRow(
            title: on ? s.vacationOn(until: store.profile.vacation!.end) : s.meOnVacation,
            detail: on ? s.remindersSilent : s.turnOnSilences,
            icon: "beach.umbrella",
            isOn: Binding(get: { on }, set: { value in
                if value {
                    let start = Calendar.remi.startOfDay(for: .now)
                    store.startVacation(DayRange(start: start, end: Calendar.remi.date(byAdding: .day, value: 6, to: start)!))
                } else {
                    store.endVacation()
                }
            }),
            tint: Color(hex: 0x9A5B00))
        .foregroundStyle(on ? Brand.holidayText : Brand.text)
        .background(on ? Brand.holidayBackground : Brand.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(on ? .clear : Brand.line))
    }

    private func listRow(_ title: String, _ icon: String, color: Color = Brand.text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22)
            Text(title).font(.body.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
    }
}
