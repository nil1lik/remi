import SwiftUI
import UniformTypeIdentifiers

struct ScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var selectedDay = Calendar.schedule.startOfDay(for: .now)
    @State private var showSettings = false
    @State private var showFilePicker = false
    @State private var openedLesson: Lesson?

    private var calendar: Calendar { .schedule }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(DateText.dayMonth.string(from: selectedDay).capitalized(with: Locale(identifier: "tr_TR")))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, -8)

                    WeekStrip(selectedDay: $selectedDay)

                    if store.lessons.isEmpty {
                        EmptyScheduleView { showFilePicker = true }
                    } else {
                        dayContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBackground)
            .navigationTitle(isToday ? "Bugün" : Weekday(date: selectedDay).name)
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Bugün") {
                            withAnimation(.snappy) { selectedDay = calendar.startOfDay(for: .now) }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ayarlar")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $openedLesson) { lesson in
                LessonDetailView(lessonID: lesson.id)
            }
            .sheet(item: $store.pendingImport) { pending in
                ImportPreviewView(pending: pending)
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: ScheduleFileTypes.all) { result in
                if case .success(let url) = result { store.prepareImport(from: url) }
            }
            .alert("İçe aktarılamadı", isPresented: Binding(
                get: { store.importError != nil },
                set: { if !$0 { store.importError = nil } }
            )) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(store.importError ?? "")
            }
            .onChange(of: store.importRequestID) {
                // Ayarlar sayfası kapanınca dosya seçiciyi aç.
                showSettings = false
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    showFilePicker = true
                }
            }
            .onChange(of: store.pendingImport?.id) {
                if store.pendingImport != nil { showSettings = false; openedLesson = nil }
            }
        }
    }

    @ViewBuilder
    private var dayContent: some View {
        let lessons = store.lessons(on: selectedDay)
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 12) {
                if lessons.isEmpty {
                    FreeDayCard()
                } else {
                    if isToday {
                        NowCard(lessons: lessons, day: selectedDay, now: context.date)
                    }
                    HStack {
                        Text("\(lessons.count) ders")
                            .font(.headline)
                        Spacer()
                        if let first = lessons.first, let last = lessons.last {
                            Text("\(Lesson.clock(first.start)) – \(Lesson.clock(last.end ?? last.start))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    ForEach(lessons) { lesson in
                        Button {
                            openedLesson = lesson
                        } label: {
                            LessonCard(lesson: lesson,
                                       state: state(of: lesson, now: context.date),
                                       reminder: store.effectiveReminder(for: lesson))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func state(of lesson: Lesson, now: Date) -> LessonCard.Phase {
        guard isToday else { return calendar.startOfDay(for: now) > selectedDay ? .past : .upcoming }
        let start = lesson.startDate(on: selectedDay)
        let end = lesson.endDate(on: selectedDay)
        if now >= end { return .past }
        if now >= start { return .live(progress: now.timeIntervalSince(start) / end.timeIntervalSince(start)) }
        return .upcoming
    }
}

enum ScheduleFileTypes {
    static let all: [UTType] = [
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .spreadsheet,
        .commaSeparatedText,
    ]
}

// MARK: - Hafta şeridi

struct WeekStrip: View {
    @Binding var selectedDay: Date
    @Environment(ScheduleStore.self) private var store
    private var calendar: Calendar { .schedule }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDay)!.start
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                let today = calendar.isDateInToday(day)
                Button {
                    withAnimation(.snappy) { selectedDay = day }
                } label: {
                    VStack(spacing: 6) {
                        Text(Weekday(date: day).shortName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                        Text("\(calendar.component(.day, from: day))")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(selected ? .white : today ? Color.accentColor : .primary)
                        Circle()
                            .fill(selected ? .white : Color.accentColor)
                            .frame(width: 5, height: 5)
                            .opacity(store.hasLessons(on: day) ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.cardBackground)
                    }
                    .overlay {
                        if today && !selected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DateText.dayMonth.string(from: day))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let weeks = value.translation.width < 0 ? 1 : -1
                withAnimation(.snappy) {
                    selectedDay = calendar.date(byAdding: .weekOfYear, value: weeks, to: selectedDay)!
                }
            }
        )
        .sensoryFeedback(.selection, trigger: selectedDay)
    }
}

// MARK: - Kartlar

struct NowCard: View {
    let lessons: [Lesson]
    let day: Date
    let now: Date

    var body: some View {
        let live = lessons.first { now >= $0.startDate(on: day) && now < $0.endDate(on: day) }
        let next = lessons.first { $0.startDate(on: day) > now }

        if let lesson = live ?? next {
            let color = LessonPalette.color(for: lesson.title)
            VStack(alignment: .leading, spacing: 6) {
                Label(live != nil ? "Şu an" : "Sıradaki", systemImage: live != nil ? "dot.radiowaves.left.and.right" : "clock")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .opacity(0.85)
                Text(lesson.title)
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    if live != nil {
                        let left = Int(lesson.endDate(on: day).timeIntervalSince(now) / 60) + 1
                        Text("Bitmesine \(DateText.duration(minutes: left))")
                    } else {
                        let until = Int(lesson.startDate(on: day).timeIntervalSince(now) / 60) + 1
                        Text("\(DateText.duration(minutes: until)) sonra · \(Lesson.clock(lesson.start))")
                    }
                    if let location = lesson.location {
                        Text("·")
                        Text(location)
                    }
                }
                .font(.subheadline.weight(.medium))
                .opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .shadow(color: color.opacity(0.35), radius: 16, y: 8)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bugünkü dersler bitti")
                        .font(.headline)
                    Text("Dinlenme zamanı.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct LessonCard: View {
    enum Phase: Equatable {
        case upcoming, past
        case live(progress: Double)
    }

    let lesson: Lesson
    let state: Phase
    let reminder: ReminderSettings

    var body: some View {
        let color = LessonPalette.color(for: lesson.title)
        let isLive = if case .live = state { true } else { false }

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Lesson.clock(lesson.start))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if let end = lesson.end {
                    Text(Lesson.clock(end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(lesson.title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if isLive {
                        Text("Şimdi")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(color, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    reminderIcon
                }
                if let location = lesson.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let note = lesson.note {
                    Label(note, systemImage: "text.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if case .live(let progress) = state {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(color)
                        .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cardBackground)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(color.opacity(isLive ? 0.14 : 0.06))
        }
        .overlay {
            if isLive {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
            }
        }
        .opacity(state == .past ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var reminderIcon: some View {
        if !reminder.isEnabled {
            Image(systemName: "bell.slash")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else if lesson.customReminder != nil {
            Image(systemName: reminder.kind == .alarm ? "alarm.fill" : "bell.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FreeDayCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange.gradient)
            Text("Bu gün ders yok")
                .font(.headline)
            Text("Keyfini çıkar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct EmptyScheduleView: View {
    var onImport: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor.gradient)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text("Ders programını ekle")
                    .font(.title3.weight(.bold))
                Text("Programını Excel'de hazırla, buraya yükle. Dersler başlamadan sana haber verelim.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: 1, text: "Örnek Excel'i indir")
                StepRow(number: 2, text: "Gruplarını ve saatlerini yazıp kaydet")
                StepRow(number: 3, text: "Buraya geri yükle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 10) {
                if let url = TemplateFile.url {
                    ShareLink(item: url, preview: SharePreview("Ders Programı Şablonu")) {
                        Label("Örnek Excel'i indir", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button(action: onImport) {
                    Label("Excel'i içe aktar", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(20)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.subheadline.weight(.medium))
        }
    }
}
