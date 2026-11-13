import SwiftUI

/// Grubun sayfası: sohbeti aç, bilgiler, yerinde hatırlatma ve tatil, sıradaki dersler, silme.
struct GroupDetailView: View {
    let id: UUID
    var open: (ActiveSheet) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showWheel = false
    @State private var confirmDelete = false
    @State private var customHolidayEnd = Calendar.remi.date(byAdding: .day, value: 7, to: .now)!
    @State private var pickingHoliday = false

    var body: some View {
        if let group = store.group(id) {
            content(group)
        } else {
            ContentUnavailableView(s.groupName, systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func content(_ group: StudyGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Circle().fill(group.color.color).frame(width: 16, height: 16)
                        Text(group.name).font(Brand.display(32, language: s.language)).tracking(s.language == .ar ? 0 : -1)
                    }
                    Text("\(s.everyDays(group.days)) · \(s.timeRange(group.startMinute, group.endMinute))")
                        .font(.subheadline).foregroundStyle(Brand.secondary)
                }

                if let link = group.chatLink, let parsed = ChatLinkRule.parse(link) {
                    Button { openURL(parsed.url) } label: {
                        Label(s.openIn(parsed.app), systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(.white)
                            .background(Brand.night, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }

                if let holiday = group.holiday, holiday.end >= Calendar.remi.startOfDay(for: .now) {
                    HStack(spacing: 12) {
                        Image(systemName: "beach.umbrella").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.holidayUntil(holiday.end)).font(.headline)
                            Text(s.remindersSilent).font(.footnote)
                        }
                        Spacer()
                        Button(s.endHoliday) { store.setHoliday(nil, for: [group.id]) }
                            .font(.footnote.weight(.bold)).padding(.horizontal, 12).frame(minHeight: 38)
                            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .foregroundStyle(Brand.holidayText)
                    .padding(16)
                    .background(Brand.holidayBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                infoCard(group)

                if group.holiday == nil || group.holiday!.end < Calendar.remi.startOfDay(for: .now) { holidayPicker(group) }

                upcoming(group)

                Button(s.deleteGroup, role: .destructive) { confirmDelete = true }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.danger)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Brand.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(s.edit) { open(.editGroup(group.id)) }.font(.subheadline.weight(.bold))
            }
        }
        .confirmationDialog(s.deleteGroupConfirm(group.name), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(s.delete, role: .destructive) {
                dismiss()
                store.delete(group.id)
            }
        }
    }

    private func infoCard(_ group: StudyGroup) -> some View {
        VStack(spacing: 0) {
            row(s.daysLabel, s.days(group.days))
            Divider().overlay(Brand.line)
            row(s.time, s.timeRange(group.startMinute, group.endMinute))
            Divider().overlay(Brand.line)
            row(s.linkLabel, group.chatLink.flatMap { ChatLinkRule.parse($0)?.app.title } ?? s.noLink)
            Divider().overlay(Brand.line)
            Button { withAnimation(.snappy) { showWheel.toggle() } } label: {
                HStack {
                    Text(s.remindLabel).font(.subheadline).foregroundStyle(Brand.secondary).frame(width: 90, alignment: .leading)
                    Text("\(s.reminderShort(group.reminder)) · \(s.kind(group.reminder.kind))").font(.body.weight(.semibold)).foregroundStyle(Brand.text)
                    Spacer()
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Brand.secondary)
                        .rotationEffect(.degrees(showWheel ? 180 : 0))
                }
                .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showWheel ? .isSelected : [])
            if showWheel {
                VStack(spacing: 8) {
                    ReminderWheel(minutes: reminderBinding(group).minutesBefore)
                    SegmentedPills(options: ReminderKind.allCases, selection: reminderBinding(group).kind, title: s.kind)
                }
                .padding([.horizontal, .bottom], 10)
                .transition(.opacity)
            }
        }
        .card(radius: 22)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Brand.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.body.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// Hatırlatma yerinde değişir; ayrı form açılmaz.
    private func reminderBinding(_ group: StudyGroup) -> Binding<ReminderSetting> {
        Binding(get: { store.group(id)?.reminder ?? group.reminder },
                set: { value in
                    guard var current = store.group(id) else { return }
                    current.reminder = value
                    store.save(current)
                })
    }

    private func holidayPicker(_ group: StudyGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                holidayButton(s.oneWeek) { setHoliday(days: 6) }
                holidayButton(s.twoWeeks) { setHoliday(days: 13) }
                holidayButton(s.oneMonth) { setHoliday(days: 29) }
                holidayButton(s.pickDate) { withAnimation(.snappy) { pickingHoliday.toggle() } }
            }
            if pickingHoliday {
                HStack {
                    DatePicker(s.endDate, selection: $customHolidayEnd,
                               in: Calendar.remi.startOfDay(for: .now)...Calendar.remi.date(byAdding: .day, value: DayRange.maxDays, to: .now)!,
                               displayedComponents: .date)
                    Button(s.startVacation) {
                        store.setHoliday(DayRange(start: Calendar.remi.startOfDay(for: .now), end: customHolidayEnd), for: [group.id])
                        pickingHoliday = false
                    }
                    .font(.footnote.weight(.bold))
                }
                .padding(12)
                .card(radius: 16)
            }
        }
        .fieldLabel(s.enterVacation)
    }

    private func holidayButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Brand.text)
                .card(radius: 14)
        }
        .buttonStyle(.plain)
    }

    private func setHoliday(days: Int) {
        let start = Calendar.remi.startOfDay(for: .now)
        store.setHoliday(DayRange(start: start, end: Calendar.remi.date(byAdding: .day, value: days, to: start)!), for: [id])
    }

    private func upcoming(_ group: StudyGroup) -> some View {
        let dates = nextDates(group, count: 3)
        return VStack(spacing: 0) {
            ForEach(dates, id: \.self) { day in
                let paused = group.isOnHoliday(on: day) || store.profile.isOnVacation(on: day)
                HStack {
                    Text("\(s.date(day, "EEE d MMM")) · \(s.clock(group.startMinute))").font(.body.weight(.semibold))
                    Spacer()
                    Text(paused ? s.onHoliday : s.reminderAt(max(group.startMinute - group.reminder.minutesBefore, 0)))
                        .font(.footnote).foregroundStyle(Brand.secondary)
                }
                .padding(.horizontal, 16).frame(minHeight: 48)
                .opacity(paused ? 0.5 : 1)
                if day != dates.last { Divider().overlay(Brand.line) }
            }
        }
        .card(radius: 22)
        .fieldLabel(s.upcomingLessons)
    }

    private func nextDates(_ group: StudyGroup, count: Int) -> [Date] {
        var result: [Date] = []
        var day = Calendar.remi.startOfDay(for: .now)
        while result.count < count, result.count < 60 {
            if group.meets(on: day), day.addingTimeInterval(TimeInterval(group.startMinute * 60)) > .now { result.append(day) }
            day = Calendar.remi.date(byAdding: .day, value: 1, to: day)!
            if day > Calendar.remi.date(byAdding: .day, value: 60, to: .now)! { break }
        }
        return result
    }
}
