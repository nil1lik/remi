import SwiftUI
import UniformTypeIdentifiers

struct ScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var selectedDay = Calendar.schedule.startOfDay(for: .now)
    @State private var showSettings = false
    @State private var showFilePicker = false
    @State private var openedLesson: Lesson?
    @State private var newLessonDay: NewLessonDay?
    @State private var showProgram = false

    private struct NewLessonDay: Identifiable {
        let id = UUID()
        var day: Date
    }

    private var calendar: Calendar { .schedule }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TimelineView(.everyMinute) { context in
                        let date = DateText.dayMonth.string(from: selectedDay).capitalized(with: Locale(identifier: "tr_TR"))
                        Text(isToday ? "\(DayMood(date: context.date).greeting) · \(date)" : date)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    .padding(.top, -8)

                    WeekStrip(selectedDay: $selectedDay)

                    if store.lessons.isEmpty {
                        EmptyScheduleView(
                            onCreate: { newLessonDay = NewLessonDay(day: selectedDay) },
                            onImport: { showFilePicker = true }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else {
                        dayContent
                            .id(selectedDay)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 14)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background { AmbientBackground() }
            .animation(.snappy, value: store.lessons.isEmpty)
            .navigationTitle(isToday ? "Bugün" : Weekday(date: selectedDay).name)
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Bugün") {
                            withAnimation(.snappy) { selectedDay = calendar.startOfDay(for: .now) }
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !store.lessons.isEmpty {
                        Button {
                            showProgram = true
                        } label: {
                            Image(systemName: "calendar.day.timeline.left")
                        }
                        .accessibilityLabel("Haftalık program")
                        Button {
                            newLessonDay = NewLessonDay(day: selectedDay)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Ders ekle")
                    }
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
            .sheet(item: $newLessonDay) { request in
                NavigationStack {
                    LessonEditorView(initialDay: request.day, inSheet: true)
                }
            }
            .sheet(isPresented: $showProgram) {
                NavigationStack {
                    ProgramEditorView(showsDone: true)
                }
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
                if store.pendingImport != nil {
                    showSettings = false; openedLesson = nil; showProgram = false; newLessonDay = nil
                }
            }
        }
    }

    @ViewBuilder
    private var dayContent: some View {
        let lessons = store.lessons(on: selectedDay)
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 12) {
                if lessons.isEmpty {
                    FreeDayCard { newLessonDay = NewLessonDay(day: selectedDay) }
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
                        .buttonStyle(PressableStyle())
                        .scrollTransition(.animated(.snappy)) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.6)
                                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                        }
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
    var onAdd: () -> Void
    @State private var glow = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange.gradient)
                .rotationEffect(.degrees(glow ? 18 : 0))
                .scaleEffect(glow ? 1.06 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { glow = true }
                }
            Text("Bu gün ders yok")
                .font(.headline)
            Text("Keyfini çıkar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onAdd) {
                Label("Bu güne ders ekle", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct EmptyScheduleView: View {
    var onCreate: () -> Void
    var onImport: () -> Void
    @State private var animate = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .scaleEffect(animate ? 1.08 : 0.92)
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 84, height: 84)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color.accentColor.gradient)
                    .symbolEffect(.bounce, value: animate)
            }
            .padding(.top, 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { animate = true }
            }

            VStack(spacing: 6) {
                Text("Programını oluştur")
                    .font(.title2.weight(.bold))
                Text("Derslerini buraya ekle, başlamadan önce sana haber verelim.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ChoiceCard(
                    title: "Elle oluştur",
                    subtitle: "Grup adı, günler ve saat. Yarım dakika.",
                    systemImage: "square.and.pencil",
                    colors: [Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.58, green: 0.36, blue: 0.90)],
                    prominent: true,
                    action: onCreate
                )
                ChoiceCard(
                    title: "Excel'den yükle",
                    subtitle: "Programın tabloda hazırsa tek seferde aktar.",
                    systemImage: "tablecells",
                    colors: [Color(red: 0.05, green: 0.65, blue: 0.62), Color(red: 0.20, green: 0.66, blue: 0.33)],
                    prominent: false,
                    action: onImport
                )
            }

            if let url = TemplateFile.url {
                ShareLink(item: url, preview: SharePreview("Ders Programı Şablonu")) {
                    Label("Örnek Excel'i indir", systemImage: "arrow.down.doc")
                        .font(.footnote.weight(.medium))
                }
            }
        }
        .padding(20)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct ChoiceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(colors[0]))
                    .frame(width: 48, height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(prominent ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(colors[0].opacity(0.14)))
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.footnote)
                        .opacity(prominent ? 0.85 : 1)
                        .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(prominent ? .white : .primary)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(prominent
                          ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.appBackground))
            }
            .shadow(color: prominent ? colors[0].opacity(0.35) : .clear, radius: 14, y: 8)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Basılınca hafifçe küçülen düğme.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Günün saatine göre selamlama ve arka plan tonu.
struct DayMood {
    let greeting: String
    let colors: [Color]

    init(date: Date = .now) {
        switch Calendar.schedule.component(.hour, from: date) {
        case 5..<12:
            greeting = "Günaydın"
            colors = [Color(red: 1.0, green: 0.62, blue: 0.38), Color(red: 0.98, green: 0.45, blue: 0.62)]
        case 12..<18:
            greeting = "İyi günler"
            colors = [Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.13, green: 0.70, blue: 0.85)]
        case 18..<23:
            greeting = "İyi akşamlar"
            colors = [Color(red: 0.58, green: 0.36, blue: 0.90), Color(red: 0.95, green: 0.40, blue: 0.60)]
        default:
            greeting = "İyi geceler"
            colors = [Color(red: 0.20, green: 0.25, blue: 0.70), Color(red: 0.45, green: 0.30, blue: 0.85)]
        }
    }
}

/// Üstte günün saatine göre renk değiştiren yumuşak ışık.
struct AmbientBackground: View {
    @State private var drift = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let mood = DayMood(date: context.date)
            ZStack(alignment: .top) {
                Color.appBackground
                Circle()
                    .fill(mood.colors[0].opacity(0.32))
                    .frame(width: 360, height: 360)
                    .blur(radius: 90)
                    .offset(x: drift ? -110 : -70, y: -170)
                Circle()
                    .fill(mood.colors[1].opacity(0.26))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: drift ? 120 : 160, y: drift ? -120 : -150)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
