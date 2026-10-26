#!/usr/bin/env python3
"""Uygulamanın içindeki örnek Excel şablonunu üretir.

Kullanım: python3 tools/make_template.py
Çıktı: DersProgrami/Resources/Ders-Programi-Sablon.xlsx
"""
import os
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "DersProgrami", "Resources", "Ders-Programi-Sablon.xlsx")

HEADERS = ["Grup / Sınıf", "Günler", "Saat", "Yer", "Not", "Tarih (tek seferlik)"]
WIDTHS = [22, 22, 16, 18, 28, 20]

# (grup, günler, saat, yer, not, tarih)
SAMPLE = [
    ("A1-20 sınıfı", "Perşembe Cmt", "09.00-10.00", "Salon 2", "", ""),
    ("A2-14", "Pazartesi, Çarşamba", "17.30-19.00", "Online", "Zoom linki grupta", ""),
    ("B1-07", "Salı Perşembe", "18.00-19.30", "Salon 1", "", ""),
    ("Özel ders · Elif", "Cuma", "16.00-17.00", "", "Konu tekrarı", ""),
    ("Seviye sınavı", "", "10.00-11.30", "Salon 1", "Kağıtları yazdır", "07.11.2026"),
]

GUIDE = [
    ("Ders programı nasıl doldurulur?", 4),
    ("", 0),
    ("1. \"Ders Programı\" sayfasındaki örnek satırları silip kendi gruplarını yaz. Başlık satırını silme.", 3),
    ("2. Grup / Sınıf: grubun adı (A1-20 sınıfı, B1-07, Özel ders · Elif…). Zorunlu.", 3),
    ("3. Günler: Perşembe Cmt, Pazartesi, Çarşamba ya da Pazartesi-Cuma gibi yazabilirsin.", 3),
    ("   Pzt, Sal, Çar, Per, Cum, Cmt, Paz kısaltmaları da olur. Her gün o haftanın aynı saatinde tekrarlanır.", 3),
    ("4. Saat: 09.00-10.00 gibi başlangıç ve bitişi birlikte yaz. Yalnız 09.00 da olur.", 3),
    ("   Aynı grubun günlere göre saati değişiyorsa her saat için ayrı satır aç.", 3),
    ("5. Yer ve Not isteğe bağlı; uygulamada grubun altında görünür.", 3),
    ("6. Tarih (tek seferlik): yalnız bir kere olacak şeyler için (sınav, telafi dersi). 07.11.2026 gibi yaz,", 3),
    ("   o satırda Günler'i boş bırak. Tarihi boş olan satırlar her hafta tekrarlanır.", 3),
    ("", 0),
    ("Bitirince dosyayı kaydet, uygulamada Ayarlar → \"Excel'den içe aktar\" ile seç.", 3),
    ("Ya da Dosyalar / WhatsApp / Mail'de dosyaya uzun bas → Paylaş → Ders Programı.", 3),
    ("Yeni içe aktarma eski programın yerine geçer.", 3),
]


def col(i):
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i]


def date_serial(dmy):
    import datetime
    d, m, y = (int(x) for x in dmy.split("."))
    return (datetime.date(y, m, d) - datetime.date(1899, 12, 30)).days


def text_cell(ref, text, style=0):
    s = f' s="{style}"' if style else ""
    return f'<c r="{ref}" t="inlineStr"{s}><is><t xml:space="preserve">{escape(text)}</t></is></c>'


def num_cell(ref, value, style):
    return f'<c r="{ref}" s="{style}"><v>{value}</v></c>'


def schedule_sheet():
    rows = []
    cells = "".join(text_cell(f"{col(i)}1", h, 1) for i, h in enumerate(HEADERS))
    rows.append(f'<row r="1" ht="24" customHeight="1">{cells}</row>')
    for r, (group, days, hours, place, note, date) in enumerate(SAMPLE, start=2):
        cells = [text_cell(f"A{r}", group)]
        if days:
            cells.append(text_cell(f"B{r}", days))
        cells.append(text_cell(f"C{r}", hours, 2))
        if place:
            cells.append(text_cell(f"D{r}", place))
        if note:
            cells.append(text_cell(f"E{r}", note))
        if date:
            cells.append(num_cell(f"F{r}", date_serial(date), 5))
        rows.append(f'<row r="{r}">{"".join(cells)}</row>')

    cols = "".join(
        # Saat sütunu metin biçiminde: Excel "09.00-10.00"ı tarihe çevirmesin.
        '<col min="%d" max="%d" width="%d" customWidth="1"%s/>' % (i + 1, i + 1, w, ' style="2"' if i == 2 else "")
        for i, w in enumerate(WIDTHS)
    )
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetViews><sheetView workbookViewId="0" tabSelected="1"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="18" customHeight="1"/>
<cols>{cols}</cols>
<sheetData>{"".join(rows)}</sheetData>
<autoFilter ref="A1:F1"/>
<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>
</worksheet>"""


def guide_sheet():
    rows = []
    for r, (text, style) in enumerate(GUIDE, start=1):
        cells = text_cell(f"A{r}", text, style) if text else ""
        height = ' ht="28" customHeight="1"' if style == 4 else ""
        rows.append(f'<row r="{r}"{height}>{cells}</row>')
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews>
<cols><col min="1" max="1" width="110" customWidth="1"/></cols>
<sheetData>{"".join(rows)}</sheetData>
</worksheet>"""


STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="hh:mm"/><numFmt numFmtId="165" formatCode="dd.mm.yyyy"/></numFmts>
<fonts count="4">
<font><sz val="12"/><name val="Calibri"/><family val="2"/></font>
<font><b/><sz val="12"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>
<font><b/><sz val="16"/><color rgb="FF4F46E5"/><name val="Calibri"/><family val="2"/></font>
<font><sz val="12"/><color rgb="FF374151"/><name val="Calibri"/><family val="2"/></font>
</fonts>
<fills count="3">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF6366F1"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="6">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="center"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>"""

WORKBOOK = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<workbookPr/>
<bookViews><workbookView activeTab="0"/></bookViews>
<sheets>
<sheet name="Ders Programı" sheetId="1" r:id="rId1"/>
<sheet name="Nasıl doldurulur" sheetId="2" r:id="rId2"/>
</sheets>
<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'Ders Programı'!$A$1:$F$1</definedName></definedNames>
</workbook>"""

WORKBOOK_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>"""


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CONTENT_TYPES)
        z.writestr("_rels/.rels", ROOT_RELS)
        z.writestr("xl/workbook.xml", WORKBOOK)
        z.writestr("xl/_rels/workbook.xml.rels", WORKBOOK_RELS)
        z.writestr("xl/styles.xml", STYLES)
        z.writestr("xl/worksheets/sheet1.xml", schedule_sheet())
        z.writestr("xl/worksheets/sheet2.xml", guide_sheet())
    print(OUT)


if __name__ == "__main__":
    main()
