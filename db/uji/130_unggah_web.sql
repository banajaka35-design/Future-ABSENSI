-- Uji paket 5d: tautan unggah dan jalur web di database (docs/unggah-web.md, kasus W1-W7, W9, W11).
-- Alur lewat Edge Function (pesan tiruan, file simulasi, postgres.js) ada di sistem/pintu/.
-- Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang'), ('MA2', 'Kantor');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2026-03-21', '2026-04-20', '2026-04-25');
insert into induk.pengguna (telegram_id, peran) values (111, 'hrd'), (222, 'karyawan'), (444, 'pembangun'), (666, 'hrd');

-- Sidik kode tiruan (64 huruf heksadesimal).
create temp table k (nama text primary key, sidik text);
insert into k values ('a', repeat('a', 64)), ('b', repeat('b', 64)), ('c', repeat('c', 64)), ('d', repeat('d', 64)),
                     ('palsu', repeat('e', 64)), ('f', repeat('f', 64));
create temp table hasil_uji (nama text primary key, isi jsonb);
grant all on hasil_uji, k to pintu;

set local role pintu;
insert into hasil_uji values ('buat_hrd', api.pintu_buat_tautan(jsonb_build_object('telegram_id', 111, 'sidik', repeat('a', 64))));
insert into hasil_uji values ('buat_karyawan', api.pintu_buat_tautan(jsonb_build_object('telegram_id', 222, 'sidik', repeat('b', 64))));
insert into hasil_uji values ('buat_pembangun', api.pintu_buat_tautan(jsonb_build_object('telegram_id', 444, 'sidik', repeat('c', 64))));
insert into hasil_uji values ('buat_666', api.pintu_buat_tautan(jsonb_build_object('telegram_id', 666, 'sidik', repeat('d', 64))));
insert into hasil_uji values ('buat_lewat', api.pintu_buat_tautan(jsonb_build_object('telegram_id', 111, 'sidik', repeat('f', 64))));
reset role;

-- W4: tautan f dibuat 20 menit lalu (lewat batas 15 menit). W5: akun 666 dinonaktifkan sesudah tautannya dibuat.
update fakta.tautan_unggah set berlaku_sampai = now() - interval '5 minutes' where sidik = repeat('f', 64);
update induk.pengguna set aktif = false where telegram_id = 666;

set local role pintu;
insert into hasil_uji values ('periksa_sah', api.pintu_periksa_tautan(jsonb_build_object('kode_sidik', repeat('a', 64))));
insert into hasil_uji values ('periksa_palsu', api.pintu_periksa_tautan(jsonb_build_object('kode_sidik', repeat('e', 64))));
insert into hasil_uji values ('periksa_lewat', api.pintu_periksa_tautan(jsonb_build_object('kode_sidik', repeat('f', 64))));
insert into hasil_uji values ('periksa_nonaktif', api.pintu_periksa_tautan(jsonb_build_object('kode_sidik', repeat('d', 64))));
insert into hasil_uji values ('web1', api.pintu_terima_web(jsonb_build_object(
  'kode_sidik', repeat('a', 64), 'nama_file', 'web1.csv', 'sidik', repeat('1', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-07 06:55:00", "Masuk", 2], ["1", "2026-04-07 15:05:00", "Keluar", 3]]'::jsonb,
  'telegram_id', 444, 'update_id', 5)));
insert into hasil_uji values ('web_dobel', api.pintu_terima_web(jsonb_build_object(
  'kode_sidik', repeat('a', 64), 'nama_file', 'web1 lagi.csv', 'sidik', repeat('1', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-07 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('web2', api.pintu_terima_web(jsonb_build_object(
  'kode_sidik', repeat('a', 64), 'nama_file', 'web2.csv', 'sidik', repeat('2', 64), 'mesin', 'MA2',
  'tap', '[["2", "2026-04-08 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('web_palsu', api.pintu_terima_web(jsonb_build_object(
  'kode_sidik', repeat('e', 64), 'nama_file', 'palsu.csv', 'sidik', repeat('3', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-09 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('web_lewat', api.pintu_terima_web(jsonb_build_object(
  'kode_sidik', repeat('f', 64), 'nama_file', 'lewat.csv', 'sidik', repeat('4', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-09 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('web_nonaktif', api.pintu_terima_web(jsonb_build_object(
  'kode_sidik', repeat('d', 64), 'nama_file', 'nonaktif.csv', 'sidik', repeat('5', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-09 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('tele', api.pintu_terima_file(jsonb_build_object(
  'update_id', 77, 'telegram_id', 111, 'nama_file', 'tele.csv', 'sidik', repeat('6', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-10 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('status_pemilik', api.pintu_status_kiriman(jsonb_build_object(
  'kode_sidik', repeat('a', 64), 'kiriman_id', (select (isi ->> 'kiriman_id')::bigint from hasil_uji where nama = 'web1'))));
insert into hasil_uji values ('status_orang_lain', api.pintu_status_kiriman(jsonb_build_object(
  'kode_sidik', repeat('c', 64), 'kiriman_id', (select (isi ->> 'kiriman_id')::bigint from hasil_uji where nama = 'web1'))));
insert into hasil_uji values ('status_palsu', api.pintu_status_kiriman(jsonb_build_object(
  'kode_sidik', repeat('e', 64), 'kiriman_id', 1)));
reset role;

create function pg_temp.h(p text) returns jsonb language sql as $$ select isi from hasil_uji where nama = p $$;
select uji.sama('W1: HRD mendapat tautan', pg_temp.h('buat_hrd') ->> 'hasil', 'dibuat');
select uji.sama('W1: tautan berlaku 15 menit',
  (select berlaku_sampai - dibuat from fakta.tautan_unggah where sidik = repeat('a', 64)), interval '15 minutes');
select uji.sama('W1: akun pembangun juga mendapat tautan', pg_temp.h('buat_pembangun') ->> 'hasil', 'dibuat');
select uji.sama('W2: akun bukan HRD ditolak', pg_temp.h('buat_karyawan') ->> 'hasil', 'ditolak');
select uji.sama('W2: tidak ada tautan untuk akun bukan HRD',
  (select count(*) from fakta.tautan_unggah where sidik = repeat('b', 64))::int, 0);
select uji.sama('periksa: tautan sah memberi daftar mesin', pg_temp.h('periksa_sah') -> 'mesin', '["MA1", "MA2"]'::jsonb);
select uji.sama('W3: kode palsu tidak sah', pg_temp.h('periksa_palsu') ->> 'sah', 'false');
select uji.sama('W4: tautan lewat 15 menit tidak sah', pg_temp.h('periksa_lewat') ->> 'sah', 'false');
select uji.sama('W5: akun dinonaktifkan -> tautannya tidak sah', pg_temp.h('periksa_nonaktif') ->> 'sah', 'false');
select uji.sama('W6: file web diterima', pg_temp.h('web1') ->> 'hasil', 'diterima');
select uji.sama('W6: asal web, pengirim pemilik tautan (bukan telegram_id kiriman Edge Function), tanpa nomor pesan',
  (select asal || '/' || (pengirim = (select id from induk.pengguna where telegram_id = 111)) || '/' || coalesce(nomor_pesan::text, '-')
   from fakta.kiriman_file where nama_file = 'web1.csv'), 'web/true/-');
select uji.sama('W6: periode terkena masuk antrean', (select count(*) from fakta.antrean_kerja
  where kiriman_id = (pg_temp.h('web1') ->> 'kiriman_id')::bigint)::int, 1);
select uji.sama('W6: telegram_id pemilik dikembalikan untuk ringkasan', pg_temp.h('web1') ->> 'telegram_id', '111');
select uji.sama('W7: file yang sama lewat web ditolak dobel', pg_temp.h('web_dobel') ->> 'hasil', 'ditolak');
select uji.sama('W9: file kedua dengan tautan yang sama diproses', pg_temp.h('web2') ->> 'hasil', 'diterima');
select uji.sama('W9: pemakaian tautan tercatat', (select jumlah_pakai from fakta.tautan_unggah where sidik = repeat('a', 64)), 3);
select uji.sama('W3: kode palsu -> file tidak diproses', pg_temp.h('web_palsu') ->> 'tautan', 'false');
select uji.sama('W4: tautan lewat -> file tidak diproses', pg_temp.h('web_lewat') ->> 'tautan', 'false');
select uji.sama('W5: akun nonaktif -> file tidak diproses', pg_temp.h('web_nonaktif') ->> 'tautan', 'false');
select uji.sama('W3-W5: tidak ada kiriman tercatat dari tautan yang tidak sah',
  (select count(*) from fakta.kiriman_file where nama_file in ('palsu.csv', 'lewat.csv', 'nonaktif.csv'))::int, 0);
select uji.sama('asal: file dari bot tercatat telegram', (select asal from fakta.kiriman_file where nama_file = 'tele.csv'), 'telegram');
select uji.sama('status: pemilik melihat kiriman dan periodenya',
  (pg_temp.h('status_pemilik') -> 'kiriman' ->> 'asal') || '/' || jsonb_array_length(pg_temp.h('status_pemilik') -> 'periode')
  || '/' || (pg_temp.h('status_pemilik') ->> 'selesai'), 'web/1/false');
select uji.sama('W11: status kiriman dengan tautan akun lain ditolak', pg_temp.h('status_orang_lain') -> 'kiriman', 'null'::jsonb);
select uji.sama('W11: status dengan kode palsu ditolak', pg_temp.h('status_palsu') ->> 'tautan', 'false');
select uji.sama('database hanya menyimpan sidik kode (64 heksadesimal)',
  (select bool_and(sidik ~ '^[0-9a-f]{64}$') from fakta.tautan_unggah), true);
select uji.harus_ditolak('akses: peran pintu tidak bisa membaca tabel tautan langsung',
  'select * from fakta.tautan_unggah', 'pintu');

rollback;
