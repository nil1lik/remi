import SwiftUI

struct TodayView: View {
    var open: (ActiveSheet) -> Void
    var showProfile: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @State private var selectedDay = Calendar.remi.startOfDay(for: .now)

    private var calendar: Calendar { .remi }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    greeting(now: context.date)
                    WeekStrip(selectedDay: $selectedDay)

                    if store.groups.isEmpty {
                        NoGroupsCard(open: open)
                    } else {
                        dayContent(plan: store.plan(for: selectedDay), now: context.date)
                            .id(selectedDay)
                            .transition(.opacity.combined(with: .offset(y: 10)))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.snappy, value: selectedDay)
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { welcomeToast }
    }

    // MARK: Başlık

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                BrandMark().frame(width: 24, height: 24)
                Text(s.date(selectedDay, "MMMM yyyy"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.secondary)
            }
            Spacer()
            if !isToday {
                Button(s.today) { withAnimation(.snappy) { selectedDay = calendar.startOfDay(for: .now) } }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Brand.chip, in: Capsule())
                    .foregroundStyle(Brand.text)
            }
            Button(action: showProfile) {
                Text(String(store.profile.displayName.first.map(String.init) ?? "R").uppercased())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(accent.fill, in: Circle())
            }
            .accessibilityLabel(s.tabProfile)
        }
    }

    private func greeting(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.greeting(at: now, name: store.profile.displayName))
                .font(Brand.display(32, language: s.language))
                .tracking(s.language == .ar ? 0 : -0.8)
            Text(s.date(selectedDay, "EEEE d MMMM"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Brand.secondary)
        }
    }

    // MARK: Gün

    @ViewBuilder
    private func dayContent(plan: DayPlan, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !plan.active.isEmpty { SummaryStrip(plan: plan) }
            if let news = plan.goodNews { GoodNewsCard(news: news) }
            if isToday, let current = plan.current(at: now) {
                NextLessonCard(lesson: current.lesson, isLive: current.isLive, now: now)
            }

            if plan.lessons.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sun.max").font(.title).foregroundStyle(Brand.ping)
                    Text(s.emptyDay).font(Brand.display(20, language: s.language))
                    Text(s.emptyDayDetail).font(.subheadline).foregroundStyle(Brand.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Brand.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            } else {
                Text(s.lessonCount(plan.lessons.count)).font(.subheadline.weight(.bold))
                VStack(spacing: 0) {
                    ForEach(plan.lessons) { lesson in
                        LessonRow(lesson: lesson, isPast: isToday && now >= lesson.end)
                        if lesson.id != plan.lessons.last?.id { Divider().overlay(Brand.line) }
                    }
                }
                .card(radius: 24)
            }
        }
    }

    @ViewBuilder
    private var welcomeToast: some View {
        if store.showWelcomeBack {
            Label(s.welcomeBack, systemImage: "sun.max.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.newsText)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.newsBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation(.snappy) { store.showWelcomeBack = false }
                }
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - Hafta şeridi

/// Minimal: gün harfi, rakam ve ders noktası. Seçili gün renkli dairede; sağa-sola kaydırınca hafta değişir.
struct WeekStrip: View {
    @Binding var selectedDay: Date
    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @Environment(\.layoutDirection) private var direction

    private var days: [Date] {
        let start = Calendar.remi.dateInterval(of: .weekOfYear, for: selectedDay)!.start
        return (0..<7).map { Calendar.remi.date(byAdding: .day, value: $0, to: start)! }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let on = Calendar.remi.isDate(day, inSameDayAs: selectedDay)
                let today = Calendar.remi.isDateInToday(day)
                let busy = !store.plan(for: day).lessons.isEmpty
                Button { withAnimation(.snappy) { selectedDay = day } } label: {
                    VStack(spacing: 6) {
                        Text(s.weekdayLetter(Weekday(date: day))).font(.caption.weight(.semibold)).foregroundStyle(Brand.secondary)
                        Text(s.number(Calendar.remi.component(.day, from: day)))
                            .font(.body.weight(.bold))
                            .foregroundStyle(on ? .white : today ? accent.text : Brand.text)
                            .frame(width: 36, height: 36)
                            .background(on ? accent.fill : .clear, in: Circle())
                        Circle().fill(busy ? (on ? Brand.text : Brand.secondary) : .clear).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.date(day, "EEEE d MMMM"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            var forward = value.translation.width < 0
            if direction == .rightToLeft { forward.toggle() }
            withAnimation(.snappy) { selectedDay = Calendar.remi.date(byAdding: .weekOfYear, value: forward ? 1 : -1, to: selectedDay)! }
        })
        .sensoryFeedback(.selection, trigger: selectedDay)
    }
}

// MARK: - Kartlar

private struct SummaryStrip: View {
    let plan: DayPlan
    @Environment(\.strings) private var s

    var body: some View {
        // Üç eşit sütun; değer sütuna sığmazsa küçülür, taşmaz.
        HStack(spacing: 0) {
            stat(s.number(plan.active.count), s.statLessons)
            Divider().overlay(Brand.line)
            stat(s.decimal(Double(plan.totalMinutes) / 60), s.statHours)
            Divider().overlay(Brand.line)
            stat(plan.firstStart.flatMap { f in plan.lastEnd.map { s.timeRange(f, $0) } } ?? "—", s.statRange, small: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .card(radius: 22)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Brand.display(small ? 17 : 22, language: s.language)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Brand.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GoodNewsCard: View {
    let news: DayPlan.GoodNews
    @Environment(\.strings) private var s

    var body: some View {
        let text = s.goodNews(news)
        HStack(spacing: 14) {
            Image(systemName: news == .eveningFree ? "moon.stars.fill" : "sun.max.fill")
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Brand.newsIcon, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.goodNews).font(.caption2.weight(.bold)).tracking(0.8).opacity(0.8)
                Text(text.title).font(.headline)
                Text(text.detail).font(.footnote).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Brand.newsText)
        .padding(14)
        .background(Brand.newsBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct NextLessonCard: View {
    let lesson: Lesson
    let isLive: Bool
    let now: Date
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PingDot()
                Text(isLive ? s.happeningNow : s.upNext).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Brand.secondary)
                Spacer()
                Text(isLive ? s.endsIn(minutes(to: lesson.end)) : s.startsIn(minutes(to: lesson.start)))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(accent.text)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.group.name).font(Brand.display(24, language: s.language))
                Text("\(s.timeRange(lesson.group.startMinute, lesson.group.endMinute)) · \(s.reminderShort(lesson.group.reminder))")
                    .font(.subheadline).foregroundStyle(Brand.secondary)
            }
            if let link = lesson.group.chatLink, let parsed = ChatLinkRule.parse(link) {
                Button { openURL(parsed.url) } label: {
                    Label("\(s.openGroup) · \(parsed.app.title)", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(accent.text)
                        .background(accent.fill.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(18)
        .card(radius: 24)
    }

    private func minutes(to date: Date) -> Int { max(Int(date.timeIntervalSince(now) / 60) + 1, 1) }
}

private struct LessonRow: View {
    let lesson: Lesson
    let isPast: Bool
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink(value: lesson.group.id) {
                HStack(spacing: 14) {
                    Text(s.clock(lesson.group.startMinute))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .leading)
                    Circle().fill(lesson.group.color.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.group.name).font(.body.weight(.semibold)).foregroundStyle(Brand.text)
                        Text(lesson.isPaused && lesson.group.holiday != nil
                             ? s.holidayUntil(lesson.group.holiday!.end)
                             : s.timeRange(lesson.group.startMinute, lesson.group.endMinute))
                            .font(.footnote).foregroundStyle(Brand.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if lesson.isPaused {
                Text(s.onHoliday)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Brand.holidayBackground, in: Capsule())
                    .foregroundStyle(Brand.holidayText)
            } else if let link = lesson.group.chatLink, let parsed = ChatLinkRule.parse(link) {
                Button { openURL(parsed.url) } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.subheadline)
                        .foregroundStyle(Brand.secondary)
                        .frame(width: 40, height: 40)
                        .background(Brand.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.openGroup(named: lesson.group.name))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .opacity(lesson.isPaused || isPast ? 0.5 : 1)
    }
}

struct NoGroupsCard: View {
    var open: (ActiveSheet) -> Void
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandMark().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(s.noGroupsTitle).font(Brand.display(24, language: s.language))
                Text(s.noGroupsDetail).font(.subheadline).foregroundStyle(Brand.secondary)
            }
            Button(s.addFirstGroup) { open(.quickGroup) }
                .buttonStyle(PrimaryButtonStyle(color: accent.fill))
            Button(s.newGroup) { open(.newGroup) }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(20)
        .card(radius: 26)
    }
}
