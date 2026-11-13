import SwiftUI

/// Hoca tatildeyken ana sayfa uyur: gece moru, yıldızlar, sönük ping, süzülen "z"ler.
/// "Tatilden geldim"e basınca ping yanar, gece açılır ve Remi uyanır.
struct SleepView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.strings) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waking = false
    @State private var breathe = false

    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.14, 3), (0.77, 0.11, 4), (0.85, 0.27, 2), (0.2, 0.34, 2), (0.49, 0.08, 3), (0.08, 0.66, 2), (0.9, 0.62, 3),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Brand.night.ignoresSafeArea()
                ForEach(Self.stars.indices, id: \.self) { i in
                    let star = Self.stars[i]
                    TwinkleStar(size: star.2, delay: Double(i) * 0.4)
                        .position(x: geo.size.width * star.0, y: geo.size.height * star.1)
                }

                VStack(spacing: 22) {
                    Spacer()
                    ZStack {
                        Circle().fill(.white.opacity(0.06)).frame(width: 168, height: 168).scaleEffect(breathe ? 1.05 : 1)
                        Circle().fill(.white.opacity(0.06)).frame(width: 124, height: 124)
                        BrandMark(stroke: .white.opacity(0.85), dotOpacity: waking ? 1 : 0.3, dotScale: waking ? 1.35 : 1)
                            .frame(width: 84, height: 84)
                            .scaleEffect(breathe ? 1.05 : 1)
                        if !waking && !reduceMotion {
                            ForEach(0..<3, id: \.self) { i in FloatingZ(size: 18 + CGFloat(i) * 4, delay: Double(i)) }
                                .offset(x: 46, y: -48)
                        }
                    }
                    .frame(height: 200)
                    Spacer()

                    VStack(spacing: 10) {
                        Text(s.sleepTitle(store.profile.displayName))
                            .font(Brand.display(32, language: s.language))
                        if let end = store.profile.vacation?.end {
                            Text(s.sleepDetail(until: end))
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .multilineTextAlignment(.center)

                    Label(s.remindersOnHold(pausedCount), systemImage: "bell.slash")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(.white.opacity(0.8))

                    Button(action: wake) {
                        Label(s.backFromVacation, systemImage: "sunrise.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .foregroundStyle(Brand.night)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 10)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .sensoryFeedback(.success, trigger: waking)
    }

    /// Tatil bitene kadar susan ders sayısı (önümüzdeki günler).
    private var pausedCount: Int {
        guard let vacation = store.profile.vacation else { return 0 }
        var count = 0
        var day = Calendar.remi.startOfDay(for: .now)
        while day <= vacation.end {
            count += store.groups.filter { $0.meets(on: day) }.count
            day = Calendar.remi.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    private func wake() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { waking = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 650))
            store.endVacation()
        }
    }
}

private struct TwinkleStar: View {
    var size: CGFloat
    var delay: Double
    @State private var on = false

    var body: some View {
        Circle().fill(.white).frame(width: size, height: size).opacity(on ? 0.9 : 0.25)
            .onAppear { withAnimation(.easeInOut(duration: 2.8).repeatForever().delay(delay)) { on = true } }
            .accessibilityHidden(true)
    }
}

private struct FloatingZ: View {
    var size: CGFloat
    var delay: Double
    @State private var up = false

    var body: some View {
        Text(verbatim: "z")
            .font(.custom("BricolageGrotesque-96ptExtraBold_ExtraBold", size: size))
            .foregroundStyle(Color(hex: 0xADA4FF))
            .offset(x: up ? 22 : 0, y: up ? -46 : 0)
            .scaleEffect(up ? 1.15 : 0.7)
            .opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 3).repeatForever(autoreverses: false).delay(delay)) { up = true } }
            .accessibilityHidden(true)
    }
}
