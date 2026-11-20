-- Uji paket 8b-2 (docs/rencana-8b-2.md): akun pembangun menyetujui atau menolak pengajuan rilis seperti bos, dengan PIN.
-- Fungsi api dipanggil sebagai peran pintu. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.divisi (kode, nama, pola) values ('ZP9', 'Uji Pembangun', 'mingguan');
insert into induk.karyawan (id, nama) values ('P9A', 'Uji A'), ('P9B', 'Uji B');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('P9A', '2030-01-01', 'ZP9', 1, 'TK/0', 'transfer', false), ('P9B', '2030-01-01', 'ZP9', 1, 'TK/0', 'tunai', false);
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('P9A', 'mulai', '2020-01-01'), ('P9B', 'mulai', '2020-01-01');
insert into induk.pengguna (telegram_id, peran) values (9901, 'hrd'), (9902, 'karyawan'), (9903, 'bos'), (9911, 'pembangun');
insert into induk.pengguna (telegram_id, peran, aktif) values (9912, 'pembangun', false);
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2033-01-21', '2033-02-20', '2033-02-25'), ('2033-02-21', '2033-03-20', '2033-03-25');
insert into aturan.pengaturan (kunci, nilai, berlaku_dari) values ('persetujuan_rilis', 'hrd_lalu_bos', current_date);

create temp table p as select row_number() over (order by tanggal_awal) as n, id from fakta.periode where tanggal_awal >= '2033-01-01';
create temp table h (nama text primary key, isi jsonb);
create temp table vb (n integer primary key, versi bigint);
grant all on h, p, vb to pintu;
create function pg_temp.pid(x integer) returns bigint language sql as $$ select id from p where n = x $$;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
create function pg_temp.status(x integer) returns text language sql as $$ select status from fakta.periode where id = (select id from p where n = x) $$;
create function pg_temp.segarkan() returns void language sql as $$
  delete from vb; insert into vb select n, fakta.versi_gaji_berlaku(id) from p $$;
create function pg_temp.vb(x integer) returns bigint language sql as $$ select versi from vb where n = x $$;
grant execute on function pg_temp.pid(integer), pg_temp.k(text), pg_temp.status(integer), pg_temp.vb(integer) to pintu;
create function pg_temp.hitung(x integer) returns bigint language plpgsql as $$
declare
  v_baca bigint;
  v_gaji bigint;
  v_n integer := coalesce((select max(nomor) from hitung.versi_hitung where periode_id = pg_temp.pid(x)), 0) + 1;
begin
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (pg_temp.pid(x), 'baca_tap', v_n, 'uji-8b2', 'b' || v_n, 'b' || v_n) returning id into v_baca;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil, versi_sumber)
  values (pg_temp.pid(x), 'hitung_gaji', v_n, 'uji-8b2', 'g' || v_n, 'g' || v_n, v_baca) returning id into v_gaji;
  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, dibayar, peringatan)
  select v_gaji, i, b, b, 0, b, b, '{}'::text[] from (values ('P9A', 1000), ('P9B', 3000)) x(i, b);
  return v_gaji;
end $$;
select pg_temp.hitung(1); select pg_temp.hitung(2);
select pg_temp.segarkan();

-- Periode 1: HRD mengajukan; pembangun menolak lalu (sesudah diajukan lagi) menyetujui; HRD merilis.
set local role pintu;
insert into h values ('daftar_hrd', api.pintu_daftar_periode('{"telegram_id": 9901, "untuk": "ajukan"}'));
insert into h values ('daftar_pembangun', api.pintu_daftar_periode('{"telegram_id": 9911, "untuk": "ajukan"}'));
insert into h values ('ajukan_1', api.pintu_ajukan(jsonb_build_object('telegram_id', 9901, 'periode_id', pg_temp.pid(1),
  'versi_gaji', pg_temp.vb(1))));
insert into h values ('tanpa_pin_belum_ada', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '730418')));
insert into h values ('pin_pembangun', api.pintu_atur_pin('{"telegram_id": 9911, "pin_baru": "730418"}'));
insert into h values ('pin_hrd', api.pintu_atur_pin('{"telegram_id": 9901, "pin_baru": "582093"}'));
insert into h values ('pin_salah', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '111222')));
insert into h values ('pin_kosong', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(1),
  'setuju', true)));
insert into h values ('tombol_tanpa_pin', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(1),
  'pengajuan_id', (pg_temp.k('ajukan_1') ->> 'pengajuan_id')::bigint, 'setuju', true)));
insert into h values ('bos_perintah', api.pintu_setujui(jsonb_build_object('telegram_id', 9903, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '730418')));
insert into h values ('karyawan', api.pintu_setujui(jsonb_build_object('telegram_id', 9902, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '730418')));
insert into h values ('hrd', api.pintu_setujui(jsonb_build_object('telegram_id', 9901, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '582093')));
insert into h values ('nonaktif', api.pintu_setujui(jsonb_build_object('telegram_id', 9912, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '730418')));
insert into h values ('periode_lain', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(2),
  'setuju', true, 'pin', '730418')));
insert into h values ('tolak_1', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(1),
  'setuju', false, 'pin', '730418')));
insert into h values ('ajukan_1b', api.pintu_ajukan(jsonb_build_object('telegram_id', 9901, 'periode_id', pg_temp.pid(1),
  'versi_gaji', pg_temp.vb(1))));
insert into h values ('setuju_1', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '730418')));
insert into h values ('setuju_1_lagi', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(1),
  'setuju', true, 'pin', '730418')));
insert into h values ('rilis_1', api.pintu_rilis(jsonb_build_object('telegram_id', 9901, 'periode_id', pg_temp.pid(1), 'pin', '582093')));
-- Periode 2: pembangun mengajukan, menyetujui, dan merilis sendiri (keputusan "pembangun bisa semua").
insert into h values ('ajukan_2', api.pintu_ajukan(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(2),
  'versi_gaji', pg_temp.vb(2))));
insert into h values ('setuju_2', api.pintu_setujui(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(2),
  'setuju', true, 'pin', '730418')));
insert into h values ('rilis_2', api.pintu_rilis(jsonb_build_object('telegram_id', 9911, 'periode_id', pg_temp.pid(2), 'pin', '730418')));
reset role;

select uji.sama('8b-2: daftar periode menandai akun pembangun',
  (pg_temp.k('daftar_hrd') ->> 'pembangun') || '/' || (pg_temp.k('daftar_pembangun') ->> 'pembangun'), 'false/true');
select uji.sama('8b-2: pengajuan memberi tahu bos dan pembangun aktif (bukan yang nonaktif)',
  concat_ws('/', pg_temp.k('ajukan_1') ->> 'bos', pg_temp.k('ajukan_1') ->> 'pembangun'), '[9903]/[9911]');
select uji.sama('8b-2: pembangun tanpa PIN terdaftar ditolak', pg_temp.k('tanpa_pin_belum_ada') ->> 'hasil', 'belum_ada_pin');
select uji.sama('8b-2: PIN salah, PIN kosong, dan tombol tanpa PIN ditolak',
  concat_ws('/', pg_temp.k('pin_salah') ->> 'hasil', pg_temp.k('pin_kosong') ->> 'hasil', pg_temp.k('tombol_tanpa_pin') ->> 'hasil'),
  'pin_salah/pin_salah/pin_salah');
select uji.sama('8b-2: bos lewat perintah diminta memakai tombol', pg_temp.k('bos_perintah') ->> 'hasil', 'pakai_tombol');
select uji.sama('8b-2: karyawan, HRD, dan pembangun nonaktif tidak bisa menyetujui',
  concat_ws('/', pg_temp.k('karyawan') ->> 'hasil', pg_temp.k('hrd') ->> 'hasil', pg_temp.k('nonaktif') ->> 'hasil'),
  'bukan_bos/bukan_bos/bukan_bos');
select uji.sama('8b-2: periode yang belum diajukan tidak bisa disetujui',
  concat_ws('/', pg_temp.k('periode_lain') ->> 'hasil', pg_temp.k('periode_lain') ->> 'status'), 'tidak_berlaku/dihitung');
select uji.sama('8b-2: pembangun menolak -> kembali dihitung; pengaju diberi tahu',
  concat_ws('/', pg_temp.k('tolak_1') ->> 'hasil', pg_temp.k('tolak_1') ->> 'oleh', pg_temp.k('tolak_1') ->> 'status',
            pg_temp.k('tolak_1') ->> 'pengaju'), 'ditolak/pembangun/dihitung/9901');
select uji.sama('8b-2: pembangun menyetujui -> HRD merilis',
  concat_ws('/', pg_temp.k('setuju_1') ->> 'hasil', pg_temp.k('setuju_1') ->> 'oleh', pg_temp.k('rilis_1') ->> 'hasil', pg_temp.status(1)),
  'disetujui/pembangun/dirilis/dirilis');
select uji.sama('8b-2: persetujuan yang sudah diputuskan tidak berlaku lagi', pg_temp.k('setuju_1_lagi') ->> 'hasil', 'tidak_berlaku');
select uji.sama('8b-2: pembangun mengajukan, menyetujui, dan merilis sendiri',
  concat_ws('/', pg_temp.k('ajukan_2') ->> 'hasil', pg_temp.k('setuju_2') ->> 'hasil', pg_temp.k('rilis_2') ->> 'hasil', pg_temp.status(2)),
  'diajukan/disetujui/dirilis/dirilis');
select uji.sama('8b-2: persetujuan pembangun tercatat "oleh pembangun" dengan akun pembangun',
  (select string_agg(x.keputusan || ':' || x.catatan || ':' || u.peran, ',' order by x.id)
   from fakta.persetujuan x join induk.pengguna u on u.id = x.penyetuju
   where x.perihal = 'rilis' and u.telegram_id = 9911), 'tolak:oleh pembangun:pembangun,setuju:oleh pembangun:pembangun,setuju:oleh pembangun:pembangun');
select uji.sama('8b-2: riwayat status periode 1 mencatat pembangun',
  (select string_agg(r.status_baru || ':' || coalesce(r.alasan, '-'), ' > ' order by r.id)
   from fakta.riwayat_status_periode r where r.periode_id = pg_temp.pid(1) and r.status_baru in ('dihitung', 'disetujui')
     and r.oleh = 'pengguna ' || (select id from induk.pengguna where telegram_id = 9911)),
  'dihitung:ditolak pembangun > disetujui:disetujui pembangun');
select uji.sama('8b-2: PIN salah tercatat sebagai percobaan gagal pembangun',
  (select count(*) from fakta.percobaan_pin x join induk.pengguna u on u.id = x.pengguna
   where u.telegram_id = 9911 and not x.berhasil), 3::bigint);
select uji.sama('8b-2: anon dan authenticated tidak bisa memanggil fungsi yang diganti',
  (select count(*) from pg_roles r cross join (values ('api.pintu_setujui(jsonb)'), ('api.pintu_ajukan(jsonb)'),
     ('api.pintu_daftar_periode(jsonb)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);
select uji.sama('8b-2: pintu tetap boleh memanggil fungsi yang diganti',
  (select count(*) from (values ('api.pintu_setujui(jsonb)'), ('api.pintu_ajukan(jsonb)'), ('api.pintu_daftar_periode(jsonb)')) f(n)
   where has_function_privilege('pintu', f.n::regprocedure, 'execute')), 3::bigint);

rollback;
