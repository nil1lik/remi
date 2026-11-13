import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var notificationStatus: UNAuthorizationStatus = .authorized
    @State private var alarmDenied = false
    @State private var confirmClear = false
    @State private var testSent = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Toggle("Derslerden önce hatırlat", isOn: $store.reminder.isEnabled)
                    if store.reminder.isEnabled {
                        ReminderControls(settings: $store.reminder)
                    }
                } header: {
                    Text("Hatırlatma")
                } footer: {
                    Text(kindExplanation)
                }

                if store.reminder.isEnabled, let warning = permissionWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Ayarlar'ı aç") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }

                if store.reminder.isEnabled {
                    Section {
                        Button {
                            testSent = true
                            Task { await store.scheduler.sendTest(kind: store.reminder.kind, minutesBefore: store.reminder.minutesBefore) }
                        } label: {
                            Label(testSent ? "Gönderildi, birkaç saniye bekle" : "Deneme hatırlatması gönder",
                                  systemImage: testSent ? "checkmark.circle" : "paperplane")
                        }
                        .disabled(testSent)
                    } footer: {
                        Text("Nasıl göründüğünü görmek için uygulamadan çıkıp kilit ekranında bekle.")
                    }
                }

                Section {
                    NavigationLink {
                        ProgramEditorView()
                    } label: {
                        Label(store.lessons.isEmpty ? "Elle program oluştur" : "Haftalık programı düzenle",
                              systemImage: "calendar.day.timeline.left")
                    }
                    if let url = TemplateFile.url {
                        ShareLink(item: url, preview: SharePreview("Ders Programı Şablonu")) {
                            Label("Örnek Excel'i indir", systemImage: "arrow.down.doc")
                        }
                    }
                    Button {
                        store.requestFilePicker()
                    } label: {
                        Label("Excel'den içe aktar", systemImage: "square.and.arrow.down")
                    }
                    if !store.lessons.isEmpty {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label("Programı temizle", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Ders programı")
                } footer: {
                    Text(programFooter)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .confirmationDialog("Tüm program silinsin mi?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Programı sil", role: .destructive) { store.clearSchedule() }
            } message: {
                Text("Kurulu hatırlatmalar da kaldırılır.")
            }
            .task(id: scenePhase) { await refreshPermissions() }
            .task(id: store.reminder.kind) { await refreshPermissions() }
            .task(id: testSent) {
                guard testSent else { return }
                try? await Task.sleep(for: .seconds(6))
                testSent = false
            }
        }
    }

    private var kindExplanation: String {
        guard store.reminder.isEnabled else { return "Hatırlatma kapalı. Uygulama sana haber vermez." }
        if !store.scheduler.alarmsSupported {
            return "Alarm için iPhone'un iOS 26 ya da üstü olmalı. Şimdilik bildirim gönderilir."
        }
        switch store.reminder.kind {
        case .notification:
            return "Kilit ekranında bildirim ve kısa bir ses. Telefon sessizdeyse ses çıkmaz."
        case .alarm:
            return "Saat uygulamasındaki alarm gibi tam ekran çalar; sessiz modda ve Odak açıkken de duyulur."
        }
    }

    private var permissionWarning: String? {
        if store.reminder.kind == .alarm, alarmDenied {
            return "Alarm izni kapalı. Ayarlar → Remi → Alarmlar'dan açabilirsin. O zamana kadar bildirim gönderilir."
        }
        if notificationStatus == .denied {
            return "Bildirim izni kapalı. Ayarlar → Remi → Bildirimler'den açmazsan hatırlatma gelmez."
        }
        return nil
    }

    private var programFooter: String {
        guard !store.lessons.isEmpty else {
            return "Derslerini elle ekleyebilir ya da örnek Excel'i doldurup buradan içe aktarabilirsin. Dosyaları WhatsApp ya da Dosyalar'dan \"Paylaş → Remi\" ile de açabilirsin."
        }
        let groups = Set(store.lessons.map(\.title)).count
        var text = "\(groups) grup, haftada \(store.lessons.filter(\.isRecurring).count) ders."
        if let date = store.lastImport {
            text += " Son içe aktarma: \(DateText.shortDate.string(from: date))."
        }
        return text + " Yeni içe aktarma eski programın yerine geçer."
    }

    private func refreshPermissions() async {
        notificationStatus = await store.scheduler.notificationStatus()
        alarmDenied = store.scheduler.alarmPermissionDenied()
    }
}
