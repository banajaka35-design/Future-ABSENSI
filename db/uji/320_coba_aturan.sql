-- Uji paket 9c (docs/rencana-9c.md): coba aturan. Data dasar sama dengan uji 280, ditambah tap telat, premi hadir,
-- dan satu orang rahasia (K5). Gerbang 2: selisih percobaan = selisih bila aturan dipasang sungguhan.
begin;
set local app.pengguna = 'uji-otomatis';

-- Data dasar seperti uji 110 (cukup untuk baca tap dan hitung gaji satu periode).
insert into aturan.jendela_tap (menit_sebelum_masuk, menit_sesudah_pulang, jarak_minimal_menit, berlaku_dari) values (120, 360, 60, '2026-01-01');
insert into aturan.toleransi (telat_menit, pulang_cepat_menit, berlaku_dari) values (5, 0, '2026-01-01');
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values ('TL', 'Uji Lantai', 'mingguan', 1, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select 'TL', 0, h, case when h = 7 then null else 'P' end, '2026-01-01' from generate_series(1, 7) h;
-- K1, K2, K3 aktif; K4 berhenti 10 Apr 2026 (hari kerja terakhir); K5 rahasia.
insert into induk.karyawan (id, nama) values ('K1', 'Uji Satu'), ('K2', 'Uji Dua'), ('K3', 'Uji Tiga'), ('K4', 'Uji Berhenti'), ('K5', 'Uji Rahasia');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                    bpjs_kesehatan, bpjs_ketenagakerjaan, gaji_rahasia)
select i, '2025-01-01', 'TL', 3500000, 500000, 'TK/0', 'transfer', false, false, i = 'K5'
from unnest(array['K1', 'K2', 'K3', 'K4', 'K5']) i;
insert into induk.status_kerja (id_karyawan, jenis, tanggal)
select i, 'mulai', '2025-01-01' from unnest(array['K1', 'K2', 'K3', 'K4', 'K5']) i;
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('K4', 'berhenti', '2026-04-10');
insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari)
select i, 0, '2025-01-01' from unnest(array['K1', 'K2', 'K3', 'K4', 'K5']) i;
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari)
select 'MA1', n::text, 'K' || n, '2025-01-01' from generate_series(1, 5) n;
-- Tiga periode: dirilis (Feb-Mar), terbuka (Mar-Apr), terbuka (Apr-Mei).
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-02-21', '2026-03-20', '2026-03-25'), ('2026-03-21', '2026-04-20', '2026-04-25'), ('2026-04-21', '2026-05-20', '2026-05-25');
-- Status periode dipasang langsung untuk uji (alur rilis sendiri diuji di 180/200).
create function pg_temp.jadi(p_awal date, p_status text) returns void language sql as $$
  select set_config('app.ubah_status_periode', 'ya', true);
  update fakta.periode set status = p_status where tanggal_awal = p_awal;
  select set_config('app.ubah_status_periode', '', true) $$;
select pg_temp.jadi('2026-02-21', 'dirilis');
insert into induk.pengguna (telegram_id, peran) values (7701, 'hrd'), (7702, 'karyawan'), (7703, 'bos'), (7704, 'pembangun'), (7705, 'hrd');

insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('M', '23:00', '07:00', 60);
-- TL otomatis sampai 13 Apr, wajib perintah mulai 13 Apr.
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari, berlaku_sampai) values
  ('lembur', 'TL', 'otomatis', '2026-01-01', '2026-04-13'), ('lembur', 'TL', 'wajib_perintah', '2026-04-13', null);
-- K1 Sabtu 11 Apr tukar ke shift malam M.
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, nilai) values ('file', 'tukar_shift', 'K1', '2026-04-11', 'M');
-- Tap:
--  7 Apr  K1 05:30-15:45 (B05b: awal 90, lebih 45); K2, K3, K5 06:55-15:05
--  8 Apr  K2 06:20-15:50 (awal 40, lebih 50); K3 06:55-15:05 (awal 5, lebih 5); K1, K5 06:55-15:05
--  9 Apr  K3 hanya 06:00 (lupa tap pulang); K1, K2, K5 06:55-15:05
-- 11 Apr  K1 shift malam 22:20 - 12 Apr 07:30 (awal 40, lebih 30); K2, K3, K5 06:55-15:05
-- 14 Apr  K3 06:00-16:30 (awal 60, lebih 90; wajib perintah); K1, K2, K5 06:55-15:05
create temp table tap_uji (n int, t text, s text);
insert into tap_uji values
  (1, '2026-04-07 05:30:00', 'Masuk'), (1, '2026-04-07 15:45:00', 'Keluar'),
  (2, '2026-04-08 06:20:00', 'Masuk'), (2, '2026-04-08 15:50:00', 'Keluar'),
  (3, '2026-04-08 06:55:00', 'Masuk'), (3, '2026-04-08 15:05:00', 'Keluar'),
  (3, '2026-04-09 06:00:00', 'Masuk'),
  (1, '2026-04-11 22:20:00', 'Masuk'), (1, '2026-04-12 07:30:00', 'Keluar'),
  (3, '2026-04-14 06:00:00', 'Masuk'), (3, '2026-04-14 16:30:00', 'Keluar');
insert into tap_uji select n, d || ' 06:55:00', 'Masuk' from (values (2, '2026-04-07'), (3, '2026-04-07'), (5, '2026-04-07'), (1, '2026-04-08'), (5, '2026-04-08'),
  (1, '2026-04-09'), (2, '2026-04-09'), (5, '2026-04-09'), (2, '2026-04-11'), (3, '2026-04-11'), (5, '2026-04-11'), (1, '2026-04-14'), (2, '2026-04-14'), (5, '2026-04-14')) x(n, d)
  union all select n, d || ' 15:05:00', 'Keluar' from (values (2, '2026-04-07'), (3, '2026-04-07'), (5, '2026-04-07'), (1, '2026-04-08'), (5, '2026-04-08'),
  (1, '2026-04-09'), (2, '2026-04-09'), (5, '2026-04-09'), (2, '2026-04-11'), (3, '2026-04-11'), (5, '2026-04-11'), (1, '2026-04-14'), (2, '2026-04-14'), (5, '2026-04-14')) x(n, d);
select fakta.terima_kiriman('uji7c2.csv', repeat('d', 64), 'MA1',
  (select jsonb_agg(jsonb_build_array(n::text, t, s, r) order by r) from (select n, t, s, row_number() over (order by t, n) as r from tap_uji) y),
  null, '2026-04-15 08:00+07');



-- Tambahan 9c: telat 8 menit (13 Apr) dan 12 menit (10 Apr) untuk K2; premi hadir hidup 100.000.
insert into tap_uji values (2, '2026-04-13 07:08:00', 'Masuk'), (2, '2026-04-13 15:05:00', 'Keluar'),
  (2, '2026-04-10 07:12:00', 'Masuk'), (2, '2026-04-10 15:05:00', 'Keluar');
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values ('premi_hadir', 'perusahaan', 'hidup', '2026-01-01');
insert into aturan.komponen_lain (kode, nominal, satuan, sifat, syarat, berlaku_dari)
values ('premi_hadir', 100000, 'per_periode', 'tidak_tetap', 'uji', '2026-01-01');
select fakta.terima_kiriman('uji9c.csv', repeat('e', 64), 'MA1',
  (select jsonb_agg(jsonb_build_array(n::text, t, s, r) order by r) from (select n, t, s, row_number() over (order by t, n) as r from tap_uji) y),
  null, '2026-04-15 08:00+07');
select count(hitung.baca_tap(id)), count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-03-21';
create temp table h (nama text primary key, isi jsonb);
create temp table v as select id as periode, (select g.id from hitung.versi_terakhir g where g.periode_id = p.id and g.jenis = 'hitung_gaji') as gaji_awal
  from fakta.periode p where tanggal_awal = '2026-03-21';
create function pg_temp.k(x text) returns jsonb language sql as $$ select isi from h where nama = x $$;
create function pg_temp.potret() returns text language sql as $$
  select concat_ws('|', (select count(*) from hitung.versi_hitung), (select string_agg(telat_menit::text, ',') from aturan.toleransi),
    (select count(*) || ':' || sum(nominal) from aturan.komponen_lain), (select string_agg(status, ',' order by id) from fakta.periode),
    (select string_agg(menit_minimal || '/' || kelipatan_menit || '/' || cara_bulat, ',') from aturan.lembur)) $$;
create temp table potret as select pg_temp.potret() as awal;
create function pg_temp.pengguna() returns bigint language sql as $$ select id from induk.pengguna where telegram_id = 7701 $$;

-- K2: antrean hitung ulang masih menunggu -> ditolak.
insert into fakta.antrean_kerja (periode_id) select periode from v
  where not exists (select 1 from fakta.antrean_kerja a where a.periode_id = v.periode and a.status = 'menunggu');
insert into h select 'antrean', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"telat_menit": 10}') from v;
update fakta.antrean_kerja set status = 'selesai', selesai = now() where status = 'menunggu';
insert into h select 'dirilis', fakta.coba_aturan_jalankan(pg_temp.pengguna(), id, '{"telat_menit": 10}') from fakta.periode where tanggal_awal = '2026-02-21';
insert into h select 'sama', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"telat_menit": 5}') from v;
insert into h select 'salah1', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"telat_menit": -1}') from v;
insert into h select 'salah2', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"lembur_kelipatan": 61}') from v;
insert into h select 'salah3', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"pajak": 0}') from v;
insert into h select 'salah4', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"lembur_bulat": "atas"}') from v;
insert into h select 'awal', jsonb_build_object('x', fakta.aturan_sekarang(periode)) from v;
insert into h select 'coba', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"telat_menit": 10, "uang_makan": 20000, "lembur_kelipatan": 15}') from v;
insert into h values ('sesudah', jsonb_build_object('potret', pg_temp.potret()));

select uji.sama('9c: periode yang masih menunggu hitung ulang ditolak (K2)', pg_temp.k('antrean') ->> 'hasil', 'antrean');
select uji.sama('9c: periode dirilis ditolak (K6)', pg_temp.k('dirilis') ->> 'hasil', 'tidak_boleh');
select uji.sama('9c: isian sama dengan sekarang -> tanpa perubahan', pg_temp.k('sama') ->> 'hasil', 'tanpa_perubahan');
select uji.sama('9c: isian di luar batas atau tidak dikenal ditolak',
  concat_ws('/', pg_temp.k('salah1') ->> 'hasil', pg_temp.k('salah2') ->> 'hasil', pg_temp.k('salah3') ->> 'hasil', pg_temp.k('salah4') ->> 'hasil'),
  'isian_salah/isian_salah/isian_salah/isian_salah');
select uji.sama('9c: nilai sekarang untuk isian awal', concat_ws('/', pg_temp.k('awal') #>> '{x,telat_menit}', pg_temp.k('awal') #>> '{x,lembur_kelipatan}',
  coalesce(pg_temp.k('awal') #>> '{x,uang_makan}', '-'), pg_temp.k('awal') #>> '{x,premi_hadir}', pg_temp.k('awal') #>> '{x,boleh}'), '5/30/-/100000/true');
select uji.sama('9c: percobaan selesai', concat_ws('/', pg_temp.k('coba') ->> 'hasil', pg_temp.k('coba') #>> '{data,aturan,telat_menit}'), 'ok/10');
select uji.sama('9c (K1): gudang tidak berubah sesudah percobaan (versi, aturan, status periode)',
  pg_temp.k('sesudah') ->> 'potret', (select awal from potret));
select uji.sama('9c (K3): orang rahasia tidak ada di daftar, hanya dihitung jumlahnya',
  concat_ws('/', pg_temp.k('coba') #>> '{data,ringkasan,rahasia}',
            (select count(*) from jsonb_array_elements(pg_temp.k('coba') #> '{data,daftar}') x where x ->> 'id' = 'K5')::text), '1/0');
select uji.sama('9c: percobaan tercatat (hanya bertambah) dengan ringkasan tanpa rahasia',
  (select concat_ws('/', hasil, aturan ->> 'telat_menit', ringkasan ->> 'rahasia', (lama_ms >= 0)::text) from fakta.coba_aturan order by id desc limit 1), 'selesai/10/1/true');
select uji.harus_ditolak('9c: catatan percobaan hanya bertambah', 'delete from fakta.coba_aturan');
-- Aturan yang tertutup di tengah periode tidak bisa dicoba (aturan bertanggal tidak boleh diubah).
insert into aturan.komponen_lain (kode, nominal, satuan, sifat, syarat, berlaku_dari, berlaku_sampai)
values ('tunjangan_shift_malam', 10000, 'per_hari', 'tidak_tetap', 'uji', '2026-01-01', '2026-04-01');
insert into h select 'tertutup', fakta.coba_aturan_jalankan(pg_temp.pengguna(), periode, '{"shift_malam": 15000}') from v;
select uji.sama('9c: aturan yang berganti di tengah periode -> gagal dengan alasan jelas, gudang tetap',
  concat_ws('/', pg_temp.k('tertutup') ->> 'hasil', ((pg_temp.k('tertutup') ->> 'alasan') like '%berganti di tengah periode%')::text,
            (select count(*) from aturan.komponen_lain where kode = 'tunjangan_shift_malam')), 'gagal/true/1');
-- Lewat pintu web (peran pintu, sesi web): nilai sekarang dan percobaan.
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) values (repeat('c', 64), pg_temp.pengguna(), now() + interval '1 hour');
grant all on h, v to pintu;
grant execute on function pg_temp.k(text) to pintu;
set local role pintu;
insert into h select 'web_awal', api.web_hrd(jsonb_build_object('sidik_sesi', repeat('c', 64), 'aksi', 'aturan_sekarang', 'periode_id', periode)) from v;
insert into h select 'web_coba', api.web_hrd(jsonb_build_object('sidik_sesi', repeat('c', 64), 'aksi', 'coba_aturan', 'periode_id', periode,
  'aturan', jsonb_build_object('telat_menit', 10, 'uang_makan', 20000, 'lembur_kelipatan', 15))) from v;
insert into h select 'web_tanpa_sesi', api.web_hrd(jsonb_build_object('sidik_sesi', repeat('d', 64), 'aksi', 'coba_aturan', 'periode_id', periode,
  'aturan', jsonb_build_object('telat_menit', 10))) from v;
reset role;
select uji.sama('9c: lewat web (peran pintu): nilai sekarang, percobaan sama dengan panggilan langsung, sesi palsu ditolak',
  concat_ws('/', pg_temp.k('web_awal') #>> '{data,telat_menit}', pg_temp.k('web_coba') ->> 'hasil',
            (pg_temp.k('web_coba') #> '{data,daftar}' = pg_temp.k('coba') #> '{data,daftar}')::text, pg_temp.k('web_tanpa_sesi') ->> 'hasil'),
  '5/ok/true/sesi_tidak_berlaku');
select uji.harus_ditolak('9c: pintu tidak bisa memanggil fungsi percobaan langsung',
  $q$select fakta.coba_aturan_jalankan(1, 1, '{}')$q$, 'pintu');

-- Gerbang 2: pasang aturan yang sama sungguhan, hitung ulang, bandingkan selisih per orang dan ringkasan.
-- Cara resmi mengganti aturan bertanggal: tutup baris terbuka, tambah baris baru (sama dengan percobaan).
update aturan.toleransi set berlaku_sampai = '2026-03-21' where berlaku_sampai is null;
insert into aturan.toleransi (telat_menit, pulang_cepat_menit, berlaku_dari) values (10, 0, '2026-03-21');
update aturan.lembur set berlaku_sampai = '2026-03-21' where berlaku_sampai is null;
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 15, 'bawah', 'penuh', '2026-03-21');
insert into aturan.komponen_lain (kode, nominal, satuan, sifat, syarat, berlaku_dari, berlaku_sampai)
select 'uang_makan', 20000, 'per_hari', 'tidak_tetap', 'uji', tanggal_awal, tanggal_akhir + 1 from fakta.periode where tanggal_awal = '2026-03-21';
select count(hitung.baca_tap(periode)), count(hitung.hitung_gaji(periode)) from v;
create temp table nyata as
  select b.id_karyawan as id, b.gaji_bersih - a.gaji_bersih as selisih
  from v
  join hitung.ringkasan_gaji a on a.versi_id = v.gaji_awal
  join hitung.ringkasan_gaji b on b.id_karyawan = a.id_karyawan
   and b.versi_id = (select g.id from hitung.versi_terakhir g where g.periode_id = v.periode and g.jenis = 'hitung_gaji')
  where not fakta.rahasia_di_periode(a.id_karyawan, v.periode);
select uji.sama('9c GERBANG 2: selisih per orang percobaan = selisih bila aturan dipasang sungguhan',
  (select string_agg(id || ':' || selisih, ',' order by id) from nyata where selisih <> 0),
  (select string_agg((x ->> 'id') || ':' || (x ->> 'selisih'), ',' order by x ->> 'id') from jsonb_array_elements(pg_temp.k('coba') #> '{data,daftar}') x
   where (x ->> 'selisih')::bigint <> 0));
select uji.sama('9c GERBANG 2: total selisih dan jumlah naik/turun sama',
  (select concat_ws('/', sum(selisih), count(*) filter (where selisih > 0), count(*) filter (where selisih < 0)) from nyata),
  concat_ws('/', pg_temp.k('coba') #>> '{data,ringkasan,selisih}', pg_temp.k('coba') #>> '{data,ringkasan,naik}', pg_temp.k('coba') #>> '{data,ringkasan,turun}'));
select uji.sama('9c: percobaan memang mengubah gaji (uji tidak kosong)', (select count(*) > 0 from nyata where selisih <> 0), true);
select uji.sama('9c: komponen yang berubah ikut dilaporkan (uang makan)',
  (select count(*) > 0 from jsonb_array_elements(pg_temp.k('coba') #> '{data,daftar}') x, jsonb_array_elements(x -> 'komponen') c
   where c ->> 'komponen' = 'uang_makan'), true);
rollback;
