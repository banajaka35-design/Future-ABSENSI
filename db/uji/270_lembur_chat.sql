-- Uji paket 7c-1 (docs/rencana-tahap-7.md bagian 9): setujui/batalkan lembur lewat chat, per orang atau divisi.
-- Kasus D04 (wajib perintah tanpa perintah tidak dibayar), F12 (setujui divisi -> dibayar), D05 (otomatis lalu dibatalkan).
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

-- Divisi TL: wajib perintah sampai 9 Apr 2026, otomatis mulai 10 Apr 2026.
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari, berlaku_sampai) values
  ('lembur', 'TL', 'wajib_perintah', '2026-01-01', '2026-04-10'), ('lembur', 'TL', 'otomatis', '2026-04-10', null);
-- Tap 7 Apr (wajib perintah) dan 14 Apr (otomatis): pulang 17:05, lewat 125 menit dari jadwal 15:00. K4 sudah berhenti 10 Apr.
select fakta.terima_kiriman('uji7c.csv', repeat('c', 64), 'MA1',
  (select jsonb_agg(jsonb_build_array(n::text, t, s, r) order by r) from (
     select n, t, s, row_number() over () as r from (
       select n, d || ' 06:55:00' as t, 'Masuk' as s from generate_series(1, 5) n, unnest(array['2026-04-07', '2026-04-14']) d
        where not (n = 4 and d = '2026-04-14')
       union all
       select n, d || ' 17:05:00', 'Keluar' from generate_series(1, 5) n, unnest(array['2026-04-07', '2026-04-14']) d
        where not (n = 4 and d = '2026-04-14')) x) y),
  null, '2026-04-15 08:00+07');
select count(hitung.baca_tap(id)), count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-03-21';

create temp table h (nama text primary key, isi jsonb);
grant all on h to pintu;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
grant execute on function pg_temp.k(text) to pintu;
create function pg_temp.kerjakan_semua() returns int language plpgsql as $$
declare n int := 0; begin
  loop exit when (api.pintu_kerjakan() ->> 'kosong') = 'true'; n := n + 1; end loop; return n; end $$;
create function pg_temp.lembur(p_id text) returns bigint language sql as $$
  select coalesce(sum(r.nominal), 0)::bigint from hitung.rincian_gaji r
  join hitung.versi_terakhir v on v.id = r.versi_id and v.jenis = 'hitung_gaji'
  join fakta.periode p on p.id = v.periode_id and p.tanggal_awal = '2026-03-21'
  where r.id_karyawan = p_id and r.komponen = 'lembur' $$;
create temp table awal as select pg_temp.lembur('K1') as k1, pg_temp.lembur('K2') as k2;
select uji.sama('7c (persiapan): 7 Apr pulang 125 menit lewat jadwal; lembur K1 dan K2 sama, hanya dari 14 Apr (otomatis)',
  (select count(*) from hitung.hasil_harian hh join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
   where hh.tanggal = '2026-04-07' and hh.menit_lebih = 125) || '/' || ((select k1 from awal) > 0)::text || '/' || ((select k1 = k2 from awal))::text,
  '5/true/true');

-- Penolakan
set local role pintu;
insert into h values ('karyawan', api.pintu_lembur_siapkan('{"telegram_id": 7702, "jenis": "setujui_lembur", "sasaran": "TL", "mulai": "2026-04-07"}'));
insert into h values ('divisi_salah', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "setujui_lembur", "sasaran": "xyz", "mulai": "2026-04-07"}'));
insert into h values ('id_salah', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "setujui_lembur", "sasaran": "99999", "mulai": "2026-04-07"}'));
insert into h values ('jenis_salah', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "izin", "sasaran": "TL", "mulai": "2026-04-07"}'));
insert into h values ('dirilis', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "batalkan_lembur", "sasaran": "TL", "mulai": "2026-03-10"}'));
insert into h values ('panjang', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "setujui_lembur", "sasaran": "TL", "mulai": "2026-03-21", "selesai": "2026-04-30"}'));
insert into h values ('berhenti', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "setujui_lembur", "sasaran": "K4", "mulai": "2026-04-14"}'));
reset role;
select uji.sama('7c: akun karyawan ditolak; divisi tidak ada; ID tidak ada; jenis salah',
  concat_ws('/', pg_temp.k('karyawan') ->> 'hasil', pg_temp.k('divisi_salah') ->> 'hasil', pg_temp.k('divisi_salah') ->> 'divisi_kode',
            pg_temp.k('id_salah') ->> 'hasil', pg_temp.k('jenis_salah') ->> 'hasil'), 'bukan_hrd/divisi_tidak_ada/XYZ/tidak_ada/jenis_salah');
select uji.sama('7c: periode dirilis, rentang lebih dari 31 hari, orang tidak aktif ditolak',
  concat_ws('/', pg_temp.k('dirilis') ->> 'hasil', pg_temp.k('panjang') ->> 'hasil', pg_temp.k('berhenti') ->> 'hasil'),
  'periode_dirilis/terlalu_panjang/tidak_aktif');

-- F12: setujui lembur divisi TL 7 Apr (wajib perintah) -> dibayar
set local role pintu;
insert into h values ('setuju', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "setujui_lembur", "sasaran": "tl", "mulai": "2026-04-07", "catatan": "target ekspor"}'));
insert into h values ('setuju_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('setuju') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select uji.sama('7c: konfirmasi divisi: nama divisi, pengaturan wajib perintah, 5 orang lembur 60 menit atau lebih',
  concat_ws('/', pg_temp.k('setuju') ->> 'hasil', pg_temp.k('setuju') ->> 'divisi_kode', pg_temp.k('setuju') ->> 'divisi',
            pg_temp.k('setuju') -> 'hari' -> 0 ->> 'pengaturan', pg_temp.k('setuju') -> 'hari' -> 0 ->> 'orang_lembur'),
  'siap/TL/Uji Lantai/wajib_perintah/5');
select uji.sama('7c: Ya -> perintah setujui_lembur divisi asal chat oleh HRD; lembur sebelum tanpa orang rahasia',
  (select concat_ws('/', x.asal, x.jenis, coalesce(x.id_karyawan, '-'), x.divisi, u.telegram_id, x.alasan)
   from fakta.perintah_hrd x join induk.pengguna u on u.id = x.oleh where x.id = (pg_temp.k('setuju_ya') ->> 'perintah_id')::bigint)
  || '|' || (pg_temp.k('setuju_ya') -> 'lembur_sebelum' ->> 'rahasia') || '/' || jsonb_array_length(pg_temp.k('setuju_ya') -> 'lembur_sebelum' -> 'daftar'),
  'chat/setujui_lembur/-/TL/7701/target ekspor|1/4');
select pg_temp.kerjakan_semua();
set local role pintu;
insert into h values ('setuju_hasil', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('setuju_ya') ->> 'perintah_id')::bigint)));
reset role;
select uji.sama('7c F12: sesudah hitung ulang lembur K1 bertambah (7 Apr dibayar); hasil berisi lembur sesudah',
  concat_ws('/', (pg_temp.lembur('K1') > (select k1 from awal))::text,
            (select (x ->> 'lembur')::bigint = pg_temp.lembur('K1') from jsonb_array_elements(pg_temp.k('setuju_hasil') -> 'lembur' -> 'daftar') x where x ->> 'id' = 'K1')::text,
            pg_temp.k('setuju_hasil') -> 'hari' -> 0 -> 'perintah' -> 0 ->> 'jenis'),
  'true/true/setujui_lembur');

-- D05: batalkan lembur K1 14 Apr (otomatis) -> lembur 14 Apr hilang; K2 tidak berubah
create temp table sesudah_setuju as select pg_temp.lembur('K1') as k1, pg_temp.lembur('K2') as k2;
set local role pintu;
insert into h values ('batal_l', api.pintu_lembur_siapkan('{"telegram_id": 7704, "jenis": "batalkan_lembur", "sasaran": "K1", "mulai": "14-04-2026"}'));
insert into h values ('batal_l2', api.pintu_lembur_siapkan('{"telegram_id": 7704, "jenis": "batalkan_lembur", "sasaran": "K1", "mulai": "2026-04-14"}'));
insert into h values ('batal_l_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7704, 'draf_id', (pg_temp.k('batal_l2') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
select uji.sama('7c: tanggal bukan yyyy-mm-dd ditolak di gudang; konfirmasi orang: otomatis, 125 menit, status hadir',
  concat_ws('/', pg_temp.k('batal_l') ->> 'hasil', pg_temp.k('batal_l2') ->> 'nama', pg_temp.k('batal_l2') -> 'hari' -> 0 ->> 'pengaturan',
            pg_temp.k('batal_l2') -> 'hari' -> 0 ->> 'menit_lebih', pg_temp.k('batal_l2') -> 'hari' -> 0 ->> 'status'),
  'tanggal_salah/Uji Satu/otomatis/125/hadir');
select uji.sama('7c D05: lembur K1 14 Apr dibatalkan -> lembur K1 = bagian 7 Apr saja; K2 tidak berubah',
  concat_ws('/', (pg_temp.lembur('K1') = (select k1 from sesudah_setuju) - (select k1 from awal))::text, (pg_temp.lembur('K2') = (select k2 from sesudah_setuju))::text)
  , 'true/true');

-- Batalkan perintah setujui divisi -> 7 Apr kembali tidak dibayar (D04)
set local role pintu;
insert into h values ('bp', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('setuju_ya') ->> 'perintah_id')::bigint)));
insert into h values ('bp_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('bp') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
set local role pintu;
insert into h values ('bp_hasil', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('bp_ya') ->> 'perintah_id')::bigint)));
insert into h values ('daftar', api.pintu_perintah_terakhir('{"telegram_id": 7701}'));
reset role;
select uji.sama('7c: konfirmasi batal perintah divisi menyebut divisi dan hari lembur',
  concat_ws('/', pg_temp.k('bp') ->> 'hasil', pg_temp.k('bp') ->> 'divisi_kode', pg_temp.k('bp') -> 'dibatalkan' ->> 'jenis',
            pg_temp.k('bp') -> 'hari' -> 0 ->> 'orang_lembur'), 'siap/TL/setujui_lembur/5');
select uji.sama('7c D04: persetujuan dibatalkan -> 7 Apr tidak dibayar lagi; K1 lembur 0 (14 Apr juga dibatalkan), K2 kembali awal',
  concat_ws('/', pg_temp.lembur('K1'), (pg_temp.lembur('K2') = (select k2 from awal))::text,
            coalesce(pg_temp.k('bp_hasil') -> 'hari' -> 0 ->> 'perintah', 'kosong')), '0/true/kosong');
select uji.sama('7c: /perintahku memuat perintah divisi dengan kode divisi',
  (select x ->> 'jenis' || ':' || coalesce(x ->> 'divisi', '-') || ':' || coalesce(x ->> 'dibatalkan_oleh', '-') from jsonb_array_elements(pg_temp.k('daftar') -> 'daftar') x
   where x ->> 'jenis' = 'setujui_lembur') = 'setujui_lembur:TL:' || (pg_temp.k('bp_ya') ->> 'perintah_id'), true);

select uji.harus_ditolak('7c: peran pintu tidak bisa memanggil fakta.lembur_target', $$select fakta.lembur_target(null, 'TL', '2026-04-07', '2026-04-07')$$, 'pintu');
select uji.harus_ditolak('7c: draf divisi untuk izin ditolak tabel',
  $$insert into fakta.draf_perintah (pengguna, jenis, divisi, tanggal_mulai, tanggal_selesai, kedaluwarsa)
    values ((select id from induk.pengguna where telegram_id = 7701), 'izin', 'TL', '2026-04-07', '2026-04-07', now())$$);

rollback;
