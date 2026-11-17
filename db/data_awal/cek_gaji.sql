-- Pemeriksaan setelah hitung gaji (paket 4b-1). Dipakai setelah pemasangan ke Supabase dan di uji simulasi. Hanya membaca.
select uji.sama('gaji: setiap periode punya hasil hitung gaji dari baca tap terakhir',
  (select count(*) from fakta.periode p
   join hitung.versi_terakhir b on b.periode_id = p.id and b.jenis = 'baca_tap'
   where not exists (select 1 from hitung.versi_terakhir g where g.periode_id = p.id and g.jenis = 'hitung_gaji'
                       and g.versi_sumber = b.id))::int, 0);
select uji.sama('gaji: setiap orang di hasil harian punya ringkasan gaji',
  (select count(*) from (select distinct v.periode_id, h.id_karyawan from hitung.hasil_harian h
                         join hitung.versi_terakhir v on v.id = h.versi_id and v.jenis = 'baca_tap') x
   where not exists (select 1 from hitung.ringkasan_gaji g join hitung.versi_terakhir w on w.id = g.versi_id and w.jenis = 'hitung_gaji'
                     where w.periode_id = x.periode_id and g.id_karyawan = x.id_karyawan))::int, 0);
select uji.sama('gaji U3: gaji bersih tiap orang = jumlah rinciannya (versi terakhir)',
  (select count(*) from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
   where g.gaji_bersih <> (select sum(r.nominal) from hitung.rincian_gaji r
                           where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan and r.kelompok <> 'perusahaan'))::int, 0);
select uji.sama('gaji U3: total gaji bersih = total rincian per periode, selisih 0',
  (select count(*) from hitung.versi_terakhir v
   where v.jenis = 'hitung_gaji'
     and (select sum(gaji_bersih) from hitung.ringkasan_gaji where versi_id = v.id)
         <> (select sum(nominal) from hitung.rincian_gaji where versi_id = v.id and kelompok <> 'perusahaan'))::int, 0);
select uji.sama('gaji: tidak ada gaji bersih negatif',
  (select count(*) from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id where g.gaji_bersih < 0)::int, 0);
select uji.sama('gaji: versi gaji terakhir setiap periode memakai versi kode terbaru',
  (select count(*) from hitung.versi_terakhir v where v.jenis = 'hitung_gaji' and v.versi_kode <> hitung.versi_kode_gaji())::int, 0);
select uji.sama('gaji: dibayar + sisa = gaji bersih + sisa lalu',
  (select count(*) from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
   where g.dibayar + g.sisa_pembulatan <> g.gaji_bersih + g.sisa_lalu)::int, 0);
select uji.sama('anomali gaji (U10): daftar tanda bisa dibuat untuk setiap periode',
  (select count(*) from fakta.periode p cross join lateral (select count(*) from hitung.anomali_gaji(p.id)) x)::int,
  (select count(*) from fakta.periode)::int);
select uji.sama('anomali gaji (U10): setiap tanda berisi keterangan',
  (select count(*) from fakta.periode p cross join lateral hitung.anomali_gaji(p.id) a where a.keterangan is null)::int, 0);
select uji.sama('baca tap: versi baca tap terakhir setiap periode memakai versi kode terbaru',
  (select count(*) from hitung.versi_terakhir v where v.jenis = 'baca_tap' and v.versi_kode <> hitung.versi_kode_baca())::int, 0);
