-- Uji paket 8c (docs/rencana-8c.md): antrean pesan gaji, isi pesan, minta ulang, contoh pesan, kunci periode.
-- Fungsi api dipanggil sebagai peran pintu. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.divisi (kode, nama, pola) values ('ZG8', 'Uji Gaji', 'mingguan');
insert into induk.karyawan (id, nama) values ('G8A', 'Uji Ani'), ('G8B', 'Uji Budi'), ('G8C', 'Uji Rahasia'), ('G8D', 'Uji Baru Rahasia');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('G8A', '2030-01-01', 'ZG8', 1, 'TK/0', 'tunai', false), ('G8B', '2030-01-01', 'ZG8', 1, 'TK/0', 'transfer', false),
  ('G8C', '2030-01-01', 'ZG8', 1, 'TK/0', 'transfer', true),
  -- G8D: tidak rahasia selama periode uji, baru dijadikan rahasia sesudahnya (F15c: tetap disembunyikan dari HRD)
  ('G8D', '2036-01-01', 'ZG8', 1, 'TK/0', 'transfer', true);
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, berlaku_sampai, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('G8D', '2030-01-01', '2036-01-01', 'ZG8', 1, 'TK/0', 'transfer', false);
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('G8A', 'mulai', '2020-01-01'), ('G8B', 'mulai', '2020-01-01'),
  ('G8C', 'mulai', '2020-01-01'), ('G8D', 'mulai', '2020-01-01');
insert into induk.pengguna (telegram_id, peran) values (8881, 'hrd'), (8891, 'pembangun');
insert into induk.pengguna (telegram_id, peran, id_karyawan) values (8802, 'karyawan', 'G8A'), (8803, 'karyawan', 'G8C');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2035-01-21', '2035-02-20', '2035-02-25'), ('2035-02-21', '2035-03-20', '2035-03-25');

create temp table p as select row_number() over (order by tanggal_awal) as n, id from fakta.periode where tanggal_awal >= '2035-01-01';
create temp table h (nama text primary key, isi jsonb);
grant all on h, p to pintu;
create function pg_temp.pid(x integer) returns bigint language sql as $$ select id from p where n = x $$;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
grant execute on function pg_temp.pid(integer), pg_temp.k(text) to pintu;
create function pg_temp.status(x integer) returns text language sql as $$ select status from fakta.periode where id = (select id from p where n = x) $$;
create function pg_temp.st(i text) returns text language sql as $$
  select string_agg(status, ',' order by periode_id) from fakta.kirim_gaji where id_karyawan = i $$;
create function pg_temp.hitung(x integer) returns bigint language plpgsql as $$
declare
  v_baca bigint;
  v_gaji bigint;
  v_n integer := coalesce((select max(nomor) from hitung.versi_hitung where periode_id = pg_temp.pid(x)), 0) + 1;
begin
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (pg_temp.pid(x), 'baca_tap', v_n, 'uji-8c', 'b' || v_n, 'b' || v_n) returning id into v_baca;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil, versi_sumber)
  values (pg_temp.pid(x), 'hitung_gaji', v_n, 'uji-8c', 'g' || v_n, 'g' || v_n, v_baca) returning id into v_gaji;
  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, dibayar,
                                     sisa_pembulatan, peringatan)
  select v_gaji, i, 3000, 3000, -150, 2850, d, 2850 - d, '{}'::text[]
  from (values ('G8A', 2000), ('G8B', 2850), ('G8C', 2850), ('G8D', 2850)) x(i, d);
  insert into hitung.rincian_gaji (versi_id, id_karyawan, komponen, kelompok, nominal, bukti)
  select v_gaji, i, c, g, n, 'bukti ' || c from (values ('G8A'), ('G8B'), ('G8C'), ('G8D')) a(i),
    (values ('gaji_pokok', 'pendapatan', 3000), ('lembur', 'pendapatan', 0), ('pph21', 'potongan', -150),
            ('bpjs_jht_perusahaan', 'perusahaan', 111)) b(c, g, n);
  return v_gaji;
end $$;
select pg_temp.hitung(1); select pg_temp.hitung(2);

-- Sebelum rilis: contoh pesan (versi berlaku) dan minta ulang
set local role pintu;
insert into h values ('contoh_karyawan', api.pintu_contoh_gaji(jsonb_build_object('telegram_id', 8802, 'id_karyawan', 'G8A', 'periode_id', pg_temp.pid(1))));
insert into h values ('contoh_hrd', api.pintu_contoh_gaji(jsonb_build_object('telegram_id', 8881, 'id_karyawan', 'G8A', 'periode_id', pg_temp.pid(1))));
insert into h values ('contoh_hrd_rahasia', api.pintu_contoh_gaji(jsonb_build_object('telegram_id', 8881, 'id_karyawan', 'G8C', 'periode_id', pg_temp.pid(1))));
insert into h values ('contoh_pembangun_rahasia', api.pintu_contoh_gaji(jsonb_build_object('telegram_id', 8891, 'id_karyawan', 'G8C', 'periode_id', pg_temp.pid(1))));
insert into h values ('contoh_hrd_rahasia_kini', api.pintu_contoh_gaji(jsonb_build_object('telegram_id', 8881, 'id_karyawan', 'G8D', 'periode_id', pg_temp.pid(1))));
insert into h values ('contoh_tidak_ada', api.pintu_contoh_gaji(jsonb_build_object('telegram_id', 8881, 'id_karyawan', 'XXX', 'periode_id', pg_temp.pid(1))));
insert into h values ('gaji_belum', api.pintu_gaji_saya('{"telegram_id": 8802}'));
insert into h values ('gaji_hrd', api.pintu_gaji_saya('{"telegram_id": 8881}'));
reset role;
select uji.sama('8c: contoh pesan: karyawan ditolak; HRD ya; HRD tidak untuk orang rahasia; pembangun ya; ID salah tidak ada',
  concat_ws('/', pg_temp.k('contoh_karyawan') ->> 'hasil', pg_temp.k('contoh_hrd') ->> 'hasil', pg_temp.k('contoh_hrd_rahasia') ->> 'hasil',
            pg_temp.k('contoh_pembangun_rahasia') ->> 'hasil', pg_temp.k('contoh_tidak_ada') ->> 'hasil'),
  'bukan_hrd/ada/rahasia/ada/tidak_ada');
select uji.sama('8c (F15c): orang yang rahasia sekarang (bukan saat periode) tetap tidak bisa dilihat HRD',
  pg_temp.k('contoh_hrd_rahasia_kini') ->> 'hasil', 'rahasia');
select uji.sama('8c: isi pesan: nama, divisi, cara bayar, total, dibayar, sisa pembulatan; komponen bernilai 0 tidak ikut',
  concat_ws('/', pg_temp.k('contoh_hrd') ->> 'nama', pg_temp.k('contoh_hrd') ->> 'divisi', pg_temp.k('contoh_hrd') ->> 'cara_bayar',
            pg_temp.k('contoh_hrd') ->> 'bersih', pg_temp.k('contoh_hrd') ->> 'dibayar', pg_temp.k('contoh_hrd') ->> 'sisa',
            (select string_agg((x ->> 'kelompok') || ':' || (x ->> 'komponen') || ':' || (x ->> 'nominal'), ',')
             from jsonb_array_elements(pg_temp.k('contoh_hrd') -> 'komponen') x)),
  'Uji Ani/Uji Gaji/tunai/2850/2000/850/pendapatan:gaji_pokok:3000,perusahaan:bpjs_jht_perusahaan:111,potongan:pph21:-150');
select uji.sama('8c: sebelum rilis, karyawan belum punya pesan gaji; HRD bukan karyawan',
  pg_temp.k('gaji_belum') ->> 'hasil' || '/' || (pg_temp.k('gaji_hrd') ->> 'hasil'), 'belum_ada/bukan_karyawan');

-- Rilis periode 1 -> antrean
insert into fakta.pengajuan_rilis (periode_id, versi_gaji, diajukan_oleh)
values (pg_temp.pid(1), fakta.versi_gaji_berlaku(pg_temp.pid(1)), (select id from induk.pengguna where telegram_id = 8881));
select fakta.ubah_status_periode(pg_temp.pid(1), 'diajukan', 'hrd', 'uji', 'uji');
insert into fakta.rilis_gaji (periode_id, versi_gaji, pengajuan_id, dirilis_oleh)
select pg_temp.pid(1), a.versi_gaji, a.id, a.diajukan_oleh from fakta.pengajuan_rilis a where a.periode_id = pg_temp.pid(1);
select fakta.ubah_status_periode(pg_temp.pid(1), 'dirilis', 'hrd', 'uji', 'uji');
select uji.sama('8c: rilis mengisi antrean: punya akun -> menunggu, belum punya -> tanpa_akun (orang rahasia ikut)',
  concat_ws('/', pg_temp.st('G8A'), pg_temp.st('G8B'), pg_temp.st('G8C')), 'menunggu/tanpa_akun/menunggu');
select uji.sama('8c: teks status rilis selama antrean berjalan', fakta.status_rilis_teks(pg_temp.pid(1)), 'Dirilis, pesan gaji sedang dikirim');
select uji.sama('8c: penjadwal melihat ada pekerjaan', fakta.ada_kirim_gaji(), true);

set local role pintu;
insert into h values ('ambil1', api.pintu_kirim_gaji_ambil('{"batas": 1}'));
insert into h values ('ambil2', api.pintu_kirim_gaji_ambil('{"batas": 10}'));
insert into h values ('ambil_kosong', api.pintu_kirim_gaji_ambil('{}'));
reset role;
select uji.sama('8c: ambil sesuai batas; baris jadi sedang dan percobaan 1; telegram_id akun karyawan itu',
  concat_ws('/', jsonb_array_length(pg_temp.k('ambil1') -> 'kirim'), pg_temp.k('ambil1') -> 'kirim' -> 0 ->> 'id',
            pg_temp.k('ambil1') -> 'kirim' -> 0 ->> 'telegram_id', jsonb_array_length(pg_temp.k('ambil2') -> 'kirim'),
            pg_temp.k('ambil2') -> 'kirim' -> 0 ->> 'telegram_id', jsonb_array_length(pg_temp.k('ambil_kosong') -> 'kirim'),
            (select string_agg(status || percobaan, ',' order by id_karyawan) from fakta.kirim_gaji where periode_id = pg_temp.pid(1))),
  '1/G8A/8802/1/8803/0/sedang1,tanpa_akun0,sedang1,tanpa_akun0');
select uji.sama('8c: belum selesai -> belum dikunci', pg_temp.status(1) || '/' || jsonb_array_length(pg_temp.k('ambil_kosong') -> 'selesai'), 'dirilis/0');

-- Hasil: G8A gagal (dicoba ulang), G8C terkirim
set local role pintu;
insert into h values ('hasil1', api.pintu_kirim_gaji_hasil(jsonb_build_object('hasil', jsonb_build_array(
  jsonb_build_object('kirim_id', (pg_temp.k('ambil1') -> 'kirim' -> 0 ->> 'kirim_id')::bigint, 'ok', false, 'galat', 'Forbidden: bot was blocked'),
  jsonb_build_object('kirim_id', (pg_temp.k('ambil2') -> 'kirim' -> 0 ->> 'kirim_id')::bigint, 'ok', true)))));
reset role;
select uji.sama('8c: gagal pertama -> menunggu lagi (galat dicatat); berhasil -> terkirim',
  concat_ws('/', pg_temp.st('G8A'), (select galat from fakta.kirim_gaji where id_karyawan = 'G8A'), pg_temp.st('G8C')),
  'menunggu/Forbidden: bot was blocked/terkirim');
-- Dua kali gagal lagi -> gagal (3 percobaan)
set local role pintu;
insert into h values ('ambil3', api.pintu_kirim_gaji_ambil('{}'));
insert into h values ('hasil3', api.pintu_kirim_gaji_hasil(jsonb_build_object('hasil', jsonb_build_array(
  jsonb_build_object('kirim_id', (pg_temp.k('ambil3') -> 'kirim' -> 0 ->> 'kirim_id')::bigint, 'ok', false, 'galat', 'x')))));
insert into h values ('ambil4', api.pintu_kirim_gaji_ambil('{}'));
insert into h values ('hasil4', api.pintu_kirim_gaji_hasil(jsonb_build_object('hasil', jsonb_build_array(
  jsonb_build_object('kirim_id', (pg_temp.k('ambil4') -> 'kirim' -> 0 ->> 'kirim_id')::bigint, 'ok', false, 'galat', 'x')))));
reset role;
select uji.sama('8c: 3 kali gagal -> gagal; antrean habis -> periode dikunci oleh sistem; ringkasan dikirim sekali',
  concat_ws('/', pg_temp.st('G8A'), pg_temp.status(1),
            (select alasan || ':' || oleh from fakta.riwayat_status_periode where periode_id = pg_temp.pid(1) order by id desc limit 1),
            jsonb_array_length(pg_temp.k('hasil3') -> 'selesai'),
            pg_temp.k('hasil4') -> 'selesai' -> 0 ->> 'terkirim', pg_temp.k('hasil4') -> 'selesai' -> 0 ->> 'tanpa_akun',
            pg_temp.k('hasil4') -> 'selesai' -> 0 ->> 'gagal', pg_temp.k('hasil4') -> 'selesai' -> 0 ->> 'penerima'),
  'gagal/dikunci/antrean pesan gaji selesai:pesan gaji/0/1/2/1/[8881, 8891]');
select uji.sama('8c: teks status sesudah dikunci', fakta.status_rilis_teks(pg_temp.pid(1)), 'Dirilis, pesan gaji selesai dikirim');
select uji.sama('8c: penjadwal tidak melihat pekerjaan lagi', fakta.ada_kirim_gaji(), false);
select uji.harus_ditolak('8c: periode dikunci tidak bisa dihitung ulang', 'select pg_temp.hitung(1)');

-- Minta ulang
set local role pintu;
insert into h values ('gaji_ada', api.pintu_gaji_saya('{"telegram_id": 8802}'));
insert into h values ('gaji_periode_salah', api.pintu_gaji_saya(jsonb_build_object('telegram_id', 8802, 'periode_id', pg_temp.pid(2))));
insert into h values ('hasil_minta', api.pintu_kirim_gaji_hasil(jsonb_build_object('hasil', jsonb_build_array(
  jsonb_build_object('kirim_id', (pg_temp.k('gaji_ada') ->> 'kirim_id')::bigint, 'ok', true)))));
insert into h select 'gaji_lagi' || i, api.pintu_gaji_saya('{"telegram_id": 8802}') from generate_series(1, 5) i;
reset role;
select uji.sama('8c: minta ulang -> pesan periode terakhir yang dirilis; periode belum dirilis -> belum_ada',
  concat_ws('/', pg_temp.k('gaji_ada') ->> 'hasil', (pg_temp.k('gaji_ada') ->> 'periode_id')::bigint = pg_temp.pid(1),
            pg_temp.k('gaji_ada') ->> 'dibayar', pg_temp.k('gaji_periode_salah') ->> 'hasil'),
  'ada/t/2000/belum_ada');
select uji.sama('8c: minta ulang yang terkirim memperbaiki status gagal -> terkirim', pg_temp.st('G8A'), 'terkirim');
select uji.sama('8c: lebih dari 5 kali per jam -> terlalu_sering',
  pg_temp.k('gaji_lagi4') ->> 'hasil' || '/' || (pg_temp.k('gaji_lagi5') ->> 'hasil'), 'ada/terlalu_sering');

-- Akun dinonaktifkan sesudah masuk antrean -> tanpa_akun saat diambil; kiriman terputus kembali menunggu
insert into fakta.pengajuan_rilis (periode_id, versi_gaji, diajukan_oleh)
values (pg_temp.pid(2), fakta.versi_gaji_berlaku(pg_temp.pid(2)), (select id from induk.pengguna where telegram_id = 8881));
select fakta.ubah_status_periode(pg_temp.pid(2), 'diajukan', 'hrd', 'uji', 'uji');
insert into fakta.rilis_gaji (periode_id, versi_gaji, pengajuan_id, dirilis_oleh)
select pg_temp.pid(2), a.versi_gaji, a.id, a.diajukan_oleh from fakta.pengajuan_rilis a where a.periode_id = pg_temp.pid(2);
select fakta.ubah_status_periode(pg_temp.pid(2), 'dirilis', 'hrd', 'uji', 'uji');
update induk.pengguna set aktif = false where telegram_id = 8803;
set local role pintu;
insert into h values ('ambil5', api.pintu_kirim_gaji_ambil('{}'));
reset role;
update fakta.kirim_gaji set diperbarui = now() - interval '11 minutes' where periode_id = pg_temp.pid(2) and status = 'sedang';
select uji.sama('8c: akun nonaktif -> tanpa_akun; kiriman terputus > 10 menit terlihat penjadwal',
  concat_ws('/', (select status from fakta.kirim_gaji where periode_id = pg_temp.pid(2) and id_karyawan = 'G8C'),
            jsonb_array_length(pg_temp.k('ambil5') -> 'kirim'), fakta.ada_kirim_gaji()),
  'tanpa_akun/1/t');
set local role pintu;
insert into h values ('ambil6', api.pintu_kirim_gaji_ambil('{}'));
reset role;
select uji.sama('8c: kiriman terputus diambil lagi (percobaan 2)',
  (select status || percobaan from fakta.kirim_gaji where periode_id = pg_temp.pid(2) and id_karyawan = 'G8A'), 'sedang2');

-- Semua belum punya akun: periode dikunci saat penjadwal berjalan
update fakta.kirim_gaji set status = 'tanpa_akun' where periode_id = pg_temp.pid(2);
select uji.sama('8c: periode dirilis tanpa antrean tersisa tetap memanggil penjadwal', fakta.ada_kirim_gaji(), true);
set local role pintu;
insert into h values ('ambil7', api.pintu_kirim_gaji_ambil('{}'));
reset role;
select uji.sama('8c: penjadwal mengunci periode dan meringkas', pg_temp.status(2) || '/' || (pg_temp.k('ambil7') -> 'selesai' -> 0 ->> 'tanpa_akun'),
  'dikunci/4');

select uji.sama('8c: anon dan authenticated tidak bisa memanggil fungsi baru',
  (select count(*) from pg_roles r cross join (values ('api.pintu_kirim_gaji_ambil(jsonb)'), ('api.pintu_kirim_gaji_hasil(jsonb)'),
     ('api.pintu_gaji_saya(jsonb)'), ('api.pintu_contoh_gaji(jsonb)'), ('fakta.isi_gaji(bigint,text)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);
select uji.harus_ditolak('8c: pintu tidak bisa membaca antrean langsung', 'select count(*) from fakta.kirim_gaji', 'pintu');
select uji.harus_ditolak('8c: pintu tidak bisa memanggil isi_gaji langsung', $q$select fakta.isi_gaji(1, 'G8A')$q$, 'pintu');

rollback;
