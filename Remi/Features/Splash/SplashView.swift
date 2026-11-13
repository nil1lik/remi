import SwiftUI

/// Açılış: Remi moru zemin, logodan yayılan halkalar, yanan ping noktası ve "remi" yazısı.
/// Sistem açılış ekranıyla (LaunchBackground) aynı renkten başlar; arada flaş olmaz.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markIn = false
    @State private var dotOn = false
    @State private var wordIn = false
    @State private var ripple = false

    var body: some View {
        ZStack {
            Brand.ink.ignoresSafeArea()

            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 120, height: 120)
                    .scaleEffect(ripple ? 2.6 + CGFloat(i) * 0.7 : 0.9)
                    .opacity(ripple ? 0 : 0.7)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.6).delay(Double(i) * 0.25), value: ripple)
            }
            .offset(y: -40)

            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.white)
                        .frame(width: 112, height: 112)
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
                    BrandMark(stroke: Brand.ink, dotOpacity: dotOn ? 1 : 0.25, dotScale: dotOn ? 1 : 0.6)
                        .frame(width: 72, height: 72)
                }
                .scaleEffect(markIn ? 1 : 0.6)
                .opacity(markIn ? 1 : 0)

                Wordmark(size: 54, color: .white)
                    .opacity(wordIn ? 1 : 0)
                    .offset(y: wordIn ? 0 : 12)
            }
            .offset(y: -20)
        }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remi")
    }

    private func run() async {
        if reduceMotion {
            (markIn, dotOn, wordIn) = (true, true, true)
            try? await Task.sleep(for: .milliseconds(500))
            onFinished()
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) { markIn = true }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { dotOn = true }
        ripple = true
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { wordIn = true }
        try? await Task.sleep(for: .milliseconds(1100))
        onFinished()
    }
}
