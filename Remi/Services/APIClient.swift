import Foundation

/// Remi API istemcisi. Erişim anahtarı yalnız bellekte, yenileme anahtarı Keychain'de durur.
/// 401 gelirse anahtar bir kez yenilenir; yenileme de reddedilirse oturum kapanır.
@MainActor
final class APIClient {
    enum APIError: Error, Equatable {
        case notConfigured
        case sessionExpired
        case conflict(Data)
        case notFound
        case server(Int)
        case offline
    }

    private static let refreshKey = "refreshToken"
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private let session: URLSession

    /// Info.plist'teki RemiAPIBaseURL. Release'te yalnız https kabul edilir.
    let baseURL: URL?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)

        let raw = (Bundle.main.object(forInfoDictionaryKey: "RemiAPIBaseURL") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if let url = URL(string: raw), let scheme = url.scheme {
            #if DEBUG
            baseURL = scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" ? url : nil
            #else
            baseURL = scheme == "https" ? url : nil
            #endif
        } else {
            baseURL = nil
        }
    }

    var isConfigured: Bool { baseURL != nil }
    var hasSession: Bool { Keychain.get(Self.refreshKey) != nil }

    // MARK: Oturum

    func signIn(provider: String, idToken: String, nonce: String?, displayName: String, language: AppLanguage) async throws -> AuthResponse {
        let body = SignInBody(idToken: idToken, nonce: nonce, displayName: displayName, locale: language.rawValue)
        let response: AuthResponse = try await send("POST", "/v1/auth/\(provider)", body: body, authorized: false)
        store(response.accessToken, expiresIn: response.expiresIn, refresh: response.refreshToken)
        return response
    }

    func signOut() async {
        if let refresh = Keychain.get(Self.refreshKey) {
            let _: Empty? = try? await send("POST", "/v1/auth/logout", body: RefreshBody(refreshToken: refresh), authorized: false)
        }
        clearSession()
    }

    func deleteAccount() async throws {
        let _: Empty = try await send("DELETE", "/v1/me", body: Optional<Empty>.none)
        clearSession()
    }

    func clearSession() {
        accessToken = nil
        Keychain.remove(Self.refreshKey)
    }

    // MARK: Veri

    func sync(since: Int64) async throws -> SyncResponse {
        try await send("GET", "/v1/sync?since=\(since)", body: Optional<Empty>.none)
    }

    func createGroup(_ group: GroupDTO) async throws -> GroupDTO { try await send("POST", "/v1/groups", body: group) }
    func updateGroup(_ group: GroupDTO) async throws -> GroupDTO { try await send("PUT", "/v1/groups/\(group.id)", body: group) }

    func deleteGroup(_ id: UUID, version: Int?) async throws {
        let query = version.map { "?version=\($0)" } ?? ""
        let _: Empty = try await send("DELETE", "/v1/groups/\(id)\(query)", body: Optional<Empty>.none)
    }

    func updateProfile(_ patch: ProfilePatch) async throws -> ProfileDTO { try await send("PATCH", "/v1/me", body: patch) }
    func startVacation(_ range: DateRangeDTO) async throws -> ProfileDTO { try await send("PUT", "/v1/me/vacation", body: range) }
    func endVacation() async throws -> ProfileDTO { try await send("DELETE", "/v1/me/vacation", body: Optional<Empty>.none) }

    // MARK: İstek

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, body: Body?, authorized: Bool = true, retried: Bool = false
    ) async throws -> Response {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else { throw APIError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder.api.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200..<300:
            if Response.self == Empty.self || data.isEmpty { return try JSONDecoder.api.decode(Response.self, from: Data("{}".utf8)) }
            return try JSONDecoder.api.decode(Response.self, from: data)
        case 401 where authorized && !retried:
            accessToken = nil
            return try await send(method, path, body: body, authorized: authorized, retried: true)
        case 401:
            if authorized { clearSession() }
            throw APIError.sessionExpired
        case 404: throw APIError.notFound
        case 409: throw APIError.conflict(data)
        default: throw APIError.server(status)
        }
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessExpiry > .now.addingTimeInterval(30) { return accessToken }
        guard let refresh = Keychain.get(Self.refreshKey) else { throw APIError.sessionExpired }
        let tokens: TokenResponse = try await send("POST", "/v1/auth/refresh", body: RefreshBody(refreshToken: refresh), authorized: false)
        store(tokens.accessToken, expiresIn: tokens.expiresIn, refresh: tokens.refreshToken)
        return tokens.accessToken
    }

    private func store(_ access: String, expiresIn: Int, refresh: String) {
        accessToken = access
        accessExpiry = .now.addingTimeInterval(TimeInterval(expiresIn))
        Keychain.set(refresh, for: Self.refreshKey)
    }
}

// MARK: - Sunucu sözleşmesi

struct Empty: Codable {}
private struct SignInBody: Encodable { var idToken: String; var nonce: String?; var displayName: String; var locale: String }
private struct RefreshBody: Encodable { var refreshToken: String }

struct TokenResponse: Decodable { var accessToken: String; var expiresIn: Int; var refreshToken: String }

struct AuthResponse: Decodable {
    var accessToken: String
    var expiresIn: Int
    var refreshToken: String
    var profile: ProfileDTO
}

struct ProfileDTO: Codable {
    var id: UUID
    var displayName: String
    var locale: String
    var theme: String
    var accent: String
    var defaultReminderMinutes: Int
    var defaultReminderKind: String
    var vacationStart: String?
    var vacationEnd: String?

    var profile: Profile {
        Profile(displayName: displayName,
                language: AppLanguage(rawValue: locale) ?? .tr,
                theme: ThemeMode(rawValue: theme) ?? .system,
                accent: AccentChoice(rawValue: accent) ?? .violet,
                defaultReminder: ReminderSetting(minutesBefore: defaultReminderMinutes,
                                                 kind: ReminderKind(rawValue: defaultReminderKind) ?? .notification),
                vacation: DayString.range(vacationStart, vacationEnd))
    }
}

struct ProfilePatch: Encodable {
    var displayName: String
    var locale: String
    var theme: String
    var accent: String
    var defaultReminderMinutes: Int
    var defaultReminderKind: String

    init(_ p: Profile) {
        (displayName, locale, theme, accent) = (p.displayName, p.language.rawValue, p.theme.rawValue, p.accent.rawValue)
        (defaultReminderMinutes, defaultReminderKind) = (p.defaultReminder.minutesBefore, p.defaultReminder.kind.rawValue)
    }
}

struct DateRangeDTO: Encodable {
    var start: String
    var end: String
    init(_ range: DayRange) { (start, end) = (DayString.format(range.start), DayString.format(range.end)) }
}

struct GroupDTO: Codable {
    var id: UUID
    var name: String
    var color: String
    var chatLink: String?
    var days: [Int]
    var startMinute: Int
    var durationMinutes: Int
    var reminderMinutes: Int
    var reminderKind: String
    var holidayStart: String?
    var holidayEnd: String?
    var version: Int?
    var deleted: Bool?

    init(_ g: StudyGroup) {
        (id, name, color, chatLink) = (g.id, g.name, g.color.rawValue, g.chatLink)
        days = g.days.map(\.rawValue).sorted()
        (startMinute, durationMinutes) = (g.startMinute, g.durationMinutes)
        (reminderMinutes, reminderKind) = (g.reminder.minutesBefore, g.reminder.kind.rawValue)
        holidayStart = g.holiday.map { DayString.format($0.start) }
        holidayEnd = g.holiday.map { DayString.format($0.end) }
        version = g.version
    }

    var group: StudyGroup {
        StudyGroup(id: id, name: name, color: GroupColor(rawValue: color) ?? .blue, chatLink: chatLink,
                   days: Set(days.compactMap(Weekday.init(rawValue:))), startMinute: startMinute,
                   durationMinutes: durationMinutes,
                   reminder: ReminderSetting(minutesBefore: reminderMinutes, kind: ReminderKind(rawValue: reminderKind) ?? .notification),
                   holiday: DayString.range(holidayStart, holidayEnd), version: version ?? 0)
    }
}

struct SyncResponse: Decodable {
    var cursor: Int64
    var profile: ProfileDTO?
    var groups: [GroupDTO]
}

/// Sunucu "current" alanında çakışan kaydın güncel halini döner.
struct ConflictBody: Decodable {
    var title: String?
    var current: GroupDTO?
}

/// Sunucuyla gün alışverişi: "2026-11-24" (saat dilimsiz).
enum DayString {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func format(_ date: Date) -> String { formatter.string(from: date) }
    static func parse(_ text: String?) -> Date? { text.flatMap(formatter.date(from:)) }
    static func range(_ start: String?, _ end: String?) -> DayRange? {
        guard let s = parse(start), let e = parse(end) else { return nil }
        return DayRange(start: s, end: e)
    }
}

extension JSONEncoder { static let api = JSONEncoder() }
extension JSONDecoder { static let api = JSONDecoder() }
