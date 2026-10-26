import SwiftUI
import UIKit

/// Her derse adından türetilen sabit bir renk verir (aynı ders her yerde aynı renkte).
enum LessonPalette {
    static let colors: [Color] = [
        Color(red: 0.39, green: 0.40, blue: 0.95), // indigo
        Color(red: 0.05, green: 0.65, blue: 0.62), // teal
        Color(red: 0.96, green: 0.52, blue: 0.20), // turuncu
        Color(red: 0.92, green: 0.30, blue: 0.53), // pembe
        Color(red: 0.20, green: 0.66, blue: 0.33), // yeşil
        Color(red: 0.58, green: 0.36, blue: 0.90), // mor
        Color(red: 0.13, green: 0.55, blue: 0.93), // mavi
        Color(red: 0.85, green: 0.62, blue: 0.05), // hardal
        Color(red: 0.90, green: 0.33, blue: 0.27), // mercan
    ]

    static func color(for title: String) -> Color {
        // `hashValue` her açılışta değişir; kalıcı renk için basit djb2.
        var hash: UInt64 = 5381
        for scalar in ScheduleImporter.normalize(title).unicodeScalars {
            hash = (hash &<< 5) &+ hash &+ UInt64(scalar.value)
        }
        return colors[Int(hash % UInt64(colors.count))]
    }
}

extension Color {
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

enum DateText {
    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM EEEE")
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    /// "25 dk", "1 sa 10 dk"
    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(max(minutes, 1)) dk" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) sa" : "\(h) sa \(m) dk"
    }
}

/// Şablonu kullanıcıya Türkçe adla paylaşmak için geçici kopya.
enum TemplateFile {
    static let url: URL? = {
        guard let source = Bundle.main.url(forResource: "Ders-Programi-Sablon", withExtension: "xlsx") else { return nil }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("Ders Programı Şablonu.xlsx")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            return source
        }
    }()
}
