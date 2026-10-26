"""Excel'in kendi kaydettiğine benzer (shared strings, gerçek saat/tarih hücreleri) test dosyası üretir.
Kullanım: python3 Tests/make_openpyxl_sample.py <çıktı.xlsx>  (openpyxl gerekir)
"""
import datetime
import sys

from openpyxl import Workbook

wb = Workbook()
info = wb.active
info.title = "Açıklama"
info["A1"] = "Bu sayfa bilgi sayfası, atlanmalı"

ws = wb.create_sheet("Haftalık Program")
ws.append(["Kardeşimin programı"])  # başlık üstünde serbest satır
ws.append([])
ws.append(["Sınıf", "GÜN", "Başlangıç Saati", "Bitiş Saati", "Derslik", "Not"])
ws.append(["Matematik", "Pazartesi", datetime.time(8, 30), datetime.time(9, 10), "201", "Ayşe Hn."])
ws.append(["Kimya", "pzt, çrş", "10:00", "10:40", None, None])
ws.append(["Edebiyat", "Salı-Perşembe", "11:00-11:40", None, "Kütüphane", None])
ws.append(["Resim", "Cuma", datetime.datetime(2026, 1, 1, 13, 0), None, None, None])
ws.append([None, None, None, None, None, None])
ws.append(["Hatalı saat", "Cuma", "öğlen", None, None, None])
ws.append(["Hatalı gün", "Bayram", "09:00", None, None, None])
wb.save(sys.argv[1])
