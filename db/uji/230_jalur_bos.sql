-- Uji paket 8d (docs/rencana-8d.md): total lengkap untuk bos/pembangun dengan PIN (F15, F15b), orang rahasia wajib transfer.
begin;
set local app.pengguna = 'uji-otomatis';
insert into induk.divisi (kode, nama, pola) values ('ZB8', 'Uji Bos', 'mingguan');
insert into induk.karyawan (id, nama) values ('B8A', 'Uji Biasa Tunai'), ('B8B', 'Uji Biasa Transfer'), ('B8R', 'Uji Rahasia');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('B8A', '2030-01-01', 'ZB8', 1, 'TK/0', 'tunai', false), ('B8B', '2030-01-01', 'ZB8', 1, 'TK/0', 'transfer', false),
  ('B8R', '2030-01-01', 'ZB8', 1, 'TK/0', 'transfer', true);
insert into induk.pengguna (telegram_id, peran) values (6601, 'hrd'), (6603, 'bos'), (6611, 'pembangun');
insert into induk.pengguna (telegram_id, peran, id_karyawan) values (6602, 'karyawan', 'B8A');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2038-01-21', '2038-02-20', '2038-02-25'),
  ('2038-02-21', '2038-03-20', '2038-03-25');
create temp table p as select row_number() over (order by tanggal_awal) as n, id from fakta.periode where tanggal_awal >= '2038-01-01';
create temp table h (nama text primary key, isi jsonb);
grant all on h, p to pintu;
create function pg_temp.pid(x integer) returns bigint language sql as $$ select id from p where n = x $$;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
grant execute on function pg_temp.pid(integer), pg_temp.k(text) to pintu;
do $$
declare
  v_baca bigint;
  v_gaji bigint;
  v_p bigint := (select id from p where n = 1);
begin
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (v_p, 'baca_tap', 1, 'uji-8d', 'b', 'b') returning id into v_baca;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil, versi_sumber)
  values (v_p, 'hitung_gaji', 1, 'uji-8d', 'g', 'g', v_baca) returning id into v_gaji;
  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, dibayar,
                                     sisa_pembulatan, peringatan)
  values (v_gaji, 'B8A', 1000, 1000, 0, 1000, 1000, 0, '{}'), (v_gaji, 'B8B', 2000, 2000, 0, 2000, 2000, 0, '{}'),
         (v_gaji, 'B8R', 9000, 9000, 0, 9000, 9000, 0, '{}');
end $$;

-- Karyawan baru tanpa riwayat, supaya hanya aturan wajib transfer yang bisa menolak (bukan riwayat yang bertabrakan).
insert into induk.karyawan (id, nama) values ('B8X', 'Uji Rahasia Tunai');
select uji.harus_ditolak('8d (i): orang rahasia tidak boleh dibayar tunai',
  $q$insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia)
     values ('B8X', '2039-01-01', 'ZB8', 1, 'TK/0', 'tunai', true)$q$);
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia)
values ('B8X', '2039-01-01', 'ZB8', 1, 'TK/0', 'transfer', true);
select uji.sama('8d (i): orang rahasia lewat transfer tetap boleh',
  (select count(*) from induk.karyawan_riwayat where id_karyawan = 'B8X'), 1::bigint);

set local role pintu;
insert into h values ('pin_bos', api.pintu_atur_pin('{"telegram_id": 6603, "pin_baru": "730418"}'));
insert into h values ('pin_karyawan', api.pintu_atur_pin('{"telegram_id": 6602, "pin_baru": "730418"}'));
insert into h values ('pin_pembangun', api.pintu_atur_pin('{"telegram_id": 6611, "pin_baru": "582093"}'));
insert into h values ('lengkap_hrd', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 6601, 'periode_id', pg_temp.pid(1), 'pin', '730418')));
insert into h values ('lengkap_karyawan', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 6602, 'periode_id', pg_temp.pid(1), 'pin', '730418')));
insert into h values ('lengkap_salah', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 6603, 'periode_id', pg_temp.pid(1), 'pin', '111112')));
insert into h values ('lengkap_kosong', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 6603, 'periode_id', pg_temp.pid(1))));
insert into h values ('lengkap_bos', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 6603, 'periode_id', pg_temp.pid(1), 'pin', '730418')));
insert into h values ('lengkap_pembangun', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 6611, 'periode_id', pg_temp.pid(1), 'pin', '582093')));
insert into h values ('lengkap_tanpa_hitung', api.pintu_total_lengkap(jsonb_build_object('telegram_id', 6603, 'periode_id', pg_temp.pid(2), 'pin', '730418')));
insert into h values ('periode_bos', api.pintu_periode_gaji('{"telegram_id": 6603}'));
insert into h values ('periode_hrd', api.pintu_periode_gaji('{"telegram_id": 6601}'));
insert into h values ('minta_hrd', api.pintu_minta_pin(jsonb_build_object('telegram_id', 6601, 'aksi', 'lengkap', 'periode_id', pg_temp.pid(1))));
insert into h values ('minta_bos', api.pintu_minta_pin(jsonb_build_object('telegram_id', 6603, 'aksi', 'lengkap', 'periode_id', pg_temp.pid(1))));
insert into h values ('ambil_bos', api.pintu_ambil_pin('{"telegram_id": 6603}'));
reset role;

select uji.sama('8d: bos dan pembangun bisa membuat PIN; karyawan tidak',
  concat_ws('/', pg_temp.k('pin_bos') ->> 'hasil', pg_temp.k('pin_pembangun') ->> 'hasil', pg_temp.k('pin_karyawan') ->> 'hasil'),
  'dibuat/dibuat/bukan_hrd');
select uji.sama('8d (F15): HRD dan karyawan tidak bisa melihat total lengkap',
  pg_temp.k('lengkap_hrd') ->> 'hasil' || '/' || (pg_temp.k('lengkap_karyawan') ->> 'hasil'), 'bukan_bos/bukan_bos');
select uji.sama('8d: PIN salah atau kosong ditolak', pg_temp.k('lengkap_salah') ->> 'hasil' || '/' || (pg_temp.k('lengkap_kosong') ->> 'hasil'),
  'pin_salah/pin_salah');
select uji.sama('8d: total lengkap termasuk orang rahasia; transfer + tunai = dibayar',
  concat_ws('/', pg_temp.k('lengkap_bos') ->> 'hasil', pg_temp.k('lengkap_bos') -> 'lengkap' ->> 'orang',
            pg_temp.k('lengkap_bos') -> 'lengkap' ->> 'bersih', pg_temp.k('lengkap_bos') -> 'lengkap' ->> 'transfer',
            pg_temp.k('lengkap_bos') -> 'lengkap' ->> 'tunai', pg_temp.k('lengkap_bos') -> 'lengkap' ->> 'dibayar'),
  'ada/3/12000/11000/1000/12000');
select uji.sama('8d (F15b): total lengkap - total terlihat HRD = jumlah gaji orang rahasia; daftar rahasia benar',
  concat_ws('/', (pg_temp.k('lengkap_bos') -> 'lengkap' ->> 'bersih')::bigint - (pg_temp.k('lengkap_bos') -> 'terlihat' ->> 'bersih')::bigint
                 - (select sum((x ->> 'bersih')::bigint) from jsonb_array_elements(pg_temp.k('lengkap_bos') -> 'daftar_rahasia') x),
            pg_temp.k('lengkap_bos') -> 'terlihat' ->> 'orang', pg_temp.k('lengkap_bos') -> 'terlihat' ->> 'rahasia',
            (select string_agg((x ->> 'id') || ':' || (x ->> 'nama') || ':' || (x ->> 'bersih') || ':' || (x ->> 'cara_bayar'), ',')
             from jsonb_array_elements(pg_temp.k('lengkap_bos') -> 'daftar_rahasia') x)),
  '0/2/1/B8R:Uji Rahasia:9000:transfer');
select uji.sama('8d: pembangun melihat hal yang sama; periode tanpa hitungan -> tidak_ada',
  concat_ws('/', pg_temp.k('lengkap_pembangun') -> 'lengkap' ->> 'bersih', pg_temp.k('lengkap_tanpa_hitung') ->> 'hasil'), '12000/tidak_ada');
select uji.sama('8d: setiap lihat total lengkap tercatat (siapa, periode)',
  (select string_agg(u.peran, ',' order by l.id) from fakta.lihat_rahasia l join induk.pengguna u on u.id = l.pengguna
   where l.periode_id = pg_temp.pid(1)), 'bos,pembangun');
select uji.harus_ditolak('8d: catatan lihat rahasia hanya bertambah', 'delete from fakta.lihat_rahasia');
select uji.sama('8d: pilihan periode hanya yang punya hitungan; hanya bos/pembangun',
  concat_ws('/', (select string_agg((x ->> 'periode_id'), ',') from jsonb_array_elements(pg_temp.k('periode_bos') -> 'periode') x
                  where (x ->> 'periode_id')::bigint in (pg_temp.pid(1), pg_temp.pid(2))) = pg_temp.pid(1)::text,
            pg_temp.k('periode_hrd') ->> 'hasil'), 't/bukan_bos');
select uji.sama('8d: minta PIN "lengkap": HRD ditolak, bos menunggu lalu diambil',
  concat_ws('/', pg_temp.k('minta_hrd') ->> 'hasil', pg_temp.k('minta_bos') ->> 'hasil', pg_temp.k('ambil_bos') ->> 'aksi'),
  'bukan_bos/menunggu/lengkap');
select uji.sama('8d: anon dan authenticated tidak bisa memanggil fungsi baru',
  (select count(*) from pg_roles r cross join (values ('api.pintu_total_lengkap(jsonb)'), ('api.pintu_periode_gaji(jsonb)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);
select uji.harus_ditolak('8d: pintu tidak bisa membaca catatan lihat rahasia', 'select count(*) from fakta.lihat_rahasia', 'pintu');
rollback;
