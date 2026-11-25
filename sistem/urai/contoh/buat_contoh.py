"""Membuat berkas contoh untuk uji pembaca berbagai format file mesin (paket F1, docs/rencana-f1-format-file.md).

Isi semua berkas berasal dari data simulasi (karangan) di data/simulasi/A/mesin/, kecuali tiruan_asli.xls yang meniru susunan
file mesin asli pemilik (5 kolom, ID 18 angka, tap sore berstatus "C/Masuk") dengan nama dan ID karangan.
Membaca file data, bukan kode generator (larangan berbagi kode tetap terjaga).

Butuh pustaka xlwt dan openpyxl (pip install xlwt openpyxl). Hanya dipakai untuk membuat ulang berkas contoh; uji otomatis
membaca berkas yang sudah tersimpan di folder ini dan tidak butuh pustaka apa pun.
Pemakaian: python3 sistem/urai/contoh/buat_contoh.py
"""
import csv
import datetime as dt
import gzip
import io
import os

import openpyxl
import xlwt

AKAR = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.join(AKAR, "..", "..", "..", "data", "simulasi", "A", "mesin")


def baca_sim(nama):
    with gzip.open(os.path.join(SIM, nama), "rt", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def ke_datetime(teks):
    # "dd/mm/yyyy jj.mm.dd" -> datetime
    tgl, jam = teks.split(" ")
    h, b, t = (int(x) for x in tgl.split("/"))
    bag = [int(x) for x in jam.split(".")] + [0]
    return dt.datetime(t, b, h, bag[0], bag[1], bag[2])


def tulis_xls(jalur, baris, angka=False):
    wb = xlwt.Workbook(encoding="utf-8")
    ws = wb.add_sheet("Sheet1")
    gaya = xlwt.easyxf(num_format_str="dd/mm/yyyy hh:mm:ss")
    for r, isi in enumerate(baris):
        for k, v in enumerate(isi):
            if angka and r > 0 and k == 2:
                ws.write(r, k, ke_datetime(v), gaya)
            elif angka and r > 0 and k == 1:
                ws.write(r, k, int(v))
            else:
                ws.write(r, k, v)
    wb.save(jalur)


def tulis_xlsx(jalur, baris, angka=False, mac=False):
    wb = openpyxl.Workbook()
    if mac:
        wb.epoch = openpyxl.utils.datetime.CALENDAR_MAC_1904
    ws = wb.active
    for r, isi in enumerate(baris):
        for k, v in enumerate(isi):
            if v == "":
                continue
            if angka and r > 0 and k == 2:
                c = ws.cell(row=r + 1, column=k + 1, value=ke_datetime(v))
                c.number_format = "dd/mm/yyyy hh:mm:ss"
            elif angka and r > 0 and k == 1:
                ws.cell(row=r + 1, column=k + 1, value=int(v))
            else:
                ws.cell(row=r + 1, column=k + 1, value=v)
    wb.save(jalur)


def tulis_teks(jalur, baris, pemisah, kode, bom=b""):
    buf = io.StringIO()
    csv.writer(buf, delimiter=pemisah, lineterminator="\r\n").writerows(baris)
    with open(jalur, "wb") as f:
        f.write(bom + buf.getvalue().encode(kode))


def main():
    ma2 = baca_sim("A_p1_MA2.csv.gz")  # 5 kolom: Nama, No.ID, Tgl/Waktu, (tanpa judul), Status
    j = lambda n: os.path.join(AKAR, n)
    # Bentuk yang sama dengan file asli, di berbagai wadah.
    tulis_xls(j("A_p1_MA2.xls"), ma2)
    tulis_xlsx(j("A_p1_MA2.xlsx"), ma2)
    tulis_xls(j("A_p1_MA2_angka.xls"), ma2, angka=True)
    tulis_xlsx(j("A_p1_MA2_angka.xlsx"), ma2, angka=True)
    tulis_xlsx(j("A_p1_MA2_1904.xlsx"), ma2[:40], angka=True, mac=True)
    tulis_teks(j("A_p1_MA2_titikkoma.csv"), ma2, ";", "cp1252")
    tulis_teks(j("A_p1_MA2_utf16.txt"), ma2, "\t", "utf-16-le", bom=b"\xff\xfe")
    # Judul berbeda: ID "No. Pegawai", tanggal dan jam di kolom terpisah, tanpa kolom status; diawali judul laporan.
    terpisah = [["Laporan Log Absensi"], [], ["No. Pegawai", "Nama", "Tanggal", "Jam"]]
    for r in ma2[1:]:
        tgl, jam = r[2].split(" ")
        terpisah.append([r[1], r[0], tgl, jam.replace(".", ":")])
    tulis_teks(j("A_p1_MA2_terpisah.csv"), terpisah, ",", "utf-8")
    # Satu periode MA1 (+-40.000 baris) dalam .xls, dipadatkan, untuk mengukur waktu baca (batas CPU Edge Function).
    ma1 = baca_sim("A_p1_MA1.csv.gz")
    tulis_xls(j("_sementara.xls"), ma1)
    with open(j("_sementara.xls"), "rb") as f, open(j("A_p1_MA1.xls.gz"), "wb") as g:
        g.write(gzip.compress(f.read(), mtime=0))
    os.remove(j("_sementara.xls"))
    # Tiruan file asli pemilik: susunan sama persis, isi karangan.
    tiruan = [["Nama", "No.ID", "Tgl/Waktu", "", "Status"]]
    orang = [("BUDI KARANGAN", "198001012010011001"), ("SITI KARANGAN", "198502022011012002")]
    for h in range(1, 6):
        for nama, nid in orang:
            for jam, status in (("07.04.12", "C/Masuk"), ("16.08.45", "C/Masuk" if h % 2 else "C/Keluar")):
                tiruan.append([nama, nid, f"0{h}/10/2026 {jam}", f"0{h}/10/2026 {jam[:5]}", status])
    tulis_xls(j("tiruan_asli.xls"), tiruan)
    # Berkas yang harus ditolak.
    tulis_xlsx(j("tolak_rekap.xlsx"), [["No.ID", "Nama", "Tanggal", "Masuk", "Pulang"],
                                       ["10001", "BUDI", "01/10/2026", "07.04", "16.08"]])
    tulis_xlsx(j("tolak_waktu_saja.xlsx"), [["Nama", "No.ID", "Waktu", "Status"],
                                            ["BUDI", "10001", "01/10/2026 07.04.12", "C/Masuk"]])
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(["Nama", "No.ID", "Tgl/Waktu", "Status"])
    ws.append(["BUDI", 198001012010011001, "01/10/2026 07.04.12", "C/Masuk"])  # ID 18 angka sebagai angka
    wb.save(j("tolak_id_angka.xlsx"))
    tulis_teks(j("tolak_dua_id.csv"), [["Nama", "No.ID", "NIK", "Tgl/Waktu", "Status"],
                                       ["BUDI", "10001", "3201", "01/10/2026 07.04.12", "C/Masuk"]], ",", "utf-8")
    with open(j("A_p1_MA2.xls"), "rb") as f:
        isi = f.read()
    with open(j("tolak_rusak.xls"), "wb") as f:
        f.write(isi[:3000])  # terpotong


if __name__ == "__main__":
    main()
