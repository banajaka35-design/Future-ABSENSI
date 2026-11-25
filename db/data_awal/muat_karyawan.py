"""Mengubah data induk karyawan simulasi menjadi SQL untuk dimuat ke gudang data.

Membaca file data (bukan kode) dari data/simulasi/<pabrik>/induk/, jadi tidak
melanggar larangan berbagi kode dengan generator.

Data dikirim dengan COPY (satu perintah per tabel), bukan satu INSERT per baris:
lewat jaringan ke Supabase, tiap perintah adalah satu perjalanan bolak-balik
(terukur 0,25 detik), sehingga 5.277 INSERT memakan 22 menit. Isi tabel hasilnya
sama persis dengan cara lama, dan semuanya tetap dalam satu transaksi.
Pemakaian: python3 db/data_awal/muat_karyawan.py A | psql ...
          python3 db/data_awal/muat_karyawan.py <folder> | psql ...   (paket 9d: data PT dari templat
          docs/pasang/templat/; folder berisi karyawan.csv, pemetaan_id_mesin.csv, dan boleh mutasi_regu.csv)
"""
import csv
import os
import sys

AKAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "simulasi")


def nilai(v):
    """Satu nilai dalam format teks COPY: kosong menjadi NULL, karakter khusus di-escape."""
    if v is None or v == "":
        return r"\N"
    s = str(v)
    for asal, ganti in (("\\", "\\\\"), ("\t", "\\t"), ("\n", "\\n"), ("\r", "\\r")):
        s = s.replace(asal, ganti)
    return s


def folder(pabrik):
    """"A"/"B" = data simulasi; selain itu nama folder data perusahaan (paket 9d)."""
    return os.path.join(AKAR, pabrik, "induk") if pabrik in ("A", "B") else pabrik


def baca(pabrik, nama, wajib=True):
    jalur = os.path.join(folder(pabrik), nama)
    if not wajib and not os.path.exists(jalur):
        return []
    # utf-8-sig: CSV yang disimpan Excel diawali tanda BOM; tanpa ini kolom pertama terbaca "\ufeffid".
    with open(jalur, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def copy(out, tabel, kolom, baris):
    out.append(f"copy {tabel} ({', '.join(kolom)}) from stdin;")
    for b in baris:
        out.append("\t".join(nilai(v) for v in b))
    out.append("\\.")


def main(pabrik):
    karyawan = baca(pabrik, "karyawan.csv")
    pemetaan = baca(pabrik, "pemetaan_id_mesin.csv")
    mutasi = {}
    for m in baca(pabrik, "mutasi_regu.csv", wajib=False):
        mutasi.setdefault(m["id_karyawan"], []).append((m["berlaku_dari"], m["regu_baru"]))

    induk, riwayat, status, regu = [], [], [], []
    for k in karyawan:
        kid = k["id"]
        induk.append((kid, k["nama"]))
        riwayat.append((kid, k["mulai"], k["divisi"], k["tipe_upah"], int(k["gaji_pokok"]),
                        int(k["tunjangan_tetap"]), k["ptkp"], k["cara_bayar"],
                        "true" if k["wajib_tap"] == "ya" else "false",
                        "true" if k["gaji_rahasia"] == "ya" else "false"))
        status.append((kid, "mulai", k["mulai"]))
        if k["berhenti"]:
            status.append((kid, "berhenti", k["berhenti"]))
        # Penugasan regu: rentang setengah terbuka, ditulis langsung tanpa mengubah baris.
        titik = [(k["mulai"], k["regu"])] + sorted(mutasi.get(kid, []))
        for i, (dari, r) in enumerate(titik):
            sampai = titik[i + 1][0] if i + 1 < len(titik) else None
            regu.append((kid, int(r), dari, sampai))

    out = ["begin;", "set local app.pengguna = 'data-awal';"]
    copy(out, "induk.karyawan", ["id", "nama"], induk)
    copy(out, "induk.karyawan_riwayat",
         ["id_karyawan", "berlaku_dari", "divisi", "tipe_upah", "gaji_pokok", "tunjangan_tetap",
          "ptkp", "cara_bayar", "wajib_tap", "gaji_rahasia"], riwayat)
    copy(out, "induk.status_kerja", ["id_karyawan", "jenis", "tanggal"], status)
    copy(out, "induk.penugasan_regu", ["id_karyawan", "regu", "berlaku_dari", "berlaku_sampai"], regu)
    copy(out, "induk.pemetaan_id_mesin", ["mesin", "id_mesin", "id_karyawan", "berlaku_dari", "berlaku_sampai"],
         [(p["mesin"], p["id_mesin"], p["id_karyawan"], p["berlaku_dari"], p["berlaku_sampai"]) for p in pemetaan])
    out.append("commit;")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "A")
