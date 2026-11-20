-- Uji paket 8b-3 (docs/rencana-8b-3.md): urutan rilis, batal, hapus PIN, undangan HRD/bos, menunggu PIN,
-- pengingat harian ke bos, teks status rilis. Fungsi api dipanggil sebagai peran pintu. Satu transaksi yang dibatalkan.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.divisi (kode, nama, pola) values ('ZM3', 'Uji Mudah', 'mingguan');
insert into induk.karyawan (id, nama) values ('M3A', 'Uji A');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('M3A', '2030-01-01', 'ZM3', 1, 'TK/0', 'transfer', false);
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('M3A', 'mulai', '2020-01-01');
insert into induk.pengguna (telegram_id, peran) values (7701, 'hrd'), (7702, 'karyawan'), (7703, 'bos'), (7711, 'pembangun'),
  (7704, 'hrd');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2034-01-21', '2034-02-20', '2034-02-25'), ('2034-02-21', '2034-03-20', '2034-03-25'), ('2034-03-21', '2034-04-20', '2034-04-25');

create temp table p as select row_number() over (order by tanggal_awal) as n, id from fakta.periode where tanggal_awal >= '2034-01-01';
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
  values (pg_temp.pid(x), 'baca_tap', v_n, 'uji-8b3', 'b' || v_n, 'b' || v_n) returning id into v_baca;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil, versi_sumber)
  values (pg_temp.pid(x), 'hitung_gaji', v_n, 'uji-8b3', 'g' || v_n, 'g' || v_n, v_baca) returning id into v_gaji;
  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, dibayar, peringatan)
  values (v_gaji, 'M3A', 1000, 1000, 0, 1000, 1000, '{}');
  return v_gaji;
end $$;
select pg_temp.hitung(1); select pg_temp.hitung(2); select pg_temp.hitung(3);
select pg_temp.segarkan();

-- ---------------------------------------------------------------------------
-- Urutan rilis (pengaturan bawaan: HRD saja)
-- ---------------------------------------------------------------------------
set local role pintu;
insert into h values ('pin_7701', api.pintu_atur_pin('{"telegram_id": 7701, "pin_baru": "730418"}'));
insert into h values ('daftar_awal', api.pintu_daftar_periode('{"telegram_id": 7701, "untuk": "ajukan"}'));
insert into h values ('ajukan_2_dulu', api.pintu_ajukan(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2),
  'versi_gaji', pg_temp.vb(2))));
insert into h values ('ajukan_1', api.pintu_ajukan(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(1),
  'versi_gaji', pg_temp.vb(1))));
reset role;
select uji.sama('8b-3: status rilis periode 1 sesudah diajukan', fakta.status_rilis_teks(pg_temp.pid(1)), 'Diajukan, menunggu rilis');
select uji.sama('8b-3: status rilis periode 2 menunggu periode 1', fakta.status_rilis_teks(pg_temp.pid(2)),
  'Belum bisa diajukan: rilis dulu periode no. ' || pg_temp.pid(1));
set local role pintu;
insert into h values ('rilis_1', api.pintu_rilis(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(1), 'pin', '730418')));
insert into h values ('daftar_sesudah', api.pintu_daftar_periode('{"telegram_id": 7701, "untuk": "ajukan"}'));
insert into h values ('ajukan_2', api.pintu_ajukan(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2),
  'versi_gaji', pg_temp.vb(2))));
reset role;
select uji.sama('8b-3: daftar /ajukan awal hanya periode 1; periode 2 dan 3 tertahan urutan',
  concat_ws('/', (select jsonb_agg(x -> 'periode_id') from jsonb_array_elements(pg_temp.k('daftar_awal') -> 'periode') x)::text,
            (select jsonb_agg(x -> 'menunggu') from jsonb_array_elements(pg_temp.k('daftar_awal') -> 'tertahan_urutan') x)::text),
  concat_ws('/', jsonb_build_array(pg_temp.pid(1))::text, jsonb_build_array(pg_temp.pid(1), pg_temp.pid(1))::text));
select uji.sama('8b-3: periode 2 tidak bisa diajukan sebelum periode 1 dirilis',
  concat_ws('/', pg_temp.k('ajukan_2_dulu') ->> 'hasil', pg_temp.k('ajukan_2_dulu') ->> 'menunggu'), 'tunggu_periode/' || pg_temp.pid(1));
select uji.sama('8b-3: rilis memberi kabar ke HRD lain, bos, pembangun (tanpa perilis)',
  concat_ws('/', pg_temp.k('rilis_1') ->> 'hasil', pg_temp.k('rilis_1') ->> 'kabari'), 'dirilis/[7703, 7704, 7711]');
select uji.sama('8b-3: sesudah periode 1 dirilis, periode 2 bisa diajukan',
  concat_ws('/', (pg_temp.k('daftar_sesudah') -> 'periode' -> 0 ->> 'periode_id'), pg_temp.k('ajukan_2') ->> 'hasil'),
  pg_temp.pid(2) || '/diajukan');
select uji.sama('8b-3: teks status Dirilis', fakta.status_rilis_teks(pg_temp.pid(1)), 'Dirilis');

-- ---------------------------------------------------------------------------
-- Batal pengajuan
-- ---------------------------------------------------------------------------
set local role pintu;
insert into h values ('batal_karyawan', api.pintu_batal(jsonb_build_object('telegram_id', 7702, 'periode_id', pg_temp.pid(2))));
insert into h values ('batal_bos', api.pintu_batal(jsonb_build_object('telegram_id', 7703, 'periode_id', pg_temp.pid(2))));
insert into h values ('batal_3', api.pintu_batal(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(3))));
insert into h values ('batal_2', api.pintu_batal(jsonb_build_object('telegram_id', 7704, 'periode_id', pg_temp.pid(2))));
reset role;
select uji.sama('8b-3: karyawan dan bos tidak bisa membatalkan',
  pg_temp.k('batal_karyawan') ->> 'hasil' || '/' || (pg_temp.k('batal_bos') ->> 'hasil'), 'bukan_hrd/bukan_hrd');
select uji.sama('8b-3: periode yang tidak diajukan tidak bisa dibatalkan',
  concat_ws('/', pg_temp.k('batal_3') ->> 'hasil', pg_temp.k('batal_3') ->> 'status'), 'tidak_bisa/dihitung');
select uji.sama('8b-3: HRD membatalkan -> dihitung; tercatat; kabar ke akun lain',
  concat_ws('/', pg_temp.k('batal_2') ->> 'hasil', pg_temp.status(2), pg_temp.k('batal_2') ->> 'kabari',
            (select alasan from fakta.riwayat_status_periode where periode_id = pg_temp.pid(2) order by id desc limit 1)),
  'dibatalkan/dihitung/[7701, 7703, 7711]/dibatalkan hrd');
-- disetujui -> dibatalkan (HRD lalu bos)
insert into aturan.pengaturan (kunci, nilai, berlaku_dari) values ('persetujuan_rilis', 'hrd_lalu_bos', current_date);
select pg_temp.segarkan();
set local role pintu;
insert into h values ('ajukan_2b', api.pintu_ajukan(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2),
  'versi_gaji', pg_temp.vb(2))));
insert into h values ('setuju_2b', api.pintu_setujui(jsonb_build_object('telegram_id', 7703, 'periode_id', pg_temp.pid(2),
  'pengajuan_id', (pg_temp.k('ajukan_2b') ->> 'pengajuan_id')::bigint, 'setuju', true)));
reset role;
select uji.sama('8b-3: teks status Disetujui', fakta.status_rilis_teks(pg_temp.pid(2)), 'Disetujui, menunggu rilis');
set local role pintu;
insert into h values ('batal_2b', api.pintu_batal(jsonb_build_object('telegram_id', 7711, 'periode_id', pg_temp.pid(2))));
reset role;
select uji.sama('8b-3: pembangun membatalkan pengajuan yang sudah disetujui -> dihitung',
  concat_ws('/', pg_temp.k('batal_2b') ->> 'hasil', pg_temp.k('batal_2b') ->> 'oleh', pg_temp.status(2),
            (select alasan from fakta.riwayat_status_periode where periode_id = pg_temp.pid(2) order by id desc limit 1)),
  'dibatalkan/pembangun/dihitung/dibatalkan pembangun');
select uji.sama('8b-3: teks status Bisa diajukan', fakta.status_rilis_teks(pg_temp.pid(2)), 'Bisa diajukan');

-- ---------------------------------------------------------------------------
-- Pengingat harian ke bos
-- ---------------------------------------------------------------------------
select pg_temp.segarkan();
set local role pintu;
insert into h values ('ajukan_2c', api.pintu_ajukan(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2),
  'versi_gaji', pg_temp.vb(2))));
insert into h values ('ingat_hari_ini', api.pintu_pengingat_rilis('{}'));
insert into h values ('ingat_besok', api.pintu_pengingat_rilis(jsonb_build_object('tanggal', current_date + 1)));
insert into h values ('ingat_besok_lagi', api.pintu_pengingat_rilis(jsonb_build_object('tanggal', current_date + 1)));
reset role;
select uji.sama('8b-3: teks status Diajukan (HRD lalu bos)', fakta.status_rilis_teks(pg_temp.pid(2)), 'Diajukan, menunggu persetujuan');
select uji.sama('8b-3: pengajuan hari ini belum diingatkan', jsonb_array_length(pg_temp.k('ingat_hari_ini') -> 'kirim'), 0);
select uji.sama('8b-3: besoknya bos diingatkan sekali, dengan nomor pengajuan untuk tombol',
  concat_ws('/', jsonb_array_length(pg_temp.k('ingat_besok') -> 'kirim'), pg_temp.k('ingat_besok') -> 'kirim' -> 0 ->> 'bos',
            pg_temp.k('ingat_besok') -> 'kirim' -> 0 ->> 'pembangun',
            (pg_temp.k('ingat_besok') -> 'kirim' -> 0 ->> 'pengajuan_id') = (pg_temp.k('ajukan_2c') ->> 'pengajuan_id'),
            jsonb_array_length(pg_temp.k('ingat_besok_lagi') -> 'kirim')),
  '1/[7703]/[]/t/0');
update induk.pengguna set aktif = false where telegram_id = 7703;
set local role pintu;
insert into h values ('ingat_tanpa_bos', api.pintu_pengingat_rilis(jsonb_build_object('tanggal', current_date + 2)));
reset role;
select uji.sama('8b-3: tanpa akun bos, pengingat ke pembangun',
  concat_ws('/', pg_temp.k('ingat_tanpa_bos') -> 'kirim' -> 0 ->> 'bos', pg_temp.k('ingat_tanpa_bos') -> 'kirim' -> 0 ->> 'pembangun'),
  '[]/[7711]');
update induk.pengguna set aktif = true where telegram_id = 7703;

-- ---------------------------------------------------------------------------
-- Hapus PIN
-- ---------------------------------------------------------------------------
create temp table uid as select telegram_id as tg, id from induk.pengguna where telegram_id between 7700 and 7799;
grant all on uid to pintu;
set local role pintu;
insert into h select 'pin_salah' || i, api.pintu_rilis(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2), 'pin', '111112'))
from generate_series(1, 5) i;
insert into h values ('terkunci', api.pintu_rilis(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2), 'pin', '730418')));
insert into h values ('daftar_pin_hrd', api.pintu_daftar_pin('{"telegram_id": 7701}'));
insert into h values ('daftar_pin', api.pintu_daftar_pin('{"telegram_id": 7711}'));
insert into h values ('hapus_hrd', api.pintu_hapus_pin(jsonb_build_object('telegram_id', 7704,
  'pengguna_id', (select id from uid where tg = 7701))));
insert into h values ('hapus_karyawan', api.pintu_hapus_pin(jsonb_build_object('telegram_id', 7711,
  'pengguna_id', (select id from uid where tg = 7702))));
insert into h values ('hapus_tanpa_pin', api.pintu_hapus_pin(jsonb_build_object('telegram_id', 7711,
  'pengguna_id', (select id from uid where tg = 7704))));
insert into h values ('hapus', api.pintu_hapus_pin(jsonb_build_object('telegram_id', 7711,
  'pengguna_id', (select id from uid where tg = 7701))));
insert into h values ('pin_baru', api.pintu_atur_pin('{"telegram_id": 7701, "pin_baru": "582093"}'));
insert into h values ('pin_lama_tidak', api.pintu_rilis(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2), 'pin', '730418')));
insert into h values ('pin_baru_benar', api.pintu_rilis(jsonb_build_object('telegram_id', 7701, 'periode_id', pg_temp.pid(2), 'pin', '582093')));
reset role;
select uji.sama('8b-3: 5 PIN salah -> terkunci', pg_temp.k('terkunci') ->> 'hasil', 'terkunci');
select uji.sama('8b-3: hanya pembangun yang bisa melihat daftar dan menghapus PIN',
  pg_temp.k('daftar_pin_hrd') ->> 'hasil' || '/' || (pg_temp.k('hapus_hrd') ->> 'hasil'), 'bukan_pembangun/bukan_pembangun');
select uji.sama('8b-3: daftar PIN berisi akun HRD dan pembangun aktif',
  (select string_agg((x ->> 'peran') || ':' || (x ->> 'punya_pin'), ',' order by (x ->> 'id')::bigint)
   from jsonb_array_elements(pg_temp.k('daftar_pin') -> 'akun') x),
  'hrd:true,pembangun:false,hrd:false');
select uji.sama('8b-3: akun karyawan dan akun tanpa PIN tidak bisa dihapus PIN-nya',
  pg_temp.k('hapus_karyawan') ->> 'hasil' || '/' || (pg_temp.k('hapus_tanpa_pin') ->> 'hasil'), 'tidak_ada/belum_ada_pin');
select uji.sama('8b-3: pembangun menghapus PIN; pemilik diberi tahu; PIN baru langsung bisa dipakai (hitungan salah mulai lagi)',
  concat_ws('/', pg_temp.k('hapus') ->> 'hasil', pg_temp.k('hapus') ->> 'telegram_id', pg_temp.k('pin_baru') ->> 'hasil',
            pg_temp.k('pin_lama_tidak') ->> 'hasil', pg_temp.k('pin_baru_benar') ->> 'hasil'),
  'dihapus/7701/dibuat/pin_salah/belum_disetujui');
select uji.sama('8b-3: hapus PIN tercatat (siapa, oleh siapa)',
  (select count(*) from fakta.hapus_pin x join induk.pengguna a on a.id = x.pengguna join induk.pengguna b on b.id = x.oleh
   where a.telegram_id = 7701 and b.telegram_id = 7711), 1::bigint);
select uji.harus_ditolak('8b-3: catatan hapus PIN hanya bertambah', 'delete from fakta.hapus_pin');

-- ---------------------------------------------------------------------------
-- Undangan akun HRD/bos
-- ---------------------------------------------------------------------------
set local role pintu;
insert into h values ('undang_hrd', api.pintu_undang(jsonb_build_object('telegram_id', 7701, 'peran', 'bos',
  'sidik', encode(sha256('8b3-undang-hrd'), 'hex'))));
insert into h values ('undang_salah', api.pintu_undang(jsonb_build_object('telegram_id', 7711, 'peran', 'pembangun',
  'sidik', encode(sha256('8b3-salah'), 'hex'))));
insert into h values ('undang_bos', api.pintu_undang(jsonb_build_object('telegram_id', 7711, 'peran', 'bos',
  'sidik', encode(sha256('8b3-bos'), 'hex'))));
insert into h values ('gabung_salah', api.pintu_gabung(jsonb_build_object('telegram_id', 7790, 'sidik', encode(sha256('bukan'), 'hex'))));
insert into h values ('gabung_bos', api.pintu_gabung(jsonb_build_object('telegram_id', 7790, 'sidik', encode(sha256('8b3-bos'), 'hex'))));
insert into h values ('gabung_lagi', api.pintu_gabung(jsonb_build_object('telegram_id', 7791, 'sidik', encode(sha256('8b3-bos'), 'hex'))));
insert into h values ('gabung_terdaftar', api.pintu_gabung(jsonb_build_object('telegram_id', 7702, 'sidik', encode(sha256('8b3-bos'), 'hex'))));
insert into h values ('peran_baru', api.pintu_akun('{"telegram_id": 7790}'));
insert into h select 'gabung_coba' || i, api.pintu_gabung(jsonb_build_object('telegram_id', 7792, 'sidik', encode(sha256(convert_to('x' || i, 'UTF8')), 'hex')))
from generate_series(1, 5) i;
insert into h values ('undang_hrd2', api.pintu_undang(jsonb_build_object('telegram_id', 7711, 'peran', 'hrd',
  'sidik', encode(sha256('8b3-hrd'), 'hex'))));
insert into h values ('gabung_terkunci', api.pintu_gabung(jsonb_build_object('telegram_id', 7792, 'sidik', encode(sha256('8b3-hrd'), 'hex'))));
reset role;
select uji.sama('8b-3: hanya pembangun yang bisa mengundang; peran hanya hrd/bos',
  concat_ws('/', pg_temp.k('undang_hrd') ->> 'hasil', pg_temp.k('undang_salah') ->> 'hasil', pg_temp.k('undang_bos') ->> 'hasil'),
  'bukan_pembangun/peran_salah/dibuat');
select uji.sama('8b-3: kode salah ditolak; kode benar -> akun bos terdaftar; pembuat diberi tahu',
  concat_ws('/', pg_temp.k('gabung_salah') ->> 'hasil', pg_temp.k('gabung_salah') ->> 'sisa', pg_temp.k('gabung_bos') ->> 'hasil',
            pg_temp.k('gabung_bos') ->> 'peran', pg_temp.k('gabung_bos') ->> 'pembangun',
            (select peran from induk.pengguna where telegram_id = 7790), pg_temp.k('peran_baru') ->> 'peran'),
  'salah/4/terdaftar/bos/7711/bos/bos');
select uji.sama('8b-3: kode sekali pakai; akun yang sudah terdaftar tidak bisa bergabung lagi',
  pg_temp.k('gabung_lagi') ->> 'hasil' || '/' || (pg_temp.k('gabung_terdaftar') ->> 'hasil') || '/' || (pg_temp.k('gabung_terdaftar') ->> 'peran'),
  'salah/sudah_terdaftar/karyawan');
select uji.sama('8b-3: 5 kode salah per jam -> terkunci, kode benar pun ditolak',
  pg_temp.k('gabung_terkunci') ->> 'hasil', 'terkunci');
select uji.sama('8b-3: undangan hanya menyimpan sidik', (select count(*) from fakta.undangan_akun where sidik !~ '^[0-9a-f]{64}$'), 0::bigint);

-- ---------------------------------------------------------------------------
-- Menunggu PIN sesudah tombol
-- ---------------------------------------------------------------------------
set local role pintu;
insert into h values ('minta_karyawan', api.pintu_minta_pin(jsonb_build_object('telegram_id', 7702, 'aksi', 'rilis', 'periode_id', pg_temp.pid(2))));
insert into h values ('minta_hrd_setujui', api.pintu_minta_pin(jsonb_build_object('telegram_id', 7701, 'aksi', 'setujui', 'periode_id', pg_temp.pid(2))));
insert into h values ('minta_salah', api.pintu_minta_pin(jsonb_build_object('telegram_id', 7701, 'aksi', 'rilis', 'periode_id', -1)));
insert into h values ('minta_hrd', api.pintu_minta_pin(jsonb_build_object('telegram_id', 7701, 'aksi', 'rilis', 'periode_id', pg_temp.pid(2))));
insert into h values ('minta_pembangun', api.pintu_minta_pin(jsonb_build_object('telegram_id', 7711, 'aksi', 'tolak', 'periode_id', pg_temp.pid(2))));
insert into h values ('ambil_hrd', api.pintu_ambil_pin('{"telegram_id": 7701}'));
insert into h values ('ambil_hrd_lagi', api.pintu_ambil_pin('{"telegram_id": 7701}'));
reset role;
update fakta.tunggu_pin set batas = now() - interval '1 minute' where telegram_id = 7711;
set local role pintu;
insert into h values ('ambil_lewat', api.pintu_ambil_pin('{"telegram_id": 7711}'));
reset role;
select uji.sama('8b-3: minta PIN: karyawan, HRD untuk setujui, periode salah ditolak',
  concat_ws('/', pg_temp.k('minta_karyawan') ->> 'hasil', pg_temp.k('minta_hrd_setujui') ->> 'hasil', pg_temp.k('minta_salah') ->> 'hasil'),
  'bukan_hrd/bukan_pembangun/tidak_ada');
select uji.sama('8b-3: tunggu PIN diambil sekali; lewat 5 menit tidak berlaku',
  concat_ws('/', pg_temp.k('minta_hrd') ->> 'hasil', pg_temp.k('minta_pembangun') ->> 'hasil', pg_temp.k('ambil_hrd') ->> 'aksi',
            (pg_temp.k('ambil_hrd') ->> 'periode_id')::bigint = pg_temp.pid(2), pg_temp.k('ambil_hrd_lagi')::text,
            pg_temp.k('ambil_lewat')::text),
  'menunggu/menunggu/rilis/t/{}/{"lewat": true}');

-- ---------------------------------------------------------------------------
-- Hak akses
-- ---------------------------------------------------------------------------
select uji.sama('8b-3: anon dan authenticated tidak bisa memanggil fungsi baru',
  (select count(*) from pg_roles r cross join (values ('api.pintu_batal(jsonb)'), ('api.pintu_daftar_pin(jsonb)'),
     ('api.pintu_hapus_pin(jsonb)'), ('api.pintu_undang(jsonb)'), ('api.pintu_gabung(jsonb)'),
     ('api.pintu_minta_pin(jsonb)'), ('api.pintu_ambil_pin(jsonb)'), ('api.pintu_pengingat_rilis(jsonb)'),
     ('fakta.status_rilis_teks(bigint)'), ('fakta.periode_menunggu(bigint)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);
select uji.harus_ditolak('8b-3: pintu tidak bisa membaca undangan', 'select count(*) from fakta.undangan_akun', 'pintu');
select uji.harus_ditolak('8b-3: pintu tidak bisa membaca tunggu PIN', 'select count(*) from fakta.tunggu_pin', 'pintu');
select uji.harus_ditolak('8b-3: pintu tidak bisa memanggil teks status langsung', 'select fakta.status_rilis_teks(1)', 'pintu');

rollback;
