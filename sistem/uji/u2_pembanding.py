#!/usr/bin/env python3
"""Kalkulator pembanding gaji (U2 versi mesin), ditulis dari docs/aturan-hitung-gaji.md (versi 3).

Tidak memakai kode SQL hitung gaji: hanya membaca masukan (hasil harian versi baca tap terakhir, data induk,
aturan) lalu menghitung sendiri, kemudian membandingkan dengan hitung.rincian_gaji dan hitung.ringkasan_gaji
versi hitung gaji terakhir. Ini pembanding buatan Claude sendiri, bukan pengganti hitungan manusia (U2 asli).

Pemakaian: DB_URL=postgresql://... python3 sistem/uji/u2_pembanding.py [id_periode ...]
Tanpa id: semua periode. Keluar 1 bila ada selisih satu rupiah pun.
"""
import csv
import datetime as dt
import io
import os
import subprocess
import sys
from collections import defaultdict

DB_URL = os.environ.get("DB_URL", "postgresql://postgres:postgres@localhost:5432/postgres")
D = dt.date


def q(sql):
    out = subprocess.run(["psql", DB_URL, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c",
                          f"copy ({sql}) to stdout with csv header"],
                         check=True, capture_output=True, text=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def tgl(s):
    return D.fromisoformat(s) if s else None


def bulat(pembilang, penyebut=1):
    """Setengah ke atas ke bilangan bulat terdekat, untuk pecahan pembilang/penyebut (penyebut > 0)."""
    if pembilang >= 0:
        return (2 * pembilang + penyebut) // (2 * penyebut)
    return -((-2 * pembilang + penyebut) // (2 * penyebut))


def berlaku(baris, tanggal, kunci_dari="berlaku_dari", kunci_sampai="berlaku_sampai"):
    return [b for b in baris if tgl(b[kunci_dari]) <= tanggal and (not b[kunci_sampai] or tanggal < tgl(b[kunci_sampai]))]


class Data:
    def __init__(self):
        self.riwayat = defaultdict(list)
        for r in q("select * from induk.karyawan_riwayat"):
            self.riwayat[r["id_karyawan"]].append(r)
        self.mulai = {}
        for r in q("select id_karyawan, min(tanggal) as t from induk.status_kerja where jenis = 'mulai' group by 1"):
            self.mulai[r["id_karyawan"]] = tgl(r["t"])
        self.pengaturan = q("select * from aturan.pengaturan")
        self.bawaan = {r["kunci"]: r["bawaan"] for r in q("select kunci, bawaan from aturan.daftar_pengaturan")}
        self.komponen = q("select * from aturan.komponen_lain")
        self.lembur = q("select * from aturan.lembur")
        self.pengali = defaultdict(list)
        for r in q("select * from aturan.pengali_lembur"):
            self.pengali[r["jenis_hari"]].append(r)
        self.bpjs = q("select * from aturan.bpjs")
        self.umk = q("select * from aturan.upah_minimum")
        self.ptkp = q("select * from aturan.ptkp")
        self.ter = q("select * from aturan.tarif_ter")
        self.kode = {r["kode"]: r for r in q("select * from induk.kode_jadwal")}
        self.thr = q("select * from aturan.thr")
        self.denda = q("select * from aturan.tingkat_denda where cakupan = 'perusahaan'")
        self.batas_potongan = q("select * from aturan.batas_potongan")
        self.pasal17 = q("select * from aturan.tarif_pasal17")
        self.cuti = q("select * from aturan.cuti where cakupan = 'perusahaan'")
        self.saldo_awal = defaultdict(list)
        for r in q("select * from induk.saldo_cuti_awal order by tanggal"):
            self.saldo_awal[r["id_karyawan"]].append(r)
        self.berhenti = defaultdict(list)
        for r in q("select id_karyawan, tanggal from induk.status_kerja where jenis = 'berhenti'"):
            self.berhenti[r["id_karyawan"]].append(tgl(r["tanggal"]))
        self.periode = q("select * from fakta.periode order by tanggal_awal")
        self.kasbon = defaultdict(list)
        for r in q("select id_karyawan, jenis, jumlah, (dibuat at time zone 'Asia/Jakarta')::date as tanggal, id "
                   "from fakta.buku_kasbon order by id"):
            self.kasbon[r["id_karyawan"]].append(r)
        self.divisi = {r["kode"]: r for r in q("select * from induk.divisi")}
        self.jadwal = q("select * from induk.jadwal_hari")
        perintah = q("select * from fakta.perintah_hrd")
        batal = {p["membatalkan"] for p in perintah if p["jenis"] == "batalkan_perintah"}
        self.perintah = [p for p in perintah if p["jenis"] != "batalkan_perintah" and p["id"] not in batal]

    def atur(self, kunci, divisi, tanggal):
        for cakupan in (divisi, "perusahaan"):
            b = berlaku([p for p in self.pengaturan if p["kunci"] == kunci and p["cakupan"] == cakupan], tanggal)
            if b:
                return b[0]["nilai"]
        return self.bawaan[kunci]

    def rw(self, orang, tanggal):
        b = berlaku(self.riwayat[orang], tanggal)
        return b[0] if b else None

    def ada_perintah(self, jenis, orang, divisi, tanggal):
        for p in self.perintah:
            if p["jenis"] != jenis or not p["tanggal_mulai"]:
                continue
            awal, akhir = tgl(p["tanggal_mulai"]), tgl(p["tanggal_selesai"] or p["tanggal_mulai"])
            if not (awal <= tanggal <= akhir):
                continue
            if p["id_karyawan"] == orang or (not p["id_karyawan"] and p["divisi"] == divisi):
                return True
        return False

    def nominal_komponen(self, kode, tanggal):
        b = berlaku([k for k in self.komponen if k["kode"] == kode and k["cakupan"] == "perusahaan"], tanggal)
        return int(b[0]["nominal"]) if b else 0

    def lama_kerja(self, kode):
        """Menit kerja satu kode jadwal (tanpa istirahat yang tidak dibayar)."""
        k = self.kode[kode]
        m = lambda t: int(t[:2]) * 60 + int(t[3:5])
        lama = m(k["jam_pulang"]) - m(k["jam_masuk"])
        if lama <= 0:
            lama += 24 * 60
        if k["istirahat_dibayar"] != "t":
            lama -= int(k["istirahat_menit"])
        return lama

    def hari_terpendek(self, divisi, regu, tanggal):
        if self.divisi[divisi]["pola"] == "rotasi":
            return False
        minggu = {}
        for j in berlaku([j for j in self.jadwal if j["divisi"] == divisi and int(j["regu"]) == int(regu)], tanggal):
            if j["kode"]:
                minggu[int(j["hari_ke"])] = self.lama_kerja(j["kode"])
        ini = minggu.get(tanggal.isoweekday())
        if ini is None or len(set(minggu.values())) < 2:
            return False
        return ini == min(minggu.values()) and ini < max(minggu.values())


def satuan(data, jenis, menit, tanggal):
    baris = sorted(berlaku(data.pengali[jenis], tanggal), key=lambda r: int(r["jam_ke"]))
    total, k, lewat = 0, 0, False
    while menit > 0:
        k += 1
        if k <= len(baris):
            p = int(baris[k - 1]["pengali_x10"])
        else:
            p, lewat = int(baris[-1]["pengali_x10"]), True
        total += p * min(60, menit)
        menit -= 60
    return total, lewat


def pasal17(data, pkp, tanggal):
    total = 0
    for t in sorted(berlaku(data.pasal17, tanggal), key=lambda x: int(x["pkp_dari"])):
        lo, hi = int(t["pkp_dari"]), (int(t["pkp_sampai"]) if t["pkp_sampai"] else None)
        if pkp > lo:
            total += ((min(pkp, hi) if hi else pkp) - lo) * int(t["persen"])
    return total // 10000


def hitung_periode(data, periode, sejarah):
    """sejarah: {orang: {'kasbon': total dipotong di periode sebelumnya, 'sisa': sisa pembulatan periode sebelumnya}}"""
    awal, akhir, bayar = tgl(periode["tanggal_awal"]), tgl(periode["tanggal_akhir"]), tgl(periode["tanggal_bayar"])
    versi = q(f"select id from hitung.versi_terakhir where periode_id = {periode['id']} and jenis = 'baca_tap'")[0]["id"]
    hasil = defaultdict(list)
    for h in q(f"select *, (masuk at time zone 'Asia/Jakarta') as masuk_l from hitung.hasil_harian where versi_id = {versi}"):
        h["tanggal"] = tgl(h["tanggal"])
        hasil[h["id_karyawan"]].append(h)

    pola_p = data.atur("pola_hari_kerja", "perusahaan", akhir)
    batas_hari = 5 if pola_p == "5_hari" else 6
    pembagi = sum(1 for i in range((akhir - awal).days + 1) if (awal + dt.timedelta(i)).isoweekday() <= batas_hari)
    aturan_lembur = berlaku(data.lembur, akhir)[0]
    umk = berlaku(data.umk, bayar)
    assert len(umk) == 1, "lebih dari satu UMK"
    umk = int(umk[0]["nilai"])

    keluar = {}
    for orang, hari in hasil.items():
        hari.sort(key=lambda h: h["tanggal"])
        r = {}
        # B. upah tetap
        aktif = [h for h in hari if h["tanggal"].isoweekday() <= batas_hari]
        r["gaji_pokok"] = bulat(sum(int(data.rw(orang, h["tanggal"])["gaji_pokok"]) for h in aktif), pembagi)
        r["tunjangan_tetap"] = bulat(sum(int(data.rw(orang, h["tanggal"])["tunjangan_tetap"]) for h in aktif), pembagi)
        tidak_dibayar = 0
        for h in hari:
            izin = h["status"] == "izin" and data.atur("izin_dibayar", h["divisi"], h["tanggal"]) == "tidak"
            if (h["status"] == "alpha" or izin) and h["jenis_hari"] in ("kerja", "cuti_bersama"):
                w = data.rw(orang, h["tanggal"])
                tidak_dibayar += int(w["gaji_pokok"]) + int(w["tunjangan_tetap"])
        r["potongan_tidak_dibayar"] = -bulat(tidak_dibayar, pembagi)
        # C. tunjangan tidak tetap
        makan = shift = 0
        for h in hari:
            if h["status"] != "hadir":
                continue
            if data.atur("uang_makan", h["divisi"], h["tanggal"]) == "dihitung" and int(h["menit_telat"]) <= 60:
                makan += data.nominal_komponen("uang_makan", h["tanggal"])
            if data.atur("tunjangan_shift_malam", h["divisi"], h["tanggal"]) == "hidup" and h["kode_jadwal"]:
                k = data.kode[h["kode_jadwal"]]
                if k["jam_pulang"] <= k["jam_masuk"]:
                    shift += data.nominal_komponen("tunjangan_shift_malam", h["tanggal"])
        r["uang_makan"], r["tunjangan_shift_malam"] = makan, shift
        div_akhir = hari[-1]["divisi"]
        premi = 0
        if data.atur("premi_hadir", div_akhir, akhir) == "hidup":
            if not any(h["status"] == "alpha" or int(h["menit_telat"]) > 0 for h in hari):
                premi = data.nominal_komponen("premi_hadir", akhir)
        r["premi_hadir"] = premi
        # D. lembur
        w_akhir = data.rw(orang, akhir) or data.rw(orang, hari[-1]["tanggal"])
        p_tetap = int(w_akhir["gaji_pokok"]) + int(w_akhir["tunjangan_tetap"])
        t_tidak = makan + shift + premi
        dasar = bulat(75 * (p_tetap + t_tidak), 100) if p_tetap * 10000 < 7500 * (p_tetap + t_tidak) else p_tetap
        lembur = 0
        for h in hari:
            if h["status"] == "hadir" and h["jenis_hari"] in ("kerja", "cuti_bersama"):
                menit, jenis = int(h["menit_lebih"]), "kerja"
            elif h["status"] == "lembur_hari_libur":
                if not h["pulang"]:
                    continue
                menit = int(h["menit_hadir"])
                if menit > 240:
                    menit -= 60
                jenis = None
            elif h["status"] == "hadir" and h["jenis_hari"] == "libur_nasional" and h["kode_jadwal"]:
                menit = data.lama_kerja(h["kode_jadwal"]) - int(h["menit_telat"]) - int(h["menit_pulang_cepat"])
                if not h["lupa_tap"]:
                    menit += int(h["menit_lebih"])
                jenis = None
            else:
                continue
            if jenis is None:
                if data.atur("pola_hari_kerja", h["divisi"], h["tanggal"]) == "5_hari":
                    jenis = "libur_5_hari"
                elif data.hari_terpendek(h["divisi"], h["regu"], h["tanggal"]):
                    jenis = "libur_6_hari_terpendek"
                else:
                    jenis = "libur_6_hari"
            menit = max(menit, 0)
            if menit < int(aturan_lembur["menit_minimal"]):
                continue
            kel = int(aturan_lembur["kelipatan_menit"])
            menit = menit // kel * kel
            if data.atur("lembur", h["divisi"], h["tanggal"]) == "wajib_perintah":
                boleh = data.ada_perintah("setujui_lembur", orang, h["divisi"], h["tanggal"])
            else:
                boleh = not data.ada_perintah("batalkan_lembur", orang, h["divisi"], h["tanggal"])
            if not boleh:
                continue
            s, _ = satuan(data, jenis, menit, h["tanggal"])
            lembur += bulat(s * dasar, 173 * 60 * 10)
        r["lembur"] = lembur
        # H. THR
        thr = 0
        for t in data.thr:
            tb = tgl(t["tanggal_bayar"])
            if not (awal <= tb <= akhir) or not any(h["tanggal"] == tb for h in hari):
                continue
            mulai = data.mulai.get(orang)
            hr = tgl(t["hari_raya"])
            w = data.rw(orang, tb)
            upah = int(w["gaji_pokok"]) + int(w["tunjangan_tetap"])
            if t["cara_prorata"] == "hari":
                hari_kerja = (hr - mulai).days
                thr += bulat(upah * min(hari_kerja, 365), 365) if hari_kerja >= 30 else 0
            else:
                bulan = (hr.year - mulai.year) * 12 + hr.month - mulai.month - (1 if hr.day < mulai.day else 0)
                thr += bulat(upah * min(bulan, 12), 12) if bulan >= 1 else 0
        r["thr"] = thr
        # I. denda dan kasbon
        denda_minta = 0
        for h in hari:
            for d in berlaku(data.denda, h["tanggal"]):
                lo, hi = int(d["dari_menit"]), (int(d["sampai_menit"]) if d["sampai_menit"] else None)
                cocok = False
                if d["jenis"] == "telat":
                    m = int(h["menit_telat"]); cocok = m > 0 and m >= lo and (hi is None or m < hi)
                elif d["jenis"] == "pulang_cepat":
                    m = int(h["menit_pulang_cepat"]); cocok = m > 0 and m >= lo and (hi is None or m < hi)
                elif d["jenis"] == "lupa_tap":
                    cocok = bool(h["lupa_tap"])
                elif d["jenis"] == "alpha":
                    cocok = h["status"] == "alpha"
                if cocok:
                    denda_minta += int(d["nominal"])
        dasar_batas = max(0, sum(r[k] for k in ("gaji_pokok", "tunjangan_tetap", "potongan_tidak_dibayar", "uang_makan",
                                                 "tunjangan_shift_malam", "premi_hadir", "lembur")))
        bp = berlaku(data.batas_potongan, akhir)
        batas = dasar_batas * int(bp[0]["persen"]) // 10000 if bp else dasar_batas
        r["denda"] = -min(denda_minta, batas)
        catatan = [k for k in data.kasbon.get(orang, []) if k["tanggal"] <= akhir]
        saldo = (sum(int(k["jumlah"]) for k in catatan if k["jenis"] == "pinjam")
                 - sum(int(k["jumlah"]) for k in catatan if k["jenis"] == "pelunasan")
                 - sejarah.get(orang, {}).get("kasbon", 0))
        cicilan = [int(k["jumlah"]) for k in catatan if k["jenis"] == "cicilan"]
        minta = min(cicilan[-1], saldo) if cicilan else saldo
        r["kasbon"] = -max(0, min(minta, batas + r["denda"]))
        # E. BPJS
        perusahaan_pajak = 0
        for b in berlaku(data.bpjs, bayar):
            program, bagian = b["program"], b["bagian"]
            ikut = w_akhir["bpjs_kesehatan"] == "t" if program == "kesehatan" else w_akhir["bpjs_ketenagakerjaan"] == "t"
            upah = p_tetap
            if b["batas_atas"]:
                upah = min(upah, int(b["batas_atas"]))
            if program == "kesehatan":
                upah = max(upah, umk)
            nilai = bulat(upah * int(b["persen"]), 10000) if ikut else 0
            if bagian == "karyawan":
                r[f"bpjs_{program}_karyawan"] = -nilai
            else:
                r[f"bpjs_{program}_perusahaan"] = nilai
                if program in ("kesehatan", "jkk", "jkm"):
                    perusahaan_pajak += nilai
        # F. PPh 21
        pendapatan = sum(r[k] for k in ("gaji_pokok", "tunjangan_tetap", "potongan_tidak_dibayar", "uang_makan",
                                        "tunjangan_shift_malam", "premi_hadir", "lembur", "thr"))
        bruto = pendapatan + perusahaan_pajak
        pph = 0
        r["pengembalian_pph21"] = 0
        terakhir = bayar.month == 12 or any(awal <= b <= akhir for b in data.berhenti.get(orang, []))
        tahun = sejarah.get(orang, {}).get("tahun", {}).get(bayar.year, [])
        if terakhir:
            lengkap = all(any(tgl(p["tanggal_bayar"]).year == bayar.year and tgl(p["tanggal_bayar"]).month == m
                              for p in data.periode) for m in range(1, bayar.month))
            if lengkap:
                iuran_ini = -(r.get("bpjs_jht_karyawan", 0) + r.get("bpjs_jp_karyawan", 0))
                b_tahun = sum(x["bruto"] for x in tahun) + bruto
                iuran = sum(x["iuran"] for x in tahun) + iuran_ini
                bulan_n = len(tahun) + 1
                sudah = sum(x["pph"] for x in tahun)
                bj = min(b_tahun * 5 // 100, 500000 * bulan_n)
                acuan = max(D(bayar.year, 1, 1), data.mulai.get(orang, D(bayar.year, 1, 1)))
                w_pajak = data.rw(orang, acuan) or w_akhir
                ptkp = int(berlaku([p for p in data.ptkp if p["status"] == w_pajak["ptkp"]], bayar)[0]["nilai_setahun"])
                pkp = max(0, (b_tahun - bj - iuran - ptkp) // 1000 * 1000)
                selisih = pasal17(data, pkp, bayar) - sudah
                if selisih >= 0:
                    pph = selisih
                else:
                    r["pengembalian_pph21"] = -selisih
        elif bruto > 0:
            acuan = max(D(bayar.year, 1, 1), data.mulai.get(orang, D(bayar.year, 1, 1)))
            w_pajak = data.rw(orang, acuan) or w_akhir
            kat = berlaku([p for p in data.ptkp if p["status"] == w_pajak["ptkp"]], bayar)[0]["kategori_ter"]
            t = [x for x in berlaku([x for x in data.ter if x["kategori"] == kat], bayar)
                 if int(x["bruto_dari"]) <= bruto and (not x["bruto_sampai"] or bruto < int(x["bruto_sampai"]))][0]
            persen = int(t["persen"])
            if data.atur("pembulatan_pph21", "perusahaan", bayar) == "terdekat":
                pph = bulat(bruto * persen, 10000)
            else:
                pph = bruto * persen // 10000
        r["pph21"] = -pph
        bersih = (pendapatan + sum(v for k, v in r.items() if k.endswith("_karyawan")) - pph + r["denda"] + r["kasbon"]
                  + r["pengembalian_pph21"])
        # M. cuti
        terpakai = 0
        for h in hari:
            if h["status"] == "cuti":
                terpakai += 1
            elif (h["status"] == "libur" and h["jenis_hari"] == "cuti_bersama" and h["tanggal"] < D(2026, 10, 28)
                  and data.atur("cuti_bersama", h["divisi"], h["tanggal"]) == "potong_cuti"):
                terpakai += 1
        saldo = None
        awal_cuti = [a for a in data.saldo_awal.get(orang, []) if tgl(a["tanggal"]) <= awal]
        if awal_cuti:
            a = awal_cuti[-1]
            t0 = tgl(a["tanggal"])
            rantai = [p for p in data.periode if t0 <= tgl(p["tanggal_awal"]) <= awal]
            bersambung = rantai and tgl(rantai[0]["tanggal_awal"]) == t0 and all(
                tgl(rantai[i + 1]["tanggal_awal"]) == tgl(rantai[i]["tanggal_akhir"]) + dt.timedelta(1) for i in range(len(rantai) - 1))
            if bersambung:
                pakai = sum(sejarah.get(orang, {}).get("cuti", {}).get(p["id"], 0) for p in rantai[:-1]) + terpakai
                aturan_cuti = berlaku(data.cuti, akhir)[0]
                mulai = data.mulai[orang]
                lahir = 0
                n = int(aturan_cuti["berlaku_setelah_bulan"])
                while True:
                    y, m = divmod(mulai.month - 1 + n, 12)
                    try:
                        ultah = D(mulai.year + y, m + 1, mulai.day)
                    except ValueError:
                        ultah = D(mulai.year + y, m + 2, 1) - dt.timedelta(1)
                    if ultah > akhir:
                        break
                    if ultah > t0:
                        lahir += int(aturan_cuti["jatah_hari"])
                    n += 12
                saldo = int(a["hari"]) + lahir - pakai
        r["_cuti"] = (terpakai, saldo)
        # J. tunai dan sisa
        lalu = sejarah.get(orang, {}).get("sisa", 0)
        total = bersih + lalu
        if total < 0:
            dibayar, sisa = 0, total
        elif w_akhir["cara_bayar"] == "tunai":
            kel = int(data.atur("pembulatan_tunai", "perusahaan", akhir))
            dibayar = total // kel * kel
            sisa = total - dibayar
        else:
            dibayar, sisa = total, 0
        iuran_ini = -(r.get("bpjs_jht_karyawan", 0) + r.get("bpjs_jp_karyawan", 0))
        r["_tahun"] = {"bruto": bruto, "iuran": iuran_ini, "pph": pph - r["pengembalian_pph21"]}
        keluar[orang] = (r, bruto, bersih, dibayar, sisa)
    return keluar


def main():
    data = Data()
    semua = q("select * from fakta.periode order by tanggal_awal")
    pilih = set(sys.argv[1:])
    selisih = 0
    orang_total = 0
    kasbon_lalu = defaultdict(int)   # total kasbon dipotong di periode-periode sebelumnya (hitungan pembanding sendiri)
    sisa_lalu = {}                    # sisa pembulatan periode sebelumnya
    tahun_lalu = defaultdict(lambda: defaultdict(list))   # per orang per tahun pajak: bruto, iuran, pph tiap periode
    cuti_lalu = defaultdict(dict)                         # per orang: cuti terpakai per periode
    for periode in semua:
        semua_orang = set(kasbon_lalu) | set(sisa_lalu) | set(tahun_lalu) | set(cuti_lalu)
        sejarah = {o: {"kasbon": kasbon_lalu[o], "sisa": sisa_lalu.get(o, 0), "tahun": tahun_lalu[o], "cuti": cuti_lalu[o]}
                   for o in semua_orang}
        harap = hitung_periode(data, periode, sejarah)
        sisa_lalu = {o: v[4] for o, v in harap.items()}
        for o, v in harap.items():
            tahun_lalu[o][tgl(periode["tanggal_bayar"]).year].append(v[0].pop("_tahun"))
            cuti_lalu[o][periode["id"]] = v[0]["_cuti"][0]
        for o, v in harap.items():
            kasbon_lalu[o] += -v[0]["kasbon"]
        if pilih and periode["id"] not in pilih:
            continue
        v = q(f"select id from hitung.versi_terakhir where periode_id = {periode['id']} and jenis = 'hitung_gaji'")
        if not v:
            print(f"periode {periode['id']}: belum ada hasil hitung gaji")
            selisih += 1
            continue
        versi = v[0]["id"]
        sistem = defaultdict(dict)
        for r in q(f"select id_karyawan, komponen, nominal from hitung.rincian_gaji where versi_id = {versi}"):
            sistem[r["id_karyawan"]][r["komponen"]] = int(r["nominal"])
        ringkas = {r["id_karyawan"]: r for r in q(f"select * from hitung.ringkasan_gaji where versi_id = {versi}")}
        for orang, v in harap.items():
            cuti = v[0].pop("_cuti")
            g = ringkas.get(orang)
            if g and (int(g["cuti_terpakai"]), int(g["saldo_cuti"]) if g["saldo_cuti"] else None) != cuti:
                print(f"  periode {periode['id']} {orang} cuti: pembanding {cuti}, sistem {g['cuti_terpakai']} {g['saldo_cuti']}")
                selisih += 1
        beda_periode = 0
        for orang, (r, bruto, bersih, dibayar, sisa) in sorted(harap.items()):
            s = sistem.get(orang, {})
            for k in set(r) | set(s):
                if r.get(k, 0) != s.get(k, 0):
                    beda_periode += 1
                    if beda_periode <= 15:
                        print(f"  periode {periode['id']} {orang} {k}: pembanding {r.get(k, 0)}, sistem {s.get(k, 0)}")
            g = ringkas.get(orang)
            if not g or (int(g["bruto_pajak"]), int(g["gaji_bersih"]), int(g["dibayar"]), int(g["sisa_pembulatan"])) \
                    != (bruto, bersih, dibayar, sisa):
                beda_periode += 1
                if beda_periode <= 15:
                    print(f"  periode {periode['id']} {orang} ringkasan: pembanding {bruto} {bersih} {dibayar} {sisa}, "
                          f"sistem {g and (g['bruto_pajak'], g['gaji_bersih'], g['dibayar'], g['sisa_pembulatan'])}")
        extra = set(sistem) - set(harap)
        beda_periode += len(extra)
        orang_total += len(harap)
        print(f"periode {periode['id']}: {len(harap)} orang, selisih {beda_periode}")
        selisih += beda_periode
    print(f"Pembanding: {orang_total} orang-periode, selisih {selisih}")
    sys.exit(1 if selisih else 0)


if __name__ == "__main__":
    main()
