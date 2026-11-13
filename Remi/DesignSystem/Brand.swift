import SwiftUI
import UIKit

/// Remi marka renkleri ve açık/koyu tema jetonları.
enum Brand {
    static let ink = Color(hex: 0x2A1F7A)        // Remi moru: giriş ekranı, uyku modu, ikon
    static let ping = Color(hex: 0xFF6B4A)       // Hatırlatmanın "ping"i: logo noktası, sıradaki ders
    static let night = Color(hex: 0x15122E)      // Uyku modu zemini

    static let background = Color(light: 0xFAF8F5, dark: 0x0F0D1A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A1729)
    static let text = Color(light: 0x15122E, dark: 0xF3F1FA)
    static let secondary = Color(light: 0x6A6580, dark: 0xA39FB8)
    static let line = Color(light: 0xECE8E1, dark: 0x2A2640)
    static let chip = Color(light: 0xF2EFEA, dark: 0x26223A)
    static let tabBar = Color(light: 0x15122E, dark: 0x26223A)
    static let tabBarText = Color(light: 0xB7B2CC, dark: 0xA39FB8)

    static let holidayBackground = Color(light: 0xFFF1D6, dark: 0x3A2A10)
    static let holidayText = Color(light: 0x6B4100, dark: 0xF2C46B)
    static let newsBackground = Color(light: 0xE3F6EC, dark: 0x123326)
    static let newsIcon = Color(light: 0xC8EEDA, dark: 0x1B4A37)
    static let newsText = Color(light: 0x0E5A3A, dark: 0x8FE3B8)
    static let danger = Color(light: 0xB3261E, dark: 0xFF8A80)

    /// Başlık yazı tipi: Bricolage Grotesque. Arapçada sistem yazı tipi (Arapça harf içermiyor).
    static func display(_ size: CGFloat, language: AppLanguage, bold: Bool = false) -> Font {
        if language == .ar { return .system(size: size, weight: .heavy) }
        return .custom(bold ? "BricolageGrotesque-96ptExtraBold_Bold" : "BricolageGrotesque-96ptExtraBold_ExtraBold",
                       size: size, relativeTo: size > 24 ? .largeTitle : .title3)
    }
}

extension AccentChoice {
    /// Dolgu rengi (beyaz yazıyla okunur) ve koyu zeminde okunur metin rengi.
    var fill: Color {
        switch self {
        case .violet: Color(hex: 0x4B3BDB)
        case .mint: Color(hex: 0x0B7A6C)
        case .coral: Color(hex: 0xC8402B)
        case .rose: Color(hex: 0xC0306A)
        case .amber: Color(hex: 0x9A5B00)
        case .ocean: Color(hex: 0x2272D0)
        }
    }

    var text: Color {
        let dark: UInt32 = switch self {
        case .violet: 0xADA4FF
        case .mint: 0x4FD1BE
        case .coral: 0xFF8A75
        case .rose: 0xFF7FAE
        case .amber: 0xF2A93B
        case .ocean: 0x6FB0FF
        }
        return Color(light: fillHex, dark: dark)
    }

    private var fillHex: UInt32 {
        switch self {
        case .violet: 0x4B3BDB
        case .mint: 0x0B7A6C
        case .coral: 0xC8402B
        case .rose: 0xC0306A
        case .amber: 0x9A5B00
        case .ocean: 0x2272D0
        }
    }
}

extension GroupColor {
    var color: Color {
        switch self {
        case .blue: Color(hex: 0x2272D0)
        case .green: Color(hex: 0x0B7A6C)
        case .coral: Color(hex: 0xC8402B)
        case .rose: Color(hex: 0xC0306A)
        case .amber: Color(hex: 0x9A5B00)
        case .violet: Color(hex: 0x4B3BDB)
        }
    }

    /// Yeni gruba sıradaki renk: mevcutlar arasında en az kullanılan.
    static func next(after groups: [StudyGroup]) -> GroupColor {
        let used = Dictionary(grouping: groups, by: \.color).mapValues(\.count)
        return allCases.min { used[$0, default: 0] < used[$1, default: 0] } ?? .blue
    }
}

// MARK: - Ortam

private struct AccentKey: EnvironmentKey {
    static let defaultValue = AccentChoice.violet
}

extension EnvironmentValues {
    /// Kullanıcının seçtiği uygulama rengi.
    var accent: AccentChoice {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Açık ve koyu temada farklı renk.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
