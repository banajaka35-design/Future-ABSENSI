-- Uji mesin baca tap (Tahap 3) terhadap kasus jebakan v1.1 (docs/kasus-jebakan.md) bagian A, B, C, F.
-- Setiap kasus memakai orang sendiri yang hanya aktif di tanggal kasusnya, supaya kasus tidak saling memengaruhi.
-- Seluruh uji berjalan dalam satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

-- ---------------------------------------------------------------------------
-- Pembantu (hanya hidup di transaksi ini)
-- ---------------------------------------------------------------------------

-- Divisi dengan jadwal mingguan tetap: p_harian berisi 7 kode (Senin..Minggu), null = libur.
create function pg_temp.divisi(p_kode text, p_mesin text, p_harian text[]) returns void language sql as $$
  insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values (p_kode, 'Uji ' || p_kode, 'mingguan', 1, p_mesin);
  insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
  select p_kode, 0, h, p_harian[h], '2026-01-01' from generate_series(1, 7) h;
$$;

-- Karyawan aktif dari p_mulai sampai p_berhenti (termasuk), dengan satu ID mesin.
create function pg_temp.orang(p_id text, p_divisi text, p_mulai date, p_berhenti date default null,
                              p_mesin text default 'MA1', p_wajib_tap boolean default true) returns void language sql as $$
  insert into induk.karyawan (id, nama) values (p_id, 'Uji ' || p_id);
  insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar, wajib_tap)
  values (p_id, '2025-01-01', p_divisi, 3500000, 500000, 'TK/0', 'tunai', p_wajib_tap);
  insert into induk.status_kerja (id_karyawan, jenis, tanggal) values (p_id, 'mulai', p_mulai);
  insert into induk.status_kerja (id_karyawan, jenis, tanggal) select p_id, 'berhenti', p_berhenti where p_berhenti is not null;
  insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari) values (p_id, 0, '2025-01-01');
  insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values (p_mesin, p_id, p_id, '2025-01-01');
$$;

create sequence pg_temp.nomor_file;
-- Kiriman file berisi tap [id_mesin, jam_lokal, status]. Sidik dibuat unik per kiriman.
create function pg_temp.kirim(p_mesin text, p_tap jsonb, p_diterima timestamptz default '2026-05-01 00:00+07') returns jsonb
language sql as $$
  select fakta.terima_kiriman('uji.csv', encode(sha256(convert_to('uji' || nextval('pg_temp.nomor_file'), 'UTF8')), 'hex'), p_mesin,
    (select jsonb_agg(jsonb_build_array(e ->> 0, e ->> 1, e ->> 2, n) order by n) from jsonb_array_elements(p_tap) with ordinality x(e, n)),
    null, p_diterima)
$$;

-- Hasil satu orang satu hari dari versi terakhir periode yang memuat tanggal itu.
create function pg_temp.h(p_id text, p_tanggal date) returns hitung.hasil_harian language sql as $$
  select h.* from hitung.hasil_harian h
  join hitung.versi_terakhir v on v.id = h.versi_id
  join fakta.periode p on p.id = v.periode_id and p_tanggal between p.tanggal_awal and p.tanggal_akhir
  where h.id_karyawan = p_id and h.tanggal = p_tanggal
$$;
create function pg_temp.jam(p timestamptz) returns text language sql as $$
  select to_char(p at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS')
$$;
create function pg_temp.anomali(p_jenis text, p_kunci text) returns bigint language sql as $$
  select count(*) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id
  where a.jenis = p_jenis and p_kunci in (coalesce(a.id_karyawan, ''), coalesce(a.divisi, ''), coalesce(a.mesin, ''), coalesce(a.nilai, ''))
$$;
-- Tap untuk mesin MA1 dikumpulkan lalu dikirim sebagai satu file, seperti ekspor mesin sungguhan
-- (kalau dipecah, tiap potongan wajar dianggap file terpotong, kasus F02).
create temp table uji_tap (isi jsonb);
create function pg_temp.hitung_semua() returns void language sql as $$
  select count(hitung.baca_tap(id)) from fakta.periode;
$$;

-- ---------------------------------------------------------------------------
-- Data dasar uji (aturan uji v0 di kasus jebakan)
-- ---------------------------------------------------------------------------

insert into induk.mesin (kode, nama) values
  ('MA1', 'Gerbang'), ('MA2', 'Kantor'), ('MB', 'Batas periode'), ('MT', 'File terpotong'), ('ML', 'Lubang'),
  ('MK', 'Jam melenceng terkoreksi'), ('MJ', 'Jam melenceng'), ('MM', 'Memori penuh');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang) values
  ('P', '07:00', '15:00'), ('S', '15:00', '23:00'), ('M', '23:00', '07:00'),
  ('KA', '07:30', '16:00'), ('KJ', '07:30', '16:30'), ('KR', '08:00', '15:00'), ('KRJ', '08:00', '15:30');
insert into aturan.jendela_tap (menit_sebelum_masuk, menit_sesudah_pulang, jarak_minimal_menit, berlaku_dari) values (120, 360, 60, '2026-01-01');
insert into aturan.toleransi (telat_menit, pulang_cepat_menit, berlaku_dari) values (5, 0, '2026-01-01');
insert into induk.kalender (tanggal, jenis, keterangan) values
  ('2026-02-16', 'cuti_bersama', 'Cuti bersama Imlek'), ('2026-02-17', 'libur_nasional', 'Imlek'),
  ('2026-03-21', 'libur_nasional', 'Idul Fitri');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-01-21', '2026-02-20', '2026-02-25'), ('2026-02-21', '2026-03-20', '2026-03-25'), ('2026-03-21', '2026-04-20', '2026-04-25');

select pg_temp.divisi('TP', 'MA1', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.divisi('TS', 'MA1', array['S', 'S', 'S', 'S', 'S', 'S', 'S']);
select pg_temp.divisi('TL', 'MA1', array['P', 'P', 'P', 'P', 'P', 'P', null]);   -- Minggu libur rutin
select pg_temp.divisi('T7', 'MA1', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values ('operasi_7_hari', 'T7', 'ya', '2026-01-01');
-- Kantor pola file asli: Senin-Kamis 07.30-16.00, Jumat 07.30-16.30; mulai 19 Feb (Ramadan) 08.00-15.00, Jumat 08.00-15.30.
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values ('KT', 'Kantor uji', 'mingguan', 1, 'MA2');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari, berlaku_sampai)
select 'KT', 0, h, case when h <= 4 then 'KA' when h = 5 then 'KJ' end, '2026-01-01', '2026-02-19' from generate_series(1, 7) h;
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select 'KT', 0, h, case when h <= 4 then 'KR' when h = 5 then 'KRJ' end, '2026-02-19' from generate_series(1, 7) h;

-- ---------------------------------------------------------------------------
-- Kasus satu hari, shift Pagi 07.00-15.00, Selasa 3 Maret 2026
-- ---------------------------------------------------------------------------
select pg_temp.orang(id, 'TP', '2026-03-03', '2026-03-03')
from unnest(array['A01', 'A02', 'A03', 'A06', 'A08', 'B03', 'B05', 'B06', 'B07', 'B08', 'B09', 'B13', 'B15']) id;
select pg_temp.orang('B04', 'TP', '2026-03-03', '2026-03-03');
select pg_temp.orang('B02', 'TS', '2026-03-03', '2026-03-03');
insert into uji_tap select $$[
  ["A01", "2026-03-03 07:05:00", "Keluar"], ["A01", "2026-03-03 15:02:00", "Keluar"],
  ["A02", "2026-03-03 07:00:00", "Masuk"], ["A02", "2026-03-03 15:01:34", "Keluar"], ["A02", "2026-03-03 15:04:42", "Keluar"],
  ["A03", "2026-03-03 07:26:46", "Keluar"], ["A03", "2026-03-03 07:31:30", "Masuk"], ["A03", "2026-03-03 15:05:11", "Keluar"],
  ["A06", "2026-03-03 06:50:00", "Masuk"], ["A06", "2026-03-03 06:50:00", "Masuk"], ["A06", "2026-03-03 15:03:00", "Keluar"],
  ["A08", "2026-03-03 07:26:00", "Masuk"], ["A08", "2026-03-03 07:26:44", "Masuk"], ["A08", "2026-03-03 15:10:00", "Keluar"],
  ["B02", "2026-03-03 14:55:00", "Masuk"], ["B02", "2026-03-03 23:10:00", "Keluar"],
  ["B03", "2026-03-03 09:40:00", "Masuk"], ["B03", "2026-03-03 15:02:00", "Keluar"],
  ["B04", "2026-03-03 14:57:00", "Masuk"], ["B04", "2026-03-03 23:01:00", "Keluar"],
  ["B05", "2026-03-03 05:30:00", "Masuk"], ["B05", "2026-03-03 15:01:00", "Keluar"],
  ["B06", "2026-03-03 06:58:00", "Masuk"],
  ["B07", "2026-03-03 15:03:00", "Keluar"],
  ["B08", "2026-03-03 11:00:00", "Masuk"],
  ["B09", "2026-03-03 02:00:00", "Masuk"],
  ["B13", "2026-03-03 06:55:00", "Masuk"], ["B13", "2026-03-03 13:30:00", "Keluar"],
  ["B15", "2026-03-03 07:00:00", "Masuk"], ["B15", "2026-03-03 07:40:00", "Keluar"],
  ["99999", "2026-03-03 08:00:00", "Masuk"]
]$$::jsonb;
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, nilai) values ('chat', 'tukar_shift', 'B04', '2026-03-03', 'S');

-- Shift Malam 10 Maret (B01) dan jendela bertumpuk: Malam Senin 9 Maret lalu Pagi Selasa 10 Maret (B10).
select pg_temp.orang('B01', 'TP', '2026-03-10', '2026-03-10');
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, nilai) values ('chat', 'tukar_shift', 'B01', '2026-03-10', 'M');
select pg_temp.orang('B10', 'TP', '2026-03-09', '2026-03-10');
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, nilai) values ('chat', 'tukar_shift', 'B10', '2026-03-09', 'M');
insert into uji_tap select $$[
  ["B01", "2026-03-10 22:58:00", "Masuk"], ["B01", "2026-03-11 07:04:00", "Keluar"],
  ["B10", "2026-03-09 22:55:00", "Masuk"], ["B10", "2026-03-10 07:01:00", "Keluar"],
  ["B10", "2026-03-10 07:04:00", "Masuk"], ["B10", "2026-03-10 15:02:00", "Keluar"]
]$$::jsonb;

-- Kantor (KT, mesin MA2): pola file asli
select pg_temp.orang('B14', 'KT', '2026-02-18', '2026-02-18', 'MA2');
select pg_temp.orang('C07', 'KT', '2026-02-23', '2026-02-23', 'MA2');
select pg_temp.orang('C08', 'KT', '2026-02-12', '2026-02-12', 'MA2');
select pg_temp.orang('C09', 'KT', '2026-02-09', '2026-02-13', 'MA2');
select pg_temp.kirim('MA2', $$[
  ["B14", "2026-02-18 07:27:00", "Masuk"], ["B14", "2026-02-18 14:32:00", "Masuk"], ["B14", "2026-02-18 16:04:00", "Keluar"],
  ["C07", "2026-02-23 07:50:00", "Masuk"], ["C07", "2026-02-23 15:02:00", "Keluar"],
  ["C08", "2026-02-12 07:25:00", "Masuk"], ["C08", "2026-02-12 15:02:00", "Keluar"],
  ["C09", "2026-02-09 07:25:00", "Masuk"], ["C09", "2026-02-09 16:21:00", "Keluar"],
  ["C09", "2026-02-10 07:25:00", "Masuk"], ["C09", "2026-02-10 16:05:00", "Keluar"],
  ["C09", "2026-02-11 07:25:00", "Masuk"], ["C09", "2026-02-11 16:05:00", "Keluar"],
  ["C09", "2026-02-12 07:25:00", "Masuk"], ["C09", "2026-02-12 16:05:00", "Keluar"],
  ["C09", "2026-02-13 07:25:00", "Masuk"], ["C09", "2026-02-13 16:21:00", "Keluar"]
]$$);

-- Kalender dan hari khusus
select pg_temp.orang('C01', 'TL', '2026-02-16', '2026-02-17');      -- 16 cuti bersama, 17 Imlek, tanpa tap
select pg_temp.orang('C03', 'TL', '2026-03-08', '2026-03-08');      -- Minggu: libur rutin, tanpa tap
select pg_temp.orang('C04', 'TL', '2026-03-15', '2026-03-15');      -- Minggu: masuk 8 jam di hari libur rutin
select pg_temp.orang('C05', 'T7', '2026-03-21', '2026-03-21');      -- operasi 7 hari, masuk Pagi di Idul Fitri
select pg_temp.orang('C10', 'TP', '2026-02-10', '2026-02-11');      -- mulai 10 Feb
select pg_temp.orang('C11', 'TP', '2026-02-17', '2026-02-18');      -- berhenti 18 Feb, ada tap 19 Feb
select pg_temp.orang('C12', 'TP', '2026-02-19', '2026-02-19');      -- tanpa tap, lalu "sakit tgl 19"
select pg_temp.orang('C13', 'TP', '2026-03-24', '2026-03-26');      -- alpha 3 hari berturut-turut
select pg_temp.orang('F14', 'TP', '2026-03-24', '2026-03-26', 'MA1', false);   -- tidak wajib tap
select pg_temp.orang('F16', 'TP', '2026-03-27', '2026-03-27');      -- alpha, lalu "tambah libur tgl 27"
insert into uji_tap select $$[
  ["C04", "2026-03-15 07:00:00", "Masuk"], ["C04", "2026-03-15 15:00:00", "Keluar"],
  ["C05", "2026-03-21 06:55:00", "Masuk"], ["C05", "2026-03-21 15:01:00", "Keluar"],
  ["C10", "2026-02-10 06:55:00", "Masuk"], ["C10", "2026-02-10 15:01:00", "Keluar"],
  ["C10", "2026-02-11 06:55:00", "Masuk"], ["C10", "2026-02-11 15:01:00", "Keluar"],
  ["C11", "2026-02-18 06:55:00", "Masuk"], ["C11", "2026-02-18 15:01:00", "Keluar"],
  ["C11", "2026-02-19 06:55:00", "Masuk"], ["C11", "2026-02-19 15:01:00", "Keluar"]
]$$::jsonb;

-- Hari tanpa tap massal: divisi 4 orang semuanya tanpa tap (C06), divisi 2 orang (C14),
-- divisi 3 orang dengan absen manual dari HRD (F08).
select pg_temp.divisi('TM6', 'MA1', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.divisi('TM2', 'MA1', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.divisi('TM8', 'MA1', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.orang('C06' || n, 'TM6', '2026-02-20', '2026-02-20') from generate_series(1, 4) n;
select pg_temp.orang('C14' || n, 'TM2', '2026-02-20', '2026-02-20') from generate_series(1, 2) n;
select pg_temp.orang('F08' || n, 'TM8', '2026-02-20', '2026-02-20') from generate_series(1, 3) n;
insert into fakta.perintah_hrd (asal, jenis, divisi, tanggal_mulai, alasan) values ('chat', 'absen_manual', 'TM8', '2026-02-20', 'mesin mati');

-- Mesin dan file (F02-F07, F10)
-- F02: mesin MT, 8 karyawan terdaftar, file 2 hari hanya memuat 3 orang.
select pg_temp.divisi('TT', 'MT', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.orang('F02' || n, 'TT', '2026-03-03', '2026-03-04', 'MT') from generate_series(1, 8) n;
select pg_temp.kirim('MT', (
  select jsonb_agg(jsonb_build_array('F02' || n, d || ' ' || j, null))
  from generate_series(1, 3) n, unnest(array['2026-03-03', '2026-03-04']) d, unnest(array['06:58:00', '15:02:00']) j));
-- F03: mesin MM, tap terakhir 12 hari sebelum dikirim.
select pg_temp.divisi('TF3', 'MM', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.orang('F03', 'TF3', '2026-03-02', '2026-03-02', 'MM');
select pg_temp.kirim('MM', $$[["F03", "2026-03-02 06:58:00", "Masuk"], ["F03", "2026-03-02 15:02:00", "Keluar"]]$$, '2026-03-14 10:00+07');
-- F04: mesin MK lebih cepat 4 menit sejak 1 Maret, koreksi tercatat.
select pg_temp.divisi('TK', 'MK', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.orang('F04', 'TK', '2026-03-05', '2026-03-05', 'MK');
insert into induk.koreksi_jam_mesin (mesin, selisih_menit, berlaku_dari) values ('MK', 4, '2026-03-01');
select pg_temp.kirim('MK', $$[["F04", "2026-03-05 07:08:00", "Masuk"], ["F04", "2026-03-05 15:05:00", "Keluar"]]$$);
-- F05: mesin MJ, 6 dari 8 orang telat 6-8 menit di hari yang sama.
select pg_temp.divisi('TJ', 'MJ', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.orang('F05' || n, 'TJ', '2026-03-06', '2026-03-06', 'MJ') from generate_series(1, 8) n;
select pg_temp.kirim('MJ', (
  select jsonb_agg(x) from (
    select jsonb_build_array('F05' || n, '2026-03-06 ' || case when n <= 6 then '07:0' || (5 + (n % 3) + 1) || ':00' else '06:50:00' end, 'Masuk') x
    from generate_series(1, 8) n
    union all
    select jsonb_build_array('F05' || n, '2026-03-06 15:03:00', 'Keluar') from generate_series(1, 8) n) t));
-- F06: ID mesin 0012 baru dipetakan ke F06 mulai 1 Maret; tap ID 0012 tanggal 27 Feb.
select pg_temp.orang('F06', 'TP', '2026-02-27', '2026-02-27');
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA1', '0012', 'F06', '2026-03-01');
-- F07: dua ID mesin untuk satu orang.
select pg_temp.orang('F07', 'TP', '2026-03-12', '2026-03-12');
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA1', '90007', 'F07', '2026-03-01');
insert into uji_tap select $$[["0012", "2026-02-27 07:00:00", "Masuk"], ["0012", "2026-02-27 15:00:00", "Keluar"]]$$::jsonb;
-- Kiriman F07 terpisah: dipakai juga untuk uji pembatalan kiriman (U4) di akhir.
select pg_temp.kirim('MA1', $$[["F07", "2026-03-12 06:57:00", "Masuk"], ["90007", "2026-03-12 15:04:00", "Keluar"]]$$);
-- F10: mesin ML, kiriman 2-4 Maret dan 11-13 Maret; 5-10 Maret tidak pernah masuk.
select pg_temp.divisi('TLB', 'ML', array['P', 'P', 'P', 'P', 'P', 'P', 'P']);
select pg_temp.orang('F10', 'TLB', '2026-03-02', '2026-03-13', 'ML');
select pg_temp.kirim('ML', (select jsonb_agg(jsonb_build_array('F10', d::date || ' ' || j, null))
                            from generate_series('2026-03-02'::date, '2026-03-04', '1 day') d, unnest(array['06:58:00', '15:02:00']) j),
                     '2026-03-05 00:00+07');
select pg_temp.kirim('ML', (select jsonb_agg(jsonb_build_array('F10', d::date || ' ' || j, null))
                            from generate_series('2026-03-11'::date, '2026-03-13', '1 day') d, unnest(array['06:58:00', '15:02:00']) j),
                     '2026-03-14 00:00+07');
-- F11: terjadwal Pagi 16-20 Maret di divisi rotasi Pagi-Siang, tapnya cocok Siang.
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values ('TR', 'Rotasi uji', 'rotasi', 1, 'MA1');
insert into induk.pola_rotasi (divisi, siklus, jangkar, berlaku_dari)
values ('TR', array['P', 'P', 'P', 'P', 'P', 'S', 'S', 'S', 'S', 'S'], '2026-03-16', '2026-01-01');
select pg_temp.orang('F11', 'TR', '2026-03-16', '2026-03-20');
insert into uji_tap select (select jsonb_agg(jsonb_build_array('F11', d::date || ' ' || j, null))
                             from generate_series('2026-03-16'::date, '2026-03-20', '1 day') d, unnest(array['14:58:00', '23:02:00']) j);
-- F13: karyawan baru mulai 1 April, tanpa tap di hari-hari kerja pertamanya.
select pg_temp.orang('F13', 'TP', '2026-04-01', '2026-04-03');

-- B11 dan B12: Malam 20 Maret (tutup buku), pulang 21 Maret 07.02; mesin MB. Kiriman pertama tengah malam.
select pg_temp.divisi('TB', 'MB', array['M', 'M', 'M', 'M', 'M', null, null]);   -- Jumat 20 Maret Malam, Sabtu 21 libur
select pg_temp.orang('B11', 'TB', '2026-03-20', '2026-03-21', 'MB');
select pg_temp.kirim('MB', $$[["B11", "2026-03-20 23:00:00", "Masuk"]]$$, '2026-03-21 00:00+07');
select pg_temp.kirim('MA1', (select jsonb_agg(e) from uji_tap, jsonb_array_elements(isi) e));

select pg_temp.hitung_semua();

-- ---------------------------------------------------------------------------
-- A. Membaca file
-- ---------------------------------------------------------------------------
select uji.sama('A01: tap 07.05 berstatus Keluar dibaca sebagai masuk', pg_temp.jam((pg_temp.h('A01', '2026-03-03')).masuk), '2026-03-03 07:05:00');
select uji.sama('A01: telat 5 menit masih dalam toleransi', (pg_temp.h('A01', '2026-03-03')).menit_telat, 0);
select uji.sama('A02: dua tap pulang berdekatan, pulang = tap terakhir 15.04.42', pg_temp.jam((pg_temp.h('A02', '2026-03-03')).pulang), '2026-03-03 15:04:42');
select uji.sama('A03: masuk = tap pagi pertama 07.26.46', pg_temp.jam((pg_temp.h('A03', '2026-03-03')).masuk), '2026-03-03 07:26:46');
select uji.sama('A03: pulang 15.05.11', pg_temp.jam((pg_temp.h('A03', '2026-03-03')).pulang), '2026-03-03 15:05:11');
select uji.sama('A06: dua baris identik dihitung satu tap',
  (select count(*) from hitung.tap_bersih b join hitung.versi_terakhir v on v.id = b.versi_id
   where b.id_karyawan = 'A06' and b.peran = 'dobel')::int, 1);
select uji.sama('A06: hari tetap hadir lengkap', (pg_temp.h('A06', '2026-03-03')).lupa_tap, null::text);
select uji.sama('A08: tap 07.26 dan 07.26.44 menjadi satu, masuk 07.26.00', pg_temp.jam((pg_temp.h('A08', '2026-03-03')).masuk), '2026-03-03 07:26:00');
select uji.sama('A11: ID 99999 masuk daftar ID tidak dikenal', pg_temp.anomali('id_tidak_dikenal', '99999'), 1::bigint);
select uji.sama('A11: tap ID tidak dikenal tidak dihitung untuk siapa pun',
  (select count(*) from hitung.tap_bersih b join hitung.versi_terakhir v on v.id = b.versi_id
   where b.peran = 'id_tidak_dikenal' and b.id_karyawan is null)::int, 3);  -- 99999 dan dua tap 0012 (F06)

-- A07: file yang sama dikirim dua kali
select uji.sama('A07: kiriman pertama diterima',
  fakta.terima_kiriman('ulang.csv', repeat('b', 64), 'MA1', '[["A01","2026-03-03 07:05:00","Keluar",1]]') ->> 'hasil', 'diterima');
select uji.sama('A07: file yang sama dikirim dua kali ditolak sebagai dobel',
  fakta.terima_kiriman('ulang.csv', repeat('b', 64), 'MA1', '[["A01","2026-03-03 07:05:00","Keluar",1]]') ->> 'hasil', 'ditolak');
select uji.sama('A07: tap dari kiriman yang ditolak tidak masuk gudang',
  (select count(*) from fakta.tap_mentah t join fakta.kiriman_file k on k.id = t.kiriman_id where k.sidik = repeat('b', 64))::int, 1);

-- ---------------------------------------------------------------------------
-- B. Shift dan jendela tap
-- ---------------------------------------------------------------------------
select uji.sama('B01: shift Malam 22.58-07.04 hadir di tanggal 10 Maret', (pg_temp.h('B01', '2026-03-10')).status, 'hadir');
select uji.sama('B01: pulang tercatat 11 Maret 07.04', pg_temp.jam((pg_temp.h('B01', '2026-03-10')).pulang), '2026-03-11 07:04:00');
select uji.sama('B02: pulang 23.10 = lebih 10 menit (belum lembur)', (pg_temp.h('B02', '2026-03-03')).menit_lebih, 10);
select uji.sama('B03: masuk 09.40 di shift Pagi = telat 160 menit', (pg_temp.h('B03', '2026-03-03')).menit_telat, 160);
select uji.sama('B03: tetap dibaca shift Pagi', (pg_temp.h('B03', '2026-03-03')).kode_jadwal, 'P');
select uji.sama('B04: tukar shift ke Siang mengalahkan jadwal regu', (pg_temp.h('B04', '2026-03-03')).kode_jadwal, 'S');
select uji.sama('B04: hadir tepat waktu di shift Siang', (pg_temp.h('B04', '2026-03-03')).menit_telat, 0);
select uji.sama('B05: datang 05.30 tidak telat', (pg_temp.h('B05', '2026-03-03')).menit_telat, 0);
select uji.sama('B05: jam sebelum 07.00 tidak menjadi lebih jam', (pg_temp.h('B05', '2026-03-03')).menit_lebih, 1);
select uji.sama('B06: satu tap 06.58 = masuk + lupa tap pulang', (pg_temp.h('B06', '2026-03-03')).lupa_tap, 'pulang');
select uji.sama('B07: satu tap 15.03 = pulang + lupa tap masuk', (pg_temp.h('B07', '2026-03-03')).lupa_tap, 'masuk');
select uji.sama('B08: satu tap 11.00 = lupa tap pulang', (pg_temp.h('B08', '2026-03-03')).lupa_tap, 'pulang');
select uji.sama('B08: ditandai ambigu', (pg_temp.h('B08', '2026-03-03')).ambigu, true);
select uji.sama('B08: masuk rekap harian HRD', pg_temp.anomali('tap_ambigu', 'B08'), 1::bigint);
select uji.sama('B09: tap 02.00 di luar jendela tidak dipakai, hari itu alpha', (pg_temp.h('B09', '2026-03-03')).status, 'alpha');
select uji.sama('B09: ditandai ambigu', (pg_temp.h('B09', '2026-03-03')).ambigu, true);
select uji.sama('B10: shift Malam 9 Maret terbaca lengkap', pg_temp.jam((pg_temp.h('B10', '2026-03-09')).pulang), '2026-03-10 07:01:00');
select uji.sama('B10: shift Pagi 10 Maret terbaca lengkap', pg_temp.jam((pg_temp.h('B10', '2026-03-10')).masuk), '2026-03-10 07:04:00');
select uji.sama('B10: kedua hari ditandai jendela bertumpuk',
  ('jendela_bertumpuk' = any ((pg_temp.h('B10', '2026-03-09')).tanda)) and ('jendela_bertumpuk' = any ((pg_temp.h('B10', '2026-03-10')).tanda)), true);
select uji.sama('B11: Malam 20 Maret menunggu sebelum tap 21 Maret hingga jam 13.00 masuk', (pg_temp.h('B11', '2026-03-20')).status, 'menunggu');
select uji.sama('B13: pulang 13.30 = pulang cepat 90 menit', (pg_temp.h('B13', '2026-03-03')).menit_pulang_cepat, 90);
select uji.sama('B14: tap 14.32 di tengah tidak dianggap pulang', pg_temp.jam((pg_temp.h('B14', '2026-02-18')).pulang), '2026-02-18 16:04:00');
select uji.sama('B14: tidak pulang cepat', (pg_temp.h('B14', '2026-02-18')).menit_pulang_cepat, 0);
select uji.sama('B15: tap 07.00 dan 07.40 dihitung satu: lupa tap pulang', (pg_temp.h('B15', '2026-03-03')).lupa_tap, 'pulang');

-- ---------------------------------------------------------------------------
-- C. Kalender dan hari khusus
-- ---------------------------------------------------------------------------
select uji.sama('C01: tanpa tap di hari Imlek = libur, bukan alpha', (pg_temp.h('C01', '2026-02-17')).status, 'libur');
select uji.sama('C01: jenis hari libur nasional', (pg_temp.h('C01', '2026-02-17')).jenis_hari, 'libur_nasional');
select uji.sama('C02: cuti bersama terbaca sebagai cuti bersama (perlakuan gaji di Tahap 4)', (pg_temp.h('C01', '2026-02-16')).jenis_hari, 'cuti_bersama');
select uji.sama('C03: tanpa tap di hari libur rutin = libur', (pg_temp.h('C03', '2026-03-08')).status, 'libur');
select uji.sama('C04: masuk di hari libur rutin = lembur hari libur', (pg_temp.h('C04', '2026-03-15')).status, 'lembur_hari_libur');
select uji.sama('C04: seluruh 8 jam tercatat', (pg_temp.h('C04', '2026-03-15')).menit_hadir, 480);
select uji.sama('C05: operasi 7 hari masuk di Idul Fitri tetap hadir', (pg_temp.h('C05', '2026-03-21')).status, 'hadir');
select uji.sama('C05: jenis hari libur nasional (dibayar tarif hari libur di Tahap 4)', (pg_temp.h('C05', '2026-03-21')).jenis_hari, 'libur_nasional');
select uji.sama('C06: 4 dari 4 karyawan divisi tanpa tap tidak menjadi alpha', (pg_temp.h('C061', '2026-02-20')).status, 'tanpa_tap_massal');
select uji.sama('C06: pemberitahuan segera ke HRD', pg_temp.anomali('tanpa_tap_massal', 'TM6'), 1::bigint);
select uji.sama('C07: jadwal Ramadan, pulang 15.02 tanggal 23 Feb bukan pulang cepat', (pg_temp.h('C07', '2026-02-23')).menit_pulang_cepat, 0);
select uji.sama('C08: pulang 15.02 tanggal 12 Feb (jadwal 16.00) = pulang cepat 58 menit', (pg_temp.h('C08', '2026-02-12')).menit_pulang_cepat, 58);
select uji.sama('C09: Jumat 13 Feb pulang 16.21 (jadwal 16.30) = pulang cepat 9 menit', (pg_temp.h('C09', '2026-02-13')).menit_pulang_cepat, 9);
select uji.sama('C09: Senin pulang 16.21 normal', (pg_temp.h('C09', '2026-02-09')).menit_pulang_cepat, 0);
select uji.sama('C10: hari sebelum tanggal mulai tidak dihitung',
  (select count(*) from hitung.hasil_harian h join hitung.versi_terakhir v on v.id = h.versi_id
   where h.id_karyawan = 'C10' and h.tanggal < '2026-02-10')::int, 0);
select uji.sama('C11: hari setelah tanggal berhenti tidak dihitung', (pg_temp.h('C11', '2026-02-19')).status, null::text);
select uji.sama('C11: tap setelah berhenti memicu peringatan', pg_temp.anomali('tap_setelah_berhenti', 'C11'), 1::bigint);
select uji.sama('C12: tanpa tap di hari kerja = alpha', (pg_temp.h('C12', '2026-02-19')).status, 'alpha');
select uji.sama('C13: alpha 3 hari kerja berturut-turut memicu peringatan', pg_temp.anomali('alpha_beruntun', 'C13'), 1::bigint);
select uji.sama('C14: divisi 2 orang tanpa tap tetap alpha', (pg_temp.h('C141', '2026-02-20')).status, 'alpha');
select uji.sama('C14: bukan anomali massal', pg_temp.anomali('tanpa_tap_massal', 'TM2'), 0::bigint);

-- ---------------------------------------------------------------------------
-- F. Temuan lapangan
-- ---------------------------------------------------------------------------
select uji.sama('F02: file yang hanya memuat 3 dari 8 karyawan ditandai terpotong', pg_temp.anomali('file_terpotong', 'MT'), 1::bigint);
select uji.sama('F02: yang tidak ada di file tidak dijadikan alpha', (pg_temp.h('F024', '2026-03-03')).status, 'menunggu');
select uji.sama('F02: yang ada di file tetap hadir', (pg_temp.h('F021', '2026-03-03')).status, 'hadir');
select uji.sama('F03: tap terakhir 12 hari sebelum dikirim memicu peringatan', pg_temp.anomali('tap_terakhir_lama', 'MM'), 1::bigint);
select uji.sama('F04: jam mesin 07.08 dengan koreksi 4 menit = waktu baku 07.04', pg_temp.jam((pg_temp.h('F04', '2026-03-05')).masuk), '2026-03-05 07:04:00');
select uji.sama('F04: tidak telat', (pg_temp.h('F04', '2026-03-05')).menit_telat, 0);
select uji.sama('F05: 6 dari 8 orang telat tipis di satu mesin memicu peringatan jam mesin', pg_temp.anomali('jam_mesin_melenceng', 'MJ'), 1::bigint);
select uji.sama('F06: tap ID 0012 sebelum dipetakan masuk ID tidak dikenal', pg_temp.anomali('id_tidak_dikenal', '0012'), 1::bigint);
select uji.sama('F06: hari itu tidak menjadi hadir untuk F06', (pg_temp.h('F06', '2026-02-27')).status, 'alpha');
select uji.sama('F07: dua ID mesin digabung, masuk dan pulang lengkap', (pg_temp.h('F07', '2026-03-12')).lupa_tap, null::text);
select uji.sama('F07: pulang dari ID kedua', pg_temp.jam((pg_temp.h('F07', '2026-03-12')).pulang), '2026-03-12 15:04:00');
select uji.sama('F08: absen manual divisi = hadir dengan asal manual', (pg_temp.h('F081', '2026-02-20')).asal, 'manual');
select uji.sama('F08: anomali hari tanpa tap massal tercatat selesai',
  (select bool_and(a.selesai) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id
   where a.jenis = 'tanpa_tap_massal' and a.divisi = 'TM8'), true);
select uji.sama('F10: kiriman yang tidak pernah masuk ditandai lubang cakupan', pg_temp.anomali('lubang_cakupan', 'ML'), 1::bigint);
select uji.sama('F10: hari di dalam lubang menunggu, bukan alpha', (pg_temp.h('F10', '2026-03-07')).status, 'menunggu');
select uji.sama('F11: tap cocok shift Siang memunculkan usulan tukar shift tiap hari', pg_temp.anomali('usulan_tukar_shift', 'F11'), 5::bigint);
select uji.sama('F11: sebelum disetujui hasil tetap mengikuti jadwal Pagi', (pg_temp.h('F11', '2026-03-16')).kode_jadwal, 'P');
select uji.sama('F13: karyawan baru tanpa tap di hari kerja pertamanya memicu peringatan', pg_temp.anomali('belum_terdaftar_mesin', 'F13'), 1::bigint);
select uji.sama('F13: tetap alpha sampai dikoreksi', (pg_temp.h('F13', '2026-04-01')).status, 'alpha');
select uji.sama('F14: tidak wajib tap, tanpa tap = hadir (bukan alpha)', (pg_temp.h('F14', '2026-03-24')).status, 'hadir');
select uji.sama('F14: asal tidak wajib tap', (pg_temp.h('F14', '2026-03-24')).asal, 'tidak_wajib_tap');

-- ---------------------------------------------------------------------------
-- Koreksi dan data susulan, lalu hitung ulang
-- ---------------------------------------------------------------------------
select pg_temp.kirim('MB', $$[["B11", "2026-03-21 07:02:00", "Keluar"]]$$, '2026-03-21 13:30+07');
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai) values ('chat', 'sakit', 'C12', '2026-02-19');
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, nilai)
values ('chat', 'tukar_shift', 'F11', '2026-03-16', '2026-03-20', 'S');
insert into fakta.perintah_hrd (asal, jenis, tanggal_mulai, alasan) values ('chat', 'tambah_libur', '2026-03-27', 'libur mendadak');
select pg_temp.hitung_semua();

select uji.sama('B11: setelah tap 21 Maret masuk, Malam 20 Maret hadir', (pg_temp.h('B11', '2026-03-20')).status, 'hadir');
select uji.sama('B11: dihitung di periode 21 Feb-20 Mar dengan pulang 07.02',
  pg_temp.jam((pg_temp.h('B11', '2026-03-20')).pulang), '2026-03-21 07:02:00');
select uji.sama('B12: tap 07.02 tanggal 21 tercatat milik periode lain di periode baru',
  (select b.peran from hitung.tap_bersih b join hitung.versi_terakhir v on v.id = b.versi_id
   join fakta.periode p on p.id = v.periode_id and p.tanggal_awal = '2026-03-21'
   where b.id_karyawan = 'B11' and b.waktu_baku = '2026-03-21 07:02:00+07'), 'milik_periode_lain');
select uji.sama('B12: tidak menjadi tap tunggal di periode baru', (pg_temp.h('B11', '2026-03-21')).status, 'libur');
select uji.sama('C12: setelah perintah "sakit tgl 19" menjadi sakit', (pg_temp.h('C12', '2026-02-19')).status, 'sakit');
select uji.sama('F11: setelah tukar shift disetujui dihitung ulang sebagai Siang', (pg_temp.h('F11', '2026-03-16')).kode_jadwal, 'S');
select uji.sama('F11: hadir lengkap di shift Siang', (pg_temp.h('F11', '2026-03-16')).lupa_tap, null::text);
select uji.sama('F16: setelah "tambah libur tgl 27" hari itu libur', (pg_temp.h('F16', '2026-03-27')).status, 'libur');

-- Versi dan sidik
select uji.sama('versi: hitung ulang menambah versi, versi lama tetap ada',
  (select count(*) from hitung.versi_hitung where periode_id = (select id from fakta.periode where tanggal_awal = '2026-02-21'))::int, 2);
create temp table uji_sidik as select hitung.baca_tap((select min(id) from fakta.periode)) as versi;
insert into uji_sidik select hitung.baca_tap((select min(id) from fakta.periode));
select uji.sama('sidik: dua kali hitung tanpa perubahan masukan menghasilkan sidik sama',
  (select count(distinct v.sidik_hasil) from uji_sidik s join hitung.versi_hitung v on v.id = s.versi)::int, 1);
select uji.harus_ditolak('versi: hasil yang sudah jadi tidak boleh diubah',
  $$update hitung.hasil_harian set status = 'hadir' where id_karyawan = 'C12'$$);
select uji.harus_ditolak('versi: versi hitung tidak boleh dihapus', $$delete from hitung.versi_hitung$$);

-- Pembatalan kiriman tanpa sisa (U4): kiriman F07 dibatalkan lewat perintah HRD.
insert into fakta.perintah_hrd (asal, jenis, tanggal_mulai, nilai, alasan)
select 'chat', 'batalkan_kiriman', null, k.id::text, 'file salah'
from fakta.kiriman_file k join fakta.tap_mentah t on t.kiriman_id = k.id and t.id_mesin = '90007';
select pg_temp.hitung_semua();
select uji.sama('U4: setelah kiriman dibatalkan, tapnya tidak dipakai lagi', (pg_temp.h('F07', '2026-03-12')).status, 'alpha');
select uji.sama('U4: kiriman lain tidak terpengaruh', (pg_temp.h('A02', '2026-03-03')).status, 'hadir');
select uji.sama('U4: tap mentah kiriman yang dibatalkan tetap tersimpan (fakta hanya bertambah)',
  (select count(*) from fakta.tap_mentah where id_mesin = '90007')::int, 1);

rollback;
