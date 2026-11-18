"""Mengisi rekap Google Sheets dari gudang (paket 6a, docs/rekap-sheets.md).

Gudang hanya dibaca. Sheets ditimpa (PRD v2 D3). Hanya rekap satu baris per orang (D4), tanpa nomor
rekening, angka orang `gaji_rahasia` dikosongkan (F15).

Pemakaian:
  DB_URL=... GOOGLE_SA_KEY=... SHEETS_ID=... python3 web/isi_sheets.py isi
  ... python3 web/isi_sheets.py status SELESAI|GAGAL
"""
import datetime
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheets_api import (AWALAN_GAJI, CATATAN, TAB_RINGKASAN, TAB_RIWAYAT, TANDA_KUNCI, Gagal, Sheets,  # noqa: E402
                        milik_sistem, rentang)

# Kolom rupiah tetap (docs/rekap-sheets.md 2.2), urut tampil.
KOMPONEN = [
    ("gaji_pokok", "Gaji pokok"), ("tunjangan_tetap", "Tunjangan tetap"),
    ("potongan_tidak_dibayar", "Potongan hari tidak dibayar"), ("uang_makan", "Uang makan"),
    ("tunjangan_shift_malam", "Tunjangan shift malam"), ("premi_hadir", "Premi hadir"), ("lembur", "Lembur"),
    ("thr", "THR"), ("pengembalian_pph21", "Pengembalian PPh 21"), ("denda", "Denda"), ("kasbon", "Kasbon"),
    ("bpjs_kesehatan_karyawan", "BPJS Kesehatan (karyawan)"), ("bpjs_jht_karyawan", "BPJS JHT (karyawan)"),
    ("bpjs_jp_karyawan", "BPJS JP (karyawan)"), ("pph21", "PPh 21"),
]
PERUSAHAAN = [
    ("bpjs_kesehatan_perusahaan", "Ditanggung perusahaan: BPJS Kesehatan"),
    ("bpjs_jht_perusahaan", "Ditanggung perusahaan: JHT"), ("bpjs_jp_perusahaan", "Ditanggung perusahaan: JP"),
    ("bpjs_jkk_perusahaan", "Ditanggung perusahaan: JKK"), ("bpjs_jkm_perusahaan", "Ditanggung perusahaan: JKM"),
]
KOLOM_HADIR = ["ID", "Nama", "Divisi", "Cara bayar", "Hadir (hari)", "Masuk hari libur (hari)", "Telat (kali)",
               "Telat (menit)", "Lupa tap (kali)", "Alpha (hari)", "Izin (hari)", "Sakit (hari)", "Cuti (hari)"]
KOLOM_TOTAL = ["Total pendapatan", "Total potongan", "Gaji bersih", "Sisa pembulatan lalu", "Dibayar", "Sisa pembulatan"]
KOLOM_KET = ["Keterangan lembur", "Keterangan hari tidak dibayar", "Peringatan"]
KOLOM_RINGKASAN = ["Periode", "Tanggal awal", "Tanggal akhir", "Tanggal bayar", "Versi baca tap", "Versi hitung gaji",
                   "Orang", "Total pendapatan", "Total potongan", "Total gaji bersih", "Total dibayar",
                   "Total sisa pembulatan", "Transfer", "Tunai", "PPh tertahan (orang)", "Bisa diajukan",
                   "Orang rahasia (tidak termasuk)"]
KETERANGAN_RAHASIA = ("Total tidak termasuk orang yang gajinya rahasia (lihat kolom terakhir); "
                      "total lengkap hanya untuk bos.")
KOLOM_RIWAYAT = ["Waktu (WIB)", "Commit", "Pemicu", "Periode dan versi gaji", "Orang", "Lama isi (ms)",
                 "Uji teks panjang", "Uji tanda sama dengan", "Waktu file masuk"]
UJI_TEKS_PANJANG = "123456789012345678"
UJI_SAMA_DENGAN = "=1+1"

SQL = r"""
with ver as (
  select p.id as periode_id, p.tanggal_awal, p.tanggal_akhir, p.tanggal_bayar, g.id as versi_gaji,
         g.versi_kode as kode_gaji, s.id as versi_baca, s.versi_kode as kode_baca
  from fakta.periode p
  join hitung.versi_terakhir g on g.periode_id = p.id and g.jenis = 'hitung_gaji'
  join hitung.versi_hitung s on s.id = g.versi_sumber
),
rahasia as (
  select distinct on (id_karyawan) id_karyawan, gaji_rahasia
  from induk.karyawan_riwayat order by id_karyawan, berlaku_dari desc
),
hari as (
  select v.versi_gaji, h.id_karyawan,
         count(*) filter (where h.status = 'hadir') as hadir,
         count(*) filter (where h.status = 'lembur_hari_libur') as libur_masuk,
         count(*) filter (where h.status = 'hadir' and h.menit_telat > 0) as telat_kali,
         coalesce(sum(h.menit_telat), 0) as telat_menit,
         count(h.lupa_tap) as lupa,
         count(*) filter (where h.status = 'alpha') as alpha,
         count(*) filter (where h.status = 'izin') as izin,
         count(*) filter (where h.status = 'sakit') as sakit,
         count(*) filter (where h.status = 'cuti') as cuti,
         (array_agg(h.divisi order by h.tanggal desc))[1] as divisi
  from ver v join hitung.hasil_harian h on h.versi_id = v.versi_baca
  group by v.versi_gaji, h.id_karyawan
)
select json_build_object(
  'periode', coalesce((select json_agg(json_build_object(
      'id', v.periode_id, 'awal', v.tanggal_awal, 'akhir', v.tanggal_akhir, 'bayar', v.tanggal_bayar,
      'versi_gaji', v.versi_gaji, 'kode_baca', v.kode_baca, 'kode_gaji', v.kode_gaji,
      'bisa_diajukan', hitung.periode_bisa_diajukan(v.periode_id),
      'pecahan', (select json_agg(d order by d desc) from unnest(array[100000, 50000, 20000, 10000, 5000, 2000, 1000]::bigint[]) d
                  where d >= aturan.pengaturan_pada('pembulatan_tunai', null, v.tanggal_akhir)::bigint),
      'orang', (select coalesce(json_agg(json_build_object(
          'id', g.id_karyawan, 'nama', k.nama, 'rahasia', coalesce(s.gaji_rahasia, false),
          'cara', r.cara_bayar, 'divisi', hr.divisi,
          'hari', json_build_array(coalesce(hr.hadir, 0), coalesce(hr.libur_masuk, 0), coalesce(hr.telat_kali, 0),
                                   coalesce(hr.telat_menit, 0), coalesce(hr.lupa, 0), coalesce(hr.alpha, 0),
                                   coalesce(hr.izin, 0), coalesce(hr.sakit, 0), coalesce(hr.cuti, 0)),
          'pendapatan', g.total_pendapatan, 'potongan', g.total_potongan, 'bersih', g.gaji_bersih,
          'sisa_lalu', g.sisa_lalu, 'dibayar', g.dibayar, 'sisa', g.sisa_pembulatan, 'peringatan', g.peringatan,
          'komponen', (select json_object_agg(x.komponen, json_build_array(x.kelompok, x.nominal, x.bukti))
                       from hitung.rincian_gaji x where x.versi_id = g.versi_id and x.id_karyawan = g.id_karyawan)
        ) order by g.id_karyawan), '[]'::json)
        from hitung.ringkasan_gaji g
        join induk.karyawan k on k.id = g.id_karyawan
        left join rahasia s on s.id_karyawan = g.id_karyawan
        left join induk.karyawan_riwayat r on r.id_karyawan = g.id_karyawan
         and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v.tanggal_akhir
        left join hari hr on hr.versi_gaji = v.versi_gaji and hr.id_karyawan = g.id_karyawan
        where g.versi_id = v.versi_gaji)
    ) order by v.tanggal_awal) from ver v), '[]'::json)
)
"""


def ambil_gudang():
    keluar = subprocess.run(["psql", os.environ["DB_URL"], "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c", SQL],
                            check=True, capture_output=True, text=True).stdout
    return json.loads(keluar)["periode"]


CARA = ("transfer", "tunai")


def nama_tab(p, cara):
    return f"{AWALAN_GAJI}{p['awal']} sd {p['akhir']} {cara}"


def rupiah(n):
    return f"Rp{n:,}".replace(",", ".")


def amplop(dibayar, pecahan):
    """Isi amplop: dibayar dipecah dari pecahan terbesar; dibayar <= 0 -> semua 0."""
    hasil, sisa = [], max(dibayar, 0)
    for d in pecahan:
        hasil.append(sisa // d)
        sisa %= d
    return hasil


def kolom_komponen(p):
    """Kolom komponen untuk satu periode: daftar tetap + komponen lain yang ada di gudang."""
    tetap = {k for k, _ in KOMPONEN} | {k for k, _ in PERUSAHAAN}
    lain = sorted({k for o in p["orang"] for k in (o["komponen"] or {}) if k not in tetap})
    return KOMPONEN + [(k, k) for k in lain]


def baris_gaji(p, cara):
    komp = kolom_komponen(p)
    pecahan = p["pecahan"] if cara == "tunai" else []
    judul = (KOLOM_HADIR + [lbl for _, lbl in komp] + KOLOM_TOTAL + KOLOM_KET + [lbl for _, lbl in PERUSAHAAN]
             + [f"Amplop {rupiah(d)} (lembar)" for d in pecahan])
    baris = [[CATATAN], judul]
    for o in p["orang"]:
        if o["cara"] != cara:
            continue
        c = o["komponen"] or {}
        kiri = [o["id"], o["nama"], o["divisi"] or "", o["cara"] or ""] + o["hari"]
        if o["rahasia"]:
            uang = [""] * (len(komp) + len(KOLOM_TOTAL) + len(KOLOM_KET) + len(PERUSAHAAN) + len(pecahan))
        else:
            uang = ([c[k][1] if k in c else 0 for k, _ in komp]
                    + [o["pendapatan"], o["potongan"], o["bersih"], o["sisa_lalu"], o["dibayar"], o["sisa"]]
                    + [c["lembur"][2] if "lembur" in c else "",
                       c["potongan_tidak_dibayar"][2] if "potongan_tidak_dibayar" in c else "",
                       ", ".join(o["peringatan"] or [])]
                    + [c[k][1] if k in c else 0 for k, _ in PERUSAHAAN]
                    + amplop(o["dibayar"], pecahan))
        baris.append(kiri + uang)
    return baris


def baris_ringkasan(periode, status):
    baris = [[CATATAN], ["Status", status], [KETERANGAN_RAHASIA], KOLOM_RINGKASAN]
    for p in periode:
        # F15b: total untuk HRD tanpa orang rahasia, supaya total - jumlah yang terlihat = 0.
        o = [x for x in p["orang"] if not x["rahasia"]]
        n_rahasia = len(p["orang"]) - len(o)
        jumlah = lambda k: sum(x[k] for x in o)  # noqa: E731
        baris.append([p["id"], p["awal"], p["akhir"], p["bayar"] or "", p["kode_baca"], p["kode_gaji"], len(o),
                      jumlah("pendapatan"), jumlah("potongan"), jumlah("bersih"), jumlah("dibayar"), jumlah("sisa"),
                      sum(x["dibayar"] for x in o if x["cara"] == "transfer"),
                      sum(x["dibayar"] for x in o if x["cara"] == "tunai"),
                      sum(1 for x in o if "pph_masa_terakhir_tertahan" in (x["peringatan"] or [])),
                      "YA" if p["bisa_diajukan"] else "TIDAK", n_rahasia])
    return baris


def waktu():
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=7))).strftime("%Y-%m-%d %H:%M:%S WIB")


def tulis_status(s, kata):
    s.tulis(rentang(TAB_RINGKASAN, "A2"), [["Status", kata]])


def siapkan_tab(s, isi_tab):
    """Buat tab yang belum ada, hapus tab Gaji yang tidak dipakai, ukuran grid, beku baris, kunci."""
    info = s.info()
    ada = {t["properties"]["title"]: t for t in info.get("sheets", [])}
    minta = []
    for judul in isi_tab:
        if judul not in ada:
            minta.append({"addSheet": {"properties": {"title": judul}}})
    for judul in ada:
        if judul.startswith(AWALAN_GAJI) and judul not in isi_tab:
            minta.append({"deleteSheet": {"sheetId": ada[judul]["properties"]["sheetId"]}})
    s.ubah(minta)
    info = s.info()
    ada = {t["properties"]["title"]: t for t in info.get("sheets", [])}
    minta = []
    for judul, baris in isi_tab.items():
        t = ada[judul]
        sid = t["properties"]["sheetId"]
        g = t["properties"].get("gridProperties", {})
        lebar = max(len(b) for b in baris)
        tinggi = len(baris)
        if judul == TAB_RIWAYAT:  # riwayat tidak pernah dipotong
            tinggi = max(tinggi, g.get("rowCount", 0))
            lebar = max(lebar, g.get("columnCount", 0))
        beku = 4 if judul == TAB_RINGKASAN else 2
        minta.append({"updateSheetProperties": {
            "properties": {"sheetId": sid, "gridProperties": {
                "rowCount": tinggi, "columnCount": lebar, "frozenRowCount": beku}},
            "fields": "gridProperties(rowCount,columnCount,frozenRowCount)"}})
        kunci = [r for r in t.get("protectedRanges", []) if r.get("description") == TANDA_KUNCI]
        if not kunci:
            minta.append({"addProtectedRange": {"protectedRange": {
                "range": {"sheetId": sid}, "description": TANDA_KUNCI, "warningOnly": False,
                "editors": {"users": [s.email]}}}})
    s.ubah(minta)


def isi():
    mulai = time.monotonic()
    s = Sheets()
    periode = ambil_gudang()
    print(f"Gudang: {len(periode)} periode, {sum(len(p['orang']) for p in periode)} baris orang-periode")

    # 1. Tandai sedang diisi (tab Ringkasan dibuat dulu bila belum ada).
    awal = {t["properties"]["title"] for t in s.info().get("sheets", [])}
    if TAB_RINGKASAN not in awal:
        s.ubah([{"addSheet": {"properties": {"title": TAB_RINGKASAN}}}])
    tulis_status(s, f"SEDANG DIISI {waktu()}")

    # 2. Tab.
    isi_tab = {TAB_RINGKASAN: baris_ringkasan(periode, f"SEDANG DIISI {waktu()}")}
    for p in periode:
        for cara in CARA:
            isi_tab[nama_tab(p, cara)] = baris_gaji(p, cara)
    isi_tab[TAB_RIWAYAT] = [[CATATAN], KOLOM_RIWAYAT]
    siapkan_tab(s, isi_tab)

    # 3. Kosongkan lalu tulis (satu permintaan per tab; Riwayat isi tidak dikosongkan).
    for judul, baris in isi_tab.items():
        if judul == TAB_RIWAYAT:
            continue
        s.kosongkan([rentang(judul)])
        s.tulis(rentang(judul, "A1"), baris)
        print(f"  {judul}: {len(baris)} baris, {max(len(b) for b in baris)} kolom, "
              f"{len(json.dumps(baris, default=str)) / 1e6:.2f} MB")
    lama = round((time.monotonic() - mulai) * 1000)

    # 4. Riwayat isi.
    # Baris catatan dan judul ditulis ulang setiap kali (versi 4 menambah kolom "Waktu file masuk").
    s.tulis(rentang(TAB_RIWAYAT, "A1"), [[CATATAN], KOLOM_RIWAYAT])
    s.tambah_baris(TAB_RIWAYAT, [[
        waktu(), os.environ.get("GITHUB_SHA", "lokal"), os.environ.get("PEMICU", "manual"),
        "; ".join(f"{p['id']}:{p['versi_gaji']}" for p in periode), sum(len(p["orang"]) for p in periode), lama,
        UJI_TEKS_PANJANG, UJI_SAMA_DENGAN, os.environ.get("WAKTU_FILE", "")]])
    print(f"Lama isi (tanpa riwayat): {lama} ms; permintaan ke Google: {s.jumlah_permintaan}")


def status(kata):
    s = Sheets()
    if kata == "SELESAI":
        tulis_status(s, f"SELESAI {waktu()}, diperiksa sama dengan gudang")
    else:
        tulis_status(s, f"GAGAL {waktu()}, jangan dipakai")
    print("Status ditulis:", kata)


def main():
    try:
        if len(sys.argv) >= 2 and sys.argv[1] == "isi":
            isi()
        elif len(sys.argv) == 3 and sys.argv[1] == "status" and sys.argv[2] in ("SELESAI", "GAGAL"):
            status(sys.argv[2])
        else:
            print(__doc__)
            sys.exit(2)
    except Gagal as e:
        print("GAGAL:", e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
