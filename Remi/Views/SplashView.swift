import SwiftUI

/// Açılış animasyonu: renkli arka plan, çalan zil, harf harf gelen "Remi".
/// Sistem açılış ekranı (LaunchBackground rengi) ile aynı renkten başlar, böylece geçiş görünmez.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconIn = false
    @State private var ringsOn = false
    @State private var lettersIn = 0
    @State private var taglineIn = false
    @State private var ring = 0
    @State private var drift = false

    private static let name = Array("Remi")
    static let top = Color(red: 0.24, green: 0.20, blue: 0.70)
    static let bottom = Color(red: 0.55, green: 0.28, blue: 0.88)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 28) {
                ZStack {
                    if ringsOn {
                        ForEach(0..<3, id: \.self) { index in
                            PulseRing(delay: Double(index) * 0.45)
                        }
                    }
                    icon
                }
                .frame(width: 220, height: 220)

                VStack(spacing: 10) {
                    HStack(spacing: 1) {
                        ForEach(Self.name.indices, id: \.self) { index in
                            Text(String(Self.name[index]))
                                .font(.system(size: 54, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .opacity(index < lettersIn ? 1 : 0)
                                .offset(y: index < lettersIn ? 0 : 18)
                                .blur(radius: index < lettersIn ? 0 : 6)
                        }
                    }
                    Text("Hatırlaman gerekeni hatırlar.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .opacity(taglineIn ? 1 : 0)
                        .offset(y: taglineIn ? 0 : 8)
                }
            }
            .offset(y: -20)
        }
        .ignoresSafeArea()
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remi açılıyor")
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom)
            // Yavaşça süzülen ışık lekeleri.
            Circle()
                .fill(Color(red: 0.98, green: 0.45, blue: 0.70).opacity(0.55))
                .frame(width: 380)
                .blur(radius: 90)
                .offset(x: drift ? 120 : 60, y: drift ? -260 : -320)
            Circle()
                .fill(Color(red: 0.25, green: 0.75, blue: 0.95).opacity(0.45))
                .frame(width: 420)
                .blur(radius: 100)
                .offset(x: drift ? -140 : -80, y: drift ? 300 : 360)
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 260)
                .blur(radius: 70)
                .offset(x: drift ? -60 : 20, y: drift ? 20 : -40)
        }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
            Image(systemName: "bell.fill")
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(.white)
                .keyframeAnimator(initialValue: 0.0, trigger: ring) { content, angle in
                    content.rotationEffect(.degrees(angle), anchor: .top)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(18, duration: 0.12)
                        SpringKeyframe(-16, duration: 0.14)
                        SpringKeyframe(12, duration: 0.14)
                        SpringKeyframe(-8, duration: 0.14)
                        SpringKeyframe(0, duration: 0.2)
                    }
                }
            Circle()
                .fill(Color(red: 1.0, green: 0.42, blue: 0.48))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .offset(x: 30, y: -32)
                .scaleEffect(taglineIn ? 1 : 0)
        }
        .frame(width: 124, height: 124)
        .scaleEffect(iconIn ? 1 : 0.4)
        .opacity(iconIn ? 1 : 0)
        .rotationEffect(.degrees(iconIn ? 0 : -25))
    }

    private func run() async {
        if reduceMotion {
            iconIn = true; lettersIn = Self.name.count; taglineIn = true
            try? await Task.sleep(for: .milliseconds(700))
            onFinished()
            return
        }
        withAnimation(.easeInOut(duration: 2.4)) { drift = true }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { iconIn = true }
        try? await Task.sleep(for: .milliseconds(250))
        ringsOn = true
        for index in 1...Self.name.count {
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { lettersIn = index }
        }
        try? await Task.sleep(for: .milliseconds(120))
        ring += 1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { taglineIn = true }
        try? await Task.sleep(for: .milliseconds(1000))
        onFinished()
    }
}

private struct PulseRing: View {
    let delay: Double
    @State private var expand = false

    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
            .frame(width: 124, height: 124)
            .scaleEffect(expand ? 1.9 : 0.9)
            .opacity(expand ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(delay)) {
                    expand = true
                }
            }
    }
}
