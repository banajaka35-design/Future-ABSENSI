-- Data awal pemasangan demo: Pabrik A (simulasi). Struktur, kalender 2026, pengaturan, dan aturan dasar.
-- Bukan migrasi: ini isi untuk satu pemasangan. Angka aturan pemerintah sesuai PRD v3.1 bagian 8.
-- Tarif TER dan PTKP diisi di Tahap 4 bersama pengecekan sumber resminya.
-- Aman dijalankan sekali; dijalankan ulang akan ditolak oleh kunci unik dan aturan tumpang tindih.

begin;
set local app.pengguna = 'data-awal';

insert into induk.mesin (kode, nama, zona) values
  ('MA1', 'Gerbang pabrik', 'Asia/Jakarta'),
  ('MA2', 'Kantor', 'Asia/Jakarta');

insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('PRD', 'Produksi', 'rotasi', 4, 'MA1'),
  ('QC', 'Quality Control', 'rotasi', 4, 'MA1'),
  ('KAM', 'Keamanan', 'rotasi', 4, 'MA1'),
  ('GDG', 'Gudang dan Logistik', 'rotasi', 2, 'MA1'),
  ('KTR', 'Kantor', 'mingguan', 1, 'MA2');

insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit, istirahat_dibayar) values
  ('P', '07:00', '15:00', 60, false),
  ('S', '15:00', '23:00', 60, false),
  ('M', '23:00', '07:00', 60, false),
  ('K', '08:00', '16:00', 60, false),
  ('K5', '08:00', '13:00', 0, false),
  ('KR', '08:00', '15:00', 60, false),
  ('KR5', '08:00', '12:00', 0, false);

-- Rotasi 4 regu 8 hari: kode = siklus[((tanggal - jangkar) + geser_per_regu * regu) mod panjang + 1]
insert into induk.pola_rotasi (divisi, siklus, jangkar, geser_per_regu, berlaku_dari) values
  ('PRD', array['P', 'P', 'S', 'S', 'M', 'M', null, null], '2026-01-01', 2, '2026-01-01'),
  ('QC',  array['P', 'P', 'S', 'S', 'M', 'M', null, null], '2026-01-01', 2, '2026-01-01'),
  ('KAM', array['P', 'P', 'S', 'S', 'M', 'M', null, null], '2026-01-01', 2, '2026-01-01'),
  -- Gudang: 2 regu bergantian pagi dan siang tiap minggu, Minggu libur. Jangkar Senin 5 Jan 2026.
  ('GDG', array['P', 'P', 'P', 'P', 'P', 'P', null, 'S', 'S', 'S', 'S', 'S', 'S', null], '2026-01-05', 7, '2026-01-01');

-- Kantor: Senin-Jumat K, Sabtu K5, Minggu libur; Ramadan 19 Feb - 20 Mar 2026 memakai KR/KR5.
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari, berlaku_sampai)
select 'KTR', 0, h, case when h <= 5 then 'K' when h = 6 then 'K5' end, '2026-01-01', '2026-02-19'
from generate_series(1, 7) h;
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari, berlaku_sampai)
select 'KTR', 0, h, case when h <= 5 then 'KR' when h = 6 then 'KR5' end, '2026-02-19', '2026-03-21'
from generate_series(1, 7) h;
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select 'KTR', 0, h, case when h <= 5 then 'K' when h = 6 then 'K5' end, '2026-03-21'
from generate_series(1, 7) h;

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

-- Pengaturan Pabrik A (PRD bagian 11)
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values
  ('pola_hari_kerja', 'perusahaan', '6_hari_hari_pendek', '2026-01-01'),
  ('operasi_7_hari', 'PRD', 'ya', '2026-01-01'),
  ('operasi_7_hari', 'QC', 'ya', '2026-01-01'),
  ('operasi_7_hari', 'KAM', 'ya', '2026-01-01'),
  ('lembur', 'perusahaan', 'otomatis', '2026-01-01'),
  ('cuti_bersama', 'perusahaan', 'dibayar', '2026-01-01'),
  ('pembulatan_tunai', 'perusahaan', '1000', '2026-01-01'),
  ('premi_hadir', 'perusahaan', 'hidup', '2026-01-01'),
  ('tunjangan_shift_malam', 'perusahaan', 'hidup', '2026-01-01'),
  ('uang_makan', 'perusahaan', 'dihitung', '2026-01-01'),
  ('persetujuan_rilis', 'perusahaan', 'hrd_lalu_bos', '2026-01-01'),
  ('ambang_tanpa_tap_massal', 'perusahaan', '5000', '2026-01-01'),
  ('minimal_orang_tanpa_tap_massal', 'perusahaan', '3', '2026-01-01'),
  ('tanggal_tutup_buku', 'perusahaan', '20', '2026-01-01'),
  ('tanggal_gajian', 'perusahaan', '25', '2026-01-01'),
  ('kirim_rincian', 'perusahaan', 'otomatis', '2026-01-01');

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

commit;
