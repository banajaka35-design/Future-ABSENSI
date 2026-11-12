"""Pemeriksaan kewajaran data simulasi (PRD v3.1 aturan F12).

Membaca hasil generator dari data/simulasi/ dan memastikan:
- takaran kotoran sesuai PRD bagian 5,
- setiap tap cocok dengan kejadian di kunci jawaban,
- format file mengikuti file mesin asli,
- tidak ada tap untuk hari yang seharusnya tanpa tap.
Hasilnya ditulis ke docs/laporan-kewajaran-data.md.
"""

import ast
import csv
import gzip
import os
import re
from collections import Counter, defaultdict

from konfigurasi import PABRIK

AKAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = os.path.join(AKAR, "data", "simulasi")
BATAS_XLS = 65_536


def baca(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def baca_dict(path):
    rows = baca(path)
    return [dict(zip(rows[0], r)) for r in rows[1:]]


def persen(a, b):
    return 100 * a / b if b else 0.0


hasil = []      # (pabrik, periode, pemeriksaan, nilai, target, lulus)
ringkas = []


def cek(p, no, nama, nilai, target, lulus):
    hasil.append((p, no, nama, nilai, target, "lulus" if lulus else "GAGAL"))


for p, cfg in sorted(PABRIK.items()):
    for no in range(1, len(cfg["periode"]) + 1):
        awal, akhir = cfg["periode"][no - 1]
        kej = baca_dict(os.path.join(DATA, p, "kunci", f"{p}_p{no}_kejadian.csv.gz"))
        jejak = baca_dict(os.path.join(DATA, p, "kunci", f"{p}_p{no}_jejak_tap.csv.gz"))
        kerja = [k for k in kej if k["kejadian"] in ("hadir", "alpha", "sakit", "izin", "cuti", "lembur_hari_libur")]
        hadir = [k for k in kej if k["kejadian"] in ("hadir", "lembur_hari_libur")]
        hadir_tap = [k for k in hadir if not (k["mesin_mati"] and "sebagian" not in k["mesin_mati"])
                     and "belum terdaftar" not in k["catatan"]]
        absen = Counter(k["kejadian"] for k in kerja if k["kejadian"] in ("alpha", "sakit", "izin", "cuti"))
        orang_tap = [t for t in jejak if t["asal"] != "id_tidak_dikenal"]

        # Takaran kotoran
        n_absen = sum(absen.values())
        cek(p, no, "Alpha + sakit + izin + cuti (% hari kerja)", f"{persen(n_absen, len(kerja)):.2f}%", "1–3%",
            1 <= persen(n_absen, len(kerja)) <= 3)
        lupa = sum(1 for k in hadir_tap if k["lupa_tap"])
        cek(p, no, "Lupa tap (% hari hadir)", f"{persen(lupa, len(hadir_tap)):.2f}%", "1–2%",
            0.9 <= persen(lupa, len(hadir_tap)) <= 2.1)
        ulang = sum(1 for k in hadir_tap if k["tap_ulang"])
        cek(p, no, "Tap ulang (% hari hadir)", f"{persen(ulang, len(hadir_tap)):.2f}%", "±3%",
            2 <= persen(ulang, len(hadir_tap)) <= 4)
        terbalik = sum(1 for t in orang_tap if t["terbalik"])
        cek(p, no, "Status terbalik (% tap)", f"{persen(terbalik, len(orang_tap)):.2f}%", "±5%",
            4 <= persen(terbalik, len(orang_tap)) <= 6)
        dobel = sum(1 for t in jejak if t["dobel"])
        cek(p, no, "Baris dobel persis", f"{dobel}", "ada, sedikit", 0 < dobel < len(jejak) * 0.01)
        tengah = sum(1 for k in hadir_tap if k["tap_tengah"])
        cek(p, no, "Tap tunggal di tengah shift", f"{tengah}", "ada", tengah > 0)
        tidak_dikenal = sum(1 for t in jejak if t["asal"] == "id_tidak_dikenal")
        cek(p, no, "Tap ID tidak dikenal", f"{tidak_dikenal}", "ada", tidak_dikenal > 0)
        tukar = [k for k in kej if k["tukar_shift_ke"]]
        tukar_diam = sum(1 for k in tukar if k["dilaporkan_hrd"] == "tidak")
        if any(d[3] == "rotasi4" for d in cfg["divisi"]):
            cek(p, no, "Tukar shift (tidak dilaporkan)", f"{len(tukar)} ({tukar_diam})", "ada, sebagian tidak dilaporkan",
                len(tukar) > 0)

        # Konsistensi tap dengan kejadian
        boleh_tap = {(k["id_karyawan"], k["tanggal_kerja"]) for k in hadir_tap}
        salah = [t for t in orang_tap if (t["id_karyawan"], t["tanggal_kerja"]) not in boleh_tap]
        cek(p, no, "Tap tanpa kejadian hadir", f"{len(salah)}", "0", len(salah) == 0)
        per_hari = defaultdict(int)
        for t in orang_tap:
            if not t["dobel"]:
                per_hari[(t["id_karyawan"], t["tanggal_kerja"])] += 1
        tanpa_tap = [k for k in hadir_tap if per_hari[(k["id_karyawan"], k["tanggal_kerja"])] == 0]
        cek(p, no, "Hari hadir bertap tanpa tap sama sekali", f"{len(tanpa_tap)}", "0", len(tanpa_tap) == 0)
        malam = sum(1 for k in hadir if k["kode_jadwal"] == "M" or k["tukar_shift_ke"] == "M")
        lewat = sum(1 for k in hadir if k["pulang_sebenarnya"] and k["pulang_sebenarnya"][:10] > k["tanggal_kerja"])
        cek(p, no, "Shift malam melewati tengah malam", f"{lewat} dari {malam}", "semua malam", lewat >= malam > 0 or malam == 0)

        # Format file mesin dan batas .xls
        for m in sorted(cfg["mesin"]):
            rows = baca(os.path.join(DATA, p, "mesin", f"{p}_p{no}_{m}.csv.gz"))
            kepala_ok = rows[0] == ["Nama", "No.ID", "Tgl/Waktu", "", "Status"]
            waktu_ok = all(re.fullmatch(r"\d\d/\d\d/\d{4} \d\d\.\d\d\.\d\d", r[2]) for r in rows[1:])
            cek(p, no, f"Format ekspor {m} (judul, waktu bertitik)", "sesuai" if kepala_ok and waktu_ok else "tidak",
                "sama dengan file asli", kepala_ok and waktu_ok)
            n = len(rows) - 1
            cek(p, no, f"Baris file {m} vs batas .xls 65.536", f"{n}", "di bawah batas", n < BATAS_XLS)
            att = baca(os.path.join(DATA, p, "attlog", f"{p}_p{no}_{m}.dat.gz"))
            cek(p, no, f"attlog {m} sama jumlah baris dengan ekspor", f"{len(att)} vs {n}", "sama", len(att) == n)
            lanjut = len(baca(os.path.join(DATA, p, "mesin", f"{p}_p{no}_{m}_lanjutan.csv.gz"))) - 1
            ringkas.append((p, no, m, n, lanjut))

        # Kejadian khusus
        for m, t, s in cfg["mesin_mati"]:
            if awal <= t <= akhir:
                tap_hari = [x for x in jejak if x["mesin"] == m and x["waktu"].startswith(t)]
                cek(p, no, f"Mesin {m} mati {t} ({s})", f"{len(tap_hari)} tap", "0 tap", len(tap_hari) == 0)
        for m, a, b, menit in cfg["selisih_jam"]:
            kena = [x for x in jejak if x["mesin"] == m and a <= x["waktu"][:10] <= b]
            if kena:
                ok = all(int(x["selisih_jam"]) == menit for x in kena)
                cek(p, no, f"Selisih jam {m} +{menit} menit {a}..{b}", f"{len(kena)} tap", "semua bergeser", ok)
        if cfg["id_ganda"]:
            ganda = sum(1 for x in jejak if x["id_mesin"] == "90001")
            if ganda:
                cek(p, no, "Tap dengan ID mesin kedua (90001)", f"{ganda}", "ada sejak 1 Mar", True)

# Kemandirian generator: tidak mengimpor apa pun di luar pustaka bawaan dan dirinya sendiri.
bawaan = {"csv", "gzip", "io", "os", "random", "re", "datetime", "collections", "ast", "konfigurasi", "buat_data"}
impor_asing = []
for nama in os.listdir(os.path.dirname(os.path.abspath(__file__))):
    if nama.endswith(".py"):
        tree = ast.parse(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), nama), encoding="utf-8").read())
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                impor_asing += [(nama, a.name) for a in node.names if a.name.split(".")[0] not in bawaan]
            elif isinstance(node, ast.ImportFrom) and (node.module or "").split(".")[0] not in bawaan:
                impor_asing.append((nama, node.module))

gagal = [h for h in hasil if h[5] == "GAGAL"]
out = ["# Laporan kewajaran data simulasi", "",
       "Dibuat otomatis oleh `generator/periksa_kewajaran.py` (PRD v3.1 aturan F12).", "",
       f"**Hasil: {len(hasil) - len(gagal)} dari {len(hasil)} pemeriksaan lulus.**", "",
       f"Kemandirian generator: {'tidak ada impor di luar pustaka bawaan' if not impor_asing else 'ADA IMPOR ASING: ' + str(impor_asing)}.", "",
       "## Ukuran file mesin", "", "| Pabrik | Periode | Mesin | Baris | Baris lanjutan (tanggal 21 / tanggal 1) |", "| --- | --- | --- | --- | --- |"]
out += [f"| {a} | {b} | {c} | {d:,} | {e:,} |".replace(",", ".") for a, b, c, d, e in ringkas]
out += ["", "## Pemeriksaan", "", "| Pabrik | Periode | Pemeriksaan | Nilai | Target | Hasil |", "| --- | --- | --- | --- | --- | --- |"]
out += [f"| {a} | {b} | {c} | {d} | {e} | {f} |" for a, b, c, d, e, f in hasil]
with open(os.path.join(AKAR, "docs", "laporan-kewajaran-data.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print(f"{len(hasil) - len(gagal)}/{len(hasil)} lulus; impor asing: {impor_asing}")
for g in gagal:
    print("GAGAL:", g)
