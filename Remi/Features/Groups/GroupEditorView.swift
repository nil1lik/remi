import SwiftUI
import UIKit

/// Grup formu. Hızlı (ad, günler, saat), tam (tüm ayarlar) ya da düzenleme. Tek panel; içinden başka form açılmaz.
struct GroupEditorView: View {
    enum Mode: Hashable { case quick, full, edit(UUID) }

    let mode: Mode
    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss
    @State private var draft = StudyGroup(name: "", days: [], startMinute: 9 * 60)
    @State private var loaded = false
    @State private var showProblems = false
    @FocusState private var focus: Field?

    private enum Field { case name, link }

    private var isQuick: Bool { mode == .quick }
    private var title: String {
        switch mode {
        case .quick: s.quickGroup
        case .full: s.newGroup
        case .edit: s.editGroup
        }
    }
    private var problems: [GroupRules.Problem] { GroupRules.problems(of: draft) }
    private var limitReached: Bool {
        if case .edit = mode { return false }
        return !store.canAddGroup
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField
                    if !isQuick { colorField }
                    linkField
                    DayPicker(selection: $draft.days, color: draft.color.color).fieldLabel(s.whichDays)
                    timeField
                    if !isQuick { reminderField }
                    if isQuick { Text(s.quickNote).font(.footnote).foregroundStyle(Brand.secondary) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(Brand.background.ignoresSafeArea())
        .presentationDetents(isQuick ? [.large] : [.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
    }

    // MARK: Parçalar

    private var header: some View {
        HStack {
            Text(title).font(Brand.display(24, language: s.language))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Brand.secondary)
                    .frame(width: 36, height: 36).background(Brand.chip, in: Circle())
            }
            .accessibilityLabel(s.close)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Circle().fill(draft.color.color).frame(width: 12, height: 12)
            TextField(s.groupNamePlaceholder, text: $draft.name)
                .font(.title3.weight(.semibold))
                .focused($focus, equals: .name)
                .submitLabel(.done)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(draft.color.color, lineWidth: 1.5))
        .fieldLabel(s.groupName)
    }

    private var colorField: some View {
        ColorDots(options: GroupColor.allCases, selection: $draft.color, color: \.color, label: s.colorName, size: 36)
            .fieldLabel(s.color)
    }

    @ViewBuilder
    private var linkField: some View {
        let link = draft.chatLink ?? ""
        let parsed = link.isEmpty ? nil : ChatLinkRule.parse(link)
        if isQuick {
            Button(action: pasteLink) {
                Label(parsed.map { s.linkAdded($0.app) } ?? s.pasteLinkOptional, systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(parsed == nil ? Brand.secondary : Brand.newsText)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(parsed == nil ? Brand.line : Brand.newsText, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(Brand.secondary)
                    TextField("chat.whatsapp.com/… · t.me/…", text: Binding(get: { draft.chatLink ?? "" }, set: { draft.chatLink = $0 }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focus, equals: .link)
                        .environment(\.layoutDirection, .leftToRight)
                    Button(s.paste, action: pasteLink)
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 12).frame(minHeight: 38)
                        .background(Brand.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Brand.text)
                }
                .padding(.leading, 14).padding(.trailing, 8)
                .frame(minHeight: 54)
                .card(radius: 16)
                if let parsed {
                    Label(s.linkRecognized(parsed.app), systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Brand.newsText)
                } else if !link.isEmpty {
                    Label(s.linkInvalid, systemImage: "exclamationmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Brand.danger)
                }
            }
            .fieldLabel(s.chatLinkLabel)
        }
    }

    private var timeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimeStepper(startMinute: $draft.startMinute, durationMinutes: draft.durationMinutes)
            if !isQuick {
                HStack(spacing: 8) {
                    ForEach([45, 60, 90, 120], id: \.self) { minutes in
                        let on = draft.durationMinutes == minutes
                        Button { draft.durationMinutes = minutes } label: {
                            Text(s.duration(minutes))
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(on ? .white : Brand.text)
                                .background(on ? draft.color.color : Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? .clear : Brand.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        .fieldLabel(s.time)
    }

    private var reminderField: some View {
        VStack(spacing: 8) {
            ReminderWheel(minutes: $draft.reminder.minutesBefore)
            Text(s.reminderShort(draft.reminder)).font(.footnote.weight(.semibold)).foregroundStyle(Brand.secondary)
            SegmentedPills(options: ReminderKind.allCases, selection: $draft.reminder.kind, title: s.kind)
        }
        .padding(10)
        .card(radius: 20)
        .fieldLabel(s.remindWhen)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if showProblems, let message = limitReached ? s.groupLimit : problems.first.map(s.problem) {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.danger)
                    .transition(.opacity)
            }
            Button(saveTitle, action: save)
                .buttonStyle(PrimaryButtonStyle(color: accent.fill))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Brand.background)
        .overlay(alignment: .top) { Divider().overlay(Brand.line) }
        .animation(.snappy, value: showProblems)
        .sensoryFeedback(.error, trigger: showProblems) { _, new in new }
    }

    private var saveTitle: String {
        switch mode {
        case .quick: s.addGroup
        case .full: s.createGroup
        case .edit: s.save
        }
    }

    // MARK: İşlemler

    private func load() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let id) = mode, let group = store.group(id) {
            draft = group
        } else {
            draft.color = GroupColor.next(after: store.groups)
            draft.reminder = store.profile.defaultReminder
            draft.days = [Weekday(date: .now)]
            focus = .name
        }
    }

    private func pasteLink() {
        guard let text = UIPasteboard.general.string else { return }
        draft.chatLink = ChatLinkRule.normalized(text) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard problems.isEmpty, !limitReached, store.save(draft) else {
            withAnimation { showProblems = true }
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
