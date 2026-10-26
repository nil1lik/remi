import SwiftUI

/// İçe aktarılan dosyanın özeti; onaylanınca mevcut programın yerine geçer.
struct ImportPreviewView: View {
    let pending: ScheduleStore.PendingImport
    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var lessons: [Lesson] { pending.result.lessons }
    private var issues: [ScheduleImporter.Issue] { pending.result.issues }

    private struct DayGroup: Identifiable {
        var day: Weekday
        var lessons: [Lesson]
        var id: Weekday { day }
    }

    private var weekly: [DayGroup] {
        Weekday.allCases.compactMap { day in
            let items = lessons.filter { $0.weekday == day }.sorted { $0.start < $1.start }
            return items.isEmpty ? nil : DayGroup(day: day, lessons: items)
        }
    }

    private var oneOff: [Lesson] {
        lessons.filter { $0.date != nil }.sorted { ($0.date!, $0.start) < ($1.date!, $1.start) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: lessons.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(lessons.isEmpty ? .orange : .green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lessons.isEmpty ? "Ders bulunamadı" : "\(Set(lessons.map(\.title)).count) grup, \(lessons.count) ders")
                                .font(.headline)
                            Text(pending.fileName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !issues.isEmpty {
                    Section {
                        ForEach(issues) { issue in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("Satır \(issue.row)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.orange)
                                    .frame(width: 58, alignment: .leading)
                                Text(issue.message)
                                    .font(.subheadline)
                            }
                        }
                    } header: {
                        Text("Okunamayan satırlar")
                    } footer: {
                        Text("Bu satırlar eklenmeyecek. Excel'de düzeltip yeniden içe aktarabilirsin.")
                    }
                }

                ForEach(weekly) { group in
                    Section(group.day.name) {
                        ForEach(group.lessons) { PreviewRow(lesson: $0) }
                    }
                }

                if !oneOff.isEmpty {
                    Section("Tek seferlik") {
                        ForEach(oneOff) { lesson in
                            PreviewRow(lesson: lesson, prefix: DateText.shortDate.string(from: lesson.date!))
                        }
                    }
                }
            }
            .navigationTitle("Önizleme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lessons.isEmpty ? "Kapat" : "Vazgeç") { store.pendingImport = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !lessons.isEmpty {
                    VStack(spacing: 8) {
                        Button {
                            store.applyPendingImport()
                        } label: {
                            Text("Programı yükle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        if !store.lessons.isEmpty {
                            Text("Mevcut programın yerine geçer.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct PreviewRow: View {
    let lesson: Lesson
    var prefix: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LessonPalette.color(for: lesson.title))
                .frame(width: 10, height: 10)
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
}
