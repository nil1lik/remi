import SwiftUI

/// "Remi senin gibi olsun": dil, hitap, renk ve görünüm. Seçtikçe ekran o hale bürünür.
struct PersonalizeView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = Profile()
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var s: Strings { Strings(language: draft.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    BrandMark().frame(width: 30, height: 30)
                    Text(s.lastStep).font(.footnote.weight(.semibold)).foregroundStyle(Brand.secondary)
                }
                Text(s.personalizeTitle)
                    .font(Brand.display(34, language: draft.language))
                    .tracking(draft.language == .ar ? 0 : -1)

                HStack(spacing: 8) {
                    ForEach(AppLanguage.allCases) { language in
                        let on = draft.language == language
                        Button { withAnimation(.snappy) { draft.language = language } } label: {
                            Text(language.nativeName)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .foregroundStyle(Brand.text)
                                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? draft.accent.fill : Brand.line, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .fieldLabel(s.languageLabel)

                TextField(s.namePlaceholder, text: $draft.displayName)
                    .font(.title3.weight(.semibold))
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .card(radius: 14)
                    .fieldLabel(s.howToCall)
                    .onChange(of: draft.displayName) { _, v in if v.count > 40 { draft.displayName = String(v.prefix(40)) } }

                ColorDots(options: AccentChoice.allCases, selection: $draft.accent, color: \.fill, label: s.accentName, size: 42)
                    .fieldLabel(s.yourColor)

                HStack(spacing: 8) {
                    ForEach(ThemeMode.allCases) { mode in themeCard(mode) }
                }
                .fieldLabel(s.appearance)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Brand.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(s.letsStart(GroupRules.clean(draft.displayName))) {
                var profile = draft
                profile.displayName = GroupRules.clean(profile.displayName)
                withAnimation(.snappy) { store.completeOnboarding(profile) }
            }
            .buttonStyle(PrimaryButtonStyle(color: draft.accent.fill))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Brand.background)
        }
        // Seçimler anında görünsün: bu ekran kendi taslağıyla boyanır.
        .environment(\.strings, s)
        .environment(\.layoutDirection, draft.language.isRightToLeft ? .rightToLeft : .leftToRight)
        .preferredColorScheme(draft.theme.colorScheme)
        .tint(draft.accent.fill)
        .animation(.snappy, value: draft)
        .onAppear {
            guard !loaded else { return }
            draft = store.profile
            loaded = true
        }
    }

    private func themeCard(_ mode: ThemeMode) -> some View {
        let on = draft.theme == mode
        return Button { draft.theme = mode } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(mode == .dark ? Color(hex: 0x0F0D1A) : Color(hex: 0xFAF8F5))
                    .overlay {
                        if mode == .system {
                            HStack(spacing: 0) { Color(hex: 0xFAF8F5); Color(hex: 0x1A1729) }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        Capsule().fill(draft.accent.fill).frame(width: 40, height: 10).padding(8)
                    }
                    .frame(height: 52)
                Text(s.theme(mode)).font(.footnote.weight(.semibold)).foregroundStyle(Brand.text)
            }
            .padding(8)
            .card(radius: 16)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? draft.accent.fill : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
