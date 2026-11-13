import SwiftUI

/// Markalı giriş: Remi moru zemin, halkalar, dil seçici (TR / EN / ع), Apple, Google ya da girişsiz devam.
struct LoginView: View {
    var onContinue: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.strings) private var s
    @State private var busy: String?
    @State private var failed = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                languagePicker.padding(.top, 12)
                Spacer()
                VStack(spacing: 22) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.white).frame(width: 112, height: 112)
                            .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
                        BrandMark(stroke: Brand.ink).frame(width: 72, height: 72)
                    }
                    Wordmark(size: 58, color: .white)
                    Text(s.tagline)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                Spacer()
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        // Halkalar yerleşimi genişletmesin diye arka planda.
        .background { ZStack { Brand.ink; rings }.ignoresSafeArea() }
        .alert(s.signInFailed, isPresented: $failed) { Button(s.close, role: .cancel) {} }
    }

    private var rings: some View {
        ZStack {
            ForEach([220, 380, 560, 760], id: \.self) { size in
                Circle().strokeBorder(.white.opacity(size == 220 ? 0.14 : size == 380 ? 0.09 : 0.05), lineWidth: 1.5)
                    .frame(width: CGFloat(size), height: CGFloat(size))
            }
        }
        .offset(y: -90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    private var languagePicker: some View {
        HStack(spacing: 2) {
            ForEach(AppLanguage.allCases) { language in
                let on = store.profile.language == language
                Button {
                    store.updateProfile { $0.language = language }
                } label: {
                    Text(language == .ar ? "ع" : language.rawValue.uppercased())
                        .font(.subheadline.weight(.bold))
                        .frame(minWidth: 52, minHeight: 36)
                        .foregroundStyle(on ? Brand.ink : .white)
                        .background(on ? .white : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.nativeName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.white.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var buttons: some View {
        if sync.canSignIn {
            signInButtons
        } else {
            // Sunucu henüz yapılandırılmamış: yalnız cihazda kullanım.
            Button(action: onContinue) {
                Text(s.continueWithout)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Brand.night)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .padding(.bottom, 44)
        }
    }

    private var signInButtons: some View {
        VStack(spacing: 10) {
            Button { signIn("apple") } label: {
                Label(s.continueApple, systemImage: "applelogo")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Brand.night)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .trailing) { if busy == "apple" { ProgressView().tint(Brand.night).padding(.trailing, 18) } }
            }
            .buttonStyle(PressableStyle())

            if sync.googleAvailable {
                Button { signIn("google") } label: {
                    Label(s.continueGoogle, systemImage: "g.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.28), lineWidth: 1.5))
                        .overlay(alignment: .trailing) { if busy == "google" { ProgressView().tint(.white).padding(.trailing, 18) } }
                }
                .buttonStyle(PressableStyle())
            }

            Button(s.continueWithout, action: onContinue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minHeight: 44)
        }
        .disabled(busy != nil)
    }

    private func signIn(_ provider: String) {
        busy = provider
        Task {
            defer { busy = nil }
            do {
                try await sync.signIn(provider: provider)
                onContinue()
            } catch SignInService.SignInError.cancelled {
                // Kullanıcı vazgeçti.
            } catch {
                failed = true
            }
        }
    }
}
