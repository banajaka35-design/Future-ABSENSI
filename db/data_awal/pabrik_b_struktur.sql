-- Data awal pemasangan uji Pabrik B (simulasi, 180 karyawan). Dipakai uji U5: Pabrik A dan B dengan kode yang sama.
-- Bukan migrasi dan tidak dipasang ke Supabase (satu database untuk satu perusahaan; demo Supabase berisi Pabrik A).
-- Struktur dari docs/data-simulasi.md. Angka aturan pemerintah sama dengan Pabrik A.
-- Pilihan yang tidak disebut generator (tebakan, data karangan): tutup buku akhir bulan, gajian tanggal 5 bulan berikutnya,
-- UMK sama dengan Pabrik A, komponen tidak tetap sama dengan Pabrik A.

begin;
set local app.pengguna = 'data-awal';

insert into induk.mesin (kode, nama, zona) values ('MB1', 'Pabrik B', 'Asia/Jakarta');

insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('PRD', 'Produksi', 'rotasi', 2, 'MB1'),
  ('GDG', 'Gudang', 'rotasi', 2, 'MB1'),
  ('KTR', 'Kantor', 'mingguan', 1, 'MB1'),
  ('KAM', 'Keamanan', 'rotasi', 4, 'MB1');

insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit, istirahat_dibayar) values
  ('P', '07:00', '15:00', 60, false),
  ('S', '15:00', '23:00', 60, false),
  ('M', '23:00', '07:00', 60, false),
  ('K', '08:00', '16:00', 60, false);

-- Rotasi: kode = siklus[((tanggal - jangkar) + geser_per_regu * regu) mod panjang + 1]
insert into induk.pola_rotasi (divisi, siklus, jangkar, geser_per_regu, berlaku_dari) values
  -- Produksi: 2 regu bergantian pagi dan siang tiap minggu, Senin-Jumat. Jangkar Senin 5 Jan 2026.
  ('PRD', array['P', 'P', 'P', 'P', 'P', null, null, 'S', 'S', 'S', 'S', 'S', null, null], '2026-01-05', 7, '2026-01-01'),
  -- Gudang: 2 regu bergantian pagi dan siang tiap minggu, Senin-Sabtu.
  ('GDG', array['P', 'P', 'P', 'P', 'P', 'P', null, 'S', 'S', 'S', 'S', 'S', 'S', null], '2026-01-05', 7, '2026-01-01'),
  -- Keamanan: rotasi 4 regu 8 hari.
  ('KAM', array['P', 'P', 'S', 'S', 'M', 'M', null, null], '2026-01-01', 2, '2026-01-01');

-- Kantor: Senin-Jumat K.
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select 'KTR', 0, h, case when h <= 5 then 'K' end, '2026-01-01' from generate_series(1, 7) h;

-- Kalender 2026 (SKB 3 Menteri, dicek 12 Nov 2026)
insert into induk.kalender (tanggal, jenis, keterangan) values
  ('2026-01-01', 'libur_nasional', 'Tahun Baru Masehi'),
  ('2026-01-16', 'libur_nasional', 'Isra Mikraj'),
  ('2026-02-16', 'cuti_bersama', 'Cuti bersama Imlek'),
  ('2026-02-17', 'libur_nasional', 'Tahun Baru Imlek'),
  ('2026-03-18', 'cuti_bersama', 'Cuti bersama Nyepi'),
  ('2026-03-19', 'libur_nasional', 'Hari Suci Nyepi'),
  ('2026-03-20', 'cuti_bersama', 'Cuti bersama Idul Fitri'),
  ('2026-03-21', 'libur_nasional', 'Idul Fitri'),
  ('2026-03-22', 'libur_nasional', 'Idul Fitri'),
  ('2026-03-23', 'cuti_bersama', 'Cuti bersama Idul Fitri'),
  ('2026-03-24', 'cuti_bersama', 'Cuti bersama Idul Fitri'),
  ('2026-04-03', 'libur_nasional', 'Wafat Yesus Kristus'),
  ('2026-04-05', 'libur_nasional', 'Paskah'),
  ('2026-05-01', 'libur_nasional', 'Hari Buruh'),
  ('2026-05-14', 'libur_nasional', 'Kenaikan Yesus Kristus'),
  ('2026-05-15', 'cuti_bersama', 'Cuti bersama Kenaikan Yesus Kristus'),
  ('2026-05-27', 'libur_nasional', 'Idul Adha'),
  ('2026-05-28', 'cuti_bersama', 'Cuti bersama Idul Adha'),
  ('2026-08-17', 'libur_nasional', 'Hari Kemerdekaan'),
  ('2026-08-25', 'libur_nasional', 'Maulid Nabi Muhammad SAW'),
  ('2026-12-24', 'cuti_bersama', 'Cuti bersama Natal'),
  ('2026-12-25', 'libur_nasional', 'Natal');

-- Pengaturan Pabrik B
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari, berlaku_sampai) values
  ('pola_hari_kerja', 'perusahaan', '5_hari', '2026-01-01', null),
  ('pola_hari_kerja', 'GDG', '6_hari_hari_pendek', '2026-01-01', null),
  ('operasi_7_hari', 'KAM', 'ya', '2026-01-01', null),
  ('lembur', 'perusahaan', 'wajib_perintah', '2026-01-01', null),
  -- Permintaan perubahan 01 (disetujui 16 Nov 2026): potong cuti hanya sampai sebelum UU 27/2026 berlaku.
  ('cuti_bersama', 'perusahaan', 'potong_cuti', '2026-01-01', '2026-10-28'),
  ('cuti_bersama', 'perusahaan', 'dibayar', '2026-10-28', null),
  ('pembulatan_tunai', 'perusahaan', '1000', '2026-01-01', null),
  ('premi_hadir', 'perusahaan', 'hidup', '2026-01-01', null),
  ('tunjangan_shift_malam', 'perusahaan', 'hidup', '2026-01-01', null),
  ('uang_makan', 'perusahaan', 'dihitung', '2026-01-01', null),
  ('persetujuan_rilis', 'perusahaan', 'hrd', '2026-01-01', null),
  ('ambang_tanpa_tap_massal', 'perusahaan', '5000', '2026-01-01', null),
  ('minimal_orang_tanpa_tap_massal', 'perusahaan', '3', '2026-01-01', null),
  ('tanggal_tutup_buku', 'perusahaan', '0', '2026-01-01', null),
  ('tanggal_gajian', 'perusahaan', '5', '2026-01-01', null),
  ('kirim_rincian', 'perusahaan', 'otomatis', '2026-01-01', null);

-- Aturan uji v0 (kasus jebakan) sebagai nilai awal
insert into aturan.jendela_tap (menit_sebelum_masuk, menit_sesudah_pulang, jarak_minimal_menit, berlaku_dari)
values (120, 360, 60, '2026-01-01');
insert into aturan.toleransi (telat_menit, pulang_cepat_menit, berlaku_dari) values (5, 0, '2026-01-01');
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari)
values (60, 30, 'bawah', 'penuh', '2026-01-01');

-- Pengali lembur PP 35/2021 pasal 31, disimpan x10
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j
union all
select 'libur_6_hari', j, case when j <= 7 then 20 when j = 8 then 30 else 40 end, date '2021-02-02' from generate_series(1, 11) j
union all
select 'libur_6_hari_terpendek', j, case when j <= 5 then 20 when j = 6 then 30 else 40 end, date '2021-02-02' from generate_series(1, 9) j
union all
select 'libur_5_hari', j, case when j <= 8 then 20 when j = 9 then 30 else 40 end, date '2021-02-02' from generate_series(1, 12) j;

-- BPJS (persen per-sepuluh-ribu). Batas atas JP adalah angka 2025 dan masih perlu dicek untuk 2026.
insert into aturan.bpjs (program, bagian, persen, batas_atas, berlaku_dari) values
  ('kesehatan', 'karyawan', 100, 12000000, '2026-01-01'),
  ('kesehatan', 'perusahaan', 400, 12000000, '2026-01-01'),
  ('jht', 'karyawan', 200, null, '2026-01-01'),
  ('jht', 'perusahaan', 370, null, '2026-01-01'),
  ('jp', 'karyawan', 100, 10547000, '2026-01-01'),
  ('jp', 'perusahaan', 200, 10547000, '2026-01-01'),
  ('jkk', 'perusahaan', 24, null, '2026-01-01'),
  ('jkm', 'perusahaan', 30, null, '2026-01-01');

insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into aturan.thr (tanggal_bayar, hari_raya, cara_prorata, berlaku_dari) values ('2026-03-14', '2026-03-21', 'bulan_penuh', '2026-01-01');
insert into aturan.cuti (jatah_hari, berlaku_setelah_bulan, berlaku_dari) values (12, 12, '2026-01-01');
insert into aturan.batas_potongan (persen, komponen, berlaku_dari) values (5000, array['denda', 'kasbon', 'ganti_rugi'], '2026-01-01');

-- Komponen lain: nominal contoh untuk simulasi
insert into aturan.komponen_lain (kode, nominal, satuan, sifat, syarat, berlaku_dari) values
  ('uang_makan', 15000, 'per_hari', 'tidak_tetap', 'Hadir dan tidak telat lebih dari 60 menit', '2026-01-01'),
  ('premi_hadir', 100000, 'per_periode', 'tidak_tetap', 'Tanpa alpha dan tanpa telat dalam satu periode', '2026-01-01'),
  ('tunjangan_shift_malam', 10000, 'per_hari', 'tidak_tetap', 'Hadir di shift malam', '2026-01-01');

-- Empat periode uji (bulan kalender), gajian tanggal 5 bulan berikutnya.
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-02-01', '2026-02-28', '2026-03-05'),
  ('2026-03-01', '2026-03-31', '2026-04-05'),
  ('2026-04-01', '2026-04-30', '2026-05-05'),
  ('2026-12-01', '2026-12-31', '2027-01-05');

commit;
