"""Percobaan Tahap 1,5: ubah file ekspor simulasi (.csv.gz) menjadi .xls seperti
keluaran aplikasi mesin, untuk mengukur ukuran file dan beban mengurainya.
Kode percobaan, boleh dibuang. Pemakaian: python3 buat_xls.py <masukan.csv.gz> <keluaran.xls>
"""
import csv
import gzip
import sys

import xlwt

masuk, keluar = sys.argv[1], sys.argv[2]
wb = xlwt.Workbook()
ws = wb.add_sheet("absen")
with gzip.open(masuk, "rt", encoding="utf-8", newline="") as f:
    for i, row in enumerate(csv.reader(f)):
        for j, v in enumerate(row):
            ws.write(i, j, v)
wb.save(keluar)
print("baris", i + 1)
