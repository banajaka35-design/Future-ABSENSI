-- Uji paket 8f (docs/rencana-8f.md): pembangun mencabut akun HRD, bos, atau karyawan.
begin;
set local app.pengguna = 'uji-otomatis';
insert into induk.karyawan (id, nama) values ('C8A', 'Uji Cabut');
insert into induk.pengguna (telegram_id, peran, email) values (8801, 'hrd', 'hrd-cabut@contoh.test'), (8803, 'bos', null),
  (8811, 'pembangun', null), (8812, 'pembangun', null);
insert into induk.pengguna (telegram_id, peran, id_karyawan) values (8802, 'karyawan', 'C8A');
update induk.pengguna set pin_tersamar = extensions.crypt('123456', extensions.gen_salt('bf')) where telegram_id in (8801, 8803);
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2039-01-21', '2039-02-20', '2039-02-25');
create temp table h (nama text primary key, isi jsonb);
create temp table id as select telegram_id as tg, id from induk.pengguna where telegram_id between 8801 and 8812;
grant all on h, id to pintu;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
create function pg_temp.u(t bigint) returns bigint language sql as $$ select id from id where tg = t $$;
grant execute on function pg_temp.k(text), pg_temp.u(bigint) to pintu;
-- Draf terbuka milik HRD, tunggu PIN milik bos, kode email HRD yang belum dipakai.
insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, kedaluwarsa)
values (pg_temp.u(8801), 'izin', 'C8A', '2039-01-22', '2039-01-22', now() + interval '10 minutes');
insert into h values ('draf', jsonb_build_object('id', currval(pg_get_serial_sequence('fakta.draf_perintah', 'id'))));
insert into fakta.tunggu_pin (telegram_id, aksi, periode_id, batas)
values (8803, 'setujui', (select id from fakta.periode where tanggal_awal = '2039-01-21'), now() + interval '5 minutes');
insert into fakta.kode_email (pengguna, email, sidik, berlaku_sampai)
values (pg_temp.u(8801), 'hrd-cabut@contoh.test', encode(sha256('8f-kode'), 'hex'), now() + interval '10 minutes');
insert into h values ('periode', jsonb_build_object('id', (select id from fakta.periode where tanggal_awal = '2039-01-21')));

set local role pintu;
insert into h values ('daftar_hrd', api.pintu_cabut_daftar(jsonb_build_object('telegram_id', 8801)));
insert into h values ('daftar', api.pintu_cabut_daftar(jsonb_build_object('telegram_id', 8811)));
insert into h values ('cabut_oleh_bos', api.pintu_cabut_akun(jsonb_build_object('telegram_id', 8803, 'pengguna_id', pg_temp.u(8801))));
insert into h values ('cabut_pembangun', api.pintu_cabut_akun(jsonb_build_object('telegram_id', 8811, 'pengguna_id', pg_temp.u(8812))));
insert into h values ('cabut_sendiri', api.pintu_cabut_akun(jsonb_build_object('telegram_id', 8811, 'pengguna_id', pg_temp.u(8811))));
insert into h values ('cabut_hrd', api.pintu_cabut_akun(jsonb_build_object('telegram_id', 8811, 'pengguna_id', pg_temp.u(8801))));
insert into h values ('cabut_bos', api.pintu_cabut_akun(jsonb_build_object('telegram_id', 8811, 'pengguna_id', pg_temp.u(8803))));
insert into h values ('cabut_karyawan', api.pintu_cabut_akun(jsonb_build_object('telegram_id', 8812, 'pengguna_id', pg_temp.u(8802))));
insert into h values ('cabut_lagi', api.pintu_cabut_akun(jsonb_build_object('telegram_id', 8811, 'pengguna_id', pg_temp.u(8803))));
insert into h values ('simpan_draf', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 8801, 'draf_id', (pg_temp.k('draf') ->> 'id')::bigint, 'ya', true)));
insert into h values ('lengkap_bos', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 8803,
  'periode_id', (pg_temp.k('periode') ->> 'id')::bigint, 'pin', '123456')));
insert into h values ('setujui_bos', api.pintu_setujui(jsonb_build_object('telegram_id', 8803,
  'periode_id', (pg_temp.k('periode') ->> 'id')::bigint, 'setuju', true, 'pin', '123456')));
-- HP yang sama bisa bergabung lagi dengan undangan baru.
insert into h values ('undang', api.pintu_undang(jsonb_build_object('telegram_id', 8811, 'peran', 'bos', 'sidik', encode(sha256('8f-bos'), 'hex'))));
insert into h values ('gabung_lagi', api.pintu_gabung(jsonb_build_object('telegram_id', 8803, 'sidik', encode(sha256('8f-bos'), 'hex'))));
reset role;

select uji.sama('8f: hanya pembangun yang melihat daftar cabut', pg_temp.k('daftar_hrd') ->> 'hasil', 'bukan_pembangun');
select uji.sama('8f: daftar cabut = HRD, bos, karyawan (tanpa pembangun)',
  (select string_agg(a ->> 'peran', ',' order by (a ->> 'id')::bigint) from jsonb_array_elements(pg_temp.k('daftar') -> 'akun') a
   where (a ->> 'id')::bigint in (select id from id)), 'hrd,bos,karyawan');
select uji.sama('8f: label karyawan = ID dan nama',
  (select a ->> 'label' from jsonb_array_elements(pg_temp.k('daftar') -> 'akun') a where (a ->> 'id')::bigint = pg_temp.u(8802)), 'C8A Uji Cabut');
select uji.sama('8f: bos tidak bisa mencabut; pembangun tidak bisa dicabut (orang lain atau sendiri)',
  concat_ws('/', pg_temp.k('cabut_oleh_bos') ->> 'hasil', pg_temp.k('cabut_pembangun') ->> 'hasil', pg_temp.k('cabut_sendiri') ->> 'hasil'),
  'bukan_pembangun/tidak_ada/tidak_ada');
select uji.sama('8f: HRD, bos, karyawan dicabut; Telegram lama dikembalikan untuk kabar',
  concat_ws('/', pg_temp.k('cabut_hrd') ->> 'hasil', pg_temp.k('cabut_bos') ->> 'hasil', pg_temp.k('cabut_karyawan') ->> 'hasil',
            pg_temp.k('cabut_bos') ->> 'telegram_id', pg_temp.k('cabut_bos') ->> 'peran'),
  'dicabut/dicabut/dicabut/8803/bos');
select uji.sama('8f: mencabut dua kali ditolak', pg_temp.k('cabut_lagi') ->> 'hasil', 'tidak_ada');
select uji.sama('8f: akun lama nonaktif, tanpa PIN, Telegram dan email dilepas',
  (select count(*) from induk.pengguna u where u.id in (pg_temp.u(8801), pg_temp.u(8802), pg_temp.u(8803))
   and not u.aktif and u.pin_tersamar is null and u.telegram_id is null and u.email is null), 3::bigint);
select uji.sama('8f: pembangun tetap aktif', (select count(*) from induk.pengguna u where u.id in (pg_temp.u(8811), pg_temp.u(8812)) and u.aktif), 2::bigint);
select uji.sama('8f: catatan cabut lengkap (Telegram lama, peran, ID karyawan, oleh)',
  (select string_agg(concat_ws(':', c.telegram_id_lama, c.peran, coalesce(c.id_karyawan, '-'), o.telegram_id), ',' order by c.id)
   from fakta.cabut_akun c join induk.pengguna o on o.id = c.oleh where c.pengguna in (select id from id)),
  '8801:hrd:-:8811,8803:bos:-:8811,8802:karyawan:C8A:8812');
select uji.harus_ditolak('8f: catatan cabut hanya bertambah', 'delete from fakta.cabut_akun');
select uji.sama('8f: draf HRD terbuka ditutup, menyimpannya ditolak',
  concat_ws('/', (select hasil from fakta.draf_perintah where id = (pg_temp.k('draf') ->> 'id')::bigint), pg_temp.k('simpan_draf') ->> 'hasil'),
  'dibatalkan/bukan_hrd');
select uji.sama('8f: tunggu PIN bos dihapus', (select count(*) from fakta.tunggu_pin where telegram_id = 8803), 0::bigint);
select uji.sama('8f: kode email HRD yang belum dipakai tidak berlaku lagi',
  (select count(*) from fakta.kode_email where pengguna = pg_temp.u(8801) and berlaku_sampai > now()), 0::bigint);
select uji.sama('8f: bos yang dicabut tidak bisa melihat total lengkap atau menyetujui',
  concat_ws('/', pg_temp.k('lengkap_bos') ->> 'hasil', pg_temp.k('setujui_bos') ->> 'hasil'), 'bukan_bos/bukan_bos');
select uji.sama('8f: karyawan yang dicabut tidak punya akun lagi (rincian gaji -> tanpa_akun)', fakta.akun_karyawan('C8A') is null, true);
select uji.sama('8f: HP yang sama bisa bergabung lagi dengan undangan baru (akun baru)',
  concat_ws('/', pg_temp.k('undang') ->> 'hasil', pg_temp.k('gabung_lagi') ->> 'hasil', pg_temp.k('gabung_lagi') ->> 'peran',
            (select count(*) from induk.pengguna where telegram_id = 8803 and aktif and id <> pg_temp.u(8803))::text),
  'dibuat/terdaftar/bos/1');
select uji.sama('8f: anon dan authenticated tidak bisa memanggil fungsi baru',
  (select count(*) from pg_roles r cross join (values ('api.pintu_cabut_daftar(jsonb)'), ('api.pintu_cabut_akun(jsonb)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);
select uji.harus_ditolak('8f: pintu tidak bisa membaca catatan cabut', 'select count(*) from fakta.cabut_akun', 'pintu');
rollback;
