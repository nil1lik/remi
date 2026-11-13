import SwiftUI

/// Tüm haftanın programı: gün gün dersler, ekleme, düzenleme ve silme.
/// Bir NavigationStack içine konur (ana ekranda sheet, ayarlarda push).
struct ProgramEditorView: View {
    var showsDone = false

    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating: NewLessonRequest?

    enum Route: Hashable {
        case edit(Lesson.ID)
    }

    private struct NewLessonRequest: Identifiable {
        let id = UUID()
        var day: Date
    }

    private var calendar: Calendar { .schedule }

    var body: some View {
        List {
            Section {
                summary
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            ForEach(Weekday.allCases) { day in
                let lessons = store.lessons.filter { $0.weekday == day }.sorted { $0.start < $1.start }
                Section {
                    if lessons.isEmpty {
                        Button { add(on: day) } label: {
                            Label("Ders ekle", systemImage: "plus")
                                .font(.subheadline.weight(.medium))
                        }
                    } else {
                        ForEach(lessons) { lesson in
                            row(lesson)
                        }
                    }
                } header: {
                    HStack {
                        Text(day.name)
                        Spacer()
                        if !lessons.isEmpty {
                            Button { add(on: day) } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .accessibilityLabel("\(day.name) gününe ders ekle")
                        }
                    }
                }
            }

            let oneOff = store.lessons.filter { $0.date != nil }.sorted { ($0.date!, $0.start) < ($1.date!, $1.start) }
            if !oneOff.isEmpty {
                Section("Tek seferlik") {
                    ForEach(oneOff) { lesson in
                        row(lesson, prefix: DateText.shortDate.string(from: lesson.date!))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Haftalık program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { creating = NewLessonRequest(day: .now) } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ders ekle")
            }
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .edit(let id):
                if let lesson = store.lessons.first(where: { $0.id == id }) {
                    LessonEditorView(original: lesson)
                } else {
                    ContentUnavailableView("Ders bulunamadı", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
        .sheet(item: $creating) { request in
            NavigationStack {
                LessonEditorView(initialDay: request.day, inSheet: true)
            }
        }
    }

    private var summary: some View {
        let titles = Set(store.lessons.map(\.title)).count
        let minutes = store.lessons.filter(\.isRecurring).reduce(0) { $0 + (($1.end ?? $1.start + 40) - $1.start) }
        return HStack(spacing: 10) {
            StatTile(value: "\(titles)", label: "grup", systemImage: "person.3.fill", color: .indigo)
            StatTile(value: "\(store.lessons.count)", label: "ders", systemImage: "calendar", color: .teal)
            StatTile(value: DateText.duration(minutes: max(minutes, 0)), label: "haftada", systemImage: "clock.fill", color: .orange)
        }
        .padding(.vertical, 4)
    }

    private func row(_ lesson: Lesson, prefix: String? = nil) -> some View {
        NavigationLink(value: Route.edit(lesson.id)) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LessonPalette.color(for: lesson.title))
                    .frame(width: 5, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(.body.weight(.medium))
                    if let location = lesson.location {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let prefix {
                        Text(prefix).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(lesson.timeText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                withAnimation { store.delete(lesson) }
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    /// Seçilen haftanın gününe denk gelen ilk tarih (bugün ya da sonrası).
    private func add(on day: Weekday) {
        let today = calendar.startOfDay(for: .now)
        let offset = (day.rawValue - Weekday(date: today).rawValue + 7) % 7
        creating = NewLessonRequest(day: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
