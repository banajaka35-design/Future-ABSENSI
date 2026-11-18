"""Membuat file data halaman demo (web/demo/data.json) dari gudang, hanya versi terakhir.

Halaman demo tidak menyentuh database; file ini dibuat oleh GitHub Actions lalu ikut diunggah
(docs/halaman-demo.md). Hanya pustaka bawaan Python dan psql.
Keluaran: <folder>/data.json (ringkasan, daftar karyawan) dan <folder>/rincian_<periode>.json.
Pemakaian: DB_URL=... python3 web/buat_data.py [folder_keluaran]
"""
import json
import os
import subprocess
import sys

SQL = r"""
with ver as (
  select p.id as periode_id, p.tanggal_awal, p.tanggal_akhir, p.tanggal_bayar, g.id as versi_gaji, g.versi_kode as kode_gaji,
         b.versi_kode as kode_baca
  from fakta.periode p
  join hitung.versi_terakhir g on g.periode_id = p.id and g.jenis = 'hitung_gaji'
  join hitung.versi_terakhir b on b.periode_id = p.id and b.jenis = 'baca_tap'
),
rahasia as (
  select distinct on (r.id_karyawan) r.id_karyawan, r.gaji_rahasia
  from induk.karyawan_riwayat r order by r.id_karyawan, r.berlaku_dari desc
),
terlihat as (
  select g.* from hitung.ringkasan_gaji g left join rahasia s on s.id_karyawan = g.id_karyawan
  where not coalesce(s.gaji_rahasia, false)
),
cara as (
  select v.versi_gaji, g.id_karyawan, r.cara_bayar
  from ver v join hitung.ringkasan_gaji g on g.versi_id = v.versi_gaji
  join induk.karyawan_riwayat r on r.id_karyawan = g.id_karyawan
   and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v.tanggal_akhir
),
divisi as (
  select distinct on (v.versi_gaji, h.id_karyawan) v.versi_gaji, h.id_karyawan, h.divisi
  from ver v join hitung.versi_hitung x on x.id = v.versi_gaji
  join hitung.hasil_harian h on h.versi_id = x.versi_sumber
  order by v.versi_gaji, h.id_karyawan, h.tanggal desc
)
select json_build_object(
  'dibuat', to_char(now() at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI') || ' WIB',
  'periode', (select json_agg(json_build_object(
      'id', v.periode_id, 'awal', v.tanggal_awal, 'akhir', v.tanggal_akhir, 'bayar', v.tanggal_bayar,
      'kode_baca', v.kode_baca, 'kode_gaji', v.kode_gaji,
      -- F15b (paket 6a-3): total untuk HRD tanpa orang rahasia; total - jumlah per orang yang tampil = 0.
      'orang', (select count(*) from terlihat g where g.versi_id = v.versi_gaji),
      'rahasia', (select count(*) from hitung.ringkasan_gaji g join rahasia s on s.id_karyawan = g.id_karyawan
                  where g.versi_id = v.versi_gaji and s.gaji_rahasia),
      'pendapatan', (select coalesce(sum(total_pendapatan), 0) from terlihat g where g.versi_id = v.versi_gaji),
      'potongan', (select coalesce(sum(total_potongan), 0) from terlihat g where g.versi_id = v.versi_gaji),
      'bersih', (select coalesce(sum(gaji_bersih), 0) from terlihat g where g.versi_id = v.versi_gaji),
      'dibayar', (select coalesce(sum(dibayar), 0) from terlihat g where g.versi_id = v.versi_gaji),
      'sisa', (select coalesce(sum(sisa_pembulatan), 0) from terlihat g where g.versi_id = v.versi_gaji),
      'transfer', (select coalesce(sum(g.dibayar), 0) from terlihat g join cara c on c.versi_gaji = g.versi_id
                   and c.id_karyawan = g.id_karyawan where g.versi_id = v.versi_gaji and c.cara_bayar = 'transfer'),
      'tunai', (select coalesce(sum(g.dibayar), 0) from terlihat g join cara c on c.versi_gaji = g.versi_id
                and c.id_karyawan = g.id_karyawan where g.versi_id = v.versi_gaji and c.cara_bayar = 'tunai'),
      'nilai_pecahan', (select json_agg(t.pecahan order by t.pecahan desc) from hitung.pecahan_tunai(v.versi_gaji) t),
      'dibayar_tunai', (select coalesce(json_agg(g.dibayar), '[]'::json) from terlihat g join cara c on c.versi_gaji = g.versi_id
                        and c.id_karyawan = g.id_karyawan where g.versi_id = v.versi_gaji and c.cara_bayar = 'tunai'),
      'bisa_diajukan', hitung.periode_bisa_diajukan(v.periode_id),
      'tertahan', (select count(*) from terlihat g where g.versi_id = v.versi_gaji
                   and 'pph_masa_terakhir_tertahan' = any(g.peringatan)),
      'anomali', coalesce((select json_agg(json_build_object('jenis', a.jenis, 'id', a.id_karyawan, 'divisi', a.divisi,
                                                             'ket', case when coalesce(s.gaji_rahasia, false) then null
                                                                         -- 6a-4: divisi yang memuat orang rahasia tanpa angka
                                                                         when a.id_karyawan is null and exists (
                                                                           select 1 from divisi d join rahasia r2 on r2.id_karyawan = d.id_karyawan
                                                                           where d.versi_gaji = v.versi_gaji and d.divisi = a.divisi
                                                                             and r2.gaji_rahasia)
                                                                         then format('Divisi %s: angka tidak ditampilkan karena divisi ini memuat gaji rahasia',
                                                                                     a.divisi)
                                                                         else a.keterangan end)
                                           order by a.jenis, a.id_karyawan, a.divisi)
                           from hitung.anomali_gaji(v.periode_id) a left join rahasia s on s.id_karyawan = a.id_karyawan),
                          '[]'::json)
    ) order by v.tanggal_awal) from ver v),
  'karyawan', (select json_agg(json_build_object(
      'id', k.id, 'nama', k.nama, 'rahasia', coalesce(s.gaji_rahasia, false),
      'p', (select json_object_agg(v.periode_id, json_build_array(d.divisi,
                      case when coalesce(s.gaji_rahasia, false) then null else g.gaji_bersih end))
            from ver v join hitung.ringkasan_gaji g on g.versi_id = v.versi_gaji and g.id_karyawan = k.id
            left join divisi d on d.versi_gaji = v.versi_gaji and d.id_karyawan = k.id)) order by k.id)
    from induk.karyawan k left join rahasia s on s.id_karyawan = k.id
    where exists (select 1 from ver v join hitung.ringkasan_gaji g on g.versi_id = v.versi_gaji and g.id_karyawan = k.id)),
  -- Rincian per periode (dipisah per file supaya halaman awal kecil); orang rahasia tidak ikut.
  'rincian', (select json_object_agg(v.periode_id, (
      select json_object_agg(g.id_karyawan, json_build_object(
               'cara', c.cara_bayar, 'bersih', g.gaji_bersih, 'dibayar', g.dibayar, 'sisa', g.sisa_pembulatan,
               'sisa_lalu', g.sisa_lalu, 'cuti', g.cuti_terpakai, 'saldo_cuti', g.saldo_cuti, 'peringatan', g.peringatan,
               'rincian', (select json_agg(json_build_array(r.komponen, r.kelompok, r.nominal, r.bukti)
                                           order by r.kelompok desc, r.komponen)
                           from hitung.rincian_gaji r where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan)))
      from hitung.ringkasan_gaji g
      left join cara c on c.versi_gaji = g.versi_id and c.id_karyawan = g.id_karyawan
      left join rahasia s on s.id_karyawan = g.id_karyawan
      where g.versi_id = v.versi_gaji and not coalesce(s.gaji_rahasia, false))) from ver v)
)
"""


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "demo")
    hasil = subprocess.run(["psql", os.environ["DB_URL"], "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c", SQL],
                           check=True, capture_output=True, text=True).stdout
    data = json.loads(hasil)
    rincian = data.pop("rincian") or {}
    # Pecahan tunai tanpa orang rahasia (F15b): amplop orang tunai yang tampil, dipecah dari pecahan terbesar.
    for p in data["periode"]:
        nilai = p.pop("nilai_pecahan") or []
        lembar = [0] * len(nilai)
        for d in p.pop("dibayar_tunai"):
            s = max(d, 0)
            for i, n in enumerate(nilai):
                lembar[i] += s // n
                s %= n
        p["pecahan"] = [[n, l] for n, l in zip(nilai, lembar)]
    os.makedirs(folder, exist_ok=True)
    tulis = [("data.json", data)] + [(f"rincian_{pid}.json", isi or {}) for pid, isi in rincian.items()]
    for nama, isi in tulis:
        jalur = os.path.join(folder, nama)
        with open(jalur, "w", encoding="utf-8") as f:
            json.dump(isi, f, ensure_ascii=False, separators=(",", ":"))
        print(f"{jalur}: {os.path.getsize(jalur):,} byte")
    print(f"{len(data['periode'])} periode, {len(data['karyawan'])} karyawan")


if __name__ == "__main__":
    main()
