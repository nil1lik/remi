import SwiftUI
import UserNotifications

@main
struct RemiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore
    @State private var sync: SyncService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _sync = State(initialValue: SyncService(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Saat dilimi değişmiş, tatil bitmiş ya da kalabalık programın listesi azalmış olabilir.
            store.endVacationIfOver()
            store.reschedule()
            Task { await sync.syncNow() }
        }
    }
}

/// Açılış animasyonu → giriş → kişiselleştirme → ana ekran.
struct RootView: View {
    @Environment(AppStore.self) private var store
    #if DEBUG
    @State private var showSplash = !DebugDemo.skipSplash
    #else
    @State private var showSplash = true
    #endif
    #if DEBUG
    @State private var passedLogin = DebugDemo.screen == "personalize"
    #else
    @State private var passedLogin = false
    #endif

    var body: some View {
        ZStack {
            Group {
                if store.onboarded {
                    MainView()
                } else if passedLogin {
                    PersonalizeView()
                } else {
                    LoginView { withAnimation(.snappy) { passedLogin = true } }
                }
            }
            .environment(\.strings, store.strings)
            .environment(\.accent, store.profile.accent)
            .environment(\.layoutDirection, store.profile.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.locale, store.profile.language.locale)
            .preferredColorScheme(store.profile.theme.colorScheme)
            .tint(store.profile.accent.fill)

            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.5)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Uygulama açıkken de hatırlatma görünsün.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
