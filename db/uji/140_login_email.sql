-- Uji paket 5e: kode email di database (docs/login-email.md, kasus E1-E9, E11).
-- Alur lewat Edge Function (pengirim email tiruan, postgres.js) ada di sistem/pintu/.
-- Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2026-03-21', '2026-04-20', '2026-04-25');
insert into induk.pengguna (telegram_id, peran, email) values
  (111, 'hrd', 'Hrd@Contoh.id'), (222, 'karyawan', 'karyawan@contoh.id'), (null, 'hrd', 'tanpa.tg@contoh.id'),
  (444, 'pembangun', 'bangun@contoh.id'), (555, 'hrd', 'nonaktif@contoh.id');

create temp table hasil_uji (nama text primary key, isi jsonb);
grant all on hasil_uji to pintu;
-- Sidik tiruan: sidik kode benar = repeat('a'), salah = repeat('b'), dan seterusnya.
create function pg_temp.minta(p_nama text, p_email text, p_sidik text) returns void language sql as $$
  insert into hasil_uji values (p_nama, api.pintu_minta_kode_email(jsonb_build_object('email', p_email, 'sidik', p_sidik)))
$$;
create function pg_temp.tukar(p_nama text, p_email text, p_kode text, p_tautan text) returns void language sql as $$
  insert into hasil_uji values (p_nama, api.pintu_tukar_kode_email(
    jsonb_build_object('email', p_email, 'sidik_kode', p_kode, 'sidik_tautan', p_tautan)))
$$;
grant execute on function pg_temp.minta(text, text, text), pg_temp.tukar(text, text, text, text) to pintu;

set local role pintu;
select pg_temp.minta('e1', '  HRD@contoh.ID ', repeat('a', 64));
select pg_temp.minta('e2', 'tidak.ada@contoh.id', repeat('a', 64));
select pg_temp.minta('karyawan', 'karyawan@contoh.id', repeat('a', 64));
select pg_temp.tukar('e3', 'hrd@contoh.id', repeat('a', 64), repeat('1', 64));
select pg_temp.tukar('e6', 'hrd@contoh.id', repeat('a', 64), repeat('2', 64));
-- E4: kode salah 5 kali lalu kode benar
select pg_temp.minta('e4_minta', 'bangun@contoh.id', repeat('c', 64));
select pg_temp.tukar('e4_salah1', 'bangun@contoh.id', repeat('b', 64), repeat('3', 64));
select pg_temp.tukar('e4_salah2', 'bangun@contoh.id', repeat('b', 64), repeat('3', 64));
select pg_temp.tukar('e4_salah3', 'bangun@contoh.id', repeat('b', 64), repeat('3', 64));
select pg_temp.tukar('e4_salah4', 'bangun@contoh.id', repeat('b', 64), repeat('3', 64));
select pg_temp.tukar('e4_salah5', 'bangun@contoh.id', repeat('b', 64), repeat('3', 64));
select pg_temp.tukar('e4_benar', 'bangun@contoh.id', repeat('c', 64), repeat('3', 64));
-- E9: akun dinonaktifkan sesudah kode dikirim
select pg_temp.minta('e9_minta', 'nonaktif@contoh.id', repeat('d', 64));
reset role;
update induk.pengguna set aktif = false where telegram_id = 555;
-- E5: kode akun tanpa Telegram dibuat lalu dimundurkan lewat 10 menit
set local role pintu;
select pg_temp.tukar('e9', 'nonaktif@contoh.id', repeat('d', 64), repeat('4', 64));
select pg_temp.minta('e5_minta', 'tanpa.tg@contoh.id', repeat('e', 64));
reset role;
update fakta.kode_email set berlaku_sampai = now() - interval '1 second' where email = 'tanpa.tg@contoh.id';
set local role pintu;
select pg_temp.tukar('e5', 'tanpa.tg@contoh.id', repeat('e', 64), repeat('5', 64));
-- E7: minta kode baru; kode lama ditolak, kode baru berlaku. Juga E8: kode ke-3 dalam 15 menit masih boleh, ke-4 tidak.
select pg_temp.minta('e7_minta', 'tanpa.tg@contoh.id', repeat('f', 64));
select pg_temp.minta('e8_ke3', 'tanpa.tg@contoh.id', repeat('9', 64));
select pg_temp.minta('e8_ke4', 'tanpa.tg@contoh.id', repeat('8', 64));
select pg_temp.tukar('e7_lama', 'tanpa.tg@contoh.id', repeat('f', 64), repeat('6', 64));
select pg_temp.tukar('e7_baru', 'tanpa.tg@contoh.id', repeat('9', 64), repeat('7', 64));
-- E11: akun tanpa ID Telegram mengunggah dengan tautan dari email
insert into hasil_uji values ('e11', api.pintu_terima_web(jsonb_build_object(
  'kode_sidik', repeat('7', 64), 'nama_file', 'email.csv', 'sidik', repeat('0', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-07 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('bot_tetap', api.pintu_terima_file(jsonb_build_object(
  'update_id', 9, 'telegram_id', 111, 'nama_file', 'bot.csv', 'sidik', repeat('c', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-08 06:55:00", "Masuk", 2]]'::jsonb)));
reset role;

create function pg_temp.h(p text) returns jsonb language sql as $$ select isi from hasil_uji where nama = p $$;
select uji.sama('E1: email terdaftar (huruf besar, spasi) mendapat kode', pg_temp.h('e1'), '{"kirim": true, "email": "hrd@contoh.id"}'::jsonb);
select uji.sama('E1: kode berlaku 10 menit, hanya sidik tersimpan',
  (select (berlaku_sampai - dibuat)::text || '/' || (sidik = repeat('a', 64)) from fakta.kode_email where email = 'hrd@contoh.id'),
  '00:10:00/true');
select uji.sama('E2: email tidak terdaftar -> tidak ada kode', pg_temp.h('e2'), '{"kirim": false}'::jsonb);
select uji.sama('E2: akun karyawan tidak mendapat kode', pg_temp.h('karyawan') ->> 'kirim', 'false');
select uji.sama('E2: tidak ada baris kode untuk email yang tidak berhak',
  (select count(*) from fakta.kode_email where email in ('tidak.ada@contoh.id', 'karyawan@contoh.id'))::int, 0);
select uji.sama('E3: kode benar -> tautan unggah 15 menit', pg_temp.h('e3') ->> 'hasil', 'masuk');
select uji.sama('E3: tautan atas nama akun pemilik email',
  (select (t.berlaku_sampai - t.dibuat)::text || '/' || u.telegram_id from fakta.tautan_unggah t join induk.pengguna u on u.id = t.pengguna
   where t.sidik = repeat('1', 64)), '00:15:00/111');
select uji.sama('E6: kode dipakai dua kali ditolak', pg_temp.h('e6') ->> 'hasil', 'tidak_berlaku');
select uji.sama('E4: salah pertama memberi sisa 4', pg_temp.h('e4_salah1') ->> 'sisa', '4');
select uji.sama('E4: salah kelima mengunci', pg_temp.h('e4_salah5') ->> 'hasil', 'tidak_berlaku');
select uji.sama('E4: kode benar sesudah terkunci ditolak', pg_temp.h('e4_benar') ->> 'hasil', 'tidak_berlaku');
select uji.sama('E4: tidak ada tautan dari kode terkunci', (select count(*) from fakta.tautan_unggah where sidik = repeat('3', 64))::int, 0);
select uji.sama('E9: akun dinonaktifkan sesudah kode dikirim -> ditolak', pg_temp.h('e9') ->> 'hasil', 'tidak_berlaku');
select uji.sama('E5: kode lewat 10 menit ditolak', pg_temp.h('e5') ->> 'hasil', 'tidak_berlaku');
select uji.sama('E8: kode ke-3 dalam 15 menit masih dibuat', pg_temp.h('e8_ke3') ->> 'kirim', 'true');
select uji.sama('E8: kode ke-4 dalam 15 menit tidak dibuat', pg_temp.h('e8_ke4'), '{"kirim": false, "batas": true}'::jsonb);
select uji.sama('E7: kode lama sesudah minta kode baru ditolak', pg_temp.h('e7_lama') ->> 'hasil', 'salah');
select uji.sama('E7: kode terbaru berlaku', pg_temp.h('e7_baru') ->> 'hasil', 'masuk');
select uji.sama('E11: akun tanpa ID Telegram mengunggah lewat web', pg_temp.h('e11') ->> 'hasil', 'diterima');
select uji.sama('E11: kiriman atas nama akun itu, asal web, tanpa ID Telegram di jawaban',
  (select k.asal || '/' || (u.email = 'tanpa.tg@contoh.id') from fakta.kiriman_file k join induk.pengguna u on u.id = k.pengirim
   where k.nama_file = 'email.csv') || '/' || coalesce(pg_temp.h('e11') ->> 'telegram_id', 'kosong'), 'web/true/kosong');
select uji.sama('bot tetap bekerja sesudah pintu_terima_file diganti', pg_temp.h('bot_tetap') ->> 'hasil', 'diterima');
select uji.sama('bot: asal telegram', (select asal from fakta.kiriman_file where nama_file = 'bot.csv'), 'telegram');
select uji.harus_ditolak('email: satu alamat untuk satu akun (huruf besar-kecil sama)',
  'insert into induk.pengguna (peran, email) values (''hrd'', ''HRD@CONTOH.ID'')');
select uji.harus_ditolak('akses: peran pintu tidak bisa membaca kode email langsung', 'select * from fakta.kode_email', 'pintu');

rollback;
