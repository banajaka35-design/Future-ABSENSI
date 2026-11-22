-- Uji paket 7d (docs/rencana-tahap-7.md bagian 7): membatalkan perintah sakit/izin/cuti lewat chat, daftar perintah
-- chat terakhir, dan konfirmasi yang menyebut semua periode yang dihitung ulang. Data dasar sama dengan uji 240.
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
select count(hitung.baca_tap(id)) from fakta.periode where tanggal_awal = '2026-04-21';
select count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-04-21';

create temp table h (nama text primary key, isi jsonb);
grant all on h to pintu;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
create function pg_temp.status(p_id text, p_hari date) returns text language sql as $$
  select hh.status from hitung.hasil_harian hh join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
  join fakta.periode p on p.id = v.periode_id and p_hari between p.tanggal_awal and p.tanggal_akhir
  where hh.id_karyawan = p_id and hh.tanggal = p_hari $$;
create function pg_temp.kerjakan_semua() returns int language plpgsql as $$
declare n int := 0; begin
  loop exit when (api.pintu_kerjakan() ->> 'kosong') = 'true'; n := n + 1; end loop; return n; end $$;
grant execute on function pg_temp.k(text) to pintu;

-- Perintah dari file (seperti muat_masukan_hrd) dan dari chat; keduanya bisa dibatalkan.
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, tanggal_selesai)
values ('file', 'sakit', 'K2', '2026-04-08', '2026-04-08'), ('file', 'tukar_shift', 'K3', '2026-04-08', '2026-04-08');
insert into h select 'id_tukar', to_jsonb(id) from fakta.perintah_hrd where jenis = 'tukar_shift';
insert into h select 'id_sakit_file', to_jsonb(id) from fakta.perintah_hrd where asal = 'file' and jenis = 'sakit';
set local role pintu;
insert into h values ('izin_siap', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "izin", "id_karyawan": "K1", "mulai": "2026-04-08"}'));
insert into h values ('izin_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('izin_siap') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
select uji.sama('7d (persiapan): K1 izin dari chat, K2 sakit dari file', pg_temp.status('K1', '2026-04-08') || '/' || pg_temp.status('K2', '2026-04-08'), 'izin/sakit');
select uji.sama('7d: konfirmasi 7a kini menyebut semua periode yang dihitung ulang (periode sesudahnya yang punya gaji ikut)',
  (select string_agg(x ->> 'awal', ',') from jsonb_array_elements(pg_temp.k('izin_siap') -> 'periode_ulang') x)
  || '|' || jsonb_array_length(pg_temp.k('izin_siap') -> 'periode'), '2026-03-21,2026-04-21|1');

-- Penolakan
set local role pintu;
insert into h values ('karyawan', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7702, 'perintah_id', (pg_temp.k('izin_ya') ->> 'perintah_id')::bigint)));
insert into h values ('tidak_ada', api.pintu_batal_siapkan('{"telegram_id": 7701, "perintah_id": 999999}'));
insert into h values ('bukan_angka', api.pintu_batal_siapkan('{"telegram_id": 7701, "perintah_id": "abc"}'));
insert into h values ('tukar', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701,
  'perintah_id', pg_temp.k('id_tukar'))));
insert into h values ('lama', api.pintu_perintah_terakhir('{"telegram_id": 7702}'));
reset role;
select uji.sama('7d: akun karyawan ditolak', pg_temp.k('karyawan') ->> 'hasil' || '/' || (pg_temp.k('lama') ->> 'hasil'), 'bukan_hrd/bukan_hrd');
select uji.sama('7d: nomor tidak ada atau bukan angka ditolak', pg_temp.k('tidak_ada') ->> 'hasil' || '/' || (pg_temp.k('bukan_angka') ->> 'hasil'),
  'tidak_ada_perintah/tidak_ada_perintah');
select uji.sama('7d: jenis selain sakit/izin/cuti ditolak', pg_temp.k('tukar') ->> 'hasil' || '/' || (pg_temp.k('tukar') ->> 'jenis'), 'jenis_tidak_bisa/tukar_shift');

-- Batalkan izin chat K1: konfirmasi -> Ya -> kembali alpha
set local role pintu;
insert into h values ('batal_siap', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7704, 'perintah_id', (pg_temp.k('izin_ya') ->> 'perintah_id')::bigint)));
insert into h values ('batal_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7704, 'draf_id', (pg_temp.k('batal_siap') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7d: konfirmasi berisi perintah yang dibatalkan, status sekarang, semua periode ulang; tanpa angka gaji',
  concat_ws('/', pg_temp.k('batal_siap') ->> 'hasil', pg_temp.k('batal_siap') -> 'dibatalkan' ->> 'jenis', pg_temp.k('batal_siap') -> 'dibatalkan' ->> 'asal',
            pg_temp.k('batal_siap') ->> 'nama', pg_temp.k('batal_siap') -> 'hari' -> 0 ->> 'status',
            jsonb_array_length(pg_temp.k('batal_siap') -> 'periode_ulang'), (pg_temp.k('batal_siap')::text ~ '(bersih|3500000)')::text),
  'siap/izin/chat/Uji Satu/izin/2/false');
select uji.sama('7d: Ya -> perintah batalkan_perintah asal chat oleh pembangun, antrean dua periode',
  (select concat_ws('/', x.asal, x.jenis, (x.membatalkan = (pg_temp.k('izin_ya') ->> 'perintah_id')::bigint)::text, u.peran,
                    (select count(*) from fakta.antrean_kerja a where a.perintah_id = x.id))
   from fakta.perintah_hrd x join induk.pengguna u on u.id = x.oleh where x.id = (pg_temp.k('batal_ya') ->> 'perintah_id')::bigint),
  'chat/batalkan_perintah/true/pembangun/2');
select uji.sama('7d: hasil Ya membawa status sebelum (izin)', pg_temp.k('batal_ya') -> 'hari_sebelum' -> 0 ->> 'status', 'izin');
select pg_temp.kerjakan_semua();
select uji.sama('7d: sesudah hitung ulang K1 kembali alpha (hasil dari tap)', pg_temp.status('K1', '2026-04-08'), 'alpha');
set local role pintu;
insert into h values ('hasil', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7704, 'perintah_id', (pg_temp.k('batal_ya') ->> 'perintah_id')::bigint)));
insert into h values ('lagi', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('izin_ya') ->> 'perintah_id')::bigint)));
insert into h values ('batal_batal', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('batal_ya') ->> 'perintah_id')::bigint)));
reset role;
select uji.sama('7d: hasil untuk bot: alpha, selesai, tidak ada perintah yang berlaku',
  concat_ws('/', pg_temp.k('hasil') -> 'hari' -> 0 ->> 'status', pg_temp.k('hasil') ->> 'selesai_dihitung',
            coalesce(pg_temp.k('hasil') -> 'hari' -> 0 ->> 'perintah_lama', 'kosong')), 'alpha/true/kosong');
select uji.sama('7d: membatalkan dua kali ditolak (menyebut nomor pembatalnya)',
  pg_temp.k('lagi') ->> 'hasil' || '/' || ((pg_temp.k('lagi') ->> 'oleh_perintah') = (pg_temp.k('batal_ya') ->> 'perintah_id'))::text, 'sudah_dibatalkan/true');
select uji.sama('7d: perintah pembatalan sendiri tidak bisa dibatalkan', pg_temp.k('batal_batal') ->> 'hasil', 'jenis_tidak_bisa');

-- Dua draf pembatalan untuk perintah yang sama: Ya kedua ditolak.
set local role pintu;
insert into h values ('dua_a', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', pg_temp.k('id_sakit_file'))));
insert into h values ('dua_b', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7705, 'perintah_id', pg_temp.k('id_sakit_file'))));
insert into h values ('dua_a_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('dua_a') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('dua_b_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7705, 'draf_id', (pg_temp.k('dua_b') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
select uji.sama('7d: perintah dari file bisa dibatalkan; draf kedua untuk perintah yang sama ditolak; K2 kembali hadir',
  concat_ws('/', pg_temp.k('dua_a') -> 'dibatalkan' ->> 'asal', pg_temp.k('dua_a_ya') ->> 'hasil', pg_temp.k('dua_b_ya') ->> 'hasil',
            (select count(*) from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = (select id from fakta.perintah_hrd where asal = 'file' and jenis = 'sakit')),
            pg_temp.status('K2', '2026-04-08')), 'file/disimpan/sudah_dibatalkan/1/hadir');

-- Periode dikunci: pembatalan ditolak, juga bila dikunci sesudah draf dibuat.
set local role pintu;
insert into h values ('cuti_siap', api.pintu_perintah_siapkan('{"telegram_id": 7701, "jenis": "cuti", "id_karyawan": "K3", "mulai": "2026-04-07"}'));
insert into h values ('cuti_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('cuti_siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('kunci_siap', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('cuti_ya') ->> 'perintah_id')::bigint)));
reset role;
select pg_temp.jadi('2026-03-21', 'dikunci');
set local role pintu;
insert into h values ('kunci_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('kunci_siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('kunci', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('cuti_ya') ->> 'perintah_id')::bigint)));
insert into h values ('daftar', api.pintu_perintah_terakhir('{"telegram_id": 7705}'));
reset role;
select uji.sama('7d: periode dikunci sesudah draf dibuat -> Ya ditolak; batal baru juga ditolak; tidak ada pembatalan tercatat',
  concat_ws('/', pg_temp.k('kunci_siap') ->> 'hasil', pg_temp.k('kunci_ya') ->> 'hasil', pg_temp.k('kunci') ->> 'hasil',
            (select count(*) from fakta.perintah_hrd where jenis = 'batalkan_perintah' and membatalkan = (pg_temp.k('cuti_ya') ->> 'perintah_id')::bigint)),
  'siap/periode_dirilis/periode_dirilis/0');

-- Daftar perintah chat terakhir: urutan terbaru dulu, pencatat, status dibatalkan; perintah file tidak ikut.
select uji.sama('7d: /perintahku berisi perintah chat terbaru dulu, dengan pembatal; tanpa perintah file',
  (select string_agg(concat_ws(':', x ->> 'jenis', x ->> 'id_karyawan', x ->> 'oleh', (coalesce(x ->> 'dibatalkan_oleh', '-') <> '-')::text), ',')
   from jsonb_array_elements(pg_temp.k('daftar') -> 'daftar') x),
  'cuti:K3:hrd:false,batalkan_perintah:K2:hrd:false,batalkan_perintah:K1:pembangun:false,izin:K1:hrd:true');
select uji.harus_ditolak('7d: peran pintu tidak bisa memanggil fakta.periode_hitung_ulang', $$select fakta.periode_hitung_ulang('2026-04-08', '2026-04-08')$$, 'pintu');
select uji.harus_ditolak('7d: draf batal tanpa nomor perintah ditolak tabel',
  $$insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, kedaluwarsa)
    values ((select id from induk.pengguna where telegram_id = 7701), 'batalkan_perintah', 'K1', '2026-04-08', '2026-04-08', now())$$);

rollback;
