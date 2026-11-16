-- Data aturan resmi (pemerintah), bukan aturan perusahaan. Sumber dan tanggal cek: docs/cek-aturan-hukum.md.
-- Aman dijalankan berulang: baris yang sudah ada dilewati. Dijalankan setiap pemasangan, sesudah struktur Pabrik A.
-- Baris bertanggal tidak boleh diubah, hanya ditutup (aturan dasar 4); koreksi = tutup baris lama + baris baru.

-- ---------------------------------------------------------------------------
-- Kalender 2027: SKB Menteri Agama, Menteri Ketenagakerjaan, Menteri PANRB
-- No. 1205, 3, dan 2 Tahun 2026 (15 Sep 2026). 18 hari libur nasional, 8 hari cuti bersama.
-- ---------------------------------------------------------------------------
insert into induk.kalender (tanggal, jenis, keterangan) values
  ('2027-01-01', 'libur_nasional', 'Tahun Baru Masehi'),
  ('2027-01-05', 'libur_nasional', 'Isra Mikraj'),
  ('2027-02-05', 'cuti_bersama', 'Cuti bersama Imlek'),
  ('2027-02-06', 'libur_nasional', 'Tahun Baru Imlek'),
  ('2027-03-08', 'libur_nasional', 'Hari Suci Nyepi'),
  ('2027-03-09', 'cuti_bersama', 'Cuti bersama Idul Fitri'),
  ('2027-03-10', 'libur_nasional', 'Idul Fitri'),
  ('2027-03-11', 'libur_nasional', 'Idul Fitri'),
  ('2027-03-12', 'cuti_bersama', 'Cuti bersama Idul Fitri'),
  ('2027-03-15', 'cuti_bersama', 'Cuti bersama Idul Fitri'),
  ('2027-03-25', 'cuti_bersama', 'Cuti bersama Wafat Yesus Kristus'),
  ('2027-03-26', 'libur_nasional', 'Wafat Yesus Kristus'),
  ('2027-03-28', 'libur_nasional', 'Paskah'),
  ('2027-05-01', 'libur_nasional', 'Hari Buruh'),
  ('2027-05-06', 'libur_nasional', 'Kenaikan Yesus Kristus'),
  ('2027-05-17', 'libur_nasional', 'Idul Adha'),
  ('2027-05-18', 'cuti_bersama', 'Cuti bersama Idul Adha'),
  ('2027-05-19', 'cuti_bersama', 'Cuti bersama Waisak'),
  ('2027-05-20', 'libur_nasional', 'Hari Raya Waisak'),
  ('2027-06-01', 'libur_nasional', 'Hari Lahir Pancasila'),
  ('2027-06-06', 'libur_nasional', 'Tahun Baru Islam'),
  ('2027-08-15', 'libur_nasional', 'Maulid Nabi Muhammad SAW'),
  ('2027-08-17', 'libur_nasional', 'Hari Kemerdekaan'),
  ('2027-12-24', 'cuti_bersama', 'Cuti bersama Natal'),
  ('2027-12-25', 'libur_nasional', 'Natal'),
  ('2027-12-26', 'libur_nasional', 'Isra Mikraj')
on conflict (tanggal, jenis) do nothing;

-- ---------------------------------------------------------------------------
-- Batas upah Jaminan Pensiun (PP 45/2015 Pasal 29; ditetapkan BPJS Ketenagakerjaan tiap Maret).
--   Mar 2025 - Feb 2026: Rp10.547.400 (surat BPJS Ketenagakerjaan Feb 2025)
--   sejak 1 Mar 2026  : Rp11.086.300 (surat BPJS Ketenagakerjaan B/1226/022026, 25 Feb 2026)
-- Data awal lama mencatat 10.547.000 sejak 1 Jan 2026 tanpa akhir (salah). Baris itu ditutup
-- sedini yang diizinkan (sehari sesudah mulai berlaku), jadi tanggal 1 Jan 2026 saja yang masih
-- memakai angka lama (selisih Rp400 pada batas, Rp4 pada iuran JP karyawan). Dicatat di serah terima.
-- ---------------------------------------------------------------------------
update aturan.bpjs set berlaku_sampai = '2026-01-02'
where program = 'jp' and batas_atas = 10547000 and berlaku_dari = '2026-01-01' and berlaku_sampai is null;

insert into aturan.bpjs (program, bagian, persen, batas_atas, berlaku_dari, berlaku_sampai)
select v.program, v.bagian, v.persen, v.batas_atas, v.berlaku_dari::date, v.berlaku_sampai::date
from (values
  ('jp', 'karyawan',   100, 10547400, '2025-03-01', '2026-01-01'),
  ('jp', 'perusahaan', 200, 10547400, '2025-03-01', '2026-01-01'),
  ('jp', 'karyawan',   100, 10547400, '2026-01-02', '2026-03-01'),
  ('jp', 'perusahaan', 200, 10547400, '2026-01-02', '2026-03-01'),
  ('jp', 'karyawan',   100, 11086300, '2026-03-01', null),
  ('jp', 'perusahaan', 200, 11086300, '2026-03-01', null)
) as v(program, bagian, persen, batas_atas, berlaku_dari, berlaku_sampai)
where not exists (
  select 1 from aturan.bpjs b
  where b.program = v.program and b.bagian = v.bagian and b.berlaku_dari = v.berlaku_dari::date);
