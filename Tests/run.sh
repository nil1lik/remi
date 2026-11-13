#!/bin/bash
# Remi çekirdek testleri: Swift (Xcode projesi olmadan) + Excel dosyasının openpyxl ile okunması.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="${TMPDIR:-/tmp}/remi-tests"
mkdir -p "$WORK"
swiftc -O -o "$WORK/core" Remi/Core/*.swift Remi/Services/ScheduleExport.swift Remi/Services/ZipWriter.swift Tests/CoreTests/main.swift
"$WORK/core" "$WORK/program.xlsx"
"${PYTHON:-python3}" - "$WORK/program.xlsx" <<'PY'
import sys, openpyxl
ws = openpyxl.load_workbook(sys.argv[1]).active
rows = list(ws.iter_rows(values_only=True))
assert rows[0] == ("Gün", "Saat", "Grup", "Bağlantı", "Not"), rows[0]
assert rows[1][0] == "Perşembe" and rows[1][2] == "A1-20", rows[1]
assert any(r[2] == "B1-07" and r[4] for r in rows[1:]), "tatil notu"
assert ws["A1"].font.b, "başlık kalın"
print(f"✓ Excel geçerli: {len(rows) - 1} satır, openpyxl ile açıldı")
PY
