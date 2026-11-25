-- Uji paket 9b-2 (docs/rencana-9b-2.md): karyawan baru dan ubah gaji lewat web sebagai PENGAJUAN, disetujui bos atau
-- pembangun lewat bot dengan PIN (K1-K4). Data dasar sama dengan uji 330. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

-- Data dasar seperti uji 240/320.
insert into aturan.jendela_tap (menit_sebelum_masuk, menit_sesudah_pulang, jarak_minimal_menit, berlaku_dari) values (120, 360, 60, '2026-01-01');
insert into aturan.toleransi (telat_menit, pulang_cepat_menit, berlaku_dari) values (5, 0, '2026-01-01');
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select j, k, case when k = 1 then 15 else 20 end, date '2021-02-02' from unnest(array['kerja', 'libur_6_hari', 'libur_6_hari_terpendek', 'libur_5_hari']) j, generate_series(1, 12) k;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang'), ('MA2', 'Kantor');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('TL', 'Uji Lantai', 'mingguan', 1, 'MA1'), ('TM', 'Uji Kantor', 'mingguan', 1, 'MA2'), ('TR', 'Uji Rotasi', 'rotasi', 2, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select d, 0, h, case when h = 7 then null else 'P' end, '2026-01-01' from unnest(array['TL', 'TM']) d, generate_series(1, 7) h;
-- K1, K2, K3 aktif; K4 berhenti 10 Apr 2026; K5 rahasia; K6 pernah ganti data (baris tertutup, untuk uji penjaga).
insert into induk.karyawan (id, nama) values ('K1', 'Uji Satu'), ('K2', 'Uji Dua'), ('K3', 'Uji Tiga'), ('K4', 'Uji Berhenti'),
  ('K5', 'Uji Rahasia'), ('K6', 'Uji Enam');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, jabatan, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                    rekening_terenkripsi, bpjs_kesehatan, bpjs_ketenagakerjaan, gaji_rahasia)
select i, '2025-01-01', 'TL', 'Operator', 3500000 + n * 1000, 500000, 'TK/' || (n % 4), case when n = 2 then 'tunai' else 'transfer' end,
       case when n = 2 then null else convert_to('rek-' || i, 'UTF8') end, n % 2 = 0, n % 3 = 0, i = 'K5'
from unnest(array['K1', 'K2', 'K3', 'K4', 'K5']) with ordinality x(i, n);
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, berlaku_sampai, divisi, gaji_pokok, ptkp, cara_bayar)
values ('K6', '2025-01-01', '2025-06-01', 'TL', 3500000, 'TK/0', 'tunai');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar)
values ('K6', '2025-06-01', 'TL', 3600000, 'TK/0', 'tunai');
insert into induk.status_kerja (id_karyawan, jenis, tanggal)
select i, 'mulai', '2025-01-01' from unnest(array['K1', 'K2', 'K3', 'K4', 'K5', 'K6']) i;
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('K4', 'berhenti', '2026-04-10');
insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari)
select i, 0, '2025-01-01' from unnest(array['K1', 'K2', 'K3', 'K4', 'K5', 'K6']) i;
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari)
select 'MA1', n::text, 'K' || n, '2025-01-01' from generate_series(1, 6) n;
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA2', '92', 'K2', '2025-01-01');
-- Tiga periode: dirilis (Feb-Mar), terbuka (Mar-Apr), terbuka (Apr-Mei).
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-02-21', '2026-03-20', '2026-03-25'), ('2026-03-21', '2026-04-20', '2026-04-25'), ('2026-04-21', '2026-05-20', '2026-05-25');
create function pg_temp.jadi(p_awal date, p_status text) returns void language sql as $$
  select set_config('app.ubah_status_periode', 'ya', true);
  update fakta.periode set status = p_status where tanggal_awal = p_awal;
  select set_config('app.ubah_status_periode', '', true) $$;
select pg_temp.jadi('2026-02-21', 'dirilis');
insert into induk.pengguna (telegram_id, peran, email) values (8801, 'hrd', 'hrd-9b@contoh.test'), (8802, 'hrd', 'hrd2-9b@contoh.test'),
  (8803, 'pembangun', 'bangun-9b@contoh.test'), (8804, 'bos', null);
update induk.pengguna set pin_tersamar = extensions.crypt('123456', extensions.gen_salt('bf')) where telegram_id in (8801, 8803, 8804);
-- Tap 7-14 Apr (Senin-Selasa); 10 Apr (Jumat) tidak ada tap sama sekali (untuk absen manual).
create temp table tap_uji (n int, t text, s text);
insert into tap_uji select n, d || ' 06:55:00', 'Masuk' from generate_series(1, 5) n,
  unnest(array['2026-04-07', '2026-04-08', '2026-04-09', '2026-04-11', '2026-04-13', '2026-04-14']) d where not (n = 4 and d > '2026-04-10');
insert into tap_uji select n, d || ' 15:05:00', 'Keluar' from generate_series(1, 5) n,
  unnest(array['2026-04-07', '2026-04-08', '2026-04-09', '2026-04-11', '2026-04-13', '2026-04-14']) d where not (n = 4 and d > '2026-04-10');
select fakta.terima_kiriman('uji9b.csv', repeat('b', 64), 'MA1',
  (select jsonb_agg(jsonb_build_array(n::text, t, s, r) order by r) from (select n, t, s, row_number() over (order by t, n) as r from tap_uji) y),
  null, '2026-04-15 08:00+07');
-- Mesin MA2 juga mengirim (supaya divisi TM tidak "menunggu data"); tap K2 yang sama persis dihitung sekali.
select fakta.terima_kiriman('uji9b-ma2.csv', repeat('a', 64), 'MA2', '[["92", "2026-04-07 06:55:00", "Masuk", 1]]'::jsonb, null, '2026-04-15 08:00+07');
update fakta.antrean_kerja set status = 'selesai', selesai = now() where status = 'menunggu';
select count(hitung.baca_tap(id)), count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-03-21';

create temp table h (nama text primary key, isi jsonb);
create temp table v as select id as periode from fakta.periode where tanggal_awal = '2026-03-21';
create function pg_temp.k(x text) returns jsonb language sql as $$ select isi from h where nama = x $$;
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select repeat('c', 64), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 8801;
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select repeat('e', 64), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 8802;
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select repeat('f', 64), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 8803;
create function pg_temp.w(p_aksi text, p_perintah jsonb, p_sesi text default repeat('c', 64)) returns jsonb language sql as $$
  select api.web_hrd(jsonb_build_object('sidik_sesi', p_sesi, 'aksi', p_aksi, 'perintah', p_perintah)) $$;
-- Pratinjau lalu simpan (sesi yang sama).
create function pg_temp.simpan(p_perintah jsonb, p_sesi text default repeat('c', 64)) returns jsonb language plpgsql as $$
declare v jsonb := pg_temp.w('perintah_pratinjau', p_perintah, p_sesi);
begin
  if v ->> 'hasil' <> 'ok' then return v; end if;
  return pg_temp.w('perintah_simpan', jsonb_build_object('nomor', v #>> '{data,draf_id}'), p_sesi);
end $$;
create function pg_temp.batal(p_nomor bigint) returns jsonb language sql as $$
  select pg_temp.w('perintah_batal', jsonb_build_object('nomor', p_nomor)) $$;
-- Antrean dikerjakan seperti Edge Function (api.pintu_kerjakan sampai kosong).
create function pg_temp.kerja() returns integer language plpgsql as $$
declare r jsonb; n integer := 0;
begin
  loop
    r := api.pintu_kerjakan();
    exit when coalesce((r ->> 'kosong')::boolean, false) or n > 10;
    n := n + 1;
  end loop;
  return n;
end $$;
create function pg_temp.harian(p_id text) returns text language sql as $$
  select coalesce(string_agg(to_char(h.tanggal, 'MMDD') || ':' || h.status || ':' || h.asal || ':' || h.divisi, ',' order by h.tanggal), '-')
  from hitung.hasil_harian h, v
  where h.id_karyawan = p_id and h.tanggal between '2026-04-07' and '2026-04-14'
    and h.versi_id = (select x.id from hitung.versi_terakhir x where x.periode_id = v.periode and x.jenis = 'baca_tap') $$;
create function pg_temp.induk(p_id text) returns text language sql as $$
  select concat_ws('|',
    (select string_agg(to_jsonb(s)::text, ',' order by s.id) from induk.status_kerja s where s.id_karyawan = p_id),
    (select string_agg(to_jsonb(r)::text, ',' order by r.id) from induk.karyawan_riwayat r where r.id_karyawan = p_id),
    (select string_agg(to_jsonb(g)::text, ',' order by g.id) from induk.penugasan_regu g where g.id_karyawan = p_id),
    (select string_agg(to_jsonb(m)::text, ',' order by m.id) from induk.pemetaan_id_mesin m where m.id_karyawan = p_id)) $$;
create function pg_temp.potret() returns text language sql as $$
  select concat_ws('|', (select count(*) from fakta.perintah_hrd), (select count(*) from induk.status_kerja),
    (select count(*) from induk.karyawan_riwayat), (select count(*) from induk.penugasan_regu), (select count(*) from induk.pemetaan_id_mesin),
    (select count(*) from hitung.versi_hitung), (select count(*) from fakta.antrean_kerja), (select count(*) from jejak.perubahan)) $$;
create function pg_temp.satu(p_id text, p_hari text) returns text language sql as $$
  select coalesce((select x from unnest(string_to_array(pg_temp.harian(p_id), ',')) x where x like p_hari || ':%'), '-') $$;
create temp table awal as select pg_temp.harian('K1') k1, pg_temp.harian('K2') k2, pg_temp.harian('K3') k3,
  pg_temp.induk('K1') i1, pg_temp.induk('K3') i3, pg_temp.induk('K5') i5;


create function pg_temp.pu(p_id bigint) returns bigint language sql as $$ select id from induk.pengguna where telegram_id = p_id $$;
create function pg_temp.ajukan(p_perintah jsonb, p_sesi text default repeat('c', 64)) returns jsonb language plpgsql as $$
declare v jsonb := pg_temp.w('perintah_pratinjau', p_perintah, p_sesi);
begin
  if v ->> 'hasil' <> 'ok' then return v; end if;
  return pg_temp.w('perintah_simpan', jsonb_build_object('nomor', v #>> '{data,draf_id}'), p_sesi);
end $$;
create function pg_temp.putus(p_tg bigint, p_a jsonb, p_setuju boolean, p_pin text default '123456') returns jsonb language sql as $$
  select api.pintu_uang_putuskan(jsonb_build_object('telegram_id', p_tg, 'pengajuan_id', p_a #>> '{data,pengajuan_id}', 'setuju', p_setuju, 'pin', p_pin)) $$;
create function pg_temp.gaji(p_id text) returns text language sql as $$
  select coalesce((select g.gaji_bersih || '/' || (select r.nominal from hitung.rincian_gaji r where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan and r.komponen = 'gaji_pokok')
   from hitung.ringkasan_gaji g, v where g.id_karyawan = p_id
     and g.versi_id = (select x.id from hitung.versi_terakhir x where x.periode_id = v.periode and x.jenis = 'hitung_gaji')), '-') $$;
create temp table awal2 as select pg_temp.gaji('K1') g1, pg_temp.induk('K1') i1, pg_temp.potret() pot;

-- ===== Karyawan baru =====
insert into h values ('kb_umk', pg_temp.w('perintah_pratinjau', '{"jenis": "karyawan_baru", "id_karyawan": "K9", "nama": "Uji Baru", "mulai": "2026-04-13", "divisi": "TL", "id_mesin": "9", "gaji_pokok": "3.000.000", "tunjangan": "100000", "ptkp": "TK/0", "cara_bayar": "tunai", "alasan": "x"}'));
select uji.sama('9b-2 (K3): karyawan baru di bawah UMK ditolak', (pg_temp.k('kb_umk') ->> 'alasan') like '%di bawah UMK Rp3.402.892%', true);
insert into h values ('kb_id', pg_temp.w('perintah_pratinjau', '{"jenis": "karyawan_baru", "id_karyawan": "K1", "nama": "Ganda", "mulai": "2026-04-13", "divisi": "TL", "id_mesin": "9", "gaji_pokok": "4000000", "ptkp": "TK/0", "cara_bayar": "tunai", "alasan": "x"}'));
select uji.sama('9b-2: ID yang sudah dipakai ditolak', (pg_temp.k('kb_id') ->> 'alasan') like 'ID K1 sudah dipakai%', true);
insert into h values ('kb_mesin', pg_temp.w('perintah_pratinjau', '{"jenis": "karyawan_baru", "id_karyawan": "K9", "nama": "Uji Baru", "mulai": "2026-04-13", "divisi": "TL", "id_mesin": "1", "gaji_pokok": "4000000", "ptkp": "TK/0", "cara_bayar": "tunai", "alasan": "x"}'));
select uji.sama('9b-2 (U9): ID mesin yang dipakai orang lain ditolak', (pg_temp.k('kb_mesin') ->> 'alasan') like 'ID 1 di mesin MA1 sudah dipakai%', true);
insert into h values ('kb_rahasia_hrd', pg_temp.w('perintah_pratinjau', '{"jenis": "karyawan_baru", "id_karyawan": "K9", "nama": "Uji Baru", "mulai": "2026-04-13", "divisi": "TL", "id_mesin": "9", "gaji_pokok": "4000000", "ptkp": "TK/0", "cara_bayar": "tunai", "rahasia": "ya", "alasan": "x"}'));
select uji.sama('9b-2 (K4): HRD tidak bisa memasang tanda rahasia', (pg_temp.k('kb_rahasia_hrd') ->> 'alasan') like '%hanya bisa dipasang akun pembangun%', true);
create temp table p1 as select pg_temp.potret() as x;
insert into h values ('kb', pg_temp.ajukan('{"jenis": "karyawan_baru", "id_karyawan": "k9", "nama": "Uji Baru", "mulai": "2026-04-13", "divisi": "TL", "id_mesin": "9", "gaji_pokok": "4.000.000", "tunjangan": "0", "ptkp": "TK/1", "cara_bayar": "transfer", "alasan": "masuk kerja"}'));
select uji.sama('9b-2 (U1): simpan karyawan baru hanya membuat pengajuan; data induk dan hitungan tidak berubah',
  concat_ws('/', pg_temp.k('kb') ->> 'hasil', (select count(*) from induk.karyawan where id = 'K9'),
            pg_temp.potret() = (select x from p1)), 'diajukan/0/t');
select uji.sama('9b-2: penerima kabar pengajuan = akun bos dan pembangun aktif',
  (select string_agg(x, ',' order by x) from jsonb_array_elements_text(pg_temp.k('kb') #> '{data,penerima}') x), '8803,8804');
select uji.sama('9b-2 (U2): HRD tidak bisa menyetujui', pg_temp.putus(8801, pg_temp.k('kb'), true) ->> 'hasil', 'bukan_bos');
select uji.sama('9b-2: PIN salah ditolak, pengajuan tetap menunggu',
  concat_ws('/', pg_temp.putus(8804, pg_temp.k('kb'), true, '000000') ->> 'hasil', fakta.status_pengajuan((pg_temp.k('kb') #>> '{data,pengajuan_id}')::bigint)),
  'pin_salah/menunggu');
insert into h values ('kb_ok', pg_temp.putus(8804, pg_temp.k('kb'), true));
select pg_temp.kerja();
select uji.sama('9b-2: bos menyetujui dengan PIN -> karyawan baru masuk data induk dan dihitung mulai 13 Apr',
  concat_ws('/', pg_temp.k('kb_ok') ->> 'hasil', (pg_temp.k('kb_ok') ->> 'sendiri'), pg_temp.k('kb_ok') ->> 'pengaju_telegram',
            (select nama from induk.karyawan where id = 'K9'), pg_temp.harian('K9')),
  'disetujui/false/8801/Uji Baru/0413:alpha:mesin:TL,0414:alpha:mesin:TL');
select uji.sama('9b-2 (K14/B3): masuk tengah periode -> gaji pokok sebanding hari aktif (lebih kecil dari 4.000.000)',
  (select (split_part(pg_temp.gaji('K9'), '/', 2))::bigint between 1 and 3999999), true);
select uji.sama('9b-2: keputusan kedua untuk pengajuan yang sama ditolak', pg_temp.putus(8803, pg_temp.k('kb'), false) ->> 'hasil', 'tidak_berlaku');
select uji.harus_ditolak('9b-2: pengajuan dan keputusan hanya bertambah', $q$delete from fakta.keputusan_uang$q$);
insert into h values ('kb_batal', pg_temp.batal((pg_temp.k('kb_ok') ->> 'perintah_id')::bigint));
select pg_temp.kerja();
select uji.sama('9b-2: batal karyawan baru -> tidak aktif lagi, tidak dihitung; ID tetap terpakai',
  concat_ws('/', pg_temp.k('kb_batal') ->> 'hasil', pg_temp.harian('K9'), pg_temp.gaji('K9'), (select count(*) from induk.karyawan where id = 'K9'),
            (select count(*) from induk.karyawan_riwayat where id_karyawan = 'K9')), 'dibatalkan/-/-/1/0');
insert into h values ('kb_ulang', pg_temp.w('perintah_pratinjau', '{"jenis": "karyawan_baru", "id_karyawan": "K9", "nama": "Lain", "mulai": "2026-04-13", "divisi": "TL", "id_mesin": "9", "gaji_pokok": "4000000", "ptkp": "TK/0", "cara_bayar": "tunai", "alasan": "x"}'));
select uji.sama('9b-2: ID karyawan yang dibatalkan tidak bisa dipakai orang lain', (pg_temp.k('kb_ulang') ->> 'alasan') like 'ID K9 sudah dipakai%', true);

-- ===== Ubah gaji =====
insert into h values ('ug_sama', pg_temp.w('perintah_pratinjau', '{"jenis": "ubah_gaji", "id_karyawan": "K1", "mulai": "2026-04-13", "alasan": "x"}'));
select uji.sama('9b-2: ubah gaji tanpa perubahan ditolak', (pg_temp.k('ug_sama') ->> 'alasan') like 'Tidak ada yang berubah%', true);
insert into h values ('ug_nol', pg_temp.w('perintah_pratinjau', '{"jenis": "ubah_gaji", "id_karyawan": "K1", "mulai": "2026-04-13", "gaji_pokok": "35010000", "alasan": "x"}'));
select uji.sama('9b-2 (U7): kenaikan lebih dari 50% diberi peringatan', (pg_temp.k('ug_nol') #>> '{data,catatan,0}') like 'PERHATIAN: gaji naik%Periksa jumlah nolnya.', true);
insert into h values ('ug_turun', pg_temp.w('perintah_pratinjau', '{"jenis": "ubah_gaji", "id_karyawan": "K1", "mulai": "2026-04-13", "gaji_pokok": "3000000", "tunjangan": "300000", "alasan": "x"}'));
select uji.sama('9b-2 (K3): turun ke bawah UMK pada masa kerja > 1 tahun hanya diperingatkan',
  concat_ws('/', pg_temp.k('ug_turun') ->> 'hasil', (pg_temp.k('ug_turun') #>> '{data,catatan,0}') like 'PERHATIAN: gaji pokok + tunjangan di bawah UMK%',
            (pg_temp.k('ug_turun') #>> '{data,catatan,1}') like 'PERHATIAN: gaji TURUN%'), 'ok/t/t');
insert into h values ('ug_rahasia', pg_temp.w('perintah_pratinjau', '{"jenis": "ubah_gaji", "id_karyawan": "K5", "mulai": "2026-04-13", "gaji_pokok": "6000000", "alasan": "x"}'));
select uji.sama('9b-2 (K4/F15): HRD tidak bisa mengubah gaji orang rahasia', (pg_temp.k('ug_rahasia') ->> 'alasan') like 'Gaji orang ini rahasia%', true);
insert into h values ('ug_cabut', pg_temp.w('perintah_pratinjau', '{"jenis": "ubah_gaji", "id_karyawan": "K1", "mulai": "2026-04-13", "rahasia": "ya", "alasan": "x"}'));
select uji.sama('9b-2 (K4/F15c): HRD tidak bisa memasang tanda rahasia lewat ubah gaji', (pg_temp.k('ug_cabut') ->> 'alasan') like 'Tanda gaji rahasia hanya bisa diubah akun pembangun%', true);
insert into h values ('ug', pg_temp.ajukan('{"jenis": "ubah_gaji", "id_karyawan": "K1", "mulai": "2026-04-13", "gaji_pokok": "4.001.000", "alasan": "kenaikan"}'));
select uji.sama('9b-2: ringkas pengajuan ubah gaji menulis angka lama -> baru',
  pg_temp.k('ug') #>> '{data,ringkas}', 'Ubah gaji K1 Uji Satu mulai 13 Apr 2026: gaji pokok Rp3.501.000 → Rp4.001.000');
insert into h values ('ug_tolak', pg_temp.putus(8804, pg_temp.k('ug'), false));
select uji.sama('9b-2: bos menolak -> tidak ada yang berubah',
  concat_ws('/', pg_temp.k('ug_tolak') ->> 'hasil', pg_temp.induk('K1') = (select i1 from awal2)), 'ditolak/t');
insert into h values ('ug2', pg_temp.ajukan('{"jenis": "ubah_gaji", "id_karyawan": "K1", "mulai": "2026-04-13", "gaji_pokok": "4.001.000", "alasan": "kenaikan"}'));
-- Data berubah sesudah pengajuan (mutasi lewat web) -> persetujuan tidak berlaku (U3).
savepoint u3;
select pg_temp.simpan('{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-14", "jabatan": "Kepala", "alasan": "x"}');
select uji.sama('9b-2 (U3): data berubah sejak pengajuan -> persetujuan tidak berlaku',
  (pg_temp.putus(8804, pg_temp.k('ug2'), true) ->> 'hasil'), 'tidak_berlaku');
rollback to savepoint u3;
insert into h values ('ug2_ok', pg_temp.putus(8803, pg_temp.k('ug2'), true));
select pg_temp.kerja();
select uji.sama('9b-2: pembangun menyetujui pengajuan HRD; riwayat ditutup 13 Apr, gaji baru berlaku 13 Apr, isian lain tetap',
  (select string_agg(gaji_pokok || ':' || berlaku_dari || ':' || coalesce(berlaku_sampai::text, '-') || ':' || cara_bayar || ':' || ptkp
                     || ':' || coalesce(encode(rekening_terenkripsi, 'escape'), '-'), ',' order by id) from induk.karyawan_riwayat where id_karyawan = 'K1'),
  '3501000:2025-01-01:2026-04-13:transfer:TK/1:rek-K1,4001000:2026-04-13:-:transfer:TK/1:rek-K1');
select uji.sama('9b-2 (B3): ubah gaji di tengah periode -> gaji pokok periode naik, tetapi kurang dari 4.001.000',
  (select (split_part(pg_temp.gaji('K1'), '/', 2))::bigint > (split_part((select g1 from awal2), '/', 2))::bigint
          and (split_part(pg_temp.gaji('K1'), '/', 2))::bigint < 4001000), true);
insert into h values ('ug2_batal', pg_temp.batal((pg_temp.k('ug2_ok') ->> 'perintah_id')::bigint));
select pg_temp.kerja();
select uji.sama('9b-2: batal ubah gaji -> riwayat dan gaji K1 persis semula',
  concat_ws('/', pg_temp.k('ug2_batal') ->> 'hasil', pg_temp.induk('K1') = (select i1 from awal2), pg_temp.gaji('K1') = (select g1 from awal2)),
  'dibatalkan/t/t');

-- ===== Pembangun dan orang rahasia (K2, K4) =====
insert into h values ('ug_r', pg_temp.ajukan('{"jenis": "ubah_gaji", "id_karyawan": "K5", "mulai": "2026-04-13", "gaji_pokok": "6000000", "alasan": "naik"}', repeat('f', 64)));
insert into h values ('ug_r_ok', pg_temp.putus(8803, pg_temp.k('ug_r'), true));
select uji.sama('9b-2 (K2): pembangun menyetujui pengajuannya sendiri, dicatat "sendiri"',
  concat_ws('/', pg_temp.k('ug_r_ok') ->> 'hasil', pg_temp.k('ug_r_ok') ->> 'sendiri',
            (select sendiri::text from fakta.keputusan_uang where pengajuan_id = (pg_temp.k('ug_r') #>> '{data,pengajuan_id}')::bigint)), 'disetujui/true/true');
insert into h values ('daftar_hrd', pg_temp.w('perintah_daftar', null));
insert into h values ('daftar_bangun', pg_temp.w('perintah_daftar', null, repeat('f', 64)));
select uji.sama('9b-2 (U4/F15): daftar untuk HRD tanpa angka orang rahasia; pembangun melihat angka',
  concat_ws(' | ', (select x ->> 'ringkas' from jsonb_array_elements(pg_temp.k('daftar_hrd') #> '{data,pengajuan}') x where x ->> 'id' = pg_temp.k('ug_r') #>> '{data,pengajuan_id}'),
            (select x ->> 'ringkas' from jsonb_array_elements(pg_temp.k('daftar_bangun') #> '{data,pengajuan}') x where x ->> 'id' = pg_temp.k('ug_r') #>> '{data,pengajuan_id}'),
            (select x ->> 'ringkas' from jsonb_array_elements(pg_temp.k('daftar_hrd') #> '{data,perintah}') x where x ->> 'id' = pg_temp.k('ug_r_ok') ->> 'perintah_id')),
  'Ubah gaji K5 Uji Rahasia mulai 13 Apr 2026 (gaji rahasia) | Ubah gaji K5 Uji Rahasia mulai 13 Apr 2026: gaji pokok Rp3.505.000 → Rp6.000.000 | Ubah gaji K5 Uji Rahasia mulai 13 Apr 2026 (gaji rahasia)');
insert into h values ('ug_r_batal_hrd', pg_temp.batal((pg_temp.k('ug_r_ok') ->> 'perintah_id')::bigint));
select uji.sama('9b-2 (K4): HRD tidak bisa membatalkan perintah gaji rahasia', (pg_temp.k('ug_r_batal_hrd') ->> 'alasan') like '%hanya akun pembangun%', true);

-- ===== Tarik, hangus, PIN lewat tombol =====
insert into h values ('tarik', pg_temp.ajukan('{"jenis": "ubah_gaji", "id_karyawan": "K2", "mulai": "2026-04-13", "tunjangan": "600000", "alasan": "x"}'));
insert into h values ('tarik_lain', pg_temp.w('pengajuan_tarik', jsonb_build_object('nomor', pg_temp.k('tarik') #>> '{data,pengajuan_id}'), repeat('e', 64)));
insert into h values ('tarik_ok', pg_temp.w('pengajuan_tarik', jsonb_build_object('nomor', pg_temp.k('tarik') #>> '{data,pengajuan_id}')));
select uji.sama('9b-2: pengajuan hanya bisa ditarik pengajunya; sesudah ditarik tidak bisa disetujui',
  concat_ws('/', pg_temp.k('tarik_lain') ->> 'hasil', pg_temp.k('tarik_ok') ->> 'hasil', pg_temp.putus(8804, pg_temp.k('tarik'), true) ->> 'hasil'),
  'ditolak/ditarik/tidak_berlaku');
insert into h values ('lama', pg_temp.ajukan('{"jenis": "ubah_gaji", "id_karyawan": "K2", "mulai": "2026-04-13", "tunjangan": "700000", "alasan": "x"}'));
select set_config('app.ubah_status_periode', 'ya', true);
create function pg_temp.lewat() returns void language plpgsql as $$ begin
  alter table fakta.pengajuan_uang disable trigger tolak_ubah;
  update fakta.pengajuan_uang set hangus_pada = now() - interval '1 second' where id = (pg_temp.k('lama') #>> '{data,pengajuan_id}')::bigint;
  alter table fakta.pengajuan_uang enable trigger tolak_ubah; end $$;
select pg_temp.lewat();
select uji.sama('9b-2 (U11): pengajuan lewat 7 hari hangus dan tidak bisa disetujui',
  concat_ws('/', fakta.status_pengajuan((pg_temp.k('lama') #>> '{data,pengajuan_id}')::bigint), pg_temp.putus(8804, pg_temp.k('lama'), true) ->> 'hasil'),
  'hangus/tidak_berlaku');
insert into h values ('tombol', pg_temp.ajukan('{"jenis": "ubah_gaji", "id_karyawan": "K2", "mulai": "2026-04-13", "tunjangan": "650000", "alasan": "x"}'));
grant all on h to pintu;
grant execute on function pg_temp.k(text) to pintu;
set local role pintu;
insert into h select 'minta', api.pintu_uang_minta_pin(jsonb_build_object('telegram_id', 8804, 'pengajuan_id', pg_temp.k('tombol') #>> '{data,pengajuan_id}', 'setuju', true));
insert into h select 'ambil', api.pintu_ambil_pin('{"telegram_id": 8804}');
insert into h select 'minta_hrd', api.pintu_uang_minta_pin(jsonb_build_object('telegram_id', 8801, 'pengajuan_id', pg_temp.k('tombol') #>> '{data,pengajuan_id}', 'setuju', true));
insert into h select 'daftar_bot', api.pintu_uang_daftar('{"telegram_id": 8804}');
insert into h select 'rilis_pin', api.pintu_minta_pin('{"telegram_id": 8803, "aksi": "lengkap", "periode_id": 0}');
reset role;
select uji.sama('9b-2: tombol Setujui -> menunggu PIN pengajuan itu; HRD ditolak; /pengajuan berisi yang menunggu',
  concat_ws('/', pg_temp.k('minta') ->> 'hasil', pg_temp.k('ambil') ->> 'aksi', (pg_temp.k('ambil') ->> 'pengajuan_uang') = (pg_temp.k('tombol') #>> '{data,pengajuan_id}'),
            pg_temp.k('minta_hrd') ->> 'hasil',
            (select count(*) from jsonb_array_elements(pg_temp.k('daftar_bot') -> 'pengajuan') x where x ->> 'id' = pg_temp.k('tombol') #>> '{data,pengajuan_id}')),
  'menunggu/uang_setuju/t/bukan_bos/1');
-- Tunggu PIN pengajuan lalu tunggu PIN rilis/lengkap: sasaran lama dikosongkan (tidak melanggar batasan).
select api.pintu_uang_minta_pin(jsonb_build_object('telegram_id', 8803, 'pengajuan_id', pg_temp.k('tombol') #>> '{data,pengajuan_id}', 'setuju', false));
select uji.sama('9b-2: tunggu PIN berganti dari pengajuan ke periode tanpa galat',
  api.pintu_minta_pin(jsonb_build_object('telegram_id', 8803, 'aksi', 'lengkap', 'periode_id', (select periode from v))) ->> 'hasil', 'menunggu');
select uji.harus_ditolak('9b-2: pintu tidak bisa memanggil fungsi terapkan langsung', $q$select fakta.web_uang_terapkan(null::fakta.pengajuan_uang)$q$, 'pintu');
rollback;
