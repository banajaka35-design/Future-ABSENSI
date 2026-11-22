-- Uji paket 7b (docs/rencana-tahap-7.md bagian 8): kasbon lewat chat dan pembatalannya (keputusan pemilik (a)).
-- Kasbon berlaku menurut tanggal dicatat, jadi periode uji dibuat di sekitar hari ini (WIB). Data dasar sama dengan uji 240.
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
-- Periode: lalu (P1), yang memuat hari ini (P2), sesudahnya (P3).
create temp table tgl as select (now() at time zone 'Asia/Jakarta')::date as hari;
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar)
select hari - 60, hari - 31, hari - 26 from tgl union all
select hari - 30, hari + 5, hari + 10 from tgl union all
select hari + 6, hari + 35, hari + 40 from tgl;
create temp table per as select row_number() over (order by tanggal_awal) as n, id from fakta.periode;
insert into induk.pengguna (telegram_id, peran) values (7701, 'hrd'), (7702, 'karyawan'), (7703, 'bos'), (7704, 'pembangun'), (7705, 'hrd');
-- Semua hadir 30 hari terakhir supaya ada pendapatan (batas potongan 100% tanpa aturan batas).
select fakta.terima_kiriman('uji7b.csv', repeat('b', 64), 'MA1',
  (select jsonb_agg(jsonb_build_array(n::text, t, s, r) order by r) from (
     select n, t, s, row_number() over () as r from (
       select n, d::date || ' 06:55:00' as t, 'Masuk' as s from generate_series(1, 5) n, tgl, generate_series(hari - 30, hari - 1, interval '1 day') d
       union all
       select n, d::date || ' 15:05:00', 'Keluar' from generate_series(1, 5) n, tgl, generate_series(hari - 30, hari - 1, interval '1 day') d) x) y),
  null, now());
select count(hitung.baca_tap(id)), count(hitung.hitung_gaji(id)) from per where n in (2, 3);

create temp table h (nama text primary key, isi jsonb);
grant all on h to pintu;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
grant execute on function pg_temp.k(text) to pintu;
create function pg_temp.kerjakan_semua() returns int language plpgsql as $$
declare n int := 0; begin
  loop exit when (api.pintu_kerjakan() ->> 'kosong') = 'true'; n := n + 1; end loop; return n; end $$;
create function pg_temp.potong(p_id text, p_n int) returns bigint language sql as $$
  select coalesce(-sum(r.nominal), 0)::bigint from hitung.rincian_gaji r
  join hitung.versi_terakhir v on v.id = r.versi_id and v.jenis = 'hitung_gaji'
  where v.periode_id = (select id from per where n = p_n) and r.id_karyawan = p_id and r.komponen = 'kasbon' $$;
create function pg_temp.jadi(p_n int, p_status text) returns void language sql as $$
  select set_config('app.ubah_status_periode', 'ya', true);
  update fakta.periode set status = p_status where id = (select id from per where n = p_n);
  select set_config('app.ubah_status_periode', '', true) $$;
select uji.sama('7b (persiapan): versi kode gaji 6', hitung.versi_kode_gaji(), 'hitung_gaji 6 (paket 7b)');
select uji.sama('7b (persiapan): gaji P2 punya pendapatan, belum ada kasbon',
  (select count(*) from hitung.rincian_gaji r join hitung.versi_terakhir v on v.id = r.versi_id and v.jenis = 'hitung_gaji'
   where v.periode_id = (select id from per where n = 2) and r.komponen = 'gaji_pokok' and r.nominal > 0) || '/' || pg_temp.potong('K1', 2), '4/0');

-- Penolakan
set local role pintu;
insert into h values ('karyawan', api.pintu_kasbon_siapkan('{"telegram_id": 7702, "kasbon_jenis": "pinjam", "id_karyawan": "K1", "jumlah": 1000000, "cicilan": 250000}'));
insert into h values ('saldo_karyawan', api.pintu_kasbon_saldo('{"telegram_id": 7703, "id_karyawan": "K1"}'));
insert into h values ('nol', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K1", "jumlah": 0, "cicilan": 250000}'));
insert into h values ('huruf', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K1", "jumlah": "satu juta", "cicilan": 250000}'));
insert into h values ('tanpa_cicilan', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K1", "jumlah": 1000000}'));
insert into h values ('cicilan_kosong', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "cicilan", "id_karyawan": "K1", "jumlah": 100000}'));
insert into h values ('lunas_kosong', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pelunasan", "id_karyawan": "K1", "jumlah": 1}'));
insert into h values ('tidak_ada', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K99", "jumlah": 1, "cicilan": 1}'));
insert into h values ('saldo_awal', api.pintu_kasbon_saldo('{"telegram_id": 7701, "id_karyawan": "k1"}'));
reset role;
select uji.sama('7b: akun karyawan/bos ditolak', pg_temp.k('karyawan') ->> 'hasil' || '/' || (pg_temp.k('saldo_karyawan') ->> 'hasil'), 'bukan_hrd/bukan_hrd');
select uji.sama('7b: jumlah 0 atau bukan angka ditolak', pg_temp.k('nol') ->> 'hasil' || '/' || (pg_temp.k('huruf') ->> 'hasil'), 'jumlah_salah/jumlah_salah');
select uji.sama('7b: pinjam tanpa cicilan ditolak (cicilan wajib)', pg_temp.k('tanpa_cicilan') ->> 'hasil', 'cicilan_wajib');
select uji.sama('7b: ganti cicilan tanpa saldo ditolak; pelunasan melebihi saldo 0 ditolak',
  pg_temp.k('cicilan_kosong') ->> 'hasil' || '/' || (pg_temp.k('lunas_kosong') ->> 'hasil') || '/' || (pg_temp.k('lunas_kosong') ->> 'saldo'),
  'tanpa_saldo/melebihi_saldo/0');
select uji.sama('7b: ID tidak ada ditolak', pg_temp.k('tidak_ada') ->> 'hasil', 'tidak_ada');
select uji.sama('7b: saldo awal K1 0, tanpa cicilan, riwayat kosong',
  concat_ws('/', pg_temp.k('saldo_awal') ->> 'hasil', pg_temp.k('saldo_awal') -> 'kasbon' ->> 'saldo',
            coalesce(pg_temp.k('saldo_awal') -> 'kasbon' ->> 'cicilan', '-'), jsonb_array_length(pg_temp.k('saldo_awal') -> 'riwayat')), 'ada/0/-/0');
select uji.sama('7b: penolakan tidak membuat draf', (select count(*) from fakta.draf_perintah), 0::bigint);

-- Pinjam K1 1.000.000 cicilan 250.000
set local role pintu;
insert into h values ('pinjam', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K1", "jumlah": 1000000, "cicilan": 250000, "catatan": "biaya sekolah"}'));
insert into h values ('pinjam_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('pinjam') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7b: draf pinjam: periode berjalan P2, periode ulang P2 dan P3, saldo sekarang 0',
  concat_ws('/', pg_temp.k('pinjam') ->> 'hasil', ((pg_temp.k('pinjam') -> 'periode' -> 0 ->> 'id')::bigint = (select id from per where n = 2))::text,
            jsonb_array_length(pg_temp.k('pinjam') -> 'periode_ulang'), pg_temp.k('pinjam') -> 'kasbon' ->> 'saldo', pg_temp.k('pinjam') ->> 'nama'),
  'siap/true/2/0/Uji Satu');
select uji.sama('7b: Ya -> perintah kasbon (asal chat, oleh HRD, nilai) + 2 baris buku kasbon dengan perintah_id',
  (select concat_ws('/', x.asal, x.jenis, x.nilai, u.telegram_id, x.alasan,
          (select string_agg(k.jenis || ':' || k.jumlah, ',' order by k.id) from fakta.buku_kasbon k where k.perintah_id = x.id),
          (select count(*) from fakta.antrean_kerja a where a.perintah_id = x.id))
   from fakta.perintah_hrd x join induk.pengguna u on u.id = x.oleh where x.id = (pg_temp.k('pinjam_ya') ->> 'perintah_id')::bigint),
  'chat/kasbon/pinjam:1000000:250000/7701/biaya sekolah/pinjam:1000000,cicilan:250000/2');
select pg_temp.kerjakan_semua();
set local role pintu;
insert into h values ('pinjam_hasil', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('pinjam_ya') ->> 'perintah_id')::bigint)));
reset role;
select uji.sama('7b: sesudah hitung ulang: potongan kasbon P2 250.000 dan P3 250.000 (aturan I2 lama)',
  pg_temp.potong('K1', 2) || '/' || pg_temp.potong('K1', 3), '250000/250000');
select uji.sama('7b: hasil untuk bot: potongan periode berjalan 250.000, saldo 500.000, cicilan 250.000',
  concat_ws('/', pg_temp.k('pinjam_hasil') -> 'kasbon' ->> 'potongan_periode', pg_temp.k('pinjam_hasil') -> 'kasbon' ->> 'saldo',
            pg_temp.k('pinjam_hasil') -> 'kasbon' ->> 'cicilan', pg_temp.k('pinjam_hasil') ->> 'selesai_dihitung'), '250000/500000/250000/true');

-- Ganti cicilan, pelunasan melebihi saldo ditolak
set local role pintu;
insert into h values ('cicil', api.pintu_kasbon_siapkan('{"telegram_id": 7704, "kasbon_jenis": "cicilan", "id_karyawan": "K1", "jumlah": 100000, "cicilan": 999}'));
insert into h values ('cicil_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7704, 'draf_id', (pg_temp.k('cicil') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
set local role pintu;
insert into h values ('lunas_lebih', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pelunasan", "id_karyawan": "K1", "jumlah": 800001}'));
reset role;
select uji.sama('7b: ganti cicilan 100.000 (cicilan di masukan diabaikan) -> potongan P2 dan P3 100.000',
  concat_ws('/', coalesce(pg_temp.k('cicil') ->> 'cicilan', '-'), pg_temp.potong('K1', 2), pg_temp.potong('K1', 3)), '-/100000/100000');
select uji.sama('7b: pelunasan melebihi saldo (800.000) ditolak dengan saldo', pg_temp.k('lunas_lebih') ->> 'hasil' || '/' || (pg_temp.k('lunas_lebih') ->> 'saldo'),
  'melebihi_saldo/800000');

-- Batalkan pinjaman K1 -> potongan hilang (keputusan (a)); cicilan dari perintah lain tetap tercatat tetapi saldo 0.
set local role pintu;
insert into h values ('batal', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('pinjam_ya') ->> 'perintah_id')::bigint)));
insert into h values ('batal_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('batal') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7b: konfirmasi batal kasbon menyebut baris kasbon dan saldo sekarang',
  concat_ws('/', pg_temp.k('batal') ->> 'hasil', pg_temp.k('batal') -> 'dibatalkan' ->> 'jenis',
            (select string_agg(x ->> 'jenis' || ':' || (x ->> 'jumlah'), ',') from jsonb_array_elements(pg_temp.k('batal') -> 'dibatalkan' -> 'kasbon') x),
            pg_temp.k('batal') -> 'kasbon' ->> 'saldo', jsonb_array_length(pg_temp.k('batal') -> 'hari')),
  'siap/kasbon/pinjam:1000000,cicilan:250000/800000/0');
select uji.sama('7b: hasil Ya batal membawa keadaan kasbon sebelum (potongan P2 100.000)',
  pg_temp.k('batal_ya') -> 'kasbon_sebelum' ->> 'potongan_periode', '100000');
select pg_temp.kerjakan_semua();
set local role pintu;
insert into h values ('batal_hasil', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('batal_ya') ->> 'perintah_id')::bigint)));
insert into h values ('batal_lagi', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('pinjam_ya') ->> 'perintah_id')::bigint)));
insert into h values ('saldo_akhir', api.pintu_kasbon_saldo('{"telegram_id": 7701, "id_karyawan": "K1"}'));
reset role;
select uji.sama('7b GERBANG batal: kasbon dibatalkan -> potongan P2 dan P3 hilang, saldo 0',
  concat_ws('/', pg_temp.potong('K1', 2), pg_temp.potong('K1', 3), pg_temp.k('batal_hasil') -> 'kasbon' ->> 'saldo',
            pg_temp.k('batal_hasil') -> 'kasbon' ->> 'potongan_periode'), '0/0/0/0');
select uji.sama('7b: batal kedua ditolak; riwayat saldo menandai baris yang dibatalkan',
  concat_ws('/', pg_temp.k('batal_lagi') ->> 'hasil',
            (select string_agg(x ->> 'jenis' || ':' || (x ->> 'dibatalkan'), ',') from jsonb_array_elements(pg_temp.k('saldo_akhir') -> 'riwayat') x)),
  'sudah_dibatalkan/cicilan:false,cicilan:true,pinjam:true');

-- Pelunasan tunai mengurangi saldo dan potongan (K2)
set local role pintu;
insert into h values ('k2', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K2", "jumlah": 500000, "cicilan": 100000}'));
insert into h values ('k2_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('k2') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
set local role pintu;
insert into h values ('k2_lunas', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pelunasan", "id_karyawan": "K2", "jumlah": 300000, "catatan": "bayar tunai"}'));
insert into h values ('k2_lunas_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('k2_lunas') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
select uji.sama('7b: pelunasan 300.000 dari saldo 300.000 -> P2 100.000, P3 100.000, saldo 0',
  concat_ws('/', pg_temp.k('k2_lunas') -> 'kasbon' ->> 'saldo', pg_temp.potong('K2', 2), pg_temp.potong('K2', 3),
            (fakta.keadaan_kasbon('K2', (select id from per where n = 2))) ->> 'saldo'), '300000/100000/100000/0');

-- Orang rahasia: angka tidak ditampilkan
set local role pintu;
insert into h values ('rahasia_saldo', api.pintu_kasbon_saldo('{"telegram_id": 7704, "id_karyawan": "K5"}'));
insert into h values ('rahasia', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K5", "jumlah": 700000, "cicilan": 700000}'));
reset role;
select uji.sama('7b: orang rahasia: saldo tidak ditampilkan (juga ke pembangun); draf tanpa angka saldo',
  concat_ws('/', pg_temp.k('rahasia_saldo') ->> 'hasil', pg_temp.k('rahasia') ->> 'hasil', pg_temp.k('rahasia') -> 'kasbon'::text,
            (pg_temp.k('rahasia') -> 'kasbon' ? 'saldo')::text), 'rahasia/siap/{"rahasia": true}/false');

-- Periode berjalan dikunci: kasbon baru dan pembatalan kasbon ditolak
select pg_temp.jadi(2, 'dikunci');
set local role pintu;
insert into h values ('kunci', api.pintu_kasbon_siapkan('{"telegram_id": 7701, "kasbon_jenis": "pinjam", "id_karyawan": "K3", "jumlah": 100000, "cicilan": 100000}'));
insert into h values ('kunci_batal', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('k2_ya') ->> 'perintah_id')::bigint)));
reset role;
select uji.sama('7b: periode berjalan dikunci -> kasbon baru dan pembatalan ditolak',
  pg_temp.k('kunci') ->> 'hasil' || '/' || (pg_temp.k('kunci_batal') ->> 'hasil'), 'periode_dirilis/periode_dirilis');

select uji.harus_ditolak('7b: peran pintu tidak bisa memanggil fakta.keadaan_kasbon', $$select fakta.keadaan_kasbon('K1', 1)$$, 'pintu');
select uji.harus_ditolak('7b: peran pintu tidak bisa menulis buku kasbon langsung',
  $$insert into fakta.buku_kasbon (id_karyawan, jenis, jumlah) values ('K1', 'pinjam', 1)$$, 'pintu');
select uji.harus_ditolak('7b: draf kasbon pinjam tanpa cicilan ditolak tabel',
  $$insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, kedaluwarsa, kasbon_jenis, jumlah)
    values ((select id from induk.pengguna where telegram_id = 7701), 'kasbon', 'K1', current_date, current_date, now(), 'pinjam', 1)$$);

rollback;
