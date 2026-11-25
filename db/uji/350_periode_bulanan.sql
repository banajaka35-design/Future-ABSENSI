-- Uji paket P1 (docs/rencana-p1-periode.md): periode gaji berikutnya dibuat otomatis saat file mesin diterima.
-- Tanggal hari ini pura-pura lewat parameter p_hari_ini / app.hari_ini, supaya uji tidak bergantung pada tanggal sungguhan.
-- Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

-- Pengaturan seperti Pabrik A: tutup buku 20, gajian 25.
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values
  ('tanggal_tutup_buku', 'perusahaan', '20', '2026-01-01'),
  ('tanggal_gajian', 'perusahaan', '25', '2026-01-01');

-- Database tanpa periode: tidak membuat periode pertama.
select uji.sama('P1: tanpa periode sama sekali, tidak ada periode yang dibuat',
  fakta.buat_periode_sampai('2026-12-25', '2026-12-31')::text, '[]');

insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2026-11-21', '2026-12-20', '2026-12-25');

-- Fungsi tanggal.
select uji.sama('P1: tutup buku berikut 21 Des 2026 (tutup 20) = 20 Jan 2027', fakta.tutup_buku_berikut('2026-12-21'), date '2027-01-20');
select uji.sama('P1: tutup buku berikut 20 Jan 2027 = 20 Jan 2027 (hari tutup buku itu sendiri)', fakta.tutup_buku_berikut('2027-01-20'), date '2027-01-20');
select uji.sama('P1: gajian sesudah 20 Jan 2027 (gajian 25) = 25 Jan 2027', fakta.gajian_sesudah('2027-01-20'), date '2027-01-25');

-- Tap masih di dalam periode terakhir: tidak ada yang dibuat.
select uji.sama('P1: tap di dalam periode terakhir tidak membuat periode', fakta.buat_periode_sampai('2026-12-20', '2027-03-01')::text, '[]');
-- Batas hari ini: periode yang mulai sesudah hari ini tidak dibuat.
select uji.sama('P1: periode yang mulai sesudah hari ini (21 Des > 20 Des) tidak dibuat',
  fakta.buat_periode_sampai('2026-12-22', '2026-12-20')::text, '[]');

-- Tap 21 Des, hari ini 21 Des: periode no. berikut 21 Des 2026 - 20 Jan 2027, bayar 25 Jan 2027.
create temp table hasil_p1 (nama text primary key, isi jsonb) on commit drop;
insert into hasil_p1 values ('satu', fakta.buat_periode_sampai('2026-12-21', '2026-12-21', 'uji satu'));
select uji.sama('P1: satu periode baru dibuat', jsonb_array_length((select isi from hasil_p1 where nama = 'satu')), 1);
select uji.sama('P1: periode baru 21 Des 2026 - 20 Jan 2027, bayar 25 Jan 2027',
  (select concat_ws(' ', p.tanggal_awal, p.tanggal_akhir, p.tanggal_bayar, p.status) from fakta.periode p
   where p.id = ((select isi from hasil_p1 where nama = 'satu') -> 0 ->> 'id')::bigint),
  '2026-12-21 2027-01-20 2027-01-25 terbuka');
select uji.sama('P1: pembuatan periode tercatat di riwayat status periode beserta alasannya',
  (select concat_ws('|', r.status_lama, r.status_baru, r.oleh, r.alasan) from fakta.riwayat_status_periode r
   where r.periode_id = ((select isi from hasil_p1 where nama = 'satu') -> 0 ->> 'id')::bigint),
  'terbuka|uji-otomatis|uji satu');
select uji.sama('P1: periode lama tidak berubah',
  (select concat_ws(' ', tanggal_awal, tanggal_akhir, tanggal_bayar, status) from fakta.periode where tanggal_awal = '2026-11-21'),
  '2026-11-21 2026-12-20 2026-12-25 terbuka');

-- Jam mesin salah (tap tahun 2030): paling banyak 2 periode per panggilan.
insert into hasil_p1 values ('salah_tahun', fakta.buat_periode_sampai('2030-01-01', '2030-12-31'));
select uji.sama('P1: tap jauh di depan (2030) paling banyak membuat 2 periode',
  jsonb_array_length((select isi from hasil_p1 where nama = 'salah_tahun')), 2);
select uji.sama('P1: periode tetap berurutan tanpa celah (21 Jan - 20 Feb, 21 Feb - 20 Mar 2027)',
  (select string_agg(concat_ws('~', x ->> 'awal', x ->> 'akhir', x ->> 'bayar'), ' ' order by x ->> 'awal')
   from jsonb_array_elements((select isi from hasil_p1 where nama = 'salah_tahun')) x),
  '2027-01-21~2027-02-20~2027-02-25 2027-02-21~2027-03-20~2027-03-25');

-- Pengaturan bertanggal: mulai 1 Mar 2027 tutup buku akhir bulan, gajian tanggal 5.
update aturan.pengaturan set berlaku_sampai = '2027-03-01' where kunci in ('tanggal_tutup_buku', 'tanggal_gajian') and berlaku_sampai is null;
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values
  ('tanggal_tutup_buku', 'perusahaan', '0', '2027-03-01'),
  ('tanggal_gajian', 'perusahaan', '5', '2027-03-01');
insert into hasil_p1 values ('ganti_aturan', fakta.buat_periode_sampai('2027-04-15', '2027-04-30'));
select uji.sama('P1: sesudah pengaturan berganti, periode mengikuti pengaturan pada tanggal awalnya (21-31 Mar, lalu April penuh)',
  (select string_agg(concat_ws('~', x ->> 'awal', x ->> 'akhir', x ->> 'bayar'), ' ' order by x ->> 'awal')
   from jsonb_array_elements((select isi from hasil_p1 where nama = 'ganti_aturan')) x),
  '2027-03-21~2027-03-31~2027-04-05 2027-04-01~2027-04-30~2027-05-05');
select uji.sama('P1: tutup buku 0 = akhir bulan (Juni 2027 -> 30 Jun)', fakta.tutup_buku_berikut('2027-06-10'), date '2027-06-30');

-- Lewat jalur penerima file: periode baru dibuat dan masuk antrean hitung, kabar periode_baru terisi.
insert into induk.mesin (kode, nama) values ('MP1', 'Uji P1');
insert into induk.pengguna (telegram_id, peran) values (9351, 'hrd');
set local app.hari_ini = '2027-05-02';
insert into hasil_p1 values ('lewat_file', api.pintu_terima_file(jsonb_build_object(
  'update_id', 93501, 'telegram_id', 9351, 'nama_file', 'p1.csv', 'sidik', repeat('d', 64), 'mesin', 'MP1',
  'tap', '[["77", "2027-05-01 06:55:00", "Masuk", 2], ["77", "2027-05-02 15:05:00", "Keluar", 3]]'::jsonb)));
select uji.sama('P1: file diterima', (select isi ->> 'hasil' from hasil_p1 where nama = 'lewat_file'), 'diterima');
select uji.sama('P1: file berisi tap 1-2 Mei 2027 membuat periode Mei (1-31 Mei, bayar 5 Jun)',
  (select concat_ws('~', x ->> 'awal', x ->> 'akhir', x ->> 'bayar')
   from jsonb_array_elements((select isi -> 'periode_baru' from hasil_p1 where nama = 'lewat_file')) x),
  '2027-05-01~2027-05-31~2027-06-05');
select uji.sama('P1: periode baru masuk antrean hitung',
  (select count(*) from fakta.antrean_kerja a
   where a.periode_id = ((select isi -> 'periode_baru' -> 0 ->> 'id' from hasil_p1 where nama = 'lewat_file'))::bigint)::int, 1);
select uji.sama('P1: riwayat periode mencatat akun pengirim dan nomor kiriman',
  (select r.oleh || ' / ' || r.alasan from fakta.riwayat_status_periode r
   where r.periode_id = ((select isi -> 'periode_baru' -> 0 ->> 'id' from hasil_p1 where nama = 'lewat_file'))::bigint),
  'telegram:9351 / dibuat otomatis dari file mesin (kiriman no. ' || (select isi ->> 'kiriman_id' from hasil_p1 where nama = 'lewat_file') || ')');
-- File kedua di periode yang sudah ada: tidak membuat apa pun.
insert into hasil_p1 values ('file_kedua', api.pintu_terima_file(jsonb_build_object(
  'update_id', 93502, 'telegram_id', 9351, 'nama_file', 'p1b.csv', 'sidik', repeat('e', 64), 'mesin', 'MP1',
  'tap', '[["77", "2027-05-02 06:55:00", "Masuk", 2]]'::jsonb)));
select uji.sama('P1: file kedua di periode yang sudah ada tidak membuat periode', (select isi ->> 'periode_baru' from hasil_p1 where nama = 'file_kedua'), '[]');

rollback;
