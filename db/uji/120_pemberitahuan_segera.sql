-- Uji paket 5c: pemberitahuan tingkat segera (U14) dan pengingat kirim file (docs/pemberitahuan-segera.md,
-- kasus N1-N3, N7-N9, P1-P6). Alur lewat pesan Telegram tiruan (N4-N6, P7, S1) ada di sistem/pintu/.
-- Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang'), ('MA2', 'Kantor');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2026-10-21', '2026-11-20', '2026-11-25');
insert into induk.pengguna (telegram_id, peran) values
  (111, 'hrd'), (444, 'pembangun'), (222, 'karyawan'), (333, 'hrd');
update induk.pengguna set aktif = false where telegram_id = 333;
insert into induk.pengguna (telegram_id, peran) values (null, 'hrd');

-- Hasil baca tap tiruan: versi 1 dengan lima anomali segera, satu yang sudah selesai, satu tingkat harian.
insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
select id, 'baca_tap', 1, 'uji', 'a', 'b' from fakta.periode;
create temp table anomali_uji as
select * from (values
  ('file_terpotong', 'segera', 'MA1', null, null, 'File MA1 kemungkinan terpotong: 3/8', false),
  ('tap_terakhir_lama', 'segera', 'MA2', null, null, 'Tap terakhir MA2 lama', false),
  ('jam_mesin_melenceng', 'segera', 'MA1', null, null, 'Jam MA1 melenceng', false),
  ('tanpa_tap_massal', 'segera', null, 'KTR', null, 'KTR tanpa tap', false),
  ('belum_terdaftar_mesin', 'segera', null, 'PRD', 'K9', 'K9 belum terdaftar', false),
  ('tanpa_tap_massal', 'segera', null, 'GDG', null, 'GDG tanpa tap, sudah ditetapkan', true),
  ('alpha_beruntun', 'harian', null, 'PRD', 'K8', 'K8 alpha beruntun', false)
) x(jenis, tingkat, mesin, divisi, id_karyawan, keterangan, selesai);
insert into hitung.anomali (versi_id, jenis, tingkat, mesin, divisi, id_karyawan, tanggal, nilai, keterangan, selesai)
select v.id, a.jenis, a.tingkat, a.mesin, a.divisi, a.id_karyawan, '2026-11-10', '1', a.keterangan, a.selesai
from anomali_uji a cross join hitung.versi_hitung v;

-- Kiriman ditolak: Excel, format, dan dobel (bukan segera).
insert into fakta.kiriman_file (nama_file, sidik, jenis, mesin, hasil, alasan) values
  ('rusak.csv', repeat('1', 64), 'tap_mesin', 'MA2', 'ditolak',
   'No.ID rusak (tertulis seperti 1,98E+17) karena file dibuka lalu disimpan di Excel. Kirim file langsung dari mesin tanpa dibuka di Excel.'),
  ('aneh.csv', repeat('2', 64), 'tap_mesin', 'MA1', 'ditolak',
   'Format file tidak dikenal. Kolom yang dibutuhkan: Nama, No.ID, Tgl/Waktu, Status. Kirim file ekspor langsung dari aplikasi mesin.'),
  ('dobel.csv', repeat('3', 64), 'tap_mesin', 'MA1', 'ditolak',
   'File yang sama sudah diterima sebelumnya (kiriman no. 1); tidak dicatat dua kali');

create temp table hasil_uji (nama text primary key, isi jsonb);
grant all on hasil_uji to pintu;
set local role pintu;
insert into hasil_uji values ('ambil1', api.pintu_pemberitahuan_ambil());
insert into hasil_uji values ('ambil2', api.pintu_pemberitahuan_ambil());
reset role;

-- Hitung ulang: versi 2 berisi anomali yang sama dengan angka nilai berbeda, ditambah satu kejadian baru.
insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
select id, 'baca_tap', 2, 'uji', 'a', 'c' from fakta.periode;
insert into hitung.anomali (versi_id, jenis, tingkat, mesin, divisi, id_karyawan, tanggal, nilai, keterangan, selesai)
select v.id, a.jenis, a.tingkat, a.mesin, a.divisi, a.id_karyawan, '2026-11-10', '2', a.keterangan, a.selesai
from anomali_uji a cross join hitung.versi_hitung v where v.nomor = 2;
insert into hitung.anomali (versi_id, jenis, tingkat, mesin, tanggal, keterangan)
select v.id, 'jam_mesin_melenceng', 'segera', 'MA2', '2026-11-12', 'Jam MA2 melenceng' from hitung.versi_hitung v where v.nomor = 2;

set local role pintu;
insert into hasil_uji values ('ambil3', api.pintu_pemberitahuan_ambil());
insert into hasil_uji values ('catat', api.pintu_pemberitahuan_hasil(jsonb_build_object(
  'id', (select jsonb_agg(k -> 'id') from hasil_uji, jsonb_array_elements(isi -> 'kejadian') k where nama = 'ambil1'),
  'hasil', '{"111": "ok", "444": "galat: chat not found"}'::jsonb)));
reset role;

create function pg_temp.h(p text) returns jsonb language sql as $$ select isi from hasil_uji where nama = p $$;
create function pg_temp.jenis(p text) returns text language sql as $$
  select string_agg(k ->> 'jenis', ',' order by k ->> 'jenis') from jsonb_array_elements(pg_temp.h(p) -> 'kejadian') k $$;

select uji.sama('N1: ketujuh jenis kejadian segera diambil sekali',
  pg_temp.jenis('ambil1'),
  'belum_terdaftar_mesin,file_rusak_excel,file_terpotong,format_tidak_dikenal,jam_mesin_melenceng,tanpa_tap_massal,tap_terakhir_lama');
select uji.sama('N3: penerima hanya hrd dan pembangun yang aktif dan punya ID Telegram',
  pg_temp.h('ambil1') -> 'penerima', '[111, 444]'::jsonb);
select uji.sama('N1: kejadian dicatat dengan penerimanya',
  (select count(*) from fakta.pemberitahuan where penerima = '{111,444}' and tingkat = 'segera'
     and id in (select (k ->> 'id')::bigint from jsonb_array_elements(pg_temp.h('ambil1') -> 'kejadian') k))::int, 7);
select uji.sama('N1: diambil lagi tanpa kejadian baru -> kosong', pg_temp.h('ambil2') -> 'kejadian', '[]'::jsonb);
select uji.sama('N2: hitung ulang (versi baru, angka nilai berubah) hanya mengambil kejadian yang benar-benar baru',
  pg_temp.jenis('ambil3'), 'jam_mesin_melenceng');
select uji.sama('N2: satu baris catatan per kejadian', (select count(*) from fakta.pemberitahuan)::int, 8);
select uji.sama('N7: anomali yang sudah selesai tidak dikirim',
  (select count(*) from fakta.pemberitahuan where isi ->> 'divisi' = 'GDG')::int, 0);
select uji.sama('N8: anomali tingkat harian tidak dikirim',
  (select count(*) from fakta.pemberitahuan where jenis = 'alpha_beruntun')::int, 0);
select uji.sama('N9: kiriman ditolak karena dobel tidak dikirim',
  (select count(*) from fakta.pemberitahuan where isi ->> 'nama_file' = 'dobel.csv')::int, 0);
select uji.sama('hasil kirim dicatat: satu penerima gagal -> sebagian_gagal',
  (select string_agg(distinct status, ',') from fakta.pemberitahuan
   where id in (select (k ->> 'id')::bigint from jsonb_array_elements(pg_temp.h('ambil1') -> 'kejadian') k)),
  'sebagian_gagal');
select uji.sama('hasil kirim: kejadian ambil3 masih akan_dikirim',
  (select status from fakta.pemberitahuan where isi ->> 'keterangan' = 'Jam MA2 melenceng'), 'akan_dikirim');

-- Tanpa penerima sama sekali: kejadian dicatat dilewati, tidak dikembalikan untuk dikirim.
update induk.pengguna set aktif = false where peran in ('hrd', 'pembangun');
insert into fakta.kiriman_file (nama_file, sidik, jenis, mesin, hasil, alasan) values
  ('rusak2.csv', repeat('4', 64), 'tap_mesin', 'MA2', 'ditolak', 'No.ID rusak (tertulis seperti 1,98E+17)');
set local role pintu;
insert into hasil_uji values ('tanpa_penerima', api.pintu_pemberitahuan_ambil());
reset role;
select uji.sama('tanpa penerima: tidak ada yang dikirim', pg_temp.h('tanpa_penerima') -> 'kejadian', '[]'::jsonb);
select uji.sama('tanpa penerima: dicatat dilewati',
  (select status from fakta.pemberitahuan where isi ->> 'nama_file' = 'rusak2.csv'), 'dilewati_tanpa_penerima');
update induk.pengguna set aktif = true where telegram_id in (111, 444);

-- Pengingat. Tutup buku 20 (bawaan). MA1 sudah mengirim file sampai 20 Nov; MA2 belum.
insert into fakta.kiriman_file (nama_file, sidik, jenis, mesin, tanggal_awal, tanggal_akhir, jumlah_baris, hasil)
values ('MA1.csv', repeat('5', 64), 'tap_mesin', 'MA1', '2026-10-21', '2026-11-20', 10, 'diterima'),
       ('MA2-lama.csv', repeat('6', 64), 'tap_mesin', 'MA2', '2026-10-21', '2026-11-19', 10, 'diterima');
set local role pintu;
insert into hasil_uji values ('p_biasa', api.pintu_pengingat('{"tanggal": "2026-11-15"}'));
insert into hasil_uji values ('p1', api.pintu_pengingat('{"tanggal": "2026-11-21"}'));
insert into hasil_uji values ('p1_lagi', api.pintu_pengingat('{"tanggal": "2026-11-21"}'));
insert into hasil_uji values ('p2', api.pintu_pengingat('{"tanggal": "2026-11-22"}'));
insert into hasil_uji values ('p3', api.pintu_pengingat('{"tanggal": "2026-11-23"}'));
reset role;
insert into induk.pengguna (telegram_id, peran) values (555, 'bos');
-- Periode berikutnya untuk hari ke-2 dengan akun bos; tutup buku 0 (akhir bulan) mulai Januari 2027.
insert into aturan.pengaturan (kunci, nilai, berlaku_dari) values ('tanggal_tutup_buku', '0', '2027-01-01');
set local role pintu;
insert into hasil_uji values ('p2_bos', api.pintu_pengingat('{"tanggal": "2026-12-22"}'));
insert into hasil_uji values ('p_akhir_bulan', api.pintu_pengingat('{"tanggal": "2027-02-01"}'));
insert into hasil_uji values ('p_akhir_bulan_31', api.pintu_pengingat('{"tanggal": "2027-01-31"}'));
reset role;

select uji.sama('P5: hari biasa tidak ada pengingat', pg_temp.h('p_biasa') -> 'kirim', '[]'::jsonb);
select uji.sama('P1: hari ke-1 sesudah tutup buku 20 Nov', pg_temp.h('p1') ->> 'hari_ke', '1');
select uji.sama('P1: hanya mesin yang belum mengirim (MA2), ke hrd dan pembangun',
  (pg_temp.h('p1') -> 'kirim' -> 0 -> 'mesin') || (pg_temp.h('p1') -> 'kirim' -> 0 -> 'penerima'), '["MA2", 111, 444]'::jsonb);
select uji.sama('P1: hari ke-1 tidak ke bos', jsonb_array_length(pg_temp.h('p1') -> 'kirim'), 1);
select uji.sama('P1: periode yang diingatkan', (pg_temp.h('p1') ->> 'periode_awal') || '/' || (pg_temp.h('p1') ->> 'tutup_buku'),
  '2026-10-21/2026-11-20');
select uji.sama('P2: dipicu lagi di hari yang sama -> tidak ada pesan kedua', pg_temp.h('p1_lagi') -> 'kirim', '[]'::jsonb);
select uji.sama('P3: hari ke-2 pengingat ke hrd tetap terkirim', pg_temp.h('p2') -> 'kirim' -> 0 ->> 'kepada', 'hrd');
select uji.sama('P3: hari ke-2 tanpa akun bos dicatat dilewati', pg_temp.h('p2') -> 'dilewati' -> 0 ->> 'status',
  'dilewati_tanpa_akun_bos');
select uji.sama('P3: catatan bos dilewati ada di tabel',
  (select count(*) from fakta.pemberitahuan where status = 'dilewati_tanpa_akun_bos')::int, 1);
select uji.sama('P5: hari ke-3 tidak ada pengingat', (pg_temp.h('p3') ->> 'hari_ke') || '/' || (pg_temp.h('p3') -> 'kirim')::text, '3/[]');
select uji.sama('P4: hari ke-2 dengan akun bos -> bos juga menerima (dua mesin belum mengirim periode Desember)',
  (select jsonb_agg(k -> 'penerima') from jsonb_array_elements(pg_temp.h('p2_bos') -> 'kirim') k),
  '[[111, 444], [555]]'::jsonb);
select uji.sama('P6: tutup buku akhir bulan -> 1 Feb adalah hari ke-1 sesudah 31 Jan',
  (pg_temp.h('p_akhir_bulan') ->> 'tutup_buku') || '/' || (pg_temp.h('p_akhir_bulan') ->> 'hari_ke'), '2027-01-31/1');
select uji.sama('P6: periode peralihan (tutup 20 Des lalu akhir Jan) dimulai 21 Des',
  pg_temp.h('p_akhir_bulan') ->> 'periode_awal', '2026-12-21');
select uji.sama('P6: tanggal 31 Jan adalah hari tutup buku sendiri, bukan hari ke-1',
  pg_temp.h('p_akhir_bulan_31') -> 'kirim', '[]'::jsonb);

select uji.harus_ditolak('akses: peran pintu tidak bisa membaca catatan pemberitahuan langsung',
  'select * from fakta.pemberitahuan', 'pintu');
select uji.harus_ditolak('akses: peran pintu tidak bisa menandai kejadian lama langsung',
  'select fakta.tandai_kejadian_lama()', 'pintu');

rollback;
