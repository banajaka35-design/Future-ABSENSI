"""Pemeriksa "isi Sheets sama dengan gudang" (gerbang Tahap 6 PRD v2; docs/rekap-sheets.md bagian 5).

Membaca ulang Sheets dari Google (nilai mentah) dan menghitung ulang dari gudang dengan perintah SQL
sendiri, terpisah dari web/isi_sheets.py. Keluar dengan kode 1 bila ada satu beda.

Pemakaian: DB_URL=... GOOGLE_SA_KEY=... SHEETS_ID=... [SHEETS_BOLEH_EDIT=email,...] python3 web/periksa_sheets.py
"""
import csv
import io
import os
import subprocess
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheets_api import AWALAN_GAJI, CATATAN, TAB_RINGKASAN, TAB_RIWAYAT, TANDA_KUNCI, Gagal, Sheets, rentang  # noqa: E402

# Salinan sendiri dari docs/rekap-sheets.md 2.2 (sengaja tidak diimpor dari penulis).
LABEL = {
    "gaji_pokok": "Gaji pokok", "tunjangan_tetap": "Tunjangan tetap",
    "potongan_tidak_dibayar": "Potongan hari tidak dibayar", "uang_makan": "Uang makan",
    "tunjangan_shift_malam": "Tunjangan shift malam", "premi_hadir": "Premi hadir", "lembur": "Lembur", "thr": "THR",
    "pengembalian_pph21": "Pengembalian PPh 21", "denda": "Denda", "kasbon": "Kasbon",
    "bpjs_kesehatan_karyawan": "BPJS Kesehatan (karyawan)", "bpjs_jht_karyawan": "BPJS JHT (karyawan)",
    "bpjs_jp_karyawan": "BPJS JP (karyawan)", "pph21": "PPh 21",
}
LABEL_PERUSAHAAN = {
    "bpjs_kesehatan_perusahaan": "Ditanggung perusahaan: BPJS Kesehatan", "bpjs_jht_perusahaan": "Ditanggung perusahaan: JHT",
    "bpjs_jp_perusahaan": "Ditanggung perusahaan: JP", "bpjs_jkk_perusahaan": "Ditanggung perusahaan: JKK",
    "bpjs_jkm_perusahaan": "Ditanggung perusahaan: JKM",
}
HADIR = ["ID", "Nama", "Divisi", "Cara bayar", "Hadir (hari)", "Masuk hari libur (hari)", "Telat (kali)", "Telat (menit)",
         "Lupa tap (kali)", "Alpha (hari)", "Izin (hari)", "Sakit (hari)", "Cuti (hari)"]
TOTAL = ["Total pendapatan", "Total potongan", "Gaji bersih", "Sisa pembulatan lalu", "Dibayar", "Sisa pembulatan"]
KET = ["Keterangan lembur", "Keterangan hari tidak dibayar", "Peringatan"]
JUDUL_RINGKASAN = ["Periode", "Tanggal awal", "Tanggal akhir", "Tanggal bayar", "Versi baca tap", "Versi hitung gaji",
                   "Orang", "Total pendapatan", "Total potongan", "Total gaji bersih", "Total dibayar",
                   "Total sisa pembulatan", "Transfer", "Tunai", "PPh tertahan (orang)", "Bisa diajukan",
                   "Orang rahasia (tidak termasuk)", "Status rilis"]
KETERANGAN_RAHASIA = ("Total tidak termasuk orang yang gajinya rahasia (lihat kolom terakhir); "
                      "total lengkap hanya untuk bos.")


def q(sql):
    out = subprocess.run(["psql", os.environ["DB_URL"], "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c",
                          f"copy ({sql}) to stdout with csv header"], check=True, capture_output=True, text=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def rapikan(baris, lebar):
    """Google membuang sel kosong di ujung baris; samakan panjangnya."""
    return [list(b) + [""] * (lebar - len(b)) for b in baris]


def main():
    salah = []

    def beda(nama, sheets, gudang):
        if sheets != gudang:
            salah.append(f"{nama}: Sheets {sheets!r}, gudang {gudang!r}")

    try:
        s = Sheets()
        info = s.info()
    except Gagal as e:
        print("GAGAL:", e, file=sys.stderr)
        sys.exit(1)
    tab = {t["properties"]["title"]: t for t in info.get("sheets", [])}

    # --- gudang ------------------------------------------------------------------------------
    periode = q("select p.id, p.tanggal_awal, p.tanggal_akhir, p.tanggal_bayar, g.id as versi_gaji, g.versi_kode as kode_gaji, "
                "b.id as versi_baca, b.versi_kode as kode_baca from hitung.versi_terakhir g "
                "join fakta.periode p on p.id = g.periode_id join hitung.versi_hitung b on b.id = g.versi_sumber "
                "where g.jenis = 'hitung_gaji' order by p.tanggal_awal")
    riwayat = defaultdict(list)
    for r in q("select id_karyawan, berlaku_dari, berlaku_sampai, cara_bayar, gaji_rahasia from induk.karyawan_riwayat"):
        riwayat[r["id_karyawan"]].append(r)
    # F15c (paket G1-2): rahasia per periode = rahasia pada hari mana pun di periode itu, atau rahasia sekarang.
    rahasia_kini = {k for k, rs in riwayat.items() if max(rs, key=lambda r: r["berlaku_dari"])["gaji_rahasia"] == "t"}

    def rahasia_periode(awal, akhir):
        return rahasia_kini | {k for k, rs in riwayat.items() for r in rs if r["gaji_rahasia"] == "t"
                               and r["berlaku_dari"] <= akhir and (not r["berlaku_sampai"] or r["berlaku_sampai"] > awal)}
    nama = {r["id"]: r["nama"] for r in q("select id, nama from induk.karyawan")}

    def cara_bayar(orang, tanggal):
        for r in riwayat.get(orang, []):
            if r["berlaku_dari"] <= tanggal and (not r["berlaku_sampai"] or tanggal < r["berlaku_sampai"]):
                return r["cara_bayar"]
        return ""

    harap_tab = {f"{AWALAN_GAJI}{p['tanggal_awal']} sd {p['tanggal_akhir']} {c}": p for p in periode
                 for c in ("transfer", "tunai")}
    beda("daftar tab Gaji", sorted(t for t in tab if t.startswith(AWALAN_GAJI)), sorted(harap_tab))
    for t in (TAB_RINGKASAN, TAB_RIWAYAT):
        if t not in tab:
            salah.append(f"tab {t} tidak ada")

    # --- kunci (K7) --------------------------------------------------------------------------
    boleh = {s.email.lower()} | {e.strip().lower() for e in os.environ.get("SHEETS_BOLEH_EDIT", "").split(",") if e.strip()}
    for judul, t in tab.items():
        if not (judul in (TAB_RINGKASAN, TAB_RIWAYAT) or judul.startswith(AWALAN_GAJI)):
            continue
        sid = t["properties"]["sheetId"]
        kunci = [r for r in t.get("protectedRanges", []) if r.get("description") == TANDA_KUNCI]
        if len(kunci) != 1:
            salah.append(f"tab {judul}: kunci {len(kunci)} (harus 1)")
            continue
        k = kunci[0]
        if k.get("range", {}) != {"sheetId": sid} and k.get("range", {}).get("sheetId") != sid:
            salah.append(f"tab {judul}: kunci tidak menutup seluruh tab")
        rng = k.get("range", {})
        if any(x in rng for x in ("startRowIndex", "endRowIndex", "startColumnIndex", "endColumnIndex")):
            salah.append(f"tab {judul}: kunci hanya sebagian tab")
        e = k.get("editors", {})
        pengguna = {u.lower() for u in e.get("users", [])}
        if k.get("warningOnly") or e.get("groups") or e.get("domainUsersCanEdit") or not pengguna <= boleh \
                or s.email.lower() not in pengguna:
            salah.append(f"tab {judul}: pengubah yang diizinkan {sorted(pengguna)}, grup {e.get('groups')}, "
                         f"domain {e.get('domainUsersCanEdit')}, hanya peringatan {k.get('warningOnly')}")

    baca = [rentang(t) for t in sorted(harap_tab) if t in tab] + [rentang(t) for t in (TAB_RINGKASAN, TAB_RIWAYAT) if t in tab]
    nilai = dict(zip([t for t in sorted(harap_tab) if t in tab] + [t for t in (TAB_RINGKASAN, TAB_RIWAYAT) if t in tab],
                     s.baca(baca))) if baca else {}

    total = {}
    terlihat = {}  # jumlah dari baris yang benar-benar terlihat di tab Gaji (uji kebocoran F15b)
    for p in periode:
        v, pid, akhir = p["versi_gaji"], p["id"], p["tanggal_akhir"]
        rahasia = rahasia_periode(p["tanggal_awal"], akhir)
        semua = {r["id_karyawan"]: r for r in q(f"select * from hitung.ringkasan_gaji where versi_id = {v}")}
        rinci = defaultdict(dict)
        kelompok = {}
        for r in q(f"select id_karyawan, komponen, kelompok, nominal, bukti from hitung.rincian_gaji where versi_id = {v}"):
            rinci[r["id_karyawan"]][r["komponen"]] = r
            kelompok[r["komponen"]] = r["kelompok"]
        hari = defaultdict(lambda: [0] * 9)
        akhir_div = {}
        for r in q(f"select id_karyawan, tanggal, status, menit_telat, lupa_tap, divisi from hitung.hasil_harian "
                   f"where versi_id = {p['versi_baca']}"):
            h = hari[r["id_karyawan"]]
            st = r["status"]
            telat = int(r["menit_telat"] or 0)
            h[0] += st == "hadir"
            h[1] += st == "lembur_hari_libur"
            h[2] += st == "hadir" and telat > 0
            h[3] += telat
            h[4] += r["lupa_tap"] != ""
            h[5] += st == "alpha"
            h[6] += st == "izin"
            h[7] += st == "sakit"
            h[8] += st == "cuti"
            if r["id_karyawan"] not in akhir_div or r["tanggal"] > akhir_div[r["id_karyawan"]][0]:
                akhir_div[r["id_karyawan"]] = (r["tanggal"], r["divisi"])
        batas = int(q(f"select aturan.pengaturan_pada('pembulatan_tunai', null, '{akhir}')::bigint b")[0]["b"])
        pecahan = [d for d in (100000, 50000, 20000, 10000, 5000, 2000, 1000) if d >= batas]

        def isi_amplop(dibayar):
            hasil, s = [], max(dibayar, 0)
            for d in pecahan:
                hasil.append(s // d)
                s %= d
            return hasil

        # Ringkasan per periode dihitung dari gudang (semua orang, termasuk rahasia).
        cara_orang = {o: cara_bayar(o, akhir) for o in semua}
        # F15b: total untuk HRD hanya orang bukan rahasia.
        t = total[pid] = {"orang": sum(1 for o in semua if o not in rahasia), "pendapatan": 0, "potongan": 0,
                          "bersih": 0, "dibayar": 0, "sisa": 0, "transfer": 0, "tunai": 0, "tertahan": 0,
                          "rahasia": sum(1 for o in semua if o in rahasia)}
        terlihat[pid] = {"orang": 0, "pendapatan": 0, "potongan": 0, "bersih": 0, "dibayar": 0, "sisa": 0,
                         "transfer": 0, "tunai": 0}
        lembar = [0] * len(pecahan)
        for o, g in semua.items():
            if cara_orang[o] == "tunai" and int(g["dibayar"]) > 0:
                lembar = [a + b for a, b in zip(lembar, isi_amplop(int(g["dibayar"])))]
            if cara_orang[o] not in ("transfer", "tunai"):
                salah.append(f"periode {pid}: {o} tidak punya cara bayar")
            if o in rahasia:
                continue
            t["pendapatan"] += int(g["total_pendapatan"])
            t["potongan"] += int(g["total_potongan"])
            t["bersih"] += int(g["gaji_bersih"])
            t["dibayar"] += int(g["dibayar"])
            t["sisa"] += int(g["sisa_pembulatan"])
            if cara_orang[o] in ("transfer", "tunai"):
                t[cara_orang[o]] += int(g["dibayar"])
            t["tertahan"] += "pph_masa_terakhir_tertahan" in [x.strip('"') for x in g["peringatan"].strip("{}").split(",")]
        # Jumlah lembar semua amplop = hitung.pecahan_tunai (perintah gudang).
        beda(f"periode {pid} jumlah lembar per pecahan semua amplop", list(zip(pecahan, lembar)),
             [(int(r["pecahan"]), int(r["lembar"])) for r in q(
                 f"select pecahan, lembar from hitung.pecahan_tunai({v}) order by pecahan desc")])

        lain = sorted(set(kelompok) - set(LABEL) - set(LABEL_PERUSAHAAN))
        komp = list(LABEL) + lain
        for cara_tab in ("transfer", "tunai"):
            judul = f"{AWALAN_GAJI}{p['tanggal_awal']} sd {p['tanggal_akhir']} {cara_tab}"
            amp = pecahan if cara_tab == "tunai" else []
            judul_harap = (HADIR + [LABEL.get(k, k) for k in komp] + TOTAL + KET + list(LABEL_PERUSAHAAN.values())
                           + [f"Amplop Rp{d:,} (lembar)".replace(",", ".") for d in amp])
            lebar = len(judul_harap)
            ring = {o: g for o, g in semua.items() if cara_orang[o] == cara_tab}
            if judul not in nilai:
                continue
            isi = rapikan(nilai[judul], lebar)
            beda(f"{judul} baris 1", isi[0][:1] if isi else None, [CATATAN])
            beda(f"{judul} judul kolom", isi[1] if len(isi) > 1 else None, judul_harap)
            data = isi[2:]
            beda(f"{judul} jumlah orang", len(data), len(ring))
            i_bersih = len(HADIR) + len(komp) + 2
            i_amplop = len(judul_harap) - len(amp)
            for b in data:
                orang = b[0]
                if not isinstance(orang, str):
                    salah.append(f"{judul}: ID {orang!r} bukan teks")
                    orang = str(orang)
                g = ring.pop(orang, None)
                if g is None:
                    salah.append(f"{judul}: {orang} tidak ada di gudang dengan cara bayar {cara_tab}")
                    continue
                cara = cara_orang[orang]
                tl = terlihat[pid]
                tl["orang"] += 1 if isinstance(b[i_bersih], int) else 0
                for kunci, kol in (("pendapatan", -2), ("potongan", -1), ("bersih", 0), ("dibayar", 2), ("sisa", 3)):
                    if isinstance(b[i_bersih + kol], int):
                        tl[kunci] += b[i_bersih + kol]
                if isinstance(b[i_bersih + 2], int):
                    tl[cara_tab] += b[i_bersih + 2]
                ingat = g["peringatan"].strip("{}")
                ingat = [x.strip('"') for x in ingat.split(",")] if ingat else []
                harap = [orang, nama.get(orang, ""), akhir_div.get(orang, ("", ""))[1], cara] + hari[orang]
                c = rinci[orang]
                if orang in rahasia:
                    harap += [""] * (lebar - len(harap))
                else:
                    harap += [int(c[k]["nominal"]) if k in c else 0 for k in komp]
                    harap += [int(g["total_pendapatan"]), int(g["total_potongan"]), int(g["gaji_bersih"]),
                              int(g["sisa_lalu"]), int(g["dibayar"]), int(g["sisa_pembulatan"])]
                    harap += [c["lembur"]["bukti"] if "lembur" in c else "",
                              c["potongan_tidak_dibayar"]["bukti"] if "potongan_tidak_dibayar" in c else "", ", ".join(ingat)]
                    harap += [int(c[k]["nominal"]) if k in c else 0 for k in LABEL_PERUSAHAAN]
                    harap += isi_amplop(int(g["dibayar"])) if amp else []
                    # Per baris: komponen pendapatan + potongan = bersih; dibayar + sisa = bersih + sisa lalu;
                    # isi amplop = dibayar.
                    angka = b[len(HADIR):len(HADIR) + len(komp)]
                    if all(isinstance(x, int) for x in angka):
                        jumlah = sum(x for k, x in zip(komp, angka) if kelompok.get(k, "pendapatan") in ("pendapatan", "potongan"))
                        beda(f"{judul} {orang} jumlah komponen = gaji bersih", jumlah, b[i_bersih])
                    ib = i_bersih
                    if all(isinstance(b[x], int) for x in (ib, ib + 1, ib + 2, ib + 3)):
                        beda(f"{judul} {orang} dibayar + sisa = bersih + sisa lalu", b[ib + 2] + b[ib + 3], b[ib] + b[ib + 1])
                    isi_a = b[i_amplop:]
                    if amp and all(isinstance(x, int) for x in isi_a) and isinstance(b[ib + 2], int):
                        beda(f"{judul} {orang} isi amplop = dibayar", sum(x * d for x, d in zip(isi_a, amp)), max(b[ib + 2], 0))
                for j, (a, e) in enumerate(zip(b, harap)):
                    if a != e or type(a) is not type(e):
                        salah.append(f"{judul} {orang} kolom {judul_harap[j]}: Sheets {a!r}, gudang {e!r}")
            for orang in ring:
                salah.append(f"{judul}: {orang} ada di gudang, tidak ada di Sheets")

    # --- Ringkasan ---------------------------------------------------------------------------
    if TAB_RINGKASAN in nilai:
        r = rapikan(nilai[TAB_RINGKASAN], len(JUDUL_RINGKASAN))
        beda("Ringkasan baris 1", r[0][:1] if r else None, [CATATAN])
        beda("Ringkasan judul kolom", r[3] if len(r) > 3 else None, JUDUL_RINGKASAN)
        beda("Ringkasan keterangan rahasia (baris 3)", r[2][:1] if len(r) > 2 else None, [KETERANGAN_RAHASIA])
        isi = r[4:]
        beda("Ringkasan jumlah periode", len(isi), len(periode))
        for b, p in zip(isi, periode):
            pid = p["id"]
            t = total.get(pid, {})
            bisa = q(f"select hitung.periode_bisa_diajukan({pid}) b")[0]["b"] == "t"
            harap = [int(pid), p["tanggal_awal"], p["tanggal_akhir"], p["tanggal_bayar"], p["kode_baca"],
                     p["kode_gaji"], t.get("orang"), t.get("pendapatan"), t.get("potongan"), t.get("bersih"),
                     t.get("dibayar"), t.get("sisa"), t.get("transfer"), t.get("tunai"), t.get("tertahan"),
                     "YA" if bisa else "TIDAK", t.get("rahasia"),
                     q(f"select fakta.status_rilis_teks({pid}) s")[0]["s"]]
            for j, (a, e) in enumerate(zip(b, harap)):
                if a != e:
                    salah.append(f"Ringkasan periode {pid} {JUDUL_RINGKASAN[j]}: Sheets {a!r}, gudang {e!r}")
            # Uji kebocoran F15b: angka Ringkasan - jumlah baris yang terlihat di tab Gaji = 0.
            tl = terlihat.get(pid, {})
            for kunci, j in (("orang", 6), ("pendapatan", 7), ("potongan", 8), ("bersih", 9), ("dibayar", 10), ("sisa", 11), ("transfer", 12), ("tunai", 13)):
                if isinstance(b[j], int) and b[j] - tl.get(kunci, 0) != 0:
                    salah.append(f"Ringkasan periode {pid} {JUDUL_RINGKASAN[j]}: selisih dengan jumlah baris terlihat "
                                 f"{b[j] - tl.get(kunci, 0)} (harus 0, F15b)")

    # --- Riwayat isi -------------------------------------------------------------------------
    if TAB_RIWAYAT in nilai:
        rw = nilai[TAB_RIWAYAT]
        if len(rw) < 3:
            salah.append("Riwayat isi: belum ada baris isi")
        else:
            akhir = rapikan([rw[-1]], 8)[0]
            beda("Riwayat isi: commit baris terakhir", akhir[1], os.environ.get("GITHUB_SHA", "lokal"))
            beda("Riwayat isi: uji teks panjang (ID 18 digit)", akhir[6], "123456789012345678")
            beda("Riwayat isi: uji tanda sama dengan", akhir[7], "=1+1")

    for x in salah[:40]:
        print("  BEDA", x)
    print(f"Pemeriksaan Sheets: {len(harap_tab)} tab Gaji, {sum(t['orang'] for t in total.values())} orang-periode bukan rahasia, "
          f"{len(rahasia_kini)} rahasia; {len(salah)} beda; permintaan ke Google: {s.jumlah_permintaan}")
    sys.exit(1 if salah else 0)


if __name__ == "__main__":
    main()
