import SwiftUI
import UIKit

/// Elle ders ekleme ve düzenleme. Yeni derste birden çok gün seçilebilir; her gün ayrı bir kayıt olur.
struct LessonEditorView: View {
    /// Düzenlenen ders; boşsa yeni ders eklenir.
    let original: Lesson?
    /// Sheet'in kökünde açıldıysa "Vazgeç" gösterilir; push edildiyse geri düğmesi yeter.
    var inSheet = false

    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Draft
    @FocusState private var focus: Field?

    private enum Field { case title, location, note }

    init(original: Lesson? = nil, initialDay: Date? = nil, inSheet: Bool = false) {
        self.original = original
        self.inSheet = inSheet
        _draft = State(initialValue: Draft(lesson: original, day: initialDay))
    }

    private var color: Color { LessonPalette.color(for: draft.trimmedTitle.isEmpty ? "Yeni" : draft.trimmedTitle) }
    private var candidates: [Lesson] { draft.makeLessons(reminder: original?.customReminder) }
    private var conflicts: [Lesson] {
        store.conflicts(with: candidates, excluding: original.map { [$0.id] } ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PreviewCard(draft: draft, color: color)
                titleCard
                whenCard
                detailsCard
                if !conflicts.isEmpty { conflictCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy, value: draft)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground)
        .environment(\.locale, Locale(identifier: "tr_TR"))
        .navigationTitle(original == nil ? "Yeni ders" : "Dersi düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Tamam") { focus = nil }
            }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear {
            if original == nil { focus = .title }
        }
        .onChange(of: draft.start) { old, new in
            // Başlangıç kayınca süre korunsun.
            draft.end = min(new + (draft.end - old), 24 * 60 - 1)
        }
    }

    // MARK: Bölümler

    private var titleCard: some View {
        EditorCard(title: "Grup / ders", systemImage: "person.3") {
            TextField("ör. A1-20 sınıfı", text: $draft.title)
                .font(.title3.weight(.semibold))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focus, equals: .title)
                .onSubmit { focus = nil }
                .fieldStyle()

            let suggestions = titleSuggestions
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { title in
                            Button { apply(suggestion: title) } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(LessonPalette.color(for: title))
                                        .frame(width: 8, height: 8)
                                    Text(title)
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.appBackground, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var whenCard: some View {
        EditorCard(title: "Ne zaman", systemImage: "calendar") {
            Picker("Tekrar", selection: $draft.repeats) {
                Text("Her hafta").tag(true)
                Text("Tek seferlik").tag(false)
            }
            .pickerStyle(.segmented)

            if draft.repeats {
                DayChips(selection: $draft.weekdays, color: color, allowsMultiple: true)
                HStack(spacing: 8) {
                    PresetButton(title: "Hafta içi") {
                        draft.weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday]
                    }
                    PresetButton(title: "Hafta sonu") { draft.weekdays = [.saturday, .sunday] }
                    if !draft.weekdays.isEmpty {
                        PresetButton(title: "Temizle") { draft.weekdays = [] }
                    }
                }
            } else {
                DatePicker("Tarih", selection: $draft.date, displayedComponents: .date)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                TimeBox(title: "Başlangıç", selection: timeBinding(\.start))
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                TimeBox(title: "Bitiş", selection: timeBinding(\.end))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([30, 40, 45, 60, 90, 120], id: \.self) { minutes in
                        let selected = draft.duration == minutes
                        Button {
                            draft.end = min(draft.start + minutes, 24 * 60 - 1)
                        } label: {
                            Text(DateText.duration(minutes: minutes))
                                .font(.subheadline.weight(.medium).monospacedDigit())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selected ? color.opacity(0.16) : Color.appBackground, in: Capsule())
                                .foregroundStyle(selected ? color : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()

            if let problem = draft.problem, problem.isTimeProblem {
                Label(problem.message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
    }

    private var detailsCard: some View {
        EditorCard(title: "Ayrıntılar", systemImage: "text.alignleft") {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Yer (ör. Salon 2, Online)", text: $draft.location)
                    .focused($focus, equals: .location)
                    .submitLabel(.next)
                    .onSubmit { focus = .note }
            }
            .fieldStyle()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .padding(.top, 2)
                TextField("Not (isteğe bağlı)", text: $draft.note, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focus, equals: .note)
            }
            .fieldStyle()
        }
    }

    private var conflictCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bu saatte başka ders var")
                    .font(.subheadline.weight(.semibold))
                ForEach(conflicts.prefix(3)) { lesson in
                    Text("\(lesson.weekday?.name ?? lesson.date.map { DateText.shortDate.string(from: $0) } ?? "") · \(lesson.timeText) · \(lesson.title)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Yine de kaydedebilirsin.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var saveBar: some View {
        VStack(spacing: 6) {
            Button(action: save) {
                Text(saveTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            .controlSize(.large)
            .disabled(draft.problem != nil)

            if let problem = draft.problem, !problem.isTimeProblem {
                Text(problem.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
        .animation(.snappy, value: color)
    }

    // MARK: Yardımcılar

    private var saveTitle: String {
        if original != nil { return "Kaydet" }
        if draft.repeats && draft.weekdays.count > 1 { return "\(draft.weekdays.count) güne ekle" }
        return "Programa ekle"
    }

    private var titleSuggestions: [String] {
        let typed = ScheduleImporter.normalize(draft.title)
        return store.groupTitles
            .filter { title in
                let key = ScheduleImporter.normalize(title)
                return key != typed && (typed.isEmpty || key.contains(typed))
            }
            .prefix(8)
            .map { $0 }
    }

    private func apply(suggestion title: String) {
        draft.title = title
        if let template = store.template(forTitle: title) {
            if draft.location.isEmpty { draft.location = template.location ?? "" }
            if let end = template.end { draft.end = min(draft.start + (end - template.start), 24 * 60 - 1) }
        }
        focus = nil
    }

    private func timeBinding(_ keyPath: WritableKeyPath<Draft, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = draft[keyPath: keyPath]
                return Calendar.schedule.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.schedule.dateComponents([.hour, .minute], from: date)
                draft[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func save() {
        let lessons = candidates
        guard !lessons.isEmpty else { return }
        if let original {
            store.replace(original.id, with: lessons)
        } else {
            store.add(lessons)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Taslak

extension LessonEditorView {
    struct Draft: Equatable {
        var title = ""
        var repeats = true
        var weekdays: Set<Weekday> = []
        var date: Date
        var start = 9 * 60
        var end = 10 * 60
        var location = ""
        var note = ""

        init(lesson: Lesson?, day: Date?) {
            let calendar = Calendar.schedule
            let base = calendar.startOfDay(for: day ?? .now)
            date = base
            if let lesson {
                title = lesson.title
                repeats = lesson.isRecurring
                if let weekday = lesson.weekday { weekdays = [weekday] }
                if let date = lesson.date { self.date = date }
                start = lesson.start
                end = lesson.end ?? lesson.start + 40
                location = lesson.location ?? ""
                note = lesson.note ?? ""
            } else {
                weekdays = [Weekday(date: base)]
                // Bugün için ekleniyorsa bir sonraki tam saati öner.
                if calendar.isDateInToday(base) {
                    let hour = calendar.component(.hour, from: .now) + 1
                    if (7...21).contains(hour) { start = hour * 60; end = start + 60 }
                }
            }
        }

        var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
        var duration: Int { end - start }

        enum Problem {
            case noTitle, noDay, endBeforeStart

            var message: String {
                switch self {
                case .noTitle: "Grup ya da ders adını yaz."
                case .noDay: "En az bir gün seç."
                case .endBeforeStart: "Bitiş saati başlangıçtan sonra olmalı."
                }
            }

            var isTimeProblem: Bool { self == .endBeforeStart }
        }

        var problem: Problem? {
            if end <= start { return .endBeforeStart }
            if trimmedTitle.isEmpty { return .noTitle }
            if repeats && weekdays.isEmpty { return .noDay }
            return nil
        }

        func makeLessons(reminder: ReminderSettings?) -> [Lesson] {
            func clean(_ text: String) -> String? {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let base = Lesson(title: trimmedTitle, weekday: nil, date: nil, start: start, end: end,
                              location: clean(location), note: clean(note), customReminder: reminder)
            if !repeats {
                var lesson = base
                lesson.date = Calendar.schedule.startOfDay(for: date)
                return [lesson]
            }
            return weekdays.sorted().map { day in
                var lesson = base
                lesson.id = UUID()
                lesson.weekday = day
                return lesson
            }
        }
    }
}

// MARK: - Parçalar

/// Yazdıkça güncellenen önizleme kartı.
private struct PreviewCard: View {
    let draft: LessonEditorView.Draft
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(whenText, systemImage: draft.repeats ? "repeat" : "calendar")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .opacity(0.85)
                    .contentTransition(.opacity)
                Spacer()
                Image(systemName: "bell.badge.fill")
                    .font(.subheadline)
                    .opacity(0.8)
            }
            Text(draft.trimmedTitle.isEmpty ? "Grup adı" : draft.trimmedTitle)
                .font(.title.weight(.bold))
                .lineLimit(2)
                .opacity(draft.trimmedTitle.isEmpty ? 0.55 : 1)
                .contentTransition(.interpolate)
            HStack(spacing: 8) {
                Text("\(Lesson.clock(draft.start)) – \(Lesson.clock(draft.end))")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if draft.duration > 0 {
                    Text("·")
                    Text(DateText.duration(minutes: draft.duration))
                        .contentTransition(.numericText())
                }
                let location = draft.location.trimmingCharacters(in: .whitespaces)
                if !location.isEmpty {
                    Text("·")
                    Text(location).lineLimit(1)
                }
            }
            .font(.subheadline.weight(.medium))
            .opacity(0.92)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 140, height: 140)
                        .offset(x: 40, y: -50)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .shadow(color: color.opacity(0.35), radius: 18, y: 10)
    }

    private var whenText: String {
        if !draft.repeats { return DateText.shortDate.string(from: draft.date) }
        return draft.weekdays.isEmpty ? "Gün seç" : "Her \(Lesson.daysText(draft.weekdays))"
    }
}

struct EditorCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Haftanın günleri; dokununca seçilir.
struct DayChips: View {
    @Binding var selection: Set<Weekday>
    var color: Color = .accentColor
    var allowsMultiple = true

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let on = selection.contains(day)
                Button {
                    if allowsMultiple {
                        if on { selection.remove(day) } else { selection.insert(day) }
                    } else {
                        selection = [day]
                    }
                } label: {
                    Text(day.shortName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.appBackground))
                        }
                        .foregroundStyle(on ? .white : .primary)
                        .scaleEffect(on ? 1 : 0.94)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct PresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.footnote.weight(.medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.secondary)
    }
}

private struct TimeBox: View {
    let title: String
    @Binding var selection: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
