import SwiftUI
import UIKit

/// Tatil gir: hocanın kendisi (tüm hatırlatmalar susar) ya da seçilen gruplar.
struct VacationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss

    @State private var me = false
    @State private var selected: Set<UUID> = []
    @State private var period: Period = .week
    @State private var start = Calendar.remi.startOfDay(for: .now)
    @State private var customEnd = Calendar.remi.date(byAdding: .day, value: 7, to: Calendar.remi.startOfDay(for: .now))!

    private enum Period: Hashable, CaseIterable { case week, twoWeeks, month, custom }

    private var end: Date {
        let c = Calendar.remi
        switch period {
        case .week: return c.date(byAdding: .day, value: 6, to: start)!
        case .twoWeeks: return c.date(byAdding: .day, value: 13, to: start)!
        case .month: return c.date(byAdding: .day, value: -1, to: c.date(byAdding: .month, value: 1, to: start)!)!
        case .custom: return max(customEnd, start)
        }
    }

    private var targets: [StudyGroup] { me ? store.groups : store.groups.filter { selected.contains($0.id) } }

    private var lessonCount: Int {
        var count = 0
        var day = start
        while day <= end {
            count += targets.filter { $0.meets(on: day) }.count
            day = Calendar.remi.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "beach.umbrella").foregroundStyle(Brand.holidayText)
                    .frame(width: 36, height: 36).background(Brand.holidayBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(s.enterVacation).font(Brand.display(24, language: s.language))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Brand.secondary)
                        .frame(width: 36, height: 36).background(Brand.chip, in: Circle())
                }
                .accessibilityLabel(s.close)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SwitchRow(title: s.meOnVacation, detail: s.meOnVacationDetail, isOn: $me.animation(.snappy), tint: accent.fill)
                        .card(radius: 20)

                    if !me && !store.groups.isEmpty { groupList }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(Period.allCases, id: \.self) { p in
                                let on = period == p
                                Button { period = p } label: {
                                    Text(label(p)).font(.subheadline.weight(.bold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(on ? .white : Brand.text)
                                        .background(on ? accent.fill : Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? .clear : Brand.line))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        HStack(spacing: 8) {
                            dateBox(s.startDate) {
                                DatePicker("", selection: $start, in: Calendar.remi.startOfDay(for: .now)..., displayedComponents: .date).labelsHidden()
                            }
                            dateBox(s.endDate) {
                                if period == .custom {
                                    DatePicker("", selection: $customEnd, in: start...Calendar.remi.date(byAdding: .day, value: DayRange.maxDays, to: start)!, displayedComponents: .date).labelsHidden()
                                } else {
                                    Text(s.date(end, "d MMM EEE")).font(.body.weight(.bold))
                                }
                            }
                        }
                    }
                    .fieldLabel(s.howLong)

                    Text(targets.isEmpty ? s.pickAGroup : s.vacationSummary(lessonCount))
                        .font(.footnote)
                        .foregroundStyle(Brand.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Button(s.startVacation, action: apply)
                .buttonStyle(PrimaryButtonStyle(color: accent.fill))
                .disabled(targets.isEmpty && !me)
                .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Brand.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.someGroups).font(.footnote.weight(.semibold)).foregroundStyle(Brand.secondary)
                Spacer()
                let all = selected.count == store.groups.count
                Button(all ? s.none : s.all) { selected = all ? [] : Set(store.groups.map(\.id)) }
                    .font(.footnote.weight(.bold))
            }
            VStack(spacing: 0) {
                ForEach(store.groups) { group in
                    let on = selected.contains(group.id)
                    Button {
                        if on { selected.remove(group.id) } else { selected.insert(group.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(group.color.color).frame(width: 10, height: 10)
                            Text(group.name).font(.body.weight(.semibold)).foregroundStyle(Brand.text)
                            Spacer()
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .font(.title3).foregroundStyle(on ? accent.fill : Brand.secondary)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    if group.id != store.groups.last?.id { Divider().overlay(Brand.line) }
                }
            }
            .card(radius: 20)
        }
    }

    private func dateBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Brand.secondary)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 14)
        .card(radius: 16)
    }

    private func label(_ p: Period) -> String {
        switch p {
        case .week: s.oneWeek
        case .twoWeeks: s.twoWeeks
        case .month: s.oneMonth
        case .custom: s.pickDate
        }
    }

    private func apply() {
        let range = DayRange(start: start, end: end)
        guard range.isValid else { return }
        if me { store.startVacation(range) } else { store.setHoliday(range, for: selected) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
