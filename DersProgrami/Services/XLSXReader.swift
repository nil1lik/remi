import Compression
import Foundation

/// Harici kütüphane kullanmadan .xlsx okur: zip arşivini açar, ilk (ya da istenen)
/// sayfanın hücrelerini metin olarak döndürür. Sayısal hücreler ham değerleriyle
/// gelir (ör. 09:00 → "0.375"); yorumlamayı `ScheduleImporter` yapar.
struct XLSXReader {
    struct Sheet {
        var name: String
        /// Satır → sütun dizini; boş hücreler "" olur.
        var rows: [[String]]
    }

    enum ReadError: LocalizedError {
        case notAnArchive
        case missingPart(String)
        case unsupportedCompression
        case corrupt

        var errorDescription: String? {
            switch self {
            case .notAnArchive: "Dosya bir Excel (.xlsx) dosyası değil."
            case .missingPart(let name): "Excel dosyasında beklenen bölüm yok: \(name)"
            case .unsupportedCompression: "Excel dosyası desteklenmeyen bir biçimde sıkıştırılmış."
            case .corrupt: "Excel dosyası okunamadı, bozuk olabilir."
            }
        }
    }

    private let archive: ZipArchive
    /// Excel'in 1904 tarih sistemi (eski Mac dosyaları).
    let uses1904Dates: Bool
    let sheetNames: [String]
    private let sheetPaths: [String]

    init(data: Data) throws {
        archive = try ZipArchive(data: data)

        let workbookXML = try archive.entry("xl/workbook.xml")
        let workbook = WorkbookParser.parse(workbookXML)
        uses1904Dates = workbook.date1904

        var targets: [String: String] = [:]
        if let rels = try? archive.entry("xl/_rels/workbook.xml.rels") {
            targets = RelationshipsParser.parse(rels)
        }
        var names: [String] = []
        var paths: [String] = []
        for (index, sheet) in workbook.sheets.enumerated() {
            let target = targets[sheet.relationshipID] ?? "worksheets/sheet\(index + 1).xml"
            names.append(sheet.name)
            paths.append(target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target)
        }
        if paths.isEmpty, archive.contains("xl/worksheets/sheet1.xml") {
            names = ["Sayfa1"]
            paths = ["xl/worksheets/sheet1.xml"]
        }
        sheetNames = names
        sheetPaths = paths
    }

    func sheet(at index: Int) throws -> Sheet {
        guard sheetPaths.indices.contains(index) else { throw ReadError.missingPart("sayfa \(index + 1)") }
        let sharedStrings = (try? archive.entry("xl/sharedStrings.xml")).map(SharedStringsParser.parse) ?? []
        let rows = SheetParser.parse(try archive.entry(sheetPaths[index]), sharedStrings: sharedStrings)
        return Sheet(name: sheetNames[index], rows: rows)
    }
}

// MARK: - Zip

private struct ZipArchive {
    private struct Entry {
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private let data: Data
    private var entries: [String: Entry] = [:]

    init(data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        guard bytes.count >= 22, bytes.starts(with: [0x50, 0x4B]) else { throw XLSXReader.ReadError.notAnArchive }

        // Merkez dizin sonu kaydını sondan geriye doğru ara.
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 22 - 65_535) {
            if bytes.u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw XLSXReader.ReadError.corrupt }

        let count = Int(bytes.u16(eocd + 10))
        var offset = Int(bytes.u32(eocd + 16))
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, bytes.u32(offset) == 0x0201_4B50 else { throw XLSXReader.ReadError.corrupt }
            let nameLength = Int(bytes.u16(offset + 28))
            let extraLength = Int(bytes.u16(offset + 30))
            let commentLength = Int(bytes.u16(offset + 32))
            guard offset + 46 + nameLength <= bytes.count else { throw XLSXReader.ReadError.corrupt }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries[name] = Entry(
                method: bytes.u16(offset + 10),
                compressedSize: Int(bytes.u32(offset + 20)),
                uncompressedSize: Int(bytes.u32(offset + 24)),
                localHeaderOffset: Int(bytes.u32(offset + 42))
            )
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    func entry(_ name: String) throws -> Data {
        guard let entry = entries[name] else { throw XLSXReader.ReadError.missingPart(name) }
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count else { throw XLSXReader.ReadError.corrupt }
        let nameLength = Int(data.u16(header + 26))
        let extraLength = Int(data.u16(header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw XLSXReader.ReadError.corrupt }
        let compressed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw XLSXReader.ReadError.unsupportedCompression
        }
    }

    /// Ham DEFLATE akışını açar (Apple'ın `COMPRESSION_ZLIB` algoritması başlıksız deflate'tir).
    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw XLSXReader.ReadError.corrupt }
        return output
    }
}

private extension [UInt8] {
    func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}

private extension Data {
    func u16(_ i: Int) -> UInt16 {
        UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8
    }
}

// MARK: - XML bölümleri

private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct SheetRef { var name: String; var relationshipID: String }
    private(set) var sheets: [SheetRef] = []
    private(set) var date1904 = false

    static func parse(_ data: Data) -> WorkbookParser {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name.localName {
        case "sheet":
            let rid = attributes.first { $0.key.localName == "id" }?.value ?? ""
            sheets.append(SheetRef(name: attributes["name"] ?? "", relationshipID: rid))
        case "workbookPr":
            date1904 = ["1", "true"].contains(attributes["date1904"] ?? "")
        default:
            break
        }
    }
}

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name.localName == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
            targets[id] = target
        }
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inText = false
    private var inPhonetic = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name.localName {
        case "si": current = ""
        case "t": inText = true
        case "rPh": inPhonetic = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText, !inPhonetic { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name.localName {
        case "si": strings.append(current)
        case "t": inText = false
        case "rPh": inPhonetic = false
        default: break
        }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [Int: [Int: String]] = [:]
    private var rowIndex = 0
    private var columnIndex = 0
    private var cellType = ""
    private var value = ""
    private var capturing = false

    private init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = SheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let lastRow = delegate.rows.keys.max() else { return [] }
        return (0...lastRow).map { r in
            let cells = delegate.rows[r] ?? [:]
            guard let lastColumn = cells.keys.max() else { return [] }
            return (0...lastColumn).map { cells[$0] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name.localName {
        case "row":
            if let r = attributes["r"].flatMap(Int.init) { rowIndex = r - 1 }
            columnIndex = 0
        case "c":
            if let reference = attributes["r"] {
                let parsed = Self.cellPosition(reference)
                columnIndex = parsed.column
                if let row = parsed.row { rowIndex = row }
            }
            cellType = attributes["t"] ?? ""
            value = ""
        case "v", "t":
            capturing = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name.localName {
        case "v", "t":
            capturing = false
        case "c":
            var text = value
            if cellType == "s", let index = Int(value.trimmingCharacters(in: .whitespaces)) {
                text = sharedStrings.indices.contains(index) ? sharedStrings[index] : ""
            }
            if !text.isEmpty { rows[rowIndex, default: [:]][columnIndex] = text }
            columnIndex += 1
        case "row":
            rowIndex += 1
        default:
            break
        }
    }

    /// "AB12" → (sütun 27, satır 11), sıfırdan başlayan dizinlerle.
    private static func cellPosition(_ reference: String) -> (column: Int, row: Int?) {
        var column = 0
        var digits = ""
        for scalar in reference.unicodeScalars {
            if ("A"..."Z").contains(scalar) {
                column = column * 26 + Int(scalar.value - 64)
            } else if ("a"..."z").contains(scalar) {
                column = column * 26 + Int(scalar.value - 96)
            } else {
                digits.unicodeScalars.append(scalar)
            }
        }
        return (max(column - 1, 0), Int(digits).map { $0 - 1 })
    }
}

private extension String {
    /// "x:sheet" → "sheet"
    var localName: Substring {
        guard let colon = lastIndex(of: ":") else { return self[...] }
        return self[index(after: colon)...]
    }
}
