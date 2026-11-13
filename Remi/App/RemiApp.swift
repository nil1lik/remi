import SwiftUI
import UserNotifications

@main
struct RemiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ScheduleStore()
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ScheduleView()
                    .scaleEffect(showSplash ? 0.94 : 1)
                    .opacity(showSplash ? 0 : 1)
                if showSplash {
                    SplashView {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { showSplash = false }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(1)
                }
            }
            .environment(store)
            // Dosyalar / WhatsApp / Mail'den "Paylaş → Remi" ile gelen Excel.
            .onOpenURL { url in
                store.prepareImport(from: url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Saat dilimi değişmiş ya da yoğun programda 7 günlük liste bitiyor olabilir.
            if phase == .active { store.rescheduleReminders() }
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
