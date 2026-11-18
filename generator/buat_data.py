"""Generator data simulasi Tahap 1 (PRD v3.1 bagian 5).

Generator ini hanya mencatat KEJADIAN: kapan seseorang benar-benar datang dan
pulang, siapa yang sakit, siapa yang lupa tap. Ia tidak menerapkan aturan
jendela tap, telat, lembur, atau rumus gaji. Dari kejadian itu ia menulis tap
seperti yang akan dicatat mesin, lengkap dengan kotoran yang ditanam.

Keluaran ada di data/simulasi/<pabrik>/. Benih acak tetap, jadi hasilnya
selalu sama setiap dijalankan.
"""

import csv
import gzip
import hashlib
import io
import os
import random
from datetime import date, datetime, timedelta

from konfigurasi import (CUTI_BERSAMA, JAM_JADWAL, LIBUR_NASIONAL, NAMA_BELAKANG,
                         NAMA_DEPAN, PABRIK, PELUANG, PELUANG_LEMBUR, RAMADAN)

AKAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "simulasi")
JANGKAR_ROTASI = date(2026, 1, 1)
SIKLUS_ROTASI = ["P", "P", "S", "S", "M", "M", None, None]  # 4 regu, 8 hari


def tgl(s):
    return date.fromisoformat(s)


def rentang(a, b):
    d = a
    while d <= b:
        yield d
        d += timedelta(days=1)


def jam_ke_datetime(d, hhmm):
    h, m = map(int, hhmm.split(":"))
    return datetime(d.year, d.month, d.day, h, m)


def kode_jadwal(pola, regu, d):
    """Kode jadwal orang pada tanggal d, atau None kalau hari libur rutinnya."""
    hari = d.weekday()  # 0 Senin ... 6 Minggu
    if pola == "rotasi4":
        return SIKLUS_ROTASI[((d - JANGKAR_ROTASI).days + 2 * regu) % 8]
    minggu = d.isocalendar()[1]
    if pola == "gudang2":
        if hari == 6:
            return None
        return "P" if (minggu + regu) % 2 == 0 else "S"
    if pola == "dua_shift5":
        if hari >= 5:
            return None
        return "P" if (minggu + regu) % 2 == 0 else "S"
    if pola == "kantor6":
        if hari == 6:
            return None
        ramadan = tgl(RAMADAN[0]) <= d <= tgl(RAMADAN[1])
        if hari == 5:
            return "KR5" if ramadan else "K5"
        return "KR" if ramadan else "K"
    if pola == "kantor5":
        return None if hari >= 5 else "K"
    raise ValueError(pola)


def jam_jadwal(kode, d):
    masuk, pulang = JAM_JADWAL[kode]
    a = jam_ke_datetime(d, masuk)
    b = jam_ke_datetime(d, pulang)
    if b <= a:
        b += timedelta(days=1)
    return a, b


class Generator:
    def __init__(self, kode_pabrik):
        self.kode = kode_pabrik
        self.cfg = PABRIK[kode_pabrik]
        self.r = random.Random(self.cfg["benih"])
        self.peluang = {**PELUANG, **self.cfg.get("peluang_khusus", {})}
        self.karyawan = []
        self.id_berikut = self.cfg["awal_id"]
        self.pemetaan = []
        self.divisi = {d[0]: d for d in self.cfg["divisi"]}
        self.mesin_divisi = {}
        for m, daftar in self.cfg["mesin"].items():
            for dv in daftar:
                self.mesin_divisi[dv] = m

    # ---------- data induk ----------
    def nama_acak(self):
        return f"{self.r.choice(NAMA_DEPAN)} {self.r.choice(NAMA_BELAKANG)}"

    def gaji_acak(self, dv):
        rentang_pokok = {"PRD": (3_450_000, 4_200_000), "QC": (3_700_000, 4_600_000),
                         "KAM": (3_450_000, 3_900_000), "GDG": (3_450_000, 4_200_000),
                         "KTR": (4_000_000, 9_000_000)}[dv]
        pokok = self.r.randrange(rentang_pokok[0], rentang_pokok[1], 50_000)
        tetap = self.r.randrange(250_000, 650_000, 50_000)
        return pokok, tetap

    def tambah_karyawan(self, dv, regu, mulai, catatan=""):
        pokok, tetap = self.gaji_acak(dv)
        k = {
            "id": str(self.id_berikut), "nama": self.nama_acak(), "divisi": dv,
            "regu": regu, "mulai": mulai, "berhenti": None,
            "tipe_upah": "bulanan", "gaji_pokok": pokok, "tunjangan_tetap": tetap,
            "ptkp": self.r.choice(["TK/0", "TK/1", "K/0", "K/1", "K/2", "K/3"]),
            # Permintaan perubahan 03: angka acak tetap diambil (hasilnya tidak dipakai) supaya urutan acak
            # dan semua data lain tidak bergeser; cara bayar mengikuti bagian.
            "cara_bayar": "tunai" if (self.r.random() is not None and dv in self.cfg["divisi_tunai"]) else "transfer",
            "wajib_tap": True, "gaji_rahasia": False, "catatan": catatan,
            "regu_berubah": [],  # (tanggal berlaku, regu baru)
        }
        self.id_berikut += 1
        self.karyawan.append(k)
        self.pemetaan.append({"mesin": self.mesin_divisi[dv], "id_mesin": k["id"],
                              "id_karyawan": k["id"], "berlaku_dari": mulai.isoformat(),
                              "berlaku_sampai": ""})
        return k

    def buat_induk(self):
        for dv, _nama, jumlah, _pola, nregu in self.cfg["divisi"]:
            for i in range(jumlah):
                mulai = date(2025, 1, 2) + timedelta(days=self.r.randrange(0, 360))
                if self.r.random() < 0.15:  # sebagian besar sudah lama bekerja
                    mulai = date(2020, 1, 2) + timedelta(days=self.r.randrange(0, 1500))
                self.tambah_karyawan(dv, i % nregu, mulai)
        for dv, n in self.cfg["tidak_wajib_tap"].items():
            for k in [x for x in self.karyawan if x["divisi"] == dv][:n]:
                k["wajib_tap"] = False
                k["catatan"] = "sopir, tidak wajib tap"
        for dv, n in self.cfg["gaji_rahasia"].items():
            for k in [x for x in self.karyawan if x["divisi"] == dv][-n:]:
                k["gaji_rahasia"] = True
        # Dua nama sama persis untuk menguji perintah chat nama ganda (PRD 9).
        a, b = self.karyawan[5], self.karyawan[17]
        b["nama"] = a["nama"]
        b["catatan"] = (b["catatan"] + "; nama sama dengan " + a["id"]).strip("; ")
        if self.cfg["id_ganda"]:
            k = self.karyawan[0]
            k["catatan"] = "terdaftar dua kali di mesin sejak 2026-03-01 (ID mesin 90001)"
            self.pemetaan.append({"mesin": self.mesin_divisi[k["divisi"]], "id_mesin": "90001",
                                  "id_karyawan": k["id"], "berlaku_dari": "2026-03-01",
                                  "berlaku_sampai": ""})

    def regu_pada(self, k, d):
        regu = k["regu"]
        for berlaku, baru in k["regu_berubah"]:
            if d >= berlaku:
                regu = baru
        return regu

    # ---------- satu periode ----------
    def jalankan_periode(self, no, awal, akhir):
        r = self.r
        kejadian, taps, masukan = [], [], []
        kirim = akhir + timedelta(days=1)

        def masuk_hrd(jenis, kid, d1, d2="", nilai="", cat=""):
            masukan.append({"tanggal_kirim": kirim.isoformat(), "jenis": jenis,
                            "id_karyawan": kid, "tanggal_mulai": d1, "tanggal_selesai": d2,
                            "nilai": nilai, "catatan": cat})

        # Karyawan keluar dan masuk di tengah periode, mutasi regu.
        aktif = [k for k in self.karyawan if k["berhenti"] is None and k["mulai"] <= awal]
        for k in aktif:
            if r.random() < PELUANG["keluar_tengah"]:
                k["berhenti"] = awal + timedelta(days=r.randrange(3, (akhir - awal).days - 2))
                masuk_hrd("berhenti", k["id"], k["berhenti"].isoformat(),
                          cat=r.choice(["resign", "resign", "PHK"]))
        for dv, _n, jumlah, _p, nregu in self.cfg["divisi"]:
            for _ in range(max(1, round(jumlah * PELUANG["masuk_tengah"]))):
                mulai = awal + timedelta(days=r.randrange(2, (akhir - awal).days - 3))
                k = self.tambah_karyawan(dv, r.randrange(nregu), mulai, "karyawan baru")
                masuk_hrd("karyawan_baru", k["id"], mulai.isoformat(), nilai=dv)
                if r.random() < 0.3:  # belum didaftarkan di mesin minggu pertama (PRD P3)
                    k["catatan"] = "karyawan baru, belum didaftar di mesin 3 hari pertama"
                    k["telat_daftar"] = mulai + timedelta(days=3)
        rotasi = [k for k in aktif if self.divisi[k["divisi"]][3] in ("rotasi4", "gudang2")
                  and k["berhenti"] is None]
        for k in r.sample(rotasi, 3 if self.kode == "A" else 1):
            berlaku = awal + timedelta(days=r.randrange(5, 20))
            baru = (self.regu_pada(k, berlaku) + 1) % self.divisi[k["divisi"]][4]
            k["regu_berubah"].append((berlaku, baru))
            masuk_hrd("mutasi_regu", k["id"], berlaku.isoformat(), nilai=str(baru))

        mesin_mati = {(m, tgl(t)): s for m, t, s in self.cfg["mesin_mati"]}
        for (m, t), s in mesin_mati.items():
            if awal <= t <= akhir and s == "dilaporkan":
                dv = ",".join(self.cfg["mesin"][m])
                masuk_hrd("absen_manual", "", t.isoformat(), nilai=dv,
                          cat="mesin mati, semua yang terjadwal hadir")

        for k in self.karyawan:
            pola = self.divisi[k["divisi"]][3]
            mesin = self.mesin_divisi[k["divisi"]]
            for d in rentang(awal, akhir):
                baris = {"pabrik": self.kode, "periode": no, "id_karyawan": k["id"],
                         "divisi": k["divisi"], "tanggal_kerja": d.isoformat(),
                         "regu": "", "kode_jadwal": "", "kejadian": "",
                         "datang_sebenarnya": "", "pulang_sebenarnya": "",
                         "lupa_tap": "", "tap_tengah": "", "tap_ulang": "",
                         "tukar_shift_ke": "", "dilaporkan_hrd": "", "mesin_mati": "",
                         "catatan": ""}
                if d < k["mulai"]:
                    continue
                if k["berhenti"] and d > k["berhenti"]:
                    continue
                regu = self.regu_pada(k, d)
                kode = kode_jadwal(pola, regu, d)
                baris["regu"] = regu
                ds = d.isoformat()
                hari_raya = ds in LIBUR_NASIONAL or ds in CUTI_BERSAMA
                tujuh_hari = pola == "rotasi4"
                if kode is None:
                    if pola in ("rotasi4", "gudang2") and k["wajib_tap"] and r.random() < PELUANG["lembur_libur"]:
                        kode, baris["kejadian"] = "P", "lembur_hari_libur"
                        baris["catatan"] = "datang di hari libur rutin"
                    else:
                        baris["kejadian"] = "libur"
                        kejadian.append(baris)
                        continue
                elif hari_raya and not tujuh_hari:
                    if ds in LIBUR_NASIONAL:
                        baris["kejadian"] = "libur_nasional"
                    elif self.cfg["cuti_bersama"] == "dibayar":
                        baris["kejadian"] = "cuti_bersama_dibayar"
                    else:
                        baris["kejadian"] = "cuti_bersama_potong_cuti"
                    baris["kode_jadwal"] = kode
                    kejadian.append(baris)
                    continue
                if tujuh_hari and hari_raya:
                    baris["catatan"] = "bekerja di hari raya (operasi 7 hari)"
                baris["kode_jadwal"] = kode
                if not k["wajib_tap"]:
                    baris["kejadian"] = "hadir_tidak_wajib_tap"
                    kejadian.append(baris)
                    continue
                if tujuh_hari and baris["kejadian"] == "" and r.random() < self.peluang["tukar_shift"]:
                    lain = [x for x in ("P", "S", "M") if x != kode]
                    kode = r.choice(lain)
                    baris["tukar_shift_ke"] = kode
                    lapor = r.random() < PELUANG["tukar_dilaporkan"]
                    baris["dilaporkan_hrd"] = "ya" if lapor else "tidak"
                    if lapor:
                        masuk_hrd("tukar_shift", k["id"], ds, nilai=kode)
                if baris["kejadian"] == "":
                    u = r.random()
                    batas = 0
                    for jenis in ("alpha", "sakit", "izin", "cuti"):
                        batas += PELUANG[jenis]
                        if u < batas:
                            baris["kejadian"] = jenis
                            break
                    if baris["kejadian"] in ("sakit", "izin", "cuti"):
                        baris["dilaporkan_hrd"] = "ya"
                        masuk_hrd(baris["kejadian"], k["id"], ds)
                    if baris["kejadian"]:
                        kejadian.append(baris)
                        continue
                    baris["kejadian"] = "hadir"
                jm, jp = jam_jadwal(kode, d)
                if r.random() < PELUANG["telat"]:
                    datang = jm + timedelta(minutes=min(90, int(6 + r.expovariate(1 / 18))))
                else:
                    datang = jm - timedelta(minutes=r.randint(5, 30))
                u = r.random()
                if u < PELUANG["pulang_cepat"]:
                    pulang = jp - timedelta(minutes=r.randint(15, 120))
                elif u < PELUANG["pulang_cepat"] + PELUANG_LEMBUR[k["divisi"]] or baris["kejadian"] == "lembur_hari_libur":
                    if baris["kejadian"] == "lembur_hari_libur":
                        pulang = jp + timedelta(minutes=r.randint(0, 20))
                    else:
                        pulang = jp + timedelta(minutes=r.randint(60, 240))
                        baris["catatan"] = (baris["catatan"] + "; pulang lambat").strip("; ")
                        if self.kode == "B" and r.random() < 0.8:
                            masuk_hrd("perintah_lembur", k["id"], ds, nilai=str(int((pulang - jp).total_seconds() // 60)))
                else:
                    pulang = jp + timedelta(minutes=r.randint(0, 15))
                datang += timedelta(seconds=r.randint(0, 59))
                pulang += timedelta(seconds=r.randint(0, 59))
                baris["datang_sebenarnya"] = datang.isoformat(sep=" ")
                baris["pulang_sebenarnya"] = pulang.isoformat(sep=" ")

                if (mesin, d) in mesin_mati:
                    baris["mesin_mati"] = mesin_mati[(mesin, d)]
                    kejadian.append(baris)
                    continue
                if k.get("telat_daftar") and d < k["telat_daftar"]:
                    baris["catatan"] = (baris["catatan"] + "; belum terdaftar di mesin").strip("; ")
                    kejadian.append(baris)
                    continue

                daftar = [(datang, "Masuk", "datang"), (pulang, "Keluar", "pulang")]
                # Tap yang jatuh pada tanggal mesin mati ikut hilang (misalnya tap pulang shift malam).
                hilang = [x for x in daftar if (mesin, x[0].date()) in mesin_mati]
                if hilang:
                    daftar = [x for x in daftar if x not in hilang]
                    baris["mesin_mati"] = mesin_mati[(mesin, hilang[0][0].date())] + " (sebagian: " + ",".join(x[2] for x in hilang) + ")"
                u = r.random()
                if u < PELUANG["lupa_tap"]:
                    if r.random() < 0.5:
                        daftar, baris["lupa_tap"] = [daftar[1]], "masuk"
                    else:
                        daftar, baris["lupa_tap"] = [daftar[0]], "pulang"
                elif u < PELUANG["lupa_tap"] + PELUANG["tap_tengah"]:
                    t = jm + timedelta(minutes=r.randint(180, 300), seconds=r.randint(0, 59))
                    daftar, baris["tap_tengah"] = [(t, "Masuk", "tengah")], "ya"
                if r.random() < PELUANG["tap_ulang"] and daftar:
                    asal = r.choice(daftar)
                    st = asal[1] if r.random() < 0.6 else ("Keluar" if asal[1] == "Masuk" else "Masuk")
                    daftar.append((asal[0] + timedelta(minutes=r.randint(1, 5), seconds=r.randint(0, 59)), st, "ulang"))
                    baris["tap_ulang"] = "ya"
                for t, st, asal in daftar:
                    self.catat_tap(taps, k, mesin, t, st, asal, d)
                kejadian.append(baris)

        # ID tidak dikenal (tamu, teknisi)
        for i in range(self.cfg["id_tidak_dikenal"]):
            m = sorted(self.cfg["mesin"])[0]
            d = awal + timedelta(days=r.randrange((akhir - awal).days + 1))
            while (m, d) in mesin_mati:
                d = awal + timedelta(days=r.randrange((akhir - awal).days + 1))
            t = jam_ke_datetime(d, "10:00") + timedelta(minutes=r.randint(0, 300), seconds=r.randint(0, 59))
            taps.append({"mesin": m, "id_mesin": str(99901 + i), "nama": "TAMU",
                         "waktu": t, "status": "Masuk", "id_karyawan": "",
                         "tanggal_kerja": "", "asal": "id_tidak_dikenal",
                         "terbalik": "", "dobel": "", "selisih_jam": 0})
        return kejadian, taps, masukan

    def catat_tap(self, taps, k, mesin, t_asli, status, asal, d_kerja):
        r = self.r
        id_mesin = k["id"]
        if self.cfg["id_ganda"] and k is self.karyawan[0] and d_kerja >= date(2026, 3, 1) and asal == "pulang":
            id_mesin = "90001"
        selisih = 0
        for m, a, b, menit in self.cfg["selisih_jam"]:
            if m == mesin and tgl(a) <= t_asli.date() <= tgl(b):
                selisih = menit
        terbalik = r.random() < PELUANG["status_terbalik"]
        st = ("Keluar" if status == "Masuk" else "Masuk") if terbalik else status
        rec = {"mesin": mesin, "id_mesin": id_mesin, "nama": k["nama"].upper()[:12],
               "waktu": t_asli + timedelta(minutes=selisih), "status": st,
               "id_karyawan": k["id"], "tanggal_kerja": d_kerja.isoformat(), "asal": asal,
               "terbalik": "ya" if terbalik else "", "dobel": "", "selisih_jam": selisih}
        taps.append(rec)
        if r.random() < PELUANG["baris_dobel"]:
            dup = dict(rec)
            dup["dobel"] = "ya"
            taps.append(dup)


# ---------- penulisan file ----------
def buka_gz(path):
    """File .gz tanpa jam pembuatan, supaya hasil selalu identik byte demi byte."""
    return io.TextIOWrapper(gzip.GzipFile(filename="", mode="wb", fileobj=open(path, "wb"), mtime=0,
                                          compresslevel=9), encoding="utf-8", newline="")


def tulis_csv(path, kolom, baris, gz=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    buka = buka_gz if gz else \
        (lambda p: open(p, "w", newline="", encoding="utf-8"))
    with buka(path) as f:
        w = csv.writer(f)
        w.writerow(kolom)
        for b in baris:
            w.writerow([b.get(c, "") if isinstance(b, dict) else c for c in kolom] if isinstance(b, dict) else b)


def baris_ekspor(taps):
    """Format ekspor aplikasi mesin, mengikuti file asli Februari 2026."""
    urut = sorted(taps, key=lambda x: (x["id_mesin"], x["waktu"], x["dobel"]))
    for x in urut:
        w = x["waktu"]
        yield [x["nama"], x["id_mesin"], w.strftime("%d/%m/%Y %H.%M.%S"),
               w.strftime("%d/%m/%Y %H.%M"), "C/" + x["status"]]


def baris_attlog(taps):
    """Format attlog.dat ZKTeco: ID, waktu, mesin, status (0 masuk/1 keluar), verifikasi, kode kerja."""
    urut = sorted(taps, key=lambda x: (x["waktu"], x["id_mesin"], x["dobel"]))
    for x in urut:
        yield f"{x['id_mesin']:>9}\t{x['waktu'].strftime('%Y-%m-%d %H:%M:%S')}\t1\t{0 if x['status'] == 'Masuk' else 1}\t1\t0"


def jalankan(kode):
    g = Generator(kode)
    g.buat_induk()
    akar = os.path.join(AKAR, kode)
    semua_taps = []
    for no, (a, b) in enumerate(g.cfg["periode"], start=1):
        awal, akhir = tgl(a), tgl(b)
        kejadian, taps, masukan = g.jalankan_periode(no, awal, akhir)
        semua_taps.extend(taps)
        tulis_csv(os.path.join(akar, "kunci", f"{kode}_p{no}_kejadian.csv.gz"),
                  list(kejadian[0].keys()), kejadian)
        tulis_csv(os.path.join(akar, "masukan_hrd", f"{kode}_p{no}_masukan_hrd.csv.gz"),
                  ["tanggal_kirim", "jenis", "id_karyawan", "tanggal_mulai", "tanggal_selesai", "nilai", "catatan"],
                  masukan)
        jejak_kolom = ["mesin", "id_mesin", "waktu", "status", "id_karyawan", "tanggal_kerja",
                       "asal", "terbalik", "dobel", "selisih_jam"]
        tulis_csv(os.path.join(akar, "kunci", f"{kode}_p{no}_jejak_tap.csv.gz"), jejak_kolom,
                  [{**t, "waktu": t["waktu"].isoformat(sep=" ")} for t in sorted(taps, key=lambda x: (x["id_mesin"], x["waktu"]))])
        for m in sorted(g.cfg["mesin"]):
            dalam = [t for t in taps if t["mesin"] == m and awal <= t["waktu"].date() <= akhir]
            lanjut = [t for t in taps if t["mesin"] == m and t["waktu"].date() == akhir + timedelta(days=1)]
            tulis_csv(os.path.join(akar, "mesin", f"{kode}_p{no}_{m}.csv.gz"),
                      ["Nama", "No.ID", "Tgl/Waktu", "", "Status"], baris_ekspor(dalam))
            tulis_csv(os.path.join(akar, "mesin", f"{kode}_p{no}_{m}_lanjutan.csv.gz"),
                      ["Nama", "No.ID", "Tgl/Waktu", "", "Status"], baris_ekspor(lanjut))
            os.makedirs(os.path.join(akar, "attlog"), exist_ok=True)
            with buka_gz(os.path.join(akar, "attlog", f"{kode}_p{no}_{m}.dat.gz")) as f:
                for line in baris_attlog(dalam):
                    f.write(line + "\n")
        print(f"{kode} periode {no} {a}..{b}: {len(kejadian)} hari-orang, {len(taps)} tap, {len(masukan)} masukan HRD")

    induk = os.path.join(akar, "induk")
    tulis_csv(os.path.join(induk, "karyawan.csv"),
              ["id", "nama", "divisi", "regu", "mulai", "berhenti", "tipe_upah", "gaji_pokok",
               "tunjangan_tetap", "ptkp", "cara_bayar", "wajib_tap", "gaji_rahasia", "catatan"],
              [{**k, "mulai": k["mulai"].isoformat(), "berhenti": k["berhenti"].isoformat() if k["berhenti"] else "",
                "wajib_tap": "ya" if k["wajib_tap"] else "tidak", "gaji_rahasia": "ya" if k["gaji_rahasia"] else ""}
               for k in g.karyawan], gz=False)
    tulis_csv(os.path.join(induk, "pemetaan_id_mesin.csv"),
              ["mesin", "id_mesin", "id_karyawan", "berlaku_dari", "berlaku_sampai"], g.pemetaan, gz=False)
    tulis_csv(os.path.join(induk, "mutasi_regu.csv"), ["id_karyawan", "berlaku_dari", "regu_baru"],
              [[k["id"], b.isoformat(), r] for k in g.karyawan for b, r in k["regu_berubah"]], gz=False)
    tulis_csv(os.path.join(induk, "divisi.csv"), ["kode", "nama", "jumlah_awal", "pola", "jumlah_regu", "mesin"],
              [[d[0], d[1], d[2], d[3], d[4], g.mesin_divisi[d[0]]] for d in g.cfg["divisi"]], gz=False)
    tulis_csv(os.path.join(induk, "jam_jadwal.csv"), ["kode", "masuk", "pulang"],
              [[k, v[0], v[1]] for k, v in JAM_JADWAL.items()], gz=False)
    kal = [[d, "libur_nasional", n] for d, n in LIBUR_NASIONAL.items()] + \
          [[d, "cuti_bersama", n] for d, n in CUTI_BERSAMA.items()] + \
          [[RAMADAN[0], "jadwal_ramadan_mulai", "Kantor KR/KR5"], [RAMADAN[1], "jadwal_ramadan_selesai", "Kantor KR/KR5"]]
    tulis_csv(os.path.join(induk, "kalender.csv"), ["tanggal", "jenis", "keterangan"], sorted(kal), gz=False)
    return g


def tulis_sidik_isi():
    """Sidik SHA-256 dari ISI setiap file (setelah dibuka kompresinya).

    Byte file .gz bisa berbeda antar komputer karena pustaka kompresi berbeda,
    jadi kesamaan data diperiksa dari isinya, bukan dari byte file terkompresi.
    """
    baris = []
    for akar, _dirs, files in os.walk(AKAR):
        for nama in files:
            path = os.path.join(akar, nama)
            if nama == "sidik_isi.txt":
                continue
            data = gzip.open(path, "rb").read() if nama.endswith(".gz") else open(path, "rb").read()
            baris.append(f"{hashlib.sha256(data).hexdigest()}  {os.path.relpath(path, AKAR)}")
    with open(os.path.join(AKAR, "sidik_isi.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(sorted(baris, key=lambda x: x.split("  ")[1])) + "\n")


if __name__ == "__main__":
    for kode in sorted(PABRIK):
        jalankan(kode)
    tulis_sidik_isi()
