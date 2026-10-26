import SwiftUI
import UserNotifications

@main
struct DersProgramiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ScheduleStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ScheduleView()
                .environment(store)
                // Dosyalar / WhatsApp / Mail'den "Paylaş → Ders Programı" ile gelen Excel.
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
