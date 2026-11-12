"""Mengubah data induk karyawan simulasi menjadi SQL untuk dimuat ke gudang data.

Membaca file data (bukan kode) dari data/simulasi/<pabrik>/induk/, jadi tidak
melanggar larangan berbagi kode dengan generator.
Pemakaian: python3 db/data_awal/muat_karyawan.py A > /tmp/karyawan.sql
"""
import csv
import os
import sys

AKAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "simulasi")


def q(v):
    return "null" if v is None or v == "" else "'" + str(v).replace("'", "''") + "'"


def baca(pabrik, nama):
    with open(os.path.join(AKAR, pabrik, "induk", nama), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def main(pabrik):
    karyawan = baca(pabrik, "karyawan.csv")
    pemetaan = baca(pabrik, "pemetaan_id_mesin.csv")
    mutasi = {}
    for m in baca(pabrik, "mutasi_regu.csv"):
        mutasi.setdefault(m["id_karyawan"], []).append((m["berlaku_dari"], m["regu_baru"]))

    out = ["begin;", "set local app.pengguna = 'data-awal';"]
    for k in karyawan:
        kid = k["id"]
        out.append(f"insert into induk.karyawan (id, nama) values ({q(kid)}, {q(k['nama'])});")
        out.append(
            "insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, tipe_upah, gaji_pokok, "
            "tunjangan_tetap, ptkp, cara_bayar, wajib_tap, gaji_rahasia) values "
            f"({q(kid)}, {q(k['mulai'])}, {q(k['divisi'])}, {q(k['tipe_upah'])}, {int(k['gaji_pokok'])}, "
            f"{int(k['tunjangan_tetap'])}, {q(k['ptkp'])}, {q(k['cara_bayar'])}, "
            f"{'true' if k['wajib_tap'] == 'ya' else 'false'}, {'true' if k['gaji_rahasia'] == 'ya' else 'false'});")
        out.append(f"insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ({q(kid)}, 'mulai', {q(k['mulai'])});")
        if k["berhenti"]:
            out.append(f"insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ({q(kid)}, 'berhenti', {q(k['berhenti'])});")
        # Penugasan regu: rentang setengah terbuka, ditulis langsung tanpa mengubah baris.
        titik = [(k["mulai"], k["regu"])] + sorted(mutasi.get(kid, []))
        for i, (dari, regu) in enumerate(titik):
            sampai = titik[i + 1][0] if i + 1 < len(titik) else None
            out.append(f"insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari, berlaku_sampai) "
                       f"values ({q(kid)}, {int(regu)}, {q(dari)}, {q(sampai)});")
    for p in pemetaan:
        out.append(f"insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari, berlaku_sampai) "
                   f"values ({q(p['mesin'])}, {q(p['id_mesin'])}, {q(p['id_karyawan'])}, {q(p['berlaku_dari'])}, {q(p['berlaku_sampai'])});")
    out.append("commit;")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "A")
