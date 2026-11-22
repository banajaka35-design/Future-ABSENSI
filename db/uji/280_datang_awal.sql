-- Uji paket 7c-2 (docs/rencana-tahap-7.md bagian 10-11; permintaan perubahan 06): jam datang awal yang disetujui.
-- B05 (tanpa persetujuan tidak dihitung), B05b (90 + 45 = 135 -> 120 menit), divisi, data tap meragukan, wajib perintah,
-- shift malam lewat tengah malam, pembatalan. Data dasar sama dengan uji 240.
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
select count(hitung.baca_tap(id)), count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-03-21';

create temp table h (nama text primary key, isi jsonb);
grant all on h to pintu;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
grant execute on function pg_temp.k(text) to pintu;
create function pg_temp.kerjakan_semua() returns int language plpgsql as $$
declare n int := 0; begin
  loop exit when (api.pintu_kerjakan() ->> 'kosong') = 'true'; n := n + 1; end loop; return n; end $$;
-- Menit lembur dibayar per orang (dari bukti rincian) dan peringatan.
create function pg_temp.menit(p_id text) returns int language sql as $$
  select coalesce((select substring(r.bukti from 'Lembur ([0-9]+) menit dibayar')::int from hitung.rincian_gaji r
   join hitung.versi_terakhir v on v.id = r.versi_id and v.jenis = 'hitung_gaji'
   join fakta.periode p on p.id = v.periode_id and p.tanggal_awal = '2026-03-21'
   where r.id_karyawan = p_id and r.komponen = 'lembur'), 0) $$;
create function pg_temp.tanda(p_id text) returns text language sql as $$
  select array_to_string(g.peringatan, ',') from hitung.ringkasan_gaji g
  join hitung.versi_terakhir v on v.id = g.versi_id and v.jenis = 'hitung_gaji'
  join fakta.periode p on p.id = v.periode_id and p.tanggal_awal = '2026-03-21' where g.id_karyawan = p_id $$;
create function pg_temp.setuju(p_tg bigint, p_sasaran text, p_mulai text, p_selesai text, p_nama text) returns jsonb language plpgsql as $$
declare r jsonb; s jsonb; begin
  set local role pintu;
  r := api.pintu_lembur_siapkan(jsonb_build_object('telegram_id', p_tg, 'jenis', 'setujui_datang_awal', 'sasaran', p_sasaran,
                                                   'mulai', p_mulai, 'selesai', p_selesai));
  insert into h values (p_nama, r);
  if r ->> 'hasil' = 'siap' then
    s := api.pintu_perintah_simpan(jsonb_build_object('telegram_id', p_tg, 'draf_id', (r ->> 'draf_id')::bigint, 'ya', true));
    insert into h values (p_nama || '_ya', s);
  end if;
  reset role;
  return r; end $$;

select uji.sama('7c-2 (persiapan): versi kode gaji 7', hitung.versi_kode_gaji(), 'hitung_gaji 7 (paket 7c-2)');
select uji.sama('7c-2 B05: tanpa persetujuan datang awal tidak dihitung (K1 45 menit sore -> 0; K2 50 -> 0; K3 hanya sore 14 Apr tanpa setujui -> 0)',
  concat_ws('/', pg_temp.menit('K1'), pg_temp.menit('K2'), pg_temp.menit('K3'), (coalesce(pg_temp.tanda('K1'), '') like '%datang_awal%')::text), '0/0/0/false');
select uji.sama('7c-2: menit datang awal dibaca dari tap tersimpan: B05b 90, K2 8 Apr 40, malam K1 11 Apr 40, lupa tap K3 9 Apr 0',
  (select string_agg(hh.id_karyawan || '@' || to_char(hh.tanggal, 'DD') || '=' ||
          hitung.menit_datang_awal(hh.status, hh.asal, hh.masuk, hh.pulang, hh.jadwal_masuk, hh.lupa_tap, hh.ambigu, hh.tanda), ',' order by hh.tanggal, hh.id_karyawan)
   from hitung.hasil_harian hh join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
   where (hh.id_karyawan, hh.tanggal) in (('K1', '2026-04-07'), ('K2', '2026-04-08'), ('K3', '2026-04-09'), ('K1', '2026-04-11'))),
  'K1@07=90,K2@08=40,K3@09=0,K1@11=40');

-- Penolakan
select pg_temp.setuju(7702, 'K1', '2026-04-07', null, 'karyawan');
select pg_temp.setuju(7701, 'XYZ', '2026-04-07', null, 'xyz');
select pg_temp.setuju(7701, 'K1', '2026-03-10', null, 'dirilis');
select uji.sama('7c-2: akun karyawan, divisi tidak ada, periode dirilis ditolak',
  concat_ws('/', pg_temp.k('karyawan') ->> 'hasil', pg_temp.k('xyz') ->> 'hasil', pg_temp.k('dirilis') ->> 'hasil'), 'bukan_hrd/divisi_tidak_ada/periode_dirilis');

-- B05b: setujui datang awal K1 7 Apr -> 90 + 45 = 135 -> 120 menit
select pg_temp.setuju(7701, 'K1', '2026-04-07', null, 'b05b');
select pg_temp.kerjakan_semua();
select uji.sama('7c-2: konfirmasi orang menyebut menit datang awal 90 dan menit lewat jam pulang 45',
  concat_ws('/', pg_temp.k('b05b') ->> 'hasil', pg_temp.k('b05b') -> 'hari' -> 0 ->> 'menit_awal', pg_temp.k('b05b') -> 'hari' -> 0 ->> 'menit_lebih'),
  'siap/90/45');
select uji.sama('7c-2 B05b: datang awal disetujui -> 120 menit dibayar, tanda lembur_datang_awal_disetujui; orang lain tidak berubah',
  concat_ws('/', pg_temp.menit('K1'), (pg_temp.tanda('K1') like '%lembur_datang_awal_disetujui%')::text, pg_temp.menit('K2'), pg_temp.menit('K3')),
  '120/true/0/0');
select uji.sama('7c-2: perintah tercatat sebagai setujui_datang_awal (bukan setujui_lembur)',
  (select x.jenis || ':' || x.id_karyawan from fakta.perintah_hrd x where x.id = (pg_temp.k('b05b_ya') ->> 'perintah_id')::bigint),
  'setujui_datang_awal:K1');

-- Divisi 8-9 Apr: K2 40 + 50 = 90 -> 90; K3 5 + 5 = 10 -> 0; K3 9 Apr lupa tap pulang -> tidak dihitung; K1, K5 5 + 5 -> 0
select pg_temp.setuju(7701, 'TL', '2026-04-08', '2026-04-09', 'divisi');
select pg_temp.kerjakan_semua();
select uji.sama('7c-2: konfirmasi divisi: orang dan menit datang awal per hari (data meragukan tidak dijumlah)',
  concat_ws('/', pg_temp.k('divisi') ->> 'divisi_kode', pg_temp.k('divisi') -> 'hari' -> 0 -> 'awal_divisi' ->> 'orang', pg_temp.k('divisi') -> 'hari' -> 0 -> 'awal_divisi' ->> 'menit',
            pg_temp.k('divisi') -> 'hari' -> 1 -> 'awal_divisi' ->> 'orang'),
  'TL/4/55/3');
select uji.sama('7c-2: persetujuan divisi -> K2 90 menit; K3 dan K5 tetap 0 (kurang dari 60); K1 tetap 120',
  concat_ws('/', pg_temp.menit('K2'), pg_temp.menit('K3'), pg_temp.menit('K1'),
            (select count(*) from hitung.rincian_gaji r join hitung.versi_terakhir v on v.id = r.versi_id and v.jenis = 'hitung_gaji'
             where r.id_karyawan = 'K5' and r.komponen = 'lembur')), '90/0/120/0');

-- Shift malam lewat tengah malam: K1 11 Apr 40 + 30 = 70 -> 60; total K1 180
select pg_temp.setuju(7704, 'K1', '2026-04-11', null, 'malam');
select pg_temp.kerjakan_semua();
select uji.sama('7c-2: shift malam 22:20-07:30 disetujui -> 60 menit; K1 total 180', pg_temp.menit('K1')::text, '180');

-- Wajib perintah 14 Apr: datang awal K3 disetujui, sore tidak -> pagi 60 saja, tanda sore tidak dibayar
select pg_temp.setuju(7701, 'K3', '2026-04-14', null, 'wajib');
select pg_temp.kerjakan_semua();
select uji.sama('7c-2: wajib perintah, hanya datang awal disetujui -> 60 menit (bagian sore 90 tidak), dua tanda',
  concat_ws('/', pg_temp.menit('K3'), (pg_temp.tanda('K3') like '%lembur_tidak_dibayar_tanpa_izin%')::text,
            (pg_temp.tanda('K3') like '%lembur_datang_awal_disetujui%')::text), '60/true/true');
-- Lalu sore juga disetujui (setujui_lembur) -> 60 + 90 = 150
set local role pintu;
insert into h values ('sore', api.pintu_lembur_siapkan('{"telegram_id": 7701, "jenis": "setujui_lembur", "sasaran": "K3", "mulai": "2026-04-14"}'));
insert into h values ('sore_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('sore') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
select uji.sama('7c-2: datang awal dan sore sama-sama disetujui -> 150 menit, tanda sore tidak dibayar hilang',
  concat_ws('/', pg_temp.menit('K3'), (pg_temp.tanda('K3') like '%lembur_tidak_dibayar_tanpa_izin%')::text), '150/false');

-- Persetujuan ganda dihitung sekali; pembatalan mengembalikan
select pg_temp.setuju(7705, 'TL', '2026-04-07', null, 'ganda');
select pg_temp.kerjakan_semua();
select uji.sama('7c-2: persetujuan orang + divisi untuk hari yang sama dihitung sekali (K1 tetap 180)', pg_temp.menit('K1')::text, '180');
set local role pintu;
insert into h values ('bp', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('b05b_ya') ->> 'perintah_id')::bigint)));
insert into h values ('bp_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('bp') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('bp2', api.pintu_batal_siapkan(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('ganda_ya') ->> 'perintah_id')::bigint)));
insert into h values ('bp2_ya', api.pintu_perintah_simpan(jsonb_build_object('telegram_id', 7701, 'draf_id', (pg_temp.k('bp2') ->> 'draf_id')::bigint, 'ya', true)));
reset role;
select pg_temp.kerjakan_semua();
set local role pintu;
insert into h values ('bp_hasil', api.pintu_perintah_hasil(jsonb_build_object('telegram_id', 7701, 'perintah_id', (pg_temp.k('bp_ya') ->> 'perintah_id')::bigint)));
reset role;
select uji.sama('7c-2: kedua persetujuan 7 Apr dibatalkan -> K1 tinggal shift malam 60 menit; hasil bot berisi lembur',
  concat_ws('/', pg_temp.k('bp') ->> 'hasil', pg_temp.k('bp') -> 'dibatalkan' ->> 'jenis', pg_temp.menit('K1'),
            jsonb_array_length(pg_temp.k('bp_hasil') -> 'lembur' -> 'daftar')), 'siap/setujui_datang_awal/60/1');

select uji.harus_ditolak('7c-2: peran pintu tidak bisa menulis perintah setujui_datang_awal langsung',
  $$insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai) values ('chat', 'setujui_datang_awal', 'K1', '2026-04-07')$$, 'pintu');

rollback;
