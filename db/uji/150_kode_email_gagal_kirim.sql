-- Uji paket 5e-2: kode email yang gagal dikirim tidak menghabiskan jatah dan tidak bisa dipakai.
-- Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';
insert into induk.pengguna (telegram_id, peran, email) values (111, 'hrd', 'hrd@contoh.id'), (112, 'hrd', 'lain@contoh.id');

create temp table hasil_uji (nama text primary key, isi jsonb);
grant all on hasil_uji to pintu;
create function pg_temp.minta(p_nama text, p_email text, p_sidik text) returns void language sql as $$
  insert into hasil_uji values (p_nama, api.pintu_minta_kode_email(jsonb_build_object('email', p_email, 'sidik', p_sidik)))
$$;
create function pg_temp.gagal(p_nama text, p_dari text, p_email text) returns void language sql as $$
  insert into hasil_uji values (p_nama, api.pintu_kode_email_gagal(jsonb_build_object(
    'id', (select isi ->> 'id' from hasil_uji where nama = p_dari), 'email', p_email)))
$$;
create function pg_temp.tukar(p_nama text, p_email text, p_kode text, p_tautan text) returns void language sql as $$
  insert into hasil_uji values (p_nama, api.pintu_tukar_kode_email(
    jsonb_build_object('email', p_email, 'sidik_kode', p_kode, 'sidik_tautan', p_tautan)))
$$;
grant execute on function pg_temp.minta(text, text, text), pg_temp.gagal(text, text, text),
  pg_temp.tukar(text, text, text, text) to pintu;

set local role pintu;
-- Brevo gagal tiga kali, lalu berhasil.
select pg_temp.minta('m1', 'hrd@contoh.id', repeat('1', 64));
select pg_temp.gagal('g1', 'm1', 'hrd@contoh.id');
select pg_temp.minta('m2', 'hrd@contoh.id', repeat('2', 64));
select pg_temp.gagal('g2', 'm2', 'hrd@contoh.id');
select pg_temp.minta('m3', 'hrd@contoh.id', repeat('3', 64));
select pg_temp.gagal('g3', 'm3', 'hrd@contoh.id');
select pg_temp.minta('m4', 'hrd@contoh.id', repeat('4', 64));
select pg_temp.tukar('t_gagal', 'hrd@contoh.id', repeat('3', 64), repeat('a', 64));
select pg_temp.tukar('t4', 'hrd@contoh.id', repeat('4', 64), repeat('b', 64));
-- Penandaan gagal hanya untuk email yang cocok, dan tidak berlaku untuk kode yang sudah dipakai.
select pg_temp.gagal('g_salah_email', 'm4', 'lain@contoh.id');
select pg_temp.gagal('g_sudah_dipakai', 'm4', 'hrd@contoh.id');
-- Jatah tetap berlaku untuk kode yang terkirim: m4 + dua lagi = 3, yang keempat tertahan.
select pg_temp.minta('m5', 'hrd@contoh.id', repeat('5', 64));
select pg_temp.minta('m6', 'hrd@contoh.id', repeat('6', 64));
select pg_temp.minta('m7', 'hrd@contoh.id', repeat('7', 64));
-- Kode terkirim sebelumnya tetap berlaku walau kode sesudahnya gagal.
select pg_temp.minta('l1', 'lain@contoh.id', repeat('8', 64));
select pg_temp.minta('l2', 'lain@contoh.id', repeat('9', 64));
select pg_temp.gagal('lg2', 'l2', 'lain@contoh.id');
select pg_temp.tukar('t_l1', 'lain@contoh.id', repeat('8', 64), repeat('c', 64));
reset role;

create function pg_temp.h(p text) returns jsonb language sql as $$ select isi from hasil_uji where nama = p $$;
select uji.sama('5e-2: kode yang gagal dikirim ditandai', pg_temp.h('g1') ->> 'ditandai', '1');
select uji.sama('5e-2: sesudah 3 kali gagal, kode keempat tetap dibuat', pg_temp.h('m4') ->> 'kirim', 'true');
-- Kode yang gagal dilewati: yang diperiksa kode terbaru yang terkirim (m4), jadi kode gagal terbaca "salah".
select uji.sama('5e-2: kode yang gagal dikirim tidak bisa dipakai', pg_temp.h('t_gagal') ->> 'hasil', 'salah');
select uji.sama('5e-2: kode yang terkirim sesudah kegagalan bisa dipakai', pg_temp.h('t4') ->> 'hasil', 'masuk');
select uji.sama('5e-2: penandaan gagal ditolak bila email tidak cocok', pg_temp.h('g_salah_email') ->> 'ditandai', '0');
select uji.sama('5e-2: kode yang sudah dipakai tidak bisa ditandai gagal', pg_temp.h('g_sudah_dipakai') ->> 'ditandai', '0');
select uji.sama('5e-2: jatah 3 per 15 menit tetap berlaku untuk kode terkirim',
  (pg_temp.h('m6') ->> 'kirim') || '/' || (pg_temp.h('m7') ->> 'kirim'), 'true/false');
select uji.sama('5e-2: kode terkirim sebelumnya tetap berlaku walau kode sesudahnya gagal', pg_temp.h('t_l1') ->> 'hasil', 'masuk');

-- Batas 50 per jam tetap menghitung kode yang gagal.
insert into fakta.kode_email (pengguna, email, sidik, berlaku_sampai, gagal_kirim)
select (select id from induk.pengguna where telegram_id = 112), 'lain@contoh.id', repeat('0', 64), now() + interval '10 minutes', now()
from generate_series(1, 50);
set local role pintu;
select pg_temp.minta('m_batas_jam', 'lain@contoh.id', repeat('e', 64));
reset role;
select uji.sama('5e-2: batas 50 kode per jam menghitung kode yang gagal', pg_temp.h('m_batas_jam'), '{"kirim": false, "batas": true}'::jsonb);

rollback;
