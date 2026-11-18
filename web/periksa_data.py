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
    # F15c (paket G1-2): rahasia per periode = rahasia pada hari mana pun di periode itu, atau rahasia sekarang.
    # Dihitung di Python dari baris riwayat (bukan SQL yang sama dengan pembuat data).
    riwayat = q("select id_karyawan, berlaku_dari, berlaku_sampai, gaji_rahasia from induk.karyawan_riwayat")
    terakhir = {}
    for r in sorted(riwayat, key=lambda r: (r["id_karyawan"], r["berlaku_dari"])):
        terakhir[r["id_karyawan"]] = r["gaji_rahasia"] == "t"
    rahasia_kini = {o for o, x in terakhir.items() if x}
    tgl = {int(r["id"]): (r["tanggal_awal"], r["tanggal_akhir"]) for r in q("select id, tanggal_awal, tanggal_akhir from fakta.periode")}

    def rahasia_periode(pid):
        awal, akhir = tgl[pid]
        return rahasia_kini | {r["id_karyawan"] for r in riwayat if r["gaji_rahasia"] == "t" and r["berlaku_dari"] <= akhir
                               and (not r["berlaku_sampai"] or r["berlaku_sampai"] > awal)}

    urut = sorted(versi, key=lambda x: tgl[x][0])
    lalu_dari = {b: a for a, b in zip(urut, urut[1:])}
    for p in data["periode"]:
        pid, v = p["id"], versi.get(p["id"])
        if v is None:
            continue
        rahasia = rahasia_periode(pid)
        pid_lalu = lalu_dari.get(pid)
        rahasia_lalu = rahasia_periode(pid_lalu) if pid_lalu else set()
        # F15b (paket 6a-3): total untuk HRD tanpa orang rahasia.
        ring = q(f"select id_karyawan, total_pendapatan, total_potongan, gaji_bersih, dibayar, sisa_pembulatan, peringatan "
                 f"from hitung.ringkasan_gaji where versi_id = {v}")
        tampil = [r for r in ring if r["id_karyawan"] not in rahasia]
        banding(f"periode {pid} orang", p["orang"], len(tampil))
        banding(f"periode {pid} orang rahasia", p["rahasia"], len(ring) - len(tampil))
        for k, kol in (("pendapatan", "total_pendapatan"), ("potongan", "total_potongan"), ("bersih", "gaji_bersih"),
                       ("dibayar", "dibayar"), ("sisa", "sisa_pembulatan")):
            banding(f"periode {pid} {k}", p[k], sum(int(r[kol]) for r in tampil))
        cara = Counter()
        cara_orang = {}
        for r in q(f"select g.id_karyawan, r.cara_bayar, g.dibayar from hitung.ringkasan_gaji g join fakta.periode p on p.id = {pid} "
                   f"join induk.karyawan_riwayat r on r.id_karyawan = g.id_karyawan and r.berlaku_dari <= p.tanggal_akhir "
                   f"and (r.berlaku_sampai is null or r.berlaku_sampai > p.tanggal_akhir) where g.versi_id = {v}"):
            cara_orang[r["id_karyawan"]] = (r["cara_bayar"], int(r["dibayar"]))
            if r["id_karyawan"] not in rahasia:
                cara[r["cara_bayar"]] += int(r["dibayar"])
        banding(f"periode {pid} transfer", p["transfer"], cara["transfer"])
        banding(f"periode {pid} tunai", p["tunai"], cara["tunai"])
        gudang_pecahan = [[int(r["pecahan"]), int(r["lembar"])] for r in q(
            f"select pecahan, lembar from hitung.pecahan_tunai({v}) order by pecahan desc")]
        nilai = [n for n, _ in gudang_pecahan]

        def amplop(dibayar):
            hasil, s = [], max(dibayar, 0)
            for n in nilai:
                hasil.append(s // n)
                s %= n
            return hasil
        tampil_lembar, rahasia_lembar = [0] * len(nilai), [0] * len(nilai)
        for o, (c, d) in cara_orang.items():
            if c == "tunai":
                tujuan = rahasia_lembar if o in rahasia else tampil_lembar
                for i, x in enumerate(amplop(d)):
                    tujuan[i] += x
        banding(f"periode {pid} pecahan (tanpa rahasia)", [list(x) for x in p["pecahan"]],
                [[n, l] for n, l in zip(nilai, tampil_lembar)])
        banding(f"periode {pid} pecahan tampil + amplop rahasia = hitung.pecahan_tunai",
                [[n, a + b] for n, a, b in zip(nilai, tampil_lembar, rahasia_lembar)], gudang_pecahan)
        banding(f"periode {pid} bisa diajukan", p["bisa_diajukan"],
                q(f"select hitung.periode_bisa_diajukan({pid}) b")[0]["b"] == "t")
        banding(f"periode {pid} tertahan", p["tertahan"], sum(
            1 for r in tampil if "pph_masa_terakhir_tertahan" in [x.strip('"') for x in r["peringatan"].strip("{}").split(",")]))
        for a in p["anomali"]:
            if a.get("id") in (rahasia | rahasia_lalu) and a.get("ket") is not None:
                salah.append(f"periode {pid}: tanda anomali orang rahasia {a['id']} masih berketerangan")
        # 6a-4: divisi orang rahasia di periode ini (hari terakhir yang punya hasil harian), perintah SQL sendiri.
        # F15c: tanda divisi membandingkan dengan periode lalu, jadi divisi orang rahasia periode lalu ikut.
        div_rahasia = set()
        for vv, rr in ((v, rahasia), (versi.get(pid_lalu), rahasia_lalu)):
            if vv is None or not rr:
                continue
            daftar_r = ",".join("'" + x.replace("'", "''") + "'" for x in sorted(rr))
            div_rahasia |= {r["divisi"] for r in q(
                f"select distinct on (h.id_karyawan) h.divisi from hitung.hasil_harian h "
                f"join hitung.versi_hitung x on x.id = {vv} where h.versi_id = x.versi_sumber "
                f"and h.id_karyawan in ({daftar_r}) order by h.id_karyawan, h.tanggal desc")}
        for a in p["anomali"]:
            ket = a.get("ket") or ""
            if "Rp" in ket and (a.get("id") in (rahasia | rahasia_lalu) or (a.get("id") is None and a.get("divisi") in div_rahasia)):
                salah.append(f"periode {pid}: tanda anomali berangka menyangkut gaji rahasia ({a.get('id') or a.get('divisi')}): {ket}")
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
        # Uji kebocoran F15b: total halaman - jumlah per orang yang tampil = 0.
        tampil_bersih = sum(k["p"][str(pid)][1] or 0 for k in data["karyawan"] if str(pid) in k["p"] and k["id"] not in rahasia)
        banding(f"periode {pid} kebocoran: total gaji bersih - jumlah gaji bersih yang tampil", p["bersih"] - tampil_bersih, 0)
        banding(f"periode {pid} kebocoran: orang - jumlah orang yang tampil",
                p["orang"] - sum(1 for k in data["karyawan"] if str(pid) in k["p"] and k["id"] not in rahasia), 0)
        for kunci, isi in (("dibayar", "dibayar"), ("sisa", "sisa")):
            banding(f"periode {pid} kebocoran: total {kunci} - jumlah yang tampil", p[kunci] - sum(r[isi] for r in rinci.values()), 0)
        for c in ("transfer", "tunai"):
            banding(f"periode {pid} kebocoran: {c} - jumlah yang tampil",
                    p[c] - sum(r["dibayar"] for r in rinci.values() if r["cara"] == c), 0)

        # ---- Paket G1: grafik (perintah SQL sendiri) ----
        div = {r["id_karyawan"]: r["divisi"] for r in q(
            f"select distinct on (h.id_karyawan) h.id_karyawan, h.divisi from hitung.hasil_harian h "
            f"join hitung.versi_hitung x on x.id = {v} where h.versi_id = x.versi_sumber "
            f"order by h.id_karyawan, h.tanggal desc")}
        kelompok = {r["komponen"]: r["kelompok"] for r in q(
            f"select distinct komponen, kelompok from hitung.rincian_gaji where versi_id = {v}")}
        harap = defaultdict(lambda: {"orang": 0, "rahasia": 0, "pokok": 0, "lembur": 0, "pot_hari": 0, "pot_lain": 0, "bersih": 0})
        for orang, b in bersih.items():
            h = harap[div.get(orang) or "-"]
            if orang in rahasia:
                h["rahasia"] += 1
                continue
            km = komponen[orang]
            h["orang"] += 1
            h["pokok"] += km.get("gaji_pokok", 0)
            h["lembur"] += km.get("lembur", 0)
            h["pot_hari"] += -km.get("potongan_tidak_dibayar", 0)
            h["pot_lain"] += -sum(n for c, n in km.items() if kelompok.get(c) == "potongan")
            h["bersih"] += b
        kunci_div = ("orang", "rahasia", "pokok", "lembur", "pot_hari", "pot_lain", "bersih")
        banding(f"periode {pid} grafik biaya per divisi", {d["divisi"]: {k: d[k] for k in kunci_div} for d in p["divisi_biaya"]},
                {d: dict(x) for d, x in harap.items()})
        # Uji kebocoran per divisi: total divisi - jumlah per orang yang tampil di divisi itu = 0.
        tampil_div = defaultdict(lambda: defaultdict(int))
        for k in data["karyawan"]:
            isi_p = k["p"].get(str(pid))
            if not isi_p or k["id"] in rahasia:
                continue
            r = rinci.get(k["id"]) or {"rincian": []}
            t_ = tampil_div[isi_p[0] or "-"]
            t_["bersih"] += isi_p[1] or 0
            for c, kel, n, _b in r["rincian"]:
                if c == "gaji_pokok":
                    t_["pokok"] += n
                elif c == "lembur":
                    t_["lembur"] += n
                elif c == "potongan_tidak_dibayar":
                    t_["pot_hari"] -= n
                if kel == "potongan":
                    t_["pot_lain"] -= n
        for d in p["divisi_biaya"]:
            for kunci in ("pokok", "lembur", "pot_hari", "pot_lain", "bersih"):
                banding(f"periode {pid} kebocoran grafik divisi {d['divisi']} {kunci}: total - jumlah yang tampil",
                        d[kunci] - tampil_div[d["divisi"]][kunci], 0)
        telat = defaultdict(int)
        for r in q(f"select h.tanggal from hitung.hasil_harian h join hitung.versi_hitung x on x.id = {v} "
                   f"where h.versi_id = x.versi_sumber and h.status = 'hadir' and h.menit_telat > 0"):
            telat[r["tanggal"]] += 1
        per = q(f"select tanggal_awal, tanggal_akhir from fakta.periode where id = {pid}")[0]
        tanggal = [r["d"] for r in q(f"select gs::date d from generate_series('{per['tanggal_awal']}'::date, "
                                     f"'{per['tanggal_akhir']}'::date, interval '1 day') gs")]
        banding(f"periode {pid} grafik telat per tanggal", [list(x) for x in p["telat"]], [[d, telat.get(d, 0)] for d in tanggal])
        banding(f"periode {pid} THR (tanpa rahasia)", p["thr"],
                sum(km.get("thr", 0) for o, km in komponen.items() if o not in rahasia))
        nilai = [n for n, _ in p["pecahan"]]
        for orang, (c, d) in cara_orang.items():
            k = daftar.get(orang)
            if k and str(pid) in k["p"]:
                banding(f"periode {pid} {orang} cara bayar (daftar)", k["p"][str(pid)][2], c)
            r = rinci.get(orang)
            if r is None:
                continue
            if c == "tunai":
                amp = r.get("amplop") or []
                banding(f"periode {pid} {orang} isi amplop = dibayar", sum(n * l for n, l in amp), max(d, 0))
                banding(f"periode {pid} {orang} pecahan amplop", [n for n, _ in amp], nilai)
            elif "amplop" in r:
                salah.append(f"periode {pid} {orang}: orang transfer punya isi amplop")
        jumlah_amp = defaultdict(int)
        for r in rinci.values():
            for n, l in r.get("amplop") or []:
                jumlah_amp[n] += l
        banding(f"periode {pid} jumlah semua amplop = pecahan periode", [[n, jumlah_amp.get(n, 0)] for n in nilai],
                [list(x) for x in p["pecahan"]])

    for s in salah[:30]:
        print("  BEDA", s)
    print(f"Pemeriksaan angka demo: {len(data['periode'])} periode, {len(data['karyawan'])} karyawan, "
          f"{len(rahasia_kini)} rahasia; {len(salah)} beda")
    sys.exit(1 if salah else 0)


if __name__ == "__main__":
    main()
