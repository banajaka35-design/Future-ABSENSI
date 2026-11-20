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
-- F15c (paket G1-2, permintaan perubahan 05): rahasia per periode. Gaji satu periode disembunyikan bila orang itu
-- rahasia pada hari mana pun di periode itu, atau rahasia sekarang (status terakhir).
-- Semua periode yang punya versi gaji (sama dengan pilihan "periode lalu" di hitung.anomali_gaji), dengan versi lalu.
per as (
  select p.id as periode_id, p.tanggal_awal, p.tanggal_akhir, g.id as versi_gaji,
         lag(g.id) over (order by p.tanggal_awal) as versi_lalu
  from fakta.periode p join hitung.versi_terakhir g on g.periode_id = p.id and g.jenis = 'hitung_gaji'
),
rahasia as (
  select v.versi_gaji, k.id as id_karyawan,
         (exists (select 1 from induk.karyawan_riwayat r
                  where r.id_karyawan = k.id and r.gaji_rahasia
                    and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') && daterange(v.tanggal_awal, v.tanggal_akhir, '[]'))
          or coalesce((select r.gaji_rahasia from induk.karyawan_riwayat r where r.id_karyawan = k.id
                       order by r.berlaku_dari desc limit 1), false)) as gaji_rahasia
  from per v cross join induk.karyawan k
),
terlihat as (
  select g.* from hitung.ringkasan_gaji g
  left join rahasia s on s.versi_gaji = g.versi_id and s.id_karyawan = g.id_karyawan
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
  from per v join hitung.versi_hitung x on x.id = v.versi_gaji
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
      'rahasia', (select count(*) from hitung.ringkasan_gaji g join rahasia s on s.versi_gaji = g.versi_id and s.id_karyawan = g.id_karyawan
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
      -- Paket G1: grafik. Rupiah tanpa orang rahasia; potongan sebagai angka positif.
      'divisi_biaya', (select coalesce(json_agg(json_build_object(
            'divisi', x.divisi, 'orang', x.orang, 'rahasia', x.rahasia, 'pokok', x.pokok, 'lembur', x.lembur,
            'pot_hari', x.pot_hari, 'pot_lain', x.pot_lain, 'bersih', x.bersih) order by x.divisi), '[]'::json)
          from (select coalesce(d.divisi, '-') as divisi,
                       count(*) filter (where not coalesce(s.gaji_rahasia, false)) as orang,
                       count(*) filter (where coalesce(s.gaji_rahasia, false)) as rahasia,
                       coalesce(sum(k.pokok) filter (where not coalesce(s.gaji_rahasia, false)), 0) as pokok,
                       coalesce(sum(k.lembur) filter (where not coalesce(s.gaji_rahasia, false)), 0) as lembur,
                       coalesce(sum(k.pot_hari) filter (where not coalesce(s.gaji_rahasia, false)), 0) as pot_hari,
                       coalesce(sum(k.pot_lain) filter (where not coalesce(s.gaji_rahasia, false)), 0) as pot_lain,
                       coalesce(sum(g.gaji_bersih) filter (where not coalesce(s.gaji_rahasia, false)), 0) as bersih
                from hitung.ringkasan_gaji g
                left join rahasia s on s.versi_gaji = g.versi_id and s.id_karyawan = g.id_karyawan
                left join divisi d on d.versi_gaji = g.versi_id and d.id_karyawan = g.id_karyawan
                left join lateral (
                  select sum(r.nominal) filter (where r.komponen = 'gaji_pokok') as pokok,
                         sum(r.nominal) filter (where r.komponen = 'lembur') as lembur,
                         -sum(r.nominal) filter (where r.komponen = 'potongan_tidak_dibayar') as pot_hari,
                         -sum(r.nominal) filter (where r.kelompok = 'potongan') as pot_lain
                  from hitung.rincian_gaji r where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan) k on true
                where g.versi_id = v.versi_gaji
                group by 1) x),
      'telat', (select json_agg(json_build_array(h.tgl, h.n) order by h.tgl)
          from (select gs::date as tgl,
                       (select count(*) from hitung.hasil_harian h2 join hitung.versi_hitung x on x.id = v.versi_gaji
                        where h2.versi_id = x.versi_sumber and h2.tanggal = gs::date
                          and h2.status = 'hadir' and h2.menit_telat > 0) as n
                from generate_series(v.tanggal_awal, v.tanggal_akhir, interval '1 day') gs) h),
      'thr', (select coalesce(sum(r.nominal), 0) from terlihat g join hitung.rincian_gaji r
              on r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan and r.komponen = 'thr'
              where g.versi_id = v.versi_gaji),
      'bisa_diajukan', hitung.periode_bisa_diajukan(v.periode_id),
      'status_rilis', fakta.status_rilis_teks(v.periode_id),
      'tertahan', (select count(*) from terlihat g where g.versi_id = v.versi_gaji
                   and 'pph_masa_terakhir_tertahan' = any(g.peringatan)),
      'anomali', coalesce((select json_agg(json_build_object('jenis', a.jenis, 'id', a.id_karyawan, 'divisi', a.divisi,
                                                             -- F15c: tanda membandingkan periode ini dengan periode lalu,
                                                             -- jadi disembunyikan bila rahasia di salah satunya.
                                                             'ket', case when exists (
                                                                           select 1 from rahasia s
                                                                           where s.id_karyawan = a.id_karyawan and s.gaji_rahasia
                                                                             and s.versi_gaji in (v.versi_gaji, (select q.versi_lalu from per q where q.versi_gaji = v.versi_gaji)))
                                                                         then null
                                                                         -- 6a-4: divisi yang memuat orang rahasia tanpa angka
                                                                         when a.id_karyawan is null and exists (
                                                                           select 1 from divisi d join rahasia r2 on r2.versi_gaji = d.versi_gaji and r2.id_karyawan = d.id_karyawan
                                                                           where d.versi_gaji in (v.versi_gaji, (select q.versi_lalu from per q where q.versi_gaji = v.versi_gaji))
                                                                             and d.divisi = a.divisi
                                                                             and r2.gaji_rahasia)
                                                                         then format('Divisi %s: angka tidak ditampilkan karena divisi ini memuat gaji rahasia',
                                                                                     a.divisi)
                                                                         else a.keterangan end)
                                           order by a.jenis, a.id_karyawan, a.divisi)
                           from hitung.anomali_gaji(v.periode_id) a),
                          '[]'::json)
    ) order by v.tanggal_awal) from ver v),
  'karyawan', (select json_agg(json_build_object(
      'id', k.id, 'nama', k.nama,
      'rahasia', coalesce((select bool_or(s.gaji_rahasia) from rahasia s where s.id_karyawan = k.id), false),
      -- p: {periode: [divisi, gaji bersih (null bila rahasia), cara bayar]} (cara bayar: paket G1)
      'p', (select json_object_agg(v.periode_id, json_build_array(d.divisi,
                      case when coalesce(s.gaji_rahasia, false) then null else g.gaji_bersih end, c.cara_bayar))
            from ver v join hitung.ringkasan_gaji g on g.versi_id = v.versi_gaji and g.id_karyawan = k.id
            left join rahasia s on s.versi_gaji = v.versi_gaji and s.id_karyawan = k.id
            left join divisi d on d.versi_gaji = v.versi_gaji and d.id_karyawan = k.id
            left join cara c on c.versi_gaji = v.versi_gaji and c.id_karyawan = k.id)) order by k.id)
    from induk.karyawan k
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
      left join rahasia s on s.versi_gaji = g.versi_id and s.id_karyawan = g.id_karyawan
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
        # Paket G1: isi amplop per orang tunai (bukan rahasia; orang rahasia tidak ada di rincian).
        for r in (rincian.get(str(p["id"])) or {}).values():
            if r.get("cara") == "tunai":
                s, amp = max(r["dibayar"], 0), []
                for n in nilai:
                    amp.append(s // n)
                    s %= n
                r["amplop"] = [[n, x] for n, x in zip(nilai, amp)]
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
