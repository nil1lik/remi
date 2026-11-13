import SwiftUI

enum MainTab: Hashable { case today, program, profile }

/// Tek seferde açık olabilecek tek form. Formlar üst üste açılmaz.
enum ActiveSheet: Identifiable, Hashable {
    case quickGroup
    case newGroup
    case editGroup(UUID)
    case vacation

    var id: String {
        switch self {
        case .quickGroup: "quick"
        case .newGroup: "new"
        case .editGroup(let id): "edit-\(id)"
        case .vacation: "vacation"
        }
    }
}

/// Ana yapı: sekmeler, markalı alt çubuk, + menüsü, formlar ve tatil (uyku) modu.
struct MainView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accent) private var accent
    @State private var tab: MainTab = .today
    @State private var sheet: ActiveSheet?
    @State private var showQuickMenu = false
    @State private var todayPath = NavigationPath()
    @State private var programPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var demoApplied = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .today:
                    NavigationStack(path: $todayPath) {
                        TodayView(open: open, showProfile: { tab = .profile })
                            .navigationDestination(for: UUID.self) { GroupDetailView(id: $0, open: open) }
                    }
                case .program:
                    NavigationStack(path: $programPath) {
                        ProgramView(open: open)
                            .navigationDestination(for: UUID.self) { GroupDetailView(id: $0, open: open) }
                            .navigationDestination(for: ExportRoute.self) { _ in ExportView() }
                    }
                case .profile:
                    NavigationStack(path: $profilePath) {
                        ProfileView()
                            .navigationDestination(for: ExportRoute.self) { _ in ExportView() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }

            if showQuickMenu { quickMenu }
            tabBar
        }
        .ignoresSafeArea(.keyboard)
        .overlay {
            if store.isOnVacationToday {
                SleepView().transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.easeInOut(duration: 0.6), value: store.isOnVacationToday)
        #if DEBUG
        .onAppear(perform: applyDemoRoute)
        #endif
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .quickGroup: GroupEditorView(mode: .quick)
                case .newGroup: GroupEditorView(mode: .full)
                case .editGroup(let id): GroupEditorView(mode: .edit(id))
                case .vacation: VacationSheet()
                }
            }
            .environment(\.strings, s)
            .environment(\.accent, accent)
            .environment(\.layoutDirection, s.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .tint(accent.fill)
        }
    }

    #if DEBUG
    private func applyDemoRoute() {
        guard DebugDemo.isActive, !demoApplied else { return }
        demoApplied = true
        let first = store.groups.first?.id
        switch DebugDemo.screen {
        case "program", "week": tab = .program
        case "group": tab = .program; if let first { programPath.append(first) }
        case "export": tab = .program; programPath.append(ExportRoute())
        case "profile": tab = .profile
        case "menu": showQuickMenu = true
        case "quick": sheet = .quickGroup
        case "new": sheet = .newGroup
        case "edit": if let first { sheet = .editGroup(first) }
        case "vacation": sheet = .vacation
        default: break
        }
    }
    #endif

    private func open(_ sheet: ActiveSheet) {
        showQuickMenu = false
        self.sheet = sheet
    }

    // MARK: Alt çubuk

    private var tabBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                tabButton(.today, s.tabToday, "clock")
                tabButton(.program, s.tabProgram, "calendar")
                tabButton(.profile, s.tabProfile, "person")
            }
            .padding(6)
            .frame(height: 60)
            .background(Brand.tabBar, in: Capsule())
            .shadow(color: Brand.night.opacity(0.22), radius: 17, y: 14)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showQuickMenu.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(showQuickMenu ? Brand.night : .white)
                    .rotationEffect(.degrees(showQuickMenu ? 45 : 0))
                    .frame(width: 60, height: 60)
                    .background(showQuickMenu ? AnyShapeStyle(.white) : AnyShapeStyle(accent.fill), in: Circle())
                    .shadow(color: accent.fill.opacity(0.35), radius: 13, y: 12)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(showQuickMenu ? s.close : s.quickActions)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func tabButton(_ value: MainTab, _ title: String, _ icon: String) -> some View {
        let on = tab == value
        return Button {
            if tab == value {
                // Aynı sekmeye dokununca başa dön.
                switch value {
                case .today: todayPath = NavigationPath()
                case .program: programPath = NavigationPath()
                case .profile: profilePath = NavigationPath()
                }
            }
            tab = value
            showQuickMenu = false
        } label: {
            Label(title, systemImage: on ? icon + ".fill" : icon)
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(on ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? Brand.night : Brand.tabBarText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(on ? Color.white : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: tab)
    }

    // MARK: + menüsü

    private var quickMenu: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy) { showQuickMenu = false } }
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                quickItem(s.quickGroup, s.quickGroupDetail, "bolt.fill", accent.fill.opacity(0.12), accent.text) { open(.quickGroup) }
                quickItem(s.newGroup, s.newGroupDetail, "person.2.badge.plus", accent.fill.opacity(0.12), accent.text) { open(.newGroup) }
                quickItem(s.enterVacation, s.enterVacationDetail, "beach.umbrella", Brand.holidayBackground, Brand.holidayText) { open(.vacation) }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 92)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func quickItem(_ title: String, _ detail: String, _ icon: String, _ iconBg: Color, _ iconFg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(iconFg)
                    .frame(width: 48, height: 48)
                    .background(iconBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Brand.display(19, language: s.language))
                    Text(detail).font(.footnote).foregroundStyle(Brand.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Brand.text)
            .padding(16)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct ExportRoute: Hashable {}
