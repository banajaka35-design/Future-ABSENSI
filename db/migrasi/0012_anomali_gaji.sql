-- 0012_anomali_gaji.sql
-- Paket 4b-4: tanda anomali sebelum rilis (U10). Aturan: docs/aturan-hitung-gaji.md versi 4 bagian O
-- (ditulis sebelum file ini). Tidak mengubah angka gaji; dihitung dari versi gaji terakhir, tidak disimpan.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

create function hitung.anomali_gaji(p_periode bigint)
returns table (jenis text, id_karyawan text, divisi text, nilai_lalu bigint, nilai_sekarang bigint, keterangan text)
language sql stable set search_path = '' as $$
  with ini as (
    select v.id as versi, p.tanggal_awal, v.versi_sumber
    from fakta.periode p
    join hitung.versi_terakhir v on v.periode_id = p.id and v.jenis = 'hitung_gaji'
    where p.id = p_periode
  ),
  -- O1: periode lalu = tanggal awal terbesar sebelum P yang punya versi gaji.
  lalu as (
    select v.id as versi
    from fakta.periode p
    join hitung.versi_terakhir v on v.periode_id = p.id and v.jenis = 'hitung_gaji'
    where p.tanggal_awal < (select tanggal_awal from ini)
    order by p.tanggal_awal desc
    limit 1
  ),
  banding as (
    select r.versi_id, r.id_karyawan,
           sum(r.nominal) filter (where r.kelompok = 'pendapatan' and r.komponen not in ('thr', 'pengembalian_pph21'))::bigint as nilai,
           coalesce(sum(r.nominal) filter (where r.komponen = 'lembur'), 0)::bigint as lembur
    from hitung.rincian_gaji r
    where r.versi_id in (select versi from ini union all select versi from lalu)
    group by r.versi_id, r.id_karyawan
  ),
  -- Divisi orang = divisi di hari terakhirnya di hasil harian periode itu (sumber baca tap versi gaji).
  divisi_orang as (
    select distinct on (v.id, h.id_karyawan) v.id as versi, h.id_karyawan, h.divisi
    from hitung.versi_hitung v
    join hitung.hasil_harian h on h.versi_id = v.versi_sumber
    where v.id in (select versi from ini union all select versi from lalu)
    order by v.id, h.id_karyawan, h.tanggal desc
  ),
  lembur_divisi as (
    select d.versi, d.divisi, sum(b.lembur)::bigint as lembur
    from divisi_orang d join banding b on b.versi_id = d.versi and b.id_karyawan = d.id_karyawan
    group by d.versi, d.divisi
  )
  -- O2: gaji berubah lebih dari 15%.
  select 'gaji_berubah', s.id_karyawan, null::text, l.nilai, s.nilai,
         format('Pendapatan tanpa THR berubah dari Rp%s menjadi Rp%s (%s%%)', l.nilai, s.nilai,
                round((s.nilai - l.nilai) * 100.0 / l.nilai, 1))
  from banding s
  join banding l on l.id_karyawan = s.id_karyawan and l.versi_id = (select versi from lalu)
  where s.versi_id = (select versi from ini) and l.nilai > 0 and abs(s.nilai - l.nilai) * 100 > 15 * l.nilai
  union all
  -- O3: lembur divisi naik lebih dari 30%.
  select 'lembur_divisi_naik', null, s.divisi, coalesce(l.lembur, 0), s.lembur,
         format('Lembur divisi %s naik dari Rp%s menjadi Rp%s', s.divisi, coalesce(l.lembur, 0), s.lembur)
  from lembur_divisi s
  left join lembur_divisi l on l.divisi = s.divisi and l.versi = (select versi from lalu)
  where s.versi = (select versi from ini) and exists (select 1 from lalu)
    and s.lembur * 100 > 130 * coalesce(l.lembur, 0)
  union all
  -- O4: gaji dibayar tanpa satu pun hari dengan tap mesin.
  select 'aktif_tanpa_tap', g.id_karyawan, d.divisi, null::bigint, g.gaji_bersih,
         format('%s digaji Rp%s tanpa satu pun tap mesin di periode ini (asal hari: %s)', g.id_karyawan, g.gaji_bersih,
                (select string_agg(distinct h.asal, ', ' order by h.asal) from hitung.hasil_harian h
                 where h.versi_id = (select versi_sumber from ini) and h.id_karyawan = g.id_karyawan))
  from hitung.ringkasan_gaji g
  join divisi_orang d on d.versi = g.versi_id and d.id_karyawan = g.id_karyawan
  where g.versi_id = (select versi from ini) and g.gaji_bersih > 0
    and not exists (select 1 from hitung.hasil_harian h
                    where h.versi_id = (select versi_sumber from ini) and h.id_karyawan = g.id_karyawan and h.asal = 'mesin')
$$;
