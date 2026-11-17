"""Pemeriksaan "angka demo sama dengan gudang" (docs/halaman-demo.md).

Membaca file data halaman lalu menghitung ulang dari gudang dengan perintah SQL sendiri, terpisah dari
web/buat_data.py. Keluar dengan kode 1 bila ada satu angka yang berbeda.
Pemakaian: DB_URL=... python3 web/periksa_data.py [folder]
"""
import csv
import io
import json
import os
import subprocess
import sys
from collections import Counter, defaultdict


def q(sql):
    out = subprocess.run(["psql", os.environ["DB_URL"], "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c",
                          f"copy ({sql}) to stdout with csv header"], check=True, capture_output=True, text=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "demo")
    with open(os.path.join(folder, "data.json"), encoding="utf-8") as f:
        data = json.load(f)
    salah = []

    def banding(nama, halaman, gudang):
        if halaman != gudang:
            salah.append(f"{nama}: halaman {halaman!r}, gudang {gudang!r}")

    versi = {int(r["periode_id"]): int(r["id"]) for r in q(
        "select periode_id, id from hitung.versi_terakhir where jenis = 'hitung_gaji'")}
    banding("periode yang ditampilkan", sorted(p["id"] for p in data["periode"]), sorted(versi))
    rahasia = {r["id_karyawan"] for r in q(
        "select distinct on (id_karyawan) id_karyawan, gaji_rahasia from induk.karyawan_riwayat "
        "order by id_karyawan, berlaku_dari desc") if r["gaji_rahasia"] == "t"}
    for p in data["periode"]:
        pid, v = p["id"], versi.get(p["id"])
        if v is None:
            continue
        g = q(f"select count(*) orang, sum(total_pendapatan) pendapatan, sum(total_potongan) potongan, sum(gaji_bersih) bersih, "
              f"sum(dibayar) dibayar, sum(sisa_pembulatan) sisa from hitung.ringkasan_gaji where versi_id = {v}")[0]
        for k in ("orang", "pendapatan", "potongan", "bersih", "dibayar", "sisa"):
            banding(f"periode {pid} {k}", p[k], int(g[k]))
        cara = Counter()
        for r in q(f"select r.cara_bayar, g.dibayar from hitung.ringkasan_gaji g join fakta.periode p on p.id = {pid} "
                   f"join induk.karyawan_riwayat r on r.id_karyawan = g.id_karyawan and r.berlaku_dari <= p.tanggal_akhir "
                   f"and (r.berlaku_sampai is null or r.berlaku_sampai > p.tanggal_akhir) where g.versi_id = {v}"):
            cara[r["cara_bayar"]] += int(r["dibayar"])
        banding(f"periode {pid} transfer", p["transfer"], cara["transfer"])
        banding(f"periode {pid} tunai", p["tunai"], cara["tunai"])
        banding(f"periode {pid} pecahan", [list(x) for x in p["pecahan"]],
                [[int(r["pecahan"]), int(r["lembar"])] for r in q(
                    f"select pecahan, lembar from hitung.pecahan_tunai({v}) order by pecahan desc")])
        banding(f"periode {pid} bisa diajukan", p["bisa_diajukan"],
                q(f"select hitung.periode_bisa_diajukan({pid}) b")[0]["b"] == "t")
        banding(f"periode {pid} tertahan", p["tertahan"], int(q(
            f"select count(*) n from hitung.ringkasan_gaji where versi_id = {v} "
            f"and 'pph_masa_terakhir_tertahan' = any(peringatan)")[0]["n"]))
        banding(f"periode {pid} anomali per jenis", dict(Counter(a["jenis"] for a in p["anomali"])),
                {r["jenis"]: int(r["n"]) for r in q(f"select jenis, count(*) n from hitung.anomali_gaji({pid}) group by jenis")})

        # Per orang.
        with open(os.path.join(folder, f"rincian_{pid}.json"), encoding="utf-8") as f:
            rinci = json.load(f)
        bersih = {r["id_karyawan"]: int(r["gaji_bersih"]) for r in q(
            f"select id_karyawan, gaji_bersih from hitung.ringkasan_gaji where versi_id = {v}")}
        komponen = defaultdict(dict)
        for r in q(f"select id_karyawan, komponen, nominal from hitung.rincian_gaji where versi_id = {v}"):
            komponen[r["id_karyawan"]][r["komponen"]] = int(r["nominal"])
        daftar = {k["id"]: k for k in data["karyawan"]}
        for orang, b in bersih.items():
            k = daftar.get(orang)
            if k is None or str(pid) not in k["p"]:
                salah.append(f"periode {pid} {orang}: tidak ada di daftar karyawan halaman")
                continue
            if orang in rahasia:
                banding(f"periode {pid} {orang} rahasia: tanpa angka", (k["p"][str(pid)][1], orang in rinci), (None, False))
                continue
            banding(f"periode {pid} {orang} gaji bersih (daftar)", k["p"][str(pid)][1], b)
            r = rinci.get(orang)
            if r is None:
                salah.append(f"periode {pid} {orang}: tidak ada rincian")
                continue
            banding(f"periode {pid} {orang} gaji bersih (rincian)", r["bersih"], b)
            banding(f"periode {pid} {orang} komponen", {x[0]: x[2] for x in r["rincian"]}, komponen[orang])
        banding(f"periode {pid} jumlah orang di rincian", len(rinci), len([o for o in bersih if o not in rahasia]))

    for s in salah[:30]:
        print("  BEDA", s)
    print(f"Pemeriksaan angka demo: {len(data['periode'])} periode, {len(data['karyawan'])} karyawan, "
          f"{len(rahasia)} rahasia; {len(salah)} beda")
    sys.exit(1 if salah else 0)


if __name__ == "__main__":
    main()
