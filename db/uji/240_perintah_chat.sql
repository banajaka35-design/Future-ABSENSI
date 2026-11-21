-- Uji paket 7a (docs/rencana-tahap-7.md bagian 5): izin, sakit, cuti lewat chat, termasuk susulan.
-- Gerbang Tahap 7 (PRD v2 bagian 13): izin susulan mengubah hasil setelah hitung ulang.
-- Fungsi api dipanggil sebagai peran pintu, seperti Edge Function. Satu transaksi yang dibatalkan di akhir.
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

-- Tap 7-8 April 2026: semua hadir 7 April; 8 April K1 tidak tap (alpha, bukan hari tanpa tap massal).
select fakta.terima_kiriman('uji7a.csv', repeat('7', 64), 'MA1',
  (select jsonb_agg(jsonb_build_array(n::text, t, s, r) order by r) from (
     select n, t, s, row_number() over () as r from (
       select n, d || ' 06:55:00' as t, 'Masuk' as s from generate_series(1, 5) n, unnest(array['2026-04-07', '2026-04-08']) d
        where not (n = 1 and d = '2026-04-08')
       union all
       select n, d || ' 15:05:00', 'Keluar' from generate_series(1, 5) n, unnest(array['2026-04-07', '2026-04-08']) d
        where not (n = 1 and d = '2026-04-08')) x) y),
  null, '2026-04-09 08:00+07');
select count(hitung.baca_tap(id)) from fakta.periode where tanggal_awal = '2026-03-21';
select count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-03-21';

create temp table h (nama text primary key, isi jsonb);
grant all on h to pintu;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
create function pg_temp.status(p_id text, p_hari date) returns text language sql as $$
  select hh.status from hitung.hasil_harian hh join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
  join fakta.periode p on p.id = v.periode_id and p_hari between p.tanggal_awal and p.tanggal_akhir
  where hh.id_karyawan = p_id and hh.tanggal = p_hari $$;
grant execute on function pg_temp.k(text) to pintu;

select uji.sama('7a (persiapan): 8 Apr K1 alpha, K2 hadir', pg_temp.status('K1', '2026-04-08') || '/' || pg_temp.status('K2', '2026-04-08'), 'alpha/hadir');

set local role pintu;
-- Penolakan
insert into h values ('karyawan', api.pintu_perintah_siapkan('{"telegram_id": 7702, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-04-08"}'));
insert into h values ('bos', api.pintu_perintah_siapkan('{"telegram_id": 7703, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-04-08"}'));
insert into h values ('jenis', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "kasbon", "id_karyawan": "K1", "mulai": "2026-04-08"}'));
insert into h values ('tidak_ada', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "izin", "id_karyawan": "K99", "mulai": "2026-04-08"}'));
insert into h values ('tanggal_rusak', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-02-30"}'));
insert into h values ('terbalik', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-04-08", "selesai": "2026-04-07"}'));
insert into h values ('panjang', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "cuti", "id_karyawan": "K1", "mulai": "2026-03-21", "selesai": "2026-04-21"}'));
insert into h values ('tanpa_periode', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-06-01"}'));
insert into h values ('dirilis', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-03-20", "selesai": "2026-03-21"}'));
insert into h values ('berhenti', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "sakit", "id_karyawan": "K4", "mulai": "2026-04-10", "selesai": "2026-04-11"}'));
insert into h values ('berhenti_ok', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "sakit", "id_karyawan": "k4", "mulai": "2026-04-10"}'));
-- Izin susulan 8 April untuk K1 (gerbang)
insert into h values ('siap', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-04-08", "catatan": "  urusan keluarga "}'));
insert into h values ('orang_lain', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7705, 'draf_id', (pg_temp.k('siap') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7a: akun karyawan dan bos ditolak', pg_temp.k('karyawan') ->> 'hasil' || '/' || (pg_temp.k('bos') ->> 'hasil'), 'bukan_hrd/bukan_hrd');
select uji.sama('7a: jenis selain sakit/izin/cuti ditolak', pg_temp.k('jenis') ->> 'hasil', 'jenis_salah');
select uji.sama('7a: ID karyawan tidak ada ditolak', pg_temp.k('tidak_ada') ->> 'hasil', 'tidak_ada');
select uji.sama('7a: tanggal tidak ada (30 Feb) dan tanggal terbalik ditolak',
  pg_temp.k('tanggal_rusak') ->> 'hasil' || '/' || (pg_temp.k('terbalik') ->> 'hasil'), 'tanggal_salah/tanggal_salah');
select uji.sama('7a: rentang lebih dari 31 hari ditolak', pg_temp.k('panjang') ->> 'hasil' || '/' || (pg_temp.k('panjang') ->> 'hari'), 'terlalu_panjang/32');
select uji.sama('7a: tanggal di luar periode mana pun ditolak', pg_temp.k('tanpa_periode') ->> 'hasil', 'tanpa_periode');
select uji.sama('7a: rentang yang menyentuh periode dirilis ditolak (tanggal dan periode disebut)',
  concat_ws('/', pg_temp.k('dirilis') ->> 'hasil', pg_temp.k('dirilis') ->> 'tanggal', pg_temp.k('dirilis') -> 'periode' ->> 'status'),
  'periode_dirilis/2026-03-20/dirilis');
select uji.sama('7a: hari sesudah tanggal berhenti ditolak; tanggal berhenti sendiri (hari kerja terakhir) boleh, ID huruf kecil dikenali',
  concat_ws('/', pg_temp.k('berhenti') ->> 'hasil', pg_temp.k('berhenti') ->> 'tanggal', pg_temp.k('berhenti_ok') ->> 'hasil', pg_temp.k('berhenti_ok') ->> 'id'),
  'tidak_aktif/2026-04-11/siap/K4');
select uji.sama('7a: penolakan tidak membuat draf', (select count(*) from fakta.draf_perintah), 2::bigint);
select uji.sama('7a: draf berisi nama, divisi, status sekarang, catatan dirapikan; tanpa angka gaji',
  concat_ws('/', pg_temp.k('siap') ->> 'hasil', pg_temp.k('siap') ->> 'nama', pg_temp.k('siap') ->> 'divisi',
            pg_temp.k('siap') -> 'hari' -> 0 ->> 'status', pg_temp.k('siap') ->> 'catatan',
            (pg_temp.k('siap')::text ~ '(bersih|gaji_pokok|3500000)')::text),
  'siap/Uji Satu/Uji Lantai/alpha/urusan keluarga/false');
select uji.sama('7a: draf HRD lain tidak bisa dipakai', pg_temp.k('orang_lain') ->> 'hasil', 'tidak_berlaku');
select uji.sama('7a: sebelum Ya tidak ada perintah chat dan antrean kosong',
  (select count(*) from fakta.perintah_hrd where asal = 'chat') || '/' || (select count(*) from fakta.antrean_kerja), '0/0');

-- Ya -> perintah dicatat, antrean terisi periode yang kena dan periode sesudahnya yang sudah punya gaji (tidak ada di sini).
set local role pintu;
insert into h values ('ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('ya_lagi', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('hasil_sebelum', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('ya') ->> 'perintah_id')::bigint)));
insert into h values ('kerja1', api.pintu_kerjakan());
insert into h values ('kerja2', api.pintu_kerjakan());
insert into h values ('hasil_sesudah', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('ya') ->> 'perintah_id')::bigint)));
insert into h values ('hasil_karyawan', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7702, 'perintah_id', (pg_temp.k('ya') ->> 'perintah_id')::bigint)));
reset role;
select uji.sama('7a: Ya -> perintah izin asal chat, oleh akun HRD, catatan sebagai alasan',
  (select concat_ws('/', x.asal, x.jenis, x.id_karyawan, x.tanggal_mulai, x.tanggal_selesai, u.telegram_id, x.alasan)
   from fakta.perintah_hrd x join induk.pengguna u on u.id = x.oleh where x.id = (pg_temp.k('ya') ->> 'perintah_id')::bigint),
  'chat/izin/K1/2026-04-08/2026-04-08/7701/urusan keluarga');
select uji.sama('7a: hasil Ya membawa status sebelum (alpha)', pg_temp.k('ya') -> 'hari_sebelum' -> 0 ->> 'status', 'alpha');
select uji.sama('7a: tombol Ya hanya berlaku sekali', pg_temp.k('ya_lagi') ->> 'hasil', 'tidak_berlaku');
select uji.sama('7a: antrean berisi periode 21 Mar-20 Apr dengan nomor perintah',
  (select string_agg(p.tanggal_awal::text || '#' || (a.perintah_id = (pg_temp.k('ya') ->> 'perintah_id')::bigint)::text, ',')
   from fakta.antrean_kerja a join fakta.periode p on p.id = a.periode_id), '2026-03-21#true');
select uji.sama('7a: sebelum dihitung, hasil masih alpha dan belum selesai',
  (pg_temp.k('hasil_sebelum') -> 'hari' -> 0 ->> 'status') || '/' || (pg_temp.k('hasil_sebelum') ->> 'selesai_dihitung'), 'alpha/false');
select uji.sama('7a: antrean dikerjakan lalu kosong', (pg_temp.k('kerja1') -> 'hasil' ? 'versi_gaji') || '/' || (pg_temp.k('kerja2') ->> 'kosong'), 'true/true');
select uji.sama('7a GERBANG: izin susulan mengubah hasil setelah hitung ulang (alpha -> izin)', pg_temp.status('K1', '2026-04-08'), 'izin');
select uji.sama('7a: hasil untuk bot: izin, selesai, perintah lama = perintah ini',
  concat_ws('/', pg_temp.k('hasil_sesudah') -> 'hari' -> 0 ->> 'status', pg_temp.k('hasil_sesudah') ->> 'selesai_dihitung',
            pg_temp.k('hasil_sesudah') ->> 'gagal',
            ((pg_temp.k('hasil_sesudah') -> 'hari' -> 0 -> 'perintah_lama' ->> 'id') = pg_temp.k('ya') ->> 'perintah_id')::text),
  'izin/true/false/true');
select uji.sama('7a: hasil perintah hanya untuk HRD/pembangun', pg_temp.k('hasil_karyawan') ->> 'hasil', 'bukan_hrd');
select uji.sama('7a: hari lain dan orang lain tidak berubah', pg_temp.status('K1', '2026-04-07') || '/' || pg_temp.status('K2', '2026-04-08'), 'hadir/hadir');
select uji.sama('7a: gaji periode itu dihitung ulang dari baca tap baru',
  (select g.versi_sumber = b.id from hitung.versi_terakhir g join hitung.versi_terakhir b on b.periode_id = g.periode_id and b.jenis = 'baca_tap'
   join fakta.periode p on p.id = g.periode_id where g.jenis = 'hitung_gaji' and p.tanggal_awal = '2026-03-21'), true);

-- Periode sesudahnya yang sudah punya gaji ikut dihitung ulang (sisa pembulatan dan kasbon berantai, aturan J4).
select count(hitung.baca_tap(id)) from fakta.periode where tanggal_awal = '2026-04-21';
select count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-04-21';

-- Perintah baru di hari yang sama menggantikan yang lama; pembangun boleh; Batal tidak membuat perintah.
set local role pintu;
insert into h values ('ganti_siap', api.pintu_perintah_siapkan('{"telegram_id": 7704, "jenis": "sakit", "id_karyawan": "K1", "mulai": "2026-04-08"}'));
insert into h values ('ganti_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7704, 'draf_id', (pg_temp.k('ganti_siap') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7a: antrean berisi periode yang kena dan periode sesudahnya yang sudah punya gaji',
  (select string_agg(p.tanggal_awal::text, ',' order by p.tanggal_awal) from fakta.antrean_kerja a join fakta.periode p on p.id = a.periode_id
   where a.perintah_id = (pg_temp.k('ganti_ya') ->> 'perintah_id')::bigint), '2026-03-21,2026-04-21');
set local role pintu;
insert into h values ('kerja3', api.pintu_kerjakan());
insert into h values ('kerja4', api.pintu_kerjakan());
insert into h values ('batal_siap', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "cuti", "id_karyawan": "K2", "mulai": "2026-04-07", "selesai": "2026-04-08"}'));
insert into h values ('batal', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('batal_siap') ->> 'draf_id')::bigint, 'ya', false)));
insert into h values ('batal_lalu_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('batal_siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('kedaluwarsa_siap', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "cuti", "id_karyawan": "K3", "mulai": "2026-04-07"}'));
reset role;
select uji.sama('7a: draf menyebut perintah lama yang akan tertimpa',
  pg_temp.k('ganti_siap') -> 'hari' -> 0 -> 'perintah_lama' ->> 'jenis' || '/' || (pg_temp.k('ganti_siap') -> 'hari' -> 0 ->> 'status'), 'izin/izin');
select uji.sama('7a: pembangun boleh; perintah terbaru menang (izin -> sakit); kedua periode dihitung',
  concat_ws('/', pg_temp.k('ganti_ya') ->> 'hasil', pg_temp.status('K1', '2026-04-08'), (pg_temp.k('kerja3') -> 'hasil' ? 'versi_gaji')::text,
            (pg_temp.k('kerja4') -> 'hasil' ? 'versi_gaji')::text), 'disimpan/sakit/true/true');
select uji.sama('7a: Batal -> tidak ada perintah, draf tidak bisa dipakai lagi',
  concat_ws('/', pg_temp.k('batal') ->> 'hasil', pg_temp.k('batal_lalu_ya') ->> 'hasil',
            (select count(*) from fakta.perintah_hrd where asal = 'chat' and id_karyawan = 'K2')), 'dibatalkan/tidak_berlaku/0');
update fakta.draf_perintah set kedaluwarsa = now() - interval '1 second' where id = (pg_temp.k('kedaluwarsa_siap') ->> 'draf_id')::bigint;
set local role pintu;
insert into h values ('kedaluwarsa', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('kedaluwarsa_siap') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7a: draf lewat 15 menit tidak berlaku', pg_temp.k('kedaluwarsa') ->> 'hasil', 'tidak_berlaku');

-- Periode sesudahnya yang sudah dirilis tidak ikut antrean (tidak dihitung ulang, bukan "file kena periode dirilis").
select pg_temp.jadi('2026-04-21', 'dirilis');
set local role pintu;
insert into h values ('lanjut_siap', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "sakit", "id_karyawan": "K3", "mulai": "2026-04-07"}'));
insert into h values ('lanjut_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('lanjut_siap') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7a: periode sesudahnya yang dirilis tidak ikut antrean',
  (select string_agg(p.tanggal_awal::text, ',') from fakta.antrean_kerja a join fakta.periode p on p.id = a.periode_id
   where a.perintah_id = (pg_temp.k('lanjut_ya') ->> 'perintah_id')::bigint), '2026-03-21');

-- Periode dirilis sesudah draf dibuat: pemeriksaan diulang saat Ya.
set local role pintu;
insert into h values ('rilis_siap', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "cuti", "id_karyawan": "K2", "mulai": "2026-04-07"}'));
reset role;
select pg_temp.jadi('2026-03-21', 'dirilis');
set local role pintu;
insert into h values ('rilis_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('rilis_siap') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7a: periode dirilis sesudah draf dibuat -> Ya ditolak, tidak ada perintah',
  pg_temp.k('rilis_ya') ->> 'hasil' || '/' || (select count(*) from fakta.perintah_hrd where asal = 'chat' and id_karyawan = 'K2'), 'periode_dirilis/0');

-- Akses
select uji.harus_ditolak('7a: peran pintu tidak bisa menulis draf langsung',
  $$insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, kedaluwarsa) values (1, 'izin', 'K1', '2026-04-08', '2026-04-08', now())$$, 'pintu');
select uji.harus_ditolak('7a: peran pintu tidak bisa menulis perintah HRD langsung',
  $$insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai) values ('chat', 'izin', 'K1', '2026-04-08')$$, 'pintu');
select uji.harus_ditolak('7a: peran pintu tidak bisa memanggil pembantu fakta', $$select fakta.periksa_perintah('izin', 'K1', '2026-04-08', '2026-04-08')$$, 'pintu');
select uji.harus_ditolak('7a: perintah yang tersimpan tidak bisa diubah', $$update fakta.perintah_hrd set jenis = 'cuti' where asal = 'chat'$$);

rollback;
