import SwiftUI

// MARK: - Logo

/// Remi işareti: kalın, yuvarlak bir "r" ve ucunda mercan "ping" noktası.
struct BrandMark: View {
    var stroke: Color = Brand.text
    var dot: Color = Brand.ping
    var dotOpacity: Double = 1
    var dotScale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 48
            var r = Path()
            r.move(to: CGPoint(x: 15 * s, y: 37 * s))
            r.addLine(to: CGPoint(x: 15 * s, y: 23 * s))
            r.addArc(center: CGPoint(x: 25 * s, y: 23 * s), radius: 10 * s,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            r.addLine(to: CGPoint(x: 26 * s, y: 13 * s))
            context.stroke(r, with: .color(stroke), style: StrokeStyle(lineWidth: 7 * s, lineCap: .round, lineJoin: .round))
        }
        .overlay {
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height) / 48
                Circle()
                    .fill(dot)
                    .frame(width: 11 * s, height: 11 * s)
                    .scaleEffect(dotScale)
                    .opacity(dotOpacity)
                    .position(x: 35 * s, y: 13 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Logo dile göre aynalanmaz (Arapçada da aynı).
        .environment(\.layoutDirection, .leftToRight)
        .flipsForRightToLeftLayoutDirection(false)
        .accessibilityHidden(true)
    }
}

/// "remi" yazısı: i'nin noktası ping rengindedir.
struct Wordmark: View {
    var size: CGFloat
    var color: Color = Brand.text

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.03) {
            Text(verbatim: "rem")
                .font(.custom("BricolageGrotesque-96ptExtraBold_ExtraBold", size: size))
                .tracking(-size * 0.035)
            VStack(spacing: size * 0.09) {
                Circle().fill(Brand.ping).frame(width: size * 0.25, height: size * 0.25)
                RoundedRectangle(cornerRadius: size * 0.05).frame(width: size * 0.2, height: size * 0.52)
            }
            .padding(.bottom, size * 0.2)
            .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - size * 0.2 }
        }
        .foregroundStyle(color)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remi")
    }
}

/// Yanıp sönen mercan nokta (sıradaki ders, giriş ekranı).
struct PingDot: View {
    var size: CGFloat = 10
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Brand.ping)
                .scaleEffect(pulse ? 3 : 1)
                .opacity(pulse ? 0 : 0.6)
            Circle().fill(Brand.ping)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Yüzeyler ve düğmeler

extension View {
    /// Beyaz (koyu temada koyu) kart, ince kenarlık.
    func card(radius: CGFloat = 22, padding: CGFloat = 0) -> some View {
        self.padding(padding)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Brand.line))
    }

    /// Form alanı başlığı.
    func fieldLabel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Brand.secondary)
            self
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isEnabled ? color : Brand.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Seçenekler arasında tek seçim (Gruplar/Hafta, Bildirim/Alarm, tema).
struct SegmentedPills<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.text)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Brand.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Brand.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Haftanın 7 günü, tek satır; dokununca seçilir.
struct DayPicker: View {
    @Binding var selection: Set<Weekday>
    var color: Color
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(s.weekdayShort(day))
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(on ? .white : Brand.text)
                        .background(on ? color : Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? .clear : Brand.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.weekdayName(day))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Renk seçici: dokunulabilir daireler.
struct ColorDots<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let color: (Value) -> Color
    let label: (Value) -> String
    var size: CGFloat = 44

    var body: some View {
        HStack {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Circle()
                        .fill(color(option))
                        .frame(width: size, height: size)
                        .padding(3)
                        .overlay(Circle().strokeBorder(on ? color(option) : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(on ? .isSelected : [])
                if option != options.last { Spacer(minLength: 0) }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Başlangıç saati: − / + ile 15'er dakika. Klavye açılmaz.
struct TimeStepper: View {
    @Binding var startMinute: Int
    var durationMinutes: Int
    @Environment(\.strings) private var s

    var body: some View {
        HStack {
            step("minus", s.earlier) { startMinute = max(0, startMinute - 15) }
            Spacer()
            Text(s.timeRange(startMinute, min(startMinute + durationMinutes, 24 * 60)))
                .font(Brand.display(26, language: s.language))
                .monospacedDigit()
                .contentTransition(.numericText())
                .environment(\.layoutDirection, .leftToRight)
            Spacer()
            step("plus", s.later) { startMinute = min(24 * 60 - 15, startMinute + 15) }
        }
        .padding(10)
        .card(radius: 18)
        .animation(.snappy, value: startMinute)
        .sensoryFeedback(.selection, trigger: startMinute)
    }

    private func step(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .frame(width: 44, height: 44)
                .background(Brand.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Satıra sığmayan öğeler alt satıra iner (yatay kaydırma yok).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Hatırlatma tekerleği

/// Hatırlatma süresi elle yazılmaz, kaydırılarak seçilir: 0–60 dakika (5'er) ya da 1–12 saat.
struct ReminderWheel: View {
    @Binding var minutes: Int
    @Environment(\.strings) private var s

    private enum Unit: Hashable { case minutes, hours }

    var body: some View {
        let unit: Binding<Unit> = Binding(
            get: { minutes > 60 ? .hours : .minutes },
            set: { newUnit in
                if newUnit == .hours, minutes <= 60 { minutes = 120 }
                if newUnit == .minutes, minutes > 60 { minutes = 60 }
            })
        let value: Binding<Int> = Binding(
            get: { minutes > 60 ? minutes / 60 : minutes },
            set: { minutes = unit.wrappedValue == .hours ? $0 * 60 : $0 })

        HStack(spacing: 0) {
            Picker("", selection: value) {
                ForEach(unit.wrappedValue == .hours ? ReminderSetting.hourValues : ReminderSetting.minuteValues, id: \.self) {
                    Text(s.number($0)).tag($0)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("", selection: unit) {
                Text(s.minutesBefore).tag(Unit.minutes)
                Text(s.hoursBefore).tag(Unit.hours)
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 150)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(s.remindWhen)
        .accessibilityValue(s.reminderShort(ReminderSetting(minutesBefore: minutes)))
    }
}

/// Açık/kapalı anahtarlı satır (tatil, dışa aktarma seçenekleri).
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    @Binding var isOn: Bool
    var tint: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                if let icon { Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 22) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    if let detail { Text(detail).font(.footnote).foregroundStyle(Brand.secondary) }
                }
            }
        }
        .tint(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
