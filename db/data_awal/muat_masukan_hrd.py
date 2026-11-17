"""Mengubah masukan HRD simulasi (sakit, izin, cuti, tukar shift, absen manual, perintah lembur) menjadi perintah HRD.

Keputusan pemilik 13 Nov 2026 (paket Tahap 3, pilihan 1a): perintah dari file masukan simulasi ikut
diproses, dengan asal 'file' (PRD bagian 9: perubahan banyak orang sekaligus memakai file). Tahap 7
menambah pembaca chat; efek perintahnya sudah dibangun dan diuji di Tahap 3.

Berhenti, karyawan baru, dan mutasi regu tidak dimuat lagi di sini: ketiganya sudah masuk data induk
lewat muat_karyawan.py (status_kerja, karyawan, penugasan_regu).

Membaca file data (bukan kode) dari data/simulasi/<pabrik>/masukan_hrd/, jadi tidak melanggar
larangan berbagi kode dengan generator.
Pemakaian: python3 db/data_awal/muat_masukan_hrd.py A | psql ...
"""
import csv
import glob
import gzip
import os
import sys

AKAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "simulasi")
DIMUAT = {"sakit", "izin", "cuti", "tukar_shift", "absen_manual", "perintah_lembur"}
# Nama jenis di file simulasi yang berbeda dengan nama perintah di sistem. Perintah lembur Pabrik B
# (pengaturan "wajib perintah") menjadi persetujuan lembur untuk satu orang satu tanggal; nilai menit
# disimpan, tetapi aturan hitung belum memakainya (seluruh lembur hari itu dibayar).
GANTI_JENIS = {"perintah_lembur": "setujui_lembur"}


def nilai(v):
    if v is None or v == "":
        return r"\N"
    s = str(v)
    for asal, ganti in (("\\", "\\\\"), ("\t", "\\t"), ("\n", "\\n"), ("\r", "\\r")):
        s = s.replace(asal, ganti)
    return s


def main(pabrik):
    baris = []
    for jalur in sorted(glob.glob(os.path.join(AKAR, pabrik, "masukan_hrd", "*.csv.gz"))):
        with gzip.open(jalur, "rt", encoding="utf-8", newline="") as f:
            for m in csv.DictReader(f):
                if m["jenis"] not in DIMUAT:
                    continue
                divisi = None
                isi = m["nilai"] or None
                if m["jenis"] == "absen_manual":
                    # Absen manual satu divisi: nilai berisi kode divisi.
                    divisi, isi = m["nilai"], None
                baris.append((f"{m['tanggal_kirim']} 13:00:00+07", "file", GANTI_JENIS.get(m["jenis"], m["jenis"]), m["id_karyawan"] or None, divisi,
                              m["tanggal_mulai"], m["tanggal_selesai"] or None, isi, m["catatan"] or None))
    out = ["begin;", "set local app.pengguna = 'masukan-hrd-simulasi';",
           "copy fakta.perintah_hrd (dibuat, asal, jenis, id_karyawan, divisi, tanggal_mulai, tanggal_selesai, nilai, alasan) from stdin;"]
    out += ["\t".join(nilai(v) for v in b) for b in baris]
    out += ["\\.", "commit;"]
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "A")
