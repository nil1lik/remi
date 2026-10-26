import Foundation

/// Excel/CSV tablosunu derslere çevirir. Sütunlar başlık adlarıyla bulunur, sırası önemli değildir.
enum ScheduleImporter {
    struct Issue: Identifiable, Hashable {
        let id = UUID()
        /// Excel'deki satır numarası (1'den başlar).
        var row: Int
        var message: String
    }

    struct Result {
        var lessons: [Lesson]
        var issues: [Issue]
        var sheetName: String?
    }

    enum ImportError: LocalizedError {
        case unsupportedFile
        case headerNotFound
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                "Bu dosya türü desteklenmiyor. Lütfen Excel (.xlsx) ya da CSV dosyası seç."
            case .headerNotFound:
                "Tabloda başlık satırı bulunamadı. Şablondaki \"Grup / Sınıf\", \"Günler\" ve \"Saat\" başlıklarını silmeden doldurmalısın."
            case .empty:
                "Dosyada hiç ders bulunamadı."
            }
        }
    }

    enum Column: CaseIterable {
        case day, date, start, end, title, location, note

        var aliases: [String] {
            switch self {
            case .day: ["gun", "gunler", "day", "weekday"]
            case .date: ["tarih", "date"]
            case .start: ["saat", "saatler", "baslangic", "baslama", "baslangic saati", "start", "start time", "time", "giris"]
            case .end: ["bitis", "bitis saati", "end", "end time", "cikis"]
            case .title: ["grup", "grup adi", "sinif", "sinif adi", "ders", "ders adi", "dersin adi", "konu", "ogrenci", "group", "class", "lesson", "subject", "course"]
            case .location: ["yer", "derslik", "salon", "oda", "konum", "adres", "location", "room"]
            case .note: ["not", "notlar", "aciklama", "ogretmen", "hoca", "note", "notes", "teacher"]
            }
        }
    }

    // MARK: Giriş noktaları

    static func importFile(at url: URL) throws -> Result {
        let data = try Data(contentsOf: url)
        switch url.pathExtension.lowercased() {
        case "xlsx", "xlsm":
            return try importXLSX(data)
        case "csv", "txt", "tsv":
            return try importRows(parseCSV(String(decoding: data, as: UTF8.self)), sheetName: nil, uses1904Dates: false)
        default:
            if data.starts(with: [0x50, 0x4B]) { return try importXLSX(data) }
            throw ImportError.unsupportedFile
        }
    }

    static func importXLSX(_ data: Data) throws -> Result {
        let reader = try XLSXReader(data: data)
        // Adında "program" ya da "ders" geçen sayfayı tercih et, sonra diğerlerine bak.
        let order = reader.sheetNames.indices.sorted { a, b in
            preference(reader.sheetNames[a]) > preference(reader.sheetNames[b])
        }
        var lastError: Error = ImportError.headerNotFound
        for index in order {
            let sheet = try reader.sheet(at: index)
            do {
                return try importRows(sheet.rows, sheetName: sheet.name, uses1904Dates: reader.uses1904Dates)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func importRows(_ rows: [[String]], sheetName: String?, uses1904Dates: Bool) throws -> Result {
        guard let (headerRow, columns) = findHeader(in: rows) else { throw ImportError.headerNotFound }

        var lessons: [Lesson] = []
        var issues: [Issue] = []

        for rowIndex in rows.indices where rowIndex > headerRow {
            let row = rows[rowIndex]
            let excelRow = rowIndex + 1
            func cell(_ column: Column) -> String {
                guard let i = columns[column], row.indices.contains(i) else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let title = cell(.title)
            let dayText = cell(.day)
            let dateText = cell(.date)
            let startText = cell(.start)
            let endText = cell(.end)
            if [title, dayText, dateText, startText, endText].allSatisfy(\.isEmpty) { continue }

            guard !title.isEmpty else {
                issues.append(Issue(row: excelRow, message: "Grup adı boş, satır atlandı."))
                continue
            }

            var start: Int?
            var end: Int?
            if let range = parseTimeRange(startText) {
                (start, end) = (range.0, range.1)
            } else {
                start = parseTime(startText)
            }
            if !endText.isEmpty { end = parseTime(endText) ?? end }

            guard let start else {
                let message = startText.isEmpty
                    ? "\(title): saat boş."
                    : "\(title): saat anlaşılamadı (\"\(startText)\"). 09.00-10.00 gibi yaz."
                issues.append(Issue(row: excelRow, message: message))
                continue
            }
            if !endText.isEmpty, parseTime(endText) == nil {
                issues.append(Issue(row: excelRow, message: "\(title): bitiş saati anlaşılamadı, boş bırakıldı."))
            }
            if let e = end, e <= start { end = nil }

            let location = cell(.location).nilIfEmpty
            let note = cell(.note).nilIfEmpty

            if !dateText.isEmpty {
                guard let date = parseDate(dateText, uses1904Dates: uses1904Dates) else {
                    issues.append(Issue(row: excelRow, message: "\(title): tarih anlaşılamadı (\"\(dateText)\"). 03.11.2026 gibi yaz."))
                    continue
                }
                lessons.append(Lesson(title: title, weekday: nil, date: date, start: start, end: end,
                                      location: location, note: note))
                continue
            }

            guard let days = parseWeekdays(dayText), !days.isEmpty else {
                let message = dayText.isEmpty
                    ? "\(title): gün ya da tarih boş."
                    : "\(title): gün anlaşılamadı (\"\(dayText)\")."
                issues.append(Issue(row: excelRow, message: message))
                continue
            }
            for day in days {
                lessons.append(Lesson(title: title, weekday: day, date: nil, start: start, end: end,
                                      location: location, note: note))
            }
        }

        guard !lessons.isEmpty else {
            if issues.isEmpty { throw ImportError.empty }
            return Result(lessons: [], issues: issues, sheetName: sheetName)
        }
        return Result(lessons: lessons, issues: issues, sheetName: sheetName)
    }

    // MARK: Başlık

    static func findHeader(in rows: [[String]]) -> (Int, [Column: Int])? {
        for rowIndex in rows.indices.prefix(15) {
            var found: [Column: Int] = [:]
            for (columnIndex, raw) in rows[rowIndex].enumerated() {
                let header = normalize(raw)
                guard !header.isEmpty else { continue }
                if let column = Column.allCases.first(where: { found[$0] == nil && matches(header, $0.aliases) }) {
                    found[column] = columnIndex
                }
            }
            let hasWhen = found[.day] != nil || found[.date] != nil
            if found[.title] != nil, found[.start] != nil, hasWhen {
                return (rowIndex, found)
            }
        }
        return nil
    }

    private static func matches(_ header: String, _ aliases: [String]) -> Bool {
        aliases.contains { header == $0 || header.hasPrefix($0 + " ") || header.hasPrefix($0 + "/") || header.hasPrefix($0 + "(") }
    }

    private static func preference(_ sheetName: String) -> Int {
        let name = normalize(sheetName)
        if name.contains("program") { return 2 }
        if name.contains("ders") { return 1 }
        if name.contains("nasil") || name.contains("aciklama") || name.contains("bilgi") { return -1 }
        return 0
    }

    // MARK: Saat

    /// "09:00", "9.00", "9:00 PM", "0900", Excel saat kesri (0.375) ya da tarih+saat (45230.375).
    static func parseTime(_ text: String) -> Int? {
        var value = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty else { return nil }

        if let number = Double(value), number >= 0 {
            // Excel saati günün kesri olarak saklar; tarih+saat ise tam kısmı gün sayısıdır.
            if number < 1 || (number >= 24 && value.contains(".")) {
                let fraction = number - number.rounded(.down)
                return Int((fraction * 1440).rounded()) % 1440
            }
            if !value.contains("."), value.count == 3 || value.count == 4 {
                let whole = Int(number)
                guard whole % 100 < 60, whole / 100 < 24 else { return nil }
                return (whole / 100) * 60 + whole % 100
            }
        }

        var pm = false
        var am = false
        for suffix in ["pm", "ös", "os", "öğleden sonra"] where value.hasSuffix(suffix) {
            pm = true
            value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        for suffix in ["am", "öö", "oo"] where value.hasSuffix(suffix) {
            am = true
            value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }

        let parts = value.split(whereSeparator: { ":.,h ".contains($0) })
        guard (1...3).contains(parts.count),
              let hour = Int(parts[0]),
              parts.count == 1 || parts[1].count == 2,
              let minute = parts.count > 1 ? Int(parts[1]) : 0,
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }

        var h = hour
        if pm, h < 12 { h += 12 }
        if am, h == 12 { h = 0 }
        return h * 60 + minute
    }

    /// "09:00-09:40", "09:00 – 09:40"
    static func parseTimeRange(_ text: String) -> (Int, Int?)? {
        let parts = text.split(whereSeparator: { "-–—".contains($0) })
        guard parts.count == 2,
              let start = parseTime(String(parts[0])),
              let end = parseTime(String(parts[1]))
        else { return nil }
        return (start, end)
    }

    // MARK: Gün ve tarih

    private static let weekdayTokens: [String: Weekday] = {
        var map: [String: Weekday] = [:]
        let names: [(Weekday, [String])] = [
            (.monday, ["pazartesi", "pzt", "pts", "pt", "monday", "mon"]),
            (.tuesday, ["sali", "sal", "sl", "tuesday", "tue", "tues"]),
            (.wednesday, ["carsamba", "car", "crs", "cars", "wednesday", "wed"]),
            (.thursday, ["persembe", "per", "prs", "pers", "thursday", "thu", "thur", "thurs"]),
            (.friday, ["cuma", "cum", "cu", "friday", "fri"]),
            (.saturday, ["cumartesi", "cmt", "cts", "ctesi", "saturday", "sat"]),
            (.sunday, ["pazar", "paz", "pz", "sunday", "sun"]),
        ]
        for (day, tokens) in names {
            for token in tokens { map[token] = day }
            map[String(day.rawValue)] = day
        }
        return map
    }()

    /// "Pazartesi", "Perşembe Cmt", "Pzt, Çar", "Pazartesi - Cuma", "Salı ve Perşembe"
    static func parseWeekdays(_ text: String) -> [Weekday]? {
        let normalized = normalize(text)
            .replacingOccurrences(of: " ve ", with: ",")
            .replacingOccurrences(of: #"\s*[-–—]\s*"#, with: "-", options: .regularExpression)
        guard !normalized.isEmpty else { return nil }

        var days: [Weekday] = []
        for group in normalized.split(whereSeparator: { ",;/&+".contains($0) || $0.isWhitespace }) {
            let range = group.split(whereSeparator: { "-–—".contains($0) }).map(token)
            if range.count == 2 {
                guard let from = weekdayTokens[range[0]], let to = weekdayTokens[range[1]], from <= to else { return nil }
                days += Weekday.allCases.filter { $0 >= from && $0 <= to }
            } else if range.count == 1, let day = weekdayTokens[range[0]] {
                days.append(day)
            } else {
                return nil
            }
        }
        var seen = Set<Weekday>()
        return days.filter { seen.insert($0).inserted }
    }

    private static func token<S: StringProtocol>(_ s: S) -> String {
        s.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
    }

    /// Excel tarih seri numarası ya da "03.11.2026", "3/11/2026", "2026-11-03", "03.11.26".
    static func parseDate(_ text: String, uses1904Dates: Bool, calendar: Calendar = .schedule) -> Date? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if let serial = Double(value), serial > 59 {
            var origin = DateComponents(year: 1899, month: 12, day: 30)
            if uses1904Dates { origin = DateComponents(year: 1904, month: 1, day: 1) }
            guard let base = calendar.date(from: origin) else { return nil }
            return calendar.date(byAdding: .day, value: Int(serial.rounded(.down)), to: base)
        }

        let parts = value.split(whereSeparator: { "./- ".contains($0) }).compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        var (day, month, year) = (parts[0], parts[1], parts[2])
        if parts[0] > 31 { (year, month, day) = (parts[0], parts[1], parts[2]) }
        if year < 100 { year += 2000 }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    // MARK: CSV

    /// Excel'in Türkçe ayarlarda ürettiği ";" ayraçlı CSV'yi de okur.
    static func parseCSV(_ text: String) -> [[String]] {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let firstLine = body.prefix { $0 != "\n" && $0 != "\r" }
        let separator: Character = [";", "\t", ","].max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(body).makeIterator()
        var pending: Character? = nil

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"":
                inQuotes = true
            case separator:
                row.append(field)
                field = ""
            case "\n", "\r", "\r\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: Yardımcılar

    /// Küçük harf, Türkçe karakterler sadeleştirilmiş, tek boşluklu.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
        let map: [Character: String] = ["ç": "c", "ğ": "g", "ı": "i", "i̇": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u"]
        var result = ""
        for char in lowered {
            result += map[char] ?? String(char)
        }
        return result
            .replacingOccurrences(of: "\u{307}", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
