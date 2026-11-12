-- Pemeriksaan setelah data simulasi Tahap 3 dimuat dan dibaca. Dipakai setelah pemasangan ke Supabase
-- dan di uji simulasi. Hanya membaca.
select uji.sama('tahap 3: 4 periode uji', (select count(*) from fakta.periode)::int, 4);
select uji.sama('tahap 3: koreksi jam mesin MA2 tercatat', (select count(*) from induk.koreksi_jam_mesin where mesin = 'MA2')::int, 1);
select uji.sama('tahap 3: 12 kiriman diterima (4 file lanjutan mesin kantor kosong, ditolak)',
  (select count(*) from fakta.kiriman_file where hasil = 'diterima')::int, 12);
select uji.sama('tahap 3: setiap periode punya hasil baca tap',
  (select count(*) from fakta.periode p where not exists (select 1 from hitung.versi_terakhir v where v.periode_id = p.id))::int, 0);
select uji.sama('tahap 3: setiap karyawan aktif punya hasil di setiap hari periode',
  (select count(*) from hitung.versi_terakhir v
   join fakta.periode p on p.id = v.periode_id
   cross join lateral generate_series(p.tanggal_awal::timestamp, p.tanggal_akhir::timestamp, interval '1 day') d
   join induk.status_kerja s on s.jenis = 'mulai' and s.tanggal <= d::date
   where not exists (select 1 from induk.status_kerja b where b.id_karyawan = s.id_karyawan and b.jenis = 'berhenti' and b.tanggal < d::date)
     and not exists (select 1 from hitung.hasil_harian h where h.versi_id = v.id and h.id_karyawan = s.id_karyawan and h.tanggal = d::date))::int, 0);
select uji.sama('tahap 3: tidak ada tap tanpa peran',
  (select count(*) from hitung.tap_bersih b join hitung.versi_terakhir v on v.id = b.versi_id where b.peran is null)::int, 0);
select uji.sama('tahap 3: hari tanpa tap massal 6 Feb (mesin kantor mati) sudah ditetapkan absen manual',
  (select bool_and(a.selesai) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id
   where a.jenis = 'tanpa_tap_massal' and a.tanggal = '2026-02-06'), true);
