-- Uji paket 9a (docs/rencana-9a.md): web HRD lihat saja (sesi, akses, angka sama dengan Sheets, rahasia tanpa angka).
begin;
set local app.pengguna = 'uji-otomatis';
insert into induk.divisi (kode, nama, pola) values ('ZW9', 'Uji Web', 'mingguan');
insert into induk.karyawan (id, nama) values ('W9A', 'Uji Web Transfer'), ('W9B', 'Uji Web Tunai'), ('W9R', 'Uji Web Rahasia');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('W9A', '2040-01-01', 'ZW9', 1, 'TK/0', 'transfer', false), ('W9B', '2040-01-01', 'ZW9', 1, 'TK/0', 'tunai', false),
  ('W9R', '2040-01-01', 'ZW9', 1, 'TK/0', 'transfer', true);
insert into induk.pengguna (telegram_id, peran, email) values (9901, 'hrd', 'hrd-web@contoh.test'), (9903, 'bos', 'bos-web@contoh.test');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2041-01-21', '2041-02-20', '2041-02-25');
create temp table h (nama text primary key, isi jsonb);
grant all on h to pintu;
create function pg_temp.k(x text) returns jsonb language sql as $$ select isi from h where nama = x $$;
create function pg_temp.sd(x text) returns text language sql as $$ select encode(sha256(convert_to(x, 'UTF8')), 'hex') $$;
grant execute on function pg_temp.k(text), pg_temp.sd(text) to pintu;
do $$
declare
  v_p bigint := (select id from fakta.periode where tanggal_awal = '2041-01-21');
  v_baca bigint;
  v_lama bigint;
  v_gaji bigint;
begin
  insert into h values ('periode', jsonb_build_object('id', v_p));
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (v_p, 'baca_tap', 1, 'uji-9a', 'a', 'a') returning id into v_baca;
  -- Baca tap lebih baru yang BELUM dipakai gaji: web harus tetap memakai versi_sumber gaji (sama dengan Sheets).
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (v_p, 'baca_tap', 2, 'uji-9a', 'b', 'b') returning id into v_lama;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil, versi_sumber)
  values (v_p, 'hitung_gaji', 1, 'uji-9a', 'g', 'g', v_baca) returning id into v_gaji;
  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, dibayar,
                                     sisa_pembulatan, peringatan)
  values (v_gaji, 'W9A', 1100, 1100, -100, 1000, 1000, 0, '{}'), (v_gaji, 'W9B', 2300, 2300, -300, 2000, 2000, 0, '{pph_masa_terakhir_tertahan}'),
         (v_gaji, 'W9R', 9900, 9900, -900, 9000, 9000, 0, '{}');
  insert into hitung.rincian_gaji (versi_id, id_karyawan, komponen, kelompok, nominal, bukti)
  values (v_gaji, 'W9A', 'gaji_pokok', 'pendapatan', 1100, 'uji'), (v_gaji, 'W9A', 'bpjs', 'potongan', -100, 'uji'),
         (v_gaji, 'W9R', 'gaji_pokok', 'pendapatan', 9900, 'uji');
  insert into hitung.hasil_harian (versi_id, id_karyawan, tanggal, divisi, regu, jenis_hari, status, asal, menit_telat)
  values (v_baca, 'W9A', '2041-01-22', 'ZW9', 0, 'kerja', 'hadir', 'mesin', 7), (v_baca, 'W9A', '2041-01-23', 'ZW9', 0, 'kerja', 'alpha', 'mesin', 0),
         (v_baca, 'W9R', '2041-01-22', 'ZW9', 0, 'kerja', 'hadir', 'mesin', 0),
         (v_lama, 'W9A', '2041-01-22', 'ZW9', 0, 'kerja', 'sakit', 'perintah', 0);
  insert into hitung.anomali (versi_id, jenis, tingkat, id_karyawan, tanggal, keterangan)
  values (v_baca, 'alpha_beruntun', 'harian', 'W9A', '2041-01-23', 'uji 9a'), (v_lama, 'id_tidak_dikenal', 'segera', null, null, 'versi lain');
end $$;
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, nilai) values ('file', 'izin', 'W9A', '2041-01-24', 'RAHASIA-NILAI');
-- Kode email: HRD (benar), bos (bukan peran web).
insert into fakta.kode_email (pengguna, email, sidik, berlaku_sampai)
select id, email, pg_temp.sd(email || ':123456'), now() + interval '10 minutes' from induk.pengguna where telegram_id in (9901, 9903);

set local role pintu;
insert into h values ('salah', api.web_sesi_buat(jsonb_build_object('email', 'HRD-web@contoh.test', 'sidik_kode', pg_temp.sd('hrd-web@contoh.test:000000'), 'sidik_sesi', pg_temp.sd('sesi-x'))));
insert into h values ('masuk', api.web_sesi_buat(jsonb_build_object('email', 'hrd-web@contoh.test', 'sidik_kode', pg_temp.sd('hrd-web@contoh.test:123456'), 'sidik_sesi', pg_temp.sd('sesi-1'))));
insert into h values ('ulang', api.web_sesi_buat(jsonb_build_object('email', 'hrd-web@contoh.test', 'sidik_kode', pg_temp.sd('hrd-web@contoh.test:123456'), 'sidik_sesi', pg_temp.sd('sesi-2'))));
insert into h values ('bos', api.web_sesi_buat(jsonb_build_object('email', 'bos-web@contoh.test', 'sidik_kode', pg_temp.sd('bos-web@contoh.test:123456'), 'sidik_sesi', pg_temp.sd('sesi-3'))));
insert into h values ('palsu', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('bukan'), 'aksi', 'ringkasan')));
insert into h values ('ringkasan', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'ringkasan')));
insert into h values ('gaji', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'gaji', 'periode_id', pg_temp.k('periode') ->> 'id')));
insert into h values ('orang_a', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'orang', 'periode_id', pg_temp.k('periode') ->> 'id', 'id_karyawan', 'W9A')));
insert into h values ('orang_r', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'orang', 'periode_id', pg_temp.k('periode') ->> 'id', 'id_karyawan', 'W9R')));
insert into h values ('orang_x', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'orang', 'periode_id', pg_temp.k('periode') ->> 'id', 'id_karyawan', 'TIDAK-ADA')));
insert into h values ('periode_x', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'gaji', 'periode_id', 'abc')));
insert into h values ('cek', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'perlu_dicek', 'periode_id', pg_temp.k('periode') ->> 'id')));
insert into h values ('keberatan', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'keberatan')));
insert into h values ('aksi_x', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'hapus')));
reset role;

select uji.sama('9a: kode salah -> salah (sisa 4); benar -> sesi 2 jam; kode sekali pakai',
  concat_ws('/', pg_temp.k('salah') ->> 'hasil', pg_temp.k('salah') ->> 'sisa', pg_temp.k('masuk') ->> 'hasil', pg_temp.k('masuk') ->> 'peran',
            pg_temp.k('ulang') ->> 'hasil'), 'salah/4/masuk/hrd/tidak_berlaku');
select uji.sama('9a: sesi berlaku 2 jam', (select berlaku_sampai - dibuat from fakta.sesi_web where sidik = pg_temp.sd('sesi-1')), interval '2 hours');
select uji.sama('9a: bos tidak bisa masuk web HRD', pg_temp.k('bos') ->> 'hasil', 'tidak_berlaku');
select uji.sama('9a: kode sesi tidak disimpan, hanya sidiknya', (select count(*) from fakta.sesi_web where sidik = 'sesi-1'), 0::bigint);
select uji.sama('9a: sesi palsu ditolak', pg_temp.k('palsu') ->> 'hasil', 'sesi_tidak_berlaku');
select uji.sama('9a: ringkasan tanpa orang rahasia (F15b) dan sama dengan cara hitung Sheets',
  (select concat_ws('/', x ->> 'orang', x ->> 'rahasia', x ->> 'pendapatan', x ->> 'potongan', x ->> 'bersih', x ->> 'transfer', x ->> 'tunai', x ->> 'kode_gaji')
   from jsonb_array_elements(pg_temp.k('ringkasan') -> 'data') x where (x ->> 'id') = pg_temp.k('periode') ->> 'id'),
  '2/1/3400/-400/3000/1000/2000/uji-9a');
select uji.sama('9a: daftar gaji: orang rahasia tanpa angka; yang lain lengkap',
  (select string_agg(concat_ws(':', x ->> 'id', x ->> 'cara', coalesce(x ->> 'bersih', '-'), coalesce(x ->> 'dibayar', '-'), x ->> 'rahasia', x ->> 'divisi'), ',' order by x ->> 'id')
   from jsonb_array_elements(pg_temp.k('gaji') -> 'data') x),
  'W9A:transfer:1000:1000:false:ZW9,W9B:tunai:2000:2000:false,W9R:transfer:-:-:true:ZW9');
select uji.sama('9a: rincian orang: komponen, harian dari versi_sumber gaji (bukan baca tap yang lebih baru)',
  concat_ws('/', pg_temp.k('orang_a') #>> '{data,gaji,bersih}', jsonb_array_length(pg_temp.k('orang_a') #> '{data,komponen}'),
            pg_temp.k('orang_a') #>> '{data,harian,0,status}', pg_temp.k('orang_a') #>> '{data,harian,0,menit_telat}',
            jsonb_array_length(pg_temp.k('orang_a') #> '{data,harian}')),
  '1000/2/hadir/7/2');
select uji.sama('9a: perintah per orang tanpa kolom nilai (C9)',
  concat_ws('/', pg_temp.k('orang_a') #>> '{data,perintah,0,jenis}', pg_temp.k('orang_a') #>> '{data,perintah,0,dibatalkan}',
            ((pg_temp.k('orang_a') -> 'data')::text like '%RAHASIA-NILAI%')::text),
  'izin/false/false');
select uji.sama('9a: orang rahasia: tanpa gaji dan komponen, status harian tetap ada',
  concat_ws('/', pg_temp.k('orang_r') #>> '{data,rahasia}', coalesce(pg_temp.k('orang_r') #>> '{data,gaji}', '-'),
            coalesce(pg_temp.k('orang_r') #>> '{data,komponen}', '-'), jsonb_array_length(pg_temp.k('orang_r') #> '{data,harian}'),
            ((pg_temp.k('orang_r'))::text ~ '9900|9000|-900')::text),
  'true/-/-/1/false');
select uji.sama('9a: orang atau periode tidak ada / aksi salah',
  concat_ws('/', pg_temp.k('orang_x') ->> 'hasil', pg_temp.k('periode_x') ->> 'hasil', pg_temp.k('aksi_x') ->> 'hasil'), 'tidak_ada/tidak_ada/aksi_salah');
select uji.sama('9a: perlu dicek dari versi baca yang dipakai gaji',
  (select string_agg(x ->> 'jenis' || ':' || coalesce(x ->> 'nama', '-'), ',') from jsonb_array_elements(pg_temp.k('cek') -> 'data') x),
  'alpha_beruntun:Uji Web Transfer');
select uji.sama('9a: keberatan bisa dibaca', pg_temp.k('keberatan') ->> 'hasil', 'ok');
select uji.sama('9a: pemakaian sesi tercatat', (select jumlah_permintaan from fakta.sesi_web where sidik = pg_temp.sd('sesi-1')), 9);

-- Batas 300 per jam, batas diam 30 menit, batas mutlak 2 jam, keluar, akun dicabut.
update fakta.sesi_web set jumlah_jendela = 300 where sidik = pg_temp.sd('sesi-1');
select uji.sama('9a: lebih dari 300 permintaan per jam ditolak',
  api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'ringkasan')) ->> 'hasil', 'terlalu_banyak');
update fakta.sesi_web set jendela_mulai = now() - interval '61 minutes' where sidik = pg_temp.sd('sesi-1');
select uji.sama('9a: jendela 1 jam berganti -> boleh lagi',
  api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'ringkasan')) ->> 'hasil', 'ok');
update fakta.sesi_web set terakhir_dipakai = now() - interval '31 minutes' where sidik = pg_temp.sd('sesi-1');
select uji.sama('9a: 30 menit tidak dipakai -> sesi berakhir',
  api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-1'), 'aksi', 'ringkasan')) ->> 'hasil', 'sesi_tidak_berlaku');
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select pg_temp.sd('sesi-lama'), id, now() - interval '1 second' from induk.pengguna where telegram_id = 9901;
select uji.sama('9a: lewat 2 jam -> sesi berakhir',
  api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-lama'), 'aksi', 'ringkasan')) ->> 'hasil', 'sesi_tidak_berlaku');
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select pg_temp.sd('sesi-k'), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 9901;
select uji.sama('9a: Keluar -> sesi tidak bisa dipakai lagi',
  concat_ws('/', api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-k'), 'aksi', 'keluar')) ->> 'hasil',
            api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-k'), 'aksi', 'ringkasan')) ->> 'hasil'), 'keluar/sesi_tidak_berlaku');
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select pg_temp.sd('sesi-c'), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 9901;
update induk.pengguna set aktif = false where telegram_id = 9901;
select uji.sama('9a: akun dinonaktifkan (cabut) -> sesinya diakhiri',
  concat_ws('/', (select alasan_berakhir from fakta.sesi_web where sidik = pg_temp.sd('sesi-c')),
            api.web_hrd(jsonb_build_object('sidik_sesi', pg_temp.sd('sesi-c'), 'aksi', 'ringkasan')) ->> 'hasil'), 'akun_dicabut/sesi_tidak_berlaku');
select uji.harus_ditolak('9a: pintu tidak bisa membaca sesi langsung', 'select count(*) from fakta.sesi_web', 'pintu');
select uji.sama('9a: anon dan authenticated tidak bisa memanggil fungsi web',
  (select count(*) from pg_roles r cross join (values ('api.web_sesi_buat(jsonb)'), ('api.web_hrd(jsonb)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);
select uji.sama('9a: pintu tidak bisa memanggil fungsi pembantu langsung',
  has_function_privilege('pintu', 'fakta.web_orang(bigint, text)', 'execute'), false);
rollback;
