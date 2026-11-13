import Foundation

/// Sunucudaki value object kurallarının aynısı; telefon geçersiz veriyi hiç göndermez.
enum GroupRules {
    static let maxNameLength = 60
    static let minDuration = 15
    static let maxDuration = 600
    static let maxGroups = 200

    enum Problem: Hashable {
        case nameRequired, nameTooLong, nameInvalid
        case noDays
        case endsAfterMidnight
        case badLink
        case badReminder
        case badHoliday
    }

    static func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Kontrol ve yazı yönünü gizlice çeviren (bidi) karakterler adı sahte gösterebilir.
    static func hasUnsafeCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            s.properties.generalCategory == .control || (0x202A...0x202E).contains(s.value) || (0x2066...0x2069).contains(s.value)
        }
    }

    static func problems(of group: StudyGroup) -> [Problem] {
        var problems: [Problem] = []
        let name = clean(group.name)
        if name.isEmpty { problems.append(.nameRequired) }
        else if name.count > maxNameLength { problems.append(.nameTooLong) }
        else if hasUnsafeCharacters(name) { problems.append(.nameInvalid) }
        if group.days.isEmpty { problems.append(.noDays) }
        if group.startMinute + group.durationMinutes > 24 * 60 { problems.append(.endsAfterMidnight) }
        if let link = group.chatLink, !link.isEmpty, ChatLinkRule.parse(link) == nil { problems.append(.badLink) }
        if !ReminderSetting.isAllowed(group.reminder.minutesBefore) { problems.append(.badReminder) }
        if let holiday = group.holiday, !holiday.isValid { problems.append(.badHoliday) }
        return problems
    }
}

/// Yalnız https ve yalnız WhatsApp/Telegram grup adresleri. Kullanıcı adı, port, ? ve # yok.
enum ChatLinkRule {
    private static let hosts: [String: ChatApp] = [
        "chat.whatsapp.com": .whatsapp,
        "t.me": .telegram,
        "telegram.me": .telegram,
    ]

    static func parse(_ input: String) -> (url: URL, app: ChatApp)? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text),
              components.scheme == "https",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              let host = components.host?.lowercased(), let app = hosts[host]
        else { return nil }

        // Kodlanmış yol: "%2F" gibi kaçışlar çözülmeden reddedilir (sunucu da aynı şekilde reddeder).
        let path = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+/")
        guard (1...120).contains(path.count), path.unicodeScalars.allSatisfy(allowed.contains),
              let url = URL(string: "https://\(host)/\(path)")
        else { return nil }
        return (url, app)
    }

    static func normalized(_ input: String) -> String? { parse(input)?.url.absoluteString }
}
