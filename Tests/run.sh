#!/bin/sh
# Xcode gerektirmeden içe aktarma kodunu Mac'te derleyip test eder.
set -e
cd "$(dirname "$0")/.."
BUILD="${TMPDIR:-/tmp}/remi-tests"
mkdir -p "$BUILD"

python3 tools/make_template.py > /dev/null
FILES="Remi/Resources/Ders-Programi-Sablon.xlsx"
PY="${PYTHON:-python3}"
if "$PY" -c "import openpyxl" 2>/dev/null; then
    "$PY" Tests/make_openpyxl_sample.py "$BUILD/openpyxl-ornek.xlsx"
    FILES="$FILES $BUILD/openpyxl-ornek.xlsx"
fi

swiftc -O -o "$BUILD/importer-tests" \
    Remi/Models/Lesson.swift \
    Remi/Services/XLSXReader.swift \
    Remi/Services/ScheduleImporter.swift \
    Tests/main.swift
"$BUILD/importer-tests" $FILES
