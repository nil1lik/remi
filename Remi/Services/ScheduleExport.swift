import Foundation

/// Haftalık programın Excel (.xlsx) dosyası ve yazdırılabilir hali.
enum ScheduleExport {
    struct Row: Hashable {
        var day: Weekday
        var time: String
        var group: String
        var link: String
        var note: String
    }

    static func rows(groups: [StudyGroup], strings s: Strings, includeLinks: Bool, markHolidays: Bool) -> [Row] {
        Weekday.allCases.flatMap { day in
            groups.filter { $0.days.contains(day) }
                .sorted { $0.startMinute < $1.startMinute }
                .map { g in
                    Row(day: day, time: s.timeRange(g.startMinute, g.endMinute), group: g.name,
                        link: includeLinks ? (g.chatLink ?? "") : "",
                        note: markHolidays ? (g.holiday.map { s.holidayUntil($0.end) } ?? "") : "")
                }
        }
    }

    // MARK: Excel

    /// Tek sayfalık .xlsx dosyası (Office Open XML). Bağımlılık yok: zip "stored" kipinde yazılır.
    static func excelFile(rows: [Row], strings s: Strings, includeLinks: Bool, markHolidays: Bool) throws -> URL {
        var header = [s.dayColumn, s.timeColumn, s.groupColumn]
        if includeLinks { header.append(s.linkColumn) }
        if markHolidays { header.append(s.noteColumn) }

        var sheetRows = [row(1, header, style: 1)]
        for (index, r) in rows.enumerated() {
            var cells = [s.weekdayName(r.day), r.time, r.group]
            if includeLinks { cells.append(r.link) }
            if markHolidays { cells.append(r.note) }
            sheetRows.append(row(index + 2, cells, style: 0))
        }
        let widths = [14, 16, 28, 40, 26].prefix(header.count).enumerated()
            .map { "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\($0.element)\" customWidth=\"1\"/>" }.joined()
        let rtl = s.language.isRightToLeft ? " rightToLeft=\"1\"" : ""

        let files: [(String, String)] = [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(xml(String(s.program.prefix(31))))" sheetId="1" r:id="rId1"/></sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """),
            ("xl/styles.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf fontId="0" xfId="0"/><xf fontId="1" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
            """),
            ("xl/worksheets/sheet1.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"\(rtl)><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>\(widths)</cols><sheetData>\(sheetRows.joined())</sheetData></worksheet>
            """),
        ]

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(s.fileName).xlsx")
        try? FileManager.default.removeItem(at: url)
        try ZipWriter.archive(files.map { ($0.0, Data($0.1.utf8)) }).write(to: url, options: .atomic)
        return url
    }

    private static func row(_ number: Int, _ cells: [String], style: Int) -> String {
        let columns = Array("ABCDEFG")
        let xmlCells = cells.enumerated().map { index, value in
            "<c r=\"\(columns[index])\(number)\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
        }.joined()
        return "<row r=\"\(number)\">\(xmlCells)</row>"
    }

    /// XML'e özel karakterleri kaçışlar; XML'de geçersiz kontrol karakterlerini atar.
    static func xml(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" }.map(Character.init))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
