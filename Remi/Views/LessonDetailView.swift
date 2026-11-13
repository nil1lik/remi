import SwiftUI

/// Bir dersin ayrıntısı ve yalnız o derse özel hatırlatma ayarı.
struct LessonDetailView: View {
    let lessonID: Lesson.ID
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var detent: PresentationDetent = .medium

    private var lesson: Lesson? { store.lessons.first { $0.id == lessonID } }

    var body: some View {
        NavigationStack {
            if let lesson {
                content(lesson)
            } else {
                ContentUnavailableView("Ders bulunamadı", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private func content(_ lesson: Lesson) -> some View {
        let color = LessonPalette.color(for: lesson.title)
        let custom = Binding<Bool>(
            get: { lesson.customReminder != nil },
            set: { on in
                var updated = lesson
                updated.customReminder = on ? store.reminder : nil
                store.update(updated)
            }
        )
        let reminder = Binding<ReminderSettings>(
            get: { store.effectiveReminder(for: lesson) },
            set: { value in
                var updated = lesson
                updated.customReminder = value
                store.update(updated)
            }
        )

        return Form {
            Section {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.gradient)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Text(String(lesson.title.prefix(2)).uppercased(with: Locale(identifier: "tr_TR")))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.title)
                            .font(.title3.weight(.bold))
                        Text(whenText(lesson))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let location = lesson.location {
                    LabeledContent("Yer", value: location)
                }
                if let note = lesson.note {
                    LabeledContent("Not") {
                        Text(note).multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                Toggle("Bu derse özel ayar", isOn: custom)
                if lesson.customReminder != nil {
                    Toggle("Hatırlat", isOn: reminder.isEnabled)
                    if reminder.wrappedValue.isEnabled {
                        ReminderControls(settings: reminder)
                    }
                }
            } header: {
                Text("Hatırlatma")
            } footer: {
                if lesson.customReminder == nil {
                    let r = store.reminder
                    Text(r.isEnabled
                         ? "Genel ayar: \(ReminderSettings.label(forMinutes: r.minutesBefore).lowercased(with: Locale(identifier: "tr_TR"))), \(r.kind.title.lowercased(with: Locale(identifier: "tr_TR"))) olarak."
                         : "Genel ayarda hatırlatma kapalı.")
                }
            }

            Section {
                Button("Bu dersi programdan sil", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle("Ders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Düzenle") {
                    detent = .large
                    editing = true
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") { dismiss() }
            }
        }
        .navigationDestination(isPresented: $editing) {
            LessonEditorView(original: lesson)
        }
        .confirmationDialog("\(lesson.title) silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                dismiss()
                store.delete(lesson)
            }
        }
    }

    private func whenText(_ lesson: Lesson) -> String {
        if let date = lesson.date {
            return "\(DateText.shortDate.string(from: date)) · \(lesson.timeText)"
        }
        return "Her \(lesson.weekday?.name ?? "") · \(lesson.timeText)"
    }
}

/// Ne kadar önce ve hangi türde hatırlatılacağı (genel ayar ve derse özel ayarda ortak).
struct ReminderControls: View {
    @Binding var settings: ReminderSettings
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        Picker("Ne zaman", selection: $settings.minutesBefore) {
            ForEach(options, id: \.self) { minutes in
                Text(ReminderSettings.label(forMinutes: minutes)).tag(minutes)
            }
        }

        Picker("Tür", selection: $settings.kind) {
            ForEach(ReminderKind.allCases) { kind in
                Label(kind.title, systemImage: kind == .alarm ? "alarm" : "bell").tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!store.scheduler.alarmsSupported)
        .onChange(of: settings.kind) { _, kind in
            // İzin verilince alarmlar kurulsun diye hatırlatmaları izinden sonra yeniden kur.
            Task {
                await store.scheduler.requestPermissions(for: kind)
                store.rescheduleReminders()
            }
        }
    }

    private var options: [Int] {
        var values = ReminderSettings.minuteOptions
        if !values.contains(settings.minutesBefore) {
            values.append(settings.minutesBefore)
            values.sort()
        }
        return values
    }
}
