import UIKit

extension ScheduleExport {
    /// Programı sistemin yazdırma penceresiyle yazdırır (AirPrint ya da PDF).
    @MainActor
    static func print(rows: [Row], strings s: Strings, includeLinks: Bool, markHolidays: Bool) {
        let dir = s.language.isRightToLeft ? "rtl" : "ltr"
        var head = "<th>\(xml(s.dayColumn))</th><th>\(xml(s.timeColumn))</th><th>\(xml(s.groupColumn))</th>"
        if includeLinks { head += "<th>\(xml(s.linkColumn))</th>" }
        if markHolidays { head += "<th>\(xml(s.noteColumn))</th>" }
        var previous: Weekday?
        let body = rows.map { r in
            let day = r.day == previous ? "" : s.weekdayName(r.day)
            previous = r.day
            var cells = "<td class=\"d\">\(xml(day))</td><td>\(xml(r.time))</td><td>\(xml(r.group))</td>"
            if includeLinks { cells += "<td class=\"l\">\(xml(r.link))</td>" }
            if markHolidays { cells += "<td class=\"n\">\(xml(r.note))</td>" }
            return "<tr>\(cells)</tr>"
        }.joined()

        let html = """
        <html dir="\(dir)"><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,sans-serif;color:#15122E;margin:24px}
        h1{font-size:20px;margin:0 0 4px} p{color:#6A6580;font-size:11px;margin:0 0 16px}
        table{width:100%;border-collapse:collapse;font-size:12px} th{text-align:start;font-size:10px;color:#6A6580;border-bottom:1.5px solid #15122E;padding:6px 4px}
        td{border-bottom:1px solid #ECE8E1;padding:7px 4px} .d{font-weight:700} .l,.n{color:#6A6580;font-size:10px}
        </style></head><body><h1>\(xml(s.weeklySchedule))</h1><p>Remi · \(xml(s.takenOn(.now)))</p>
        <table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table></body></html>
        """

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = s.weeklySchedule
        info.outputType = .general
        controller.printInfo = info
        controller.printFormatter = UIMarkupTextPrintFormatter(markupText: html)
        controller.present(animated: true)
    }
}
