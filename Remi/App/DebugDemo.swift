#if DEBUG
import Foundation

/// Yalnız Debug: ortam değişkenleriyle örnek veriyle açılış ve doğrudan bir ekrana gitme.
///   REMI_DEMO=1  REMI_SCREEN=today|program|week|group|export|profile|menu|quick|new|edit|vacation|sleep|login|personalize|empty
///   REMI_LANG=tr|en|ar  REMI_THEME=light|dark  REMI_ACCENT=violet|mint|…
enum DebugDemo {
    private static let env = ProcessInfo.processInfo.environment
    static var isActive: Bool { env["REMI_DEMO"] != nil }
    static var screen: String { env["REMI_SCREEN"] ?? "today" }
    static var language: AppLanguage { AppLanguage(rawValue: env["REMI_LANG"] ?? "") ?? .tr }
    static var theme: ThemeMode { ThemeMode(rawValue: env["REMI_THEME"] ?? "") ?? .light }
    static var accent: AccentChoice { AccentChoice(rawValue: env["REMI_ACCENT"] ?? "") ?? .violet }
    static var skipSplash: Bool { isActive && screen != "splash" }
}
#endif
