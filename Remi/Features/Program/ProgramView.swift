import SwiftUI

/// Program: gruplar (varsayılan) ya da gün gün hafta. Excel ve yazdırma buradan.
struct ProgramView: View {
    var open: (ActiveSheet) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    #if DEBUG
    @State private var view: Mode = DebugDemo.screen == "week" ? .week : .groups
    #else
    @State private var view: Mode = .groups
    #endif

    private enum Mode: Hashable { case groups, week }

    private var weeklyLessons: Int { store.groups.reduce(0) { $0 + $1.days.count } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.program).font(Brand.display(32, language: s.language)).tracking(s.language == .ar ? 0 : -1)
                        Text(s.programSummary(groups: store.groups.count, lessons: weeklyLessons))
                            .font(.subheadline).foregroundStyle(Brand.secondary)
                    }
                    Spacer()
                    if !store.groups.isEmpty {
                        NavigationLink(value: ExportRoute()) {
                            Label(s.exportPrint, systemImage: "printer")
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 12).frame(minHeight: 38)
                                .background(Brand.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(Brand.text)
                        }
                    }
                }

                if store.groups.isEmpty {
                    NoGroupsCard(open: open)
                } else {
                    SegmentedPills(options: [Mode.groups, .week], selection: $view) { $0 == .groups ? s.groupsTab : s.weekTab }
                    if view == .groups { groupList } else { weekList }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Brand.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var groupList: some View {
        VStack(spacing: 10) {
            ForEach(store.groups.sorted { ($0.startMinute, $0.name) < ($1.startMinute, $1.name) }) { group in
                let onHoliday = group.holiday.map { $0.end >= Calendar.remi.startOfDay(for: .now) } ?? false
                HStack(spacing: 14) {
                    NavigationLink(value: group.id) {
                        HStack(spacing: 14) {
                            Circle().fill(group.color.color).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.name).font(.body.weight(.semibold)).foregroundStyle(Brand.text)
                                Text(onHoliday ? s.holidayUntil(group.holiday!.end) : "\(s.days(group.days)) · \(s.timeRange(group.startMinute, group.endMinute))")
                                    .font(.footnote).foregroundStyle(Brand.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if onHoliday {
                        Text(s.onHoliday).font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Brand.holidayBackground, in: Capsule()).foregroundStyle(Brand.holidayText)
                    } else if let link = group.chatLink, let parsed = ChatLinkRule.parse(link) {
                        Button { openURL(parsed.url) } label: {
                            Label(parsed.app.title, systemImage: "bubble.left.fill")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10).frame(minHeight: 38)
                                .background(Brand.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(Brand.text)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.openGroup(named: group.name))
                    }
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .card(radius: 22)
                .opacity(onHoliday ? 0.65 : 1)
            }
            Button { open(.newGroup) } label: {
                Label(s.newGroup, systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Brand.secondary)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Brand.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(.plain)
        }
    }

    private var weekList: some View {
        VStack(spacing: 0) {
            ForEach(Weekday.allCases) { day in
                let groups = store.groups.filter { $0.days.contains(day) }.sorted { $0.startMinute < $1.startMinute }
                HStack(alignment: .top, spacing: 12) {
                    Text(s.weekdayShort(day)).font(.footnote.weight(.bold))
                        .foregroundStyle(Weekday(date: .now) == day ? AnyShapeStyle(.tint) : AnyShapeStyle(Brand.text))
                        .frame(width: 38, alignment: .leading).padding(.top, 7)
                    FlowLayout(spacing: 6) {
                        if groups.isEmpty {
                            Text(s.free).font(.footnote).foregroundStyle(Brand.secondary).frame(minHeight: 30)
                        }
                        ForEach(groups) { group in
                            NavigationLink(value: group.id) {
                                HStack(spacing: 6) {
                                    Circle().fill(group.color.color).frame(width: 7, height: 7)
                                    Text("\(s.clock(group.startMinute)) \(group.name)").font(.footnote.weight(.semibold))
                                }
                                .padding(.horizontal, 10).frame(minHeight: 30)
                                .background(group.color.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(Brand.text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                if day != .sunday { Divider().overlay(Brand.line) }
            }
        }
        .card(radius: 22)
    }
}

/// Programın kâğıt önizlemesi, Excel dosyası ve yazdırma.
struct ExportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @State private var includeLinks = false
    @State private var markHolidays = true
    @State private var fileURL: URL?

    private var rows: [ScheduleExport.Row] {
        ScheduleExport.rows(groups: store.groups, strings: s, includeLinks: includeLinks, markHolidays: markHolidays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paper
                VStack(spacing: 0) {
                    SwitchRow(title: s.includeLinks, isOn: $includeLinks, tint: accent.fill)
                    Divider().overlay(Brand.line)
                    SwitchRow(title: s.markHolidays, isOn: $markHolidays, tint: accent.fill)
                }
                .card(radius: 18)
            }
            .padding(20)
        }
        .background(Brand.chip.ignoresSafeArea())
        .navigationTitle(s.preview)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label(s.downloadExcel, systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(.white).background(accent.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                Button {
                    ScheduleExport.print(rows: rows, strings: s, includeLinks: includeLinks, markHolidays: markHolidays)
                } label: {
                    Label(s.print, systemImage: "printer.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white).background(Brand.night, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .padding(.bottom, 72)
            .background(Brand.background)
        }
        .task(id: [includeLinks, markHolidays]) {
            fileURL = try? ScheduleExport.excelFile(rows: rows, strings: s, includeLinks: includeLinks, markHolidays: markHolidays)
        }
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.weeklySchedule).font(Brand.display(17, language: s.language))
                    Text(s.takenOn(.now)).font(.caption2).foregroundStyle(Brand.secondary)
                }
                Spacer()
                BrandMark(stroke: Brand.ink).frame(width: 22, height: 22)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    Text(s.dayColumn); Text(s.timeColumn); Text(s.groupColumn)
                }
                .font(.caption2.weight(.bold)).foregroundStyle(Brand.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        Text(index > 0 && rows[index - 1].day == row.day ? "" : s.weekdayName(row.day)).fontWeight(.bold)
                        Text(row.time).monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.group)
                            if !row.note.isEmpty { Text(row.note).font(.caption2).foregroundStyle(Brand.secondary) }
                            if !row.link.isEmpty { Text(row.link).font(.caption2).foregroundStyle(Brand.secondary).lineLimit(1) }
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(18)
        .foregroundStyle(Color(hex: 0x15122E))
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
        .environment(\.colorScheme, .light)
    }
}
