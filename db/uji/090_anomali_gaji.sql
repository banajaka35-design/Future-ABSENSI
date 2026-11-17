-- Uji paket 4b-4 terhadap kunci K38-K46 (docs/aturan-hitung-gaji.md versi 4, bagian O): tanda anomali sebelum rilis.
-- Dua periode: 21 Mar-20 Apr 2026 (periode pertama) dan 21 Apr-20 Mei 2026. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j
union all select 'libur_6_hari', j, case when j <= 7 then 20 when j = 8 then 30 else 40 end, date '2021-02-02' from generate_series(1, 11) j;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into aturan.thr (tanggal_bayar, hari_raya, cara_prorata, berlaku_dari) values ('2026-05-10', '2026-05-27', 'bulan_penuh', '2026-01-01');

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('TL', 'Uji 6 hari', 'mingguan', 1, 'MA1'), ('LD', 'Uji lembur naik', 'mingguan', 1, 'MA1'), ('LE', 'Uji lembur tetap', 'mingguan', 1, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select d, 0, h, case when h = 7 then null else 'P' end, '2026-01-01' from unnest(array['TL', 'LD', 'LE']) d, generate_series(1, 7) h;
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-03-21', '2026-04-20', '2026-04-25'), ('2026-04-21', '2026-05-20', '2026-05-25');

create function pg_temp.orang(p_id text, p_divisi text, p_mulai date, p_pokok bigint default 3500000,
                              p_tetap bigint default 500000, p_bayar text default 'transfer') returns void language sql as $$
  insert into induk.karyawan (id, nama) values (p_id, 'Uji ' || p_id);
  insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                      bpjs_kesehatan, bpjs_ketenagakerjaan)
  values (p_id, '2024-01-01', p_divisi, p_pokok, p_tetap, 'TK/0', p_bayar, false, false);
  insert into induk.status_kerja (id_karyawan, jenis, tanggal) values (p_id, 'mulai', p_mulai);
$$;
create temp table uji_hari (like hitung.hasil_harian including defaults);
alter table uji_hari alter column versi_id drop not null;
create function pg_temp.hari(p_id text, p_divisi text, p_dari date, p_sampai date) returns void language sql as $$
  insert into uji_hari (id_karyawan, tanggal, divisi, regu, kode_jadwal, jenis_hari, status, asal, masuk, pulang, tanda)
  select p_id, d::date, p_divisi, 0, j.kode, case when j.kode is null then 'libur_rutin' else 'kerja' end,
         case when j.kode is null then 'libur' else 'hadir' end, case when j.kode is null then 'jadwal' else 'mesin' end,
         case when j.kode is not null then (d::date + time '07:00') at time zone 'Asia/Jakarta' end,
         case when j.kode is not null then (d::date + time '15:00') at time zone 'Asia/Jakarta' end, '{}'
  from generate_series(p_dari::timestamp, p_sampai::timestamp, interval '1 day') d
  join induk.jadwal_hari j on j.divisi = p_divisi and j.regu = 0 and j.hari_ke = extract(isodow from d);
$$;
create function pg_temp.simpan() returns void language sql as $$
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  select p.id, 'baca_tap', 1, 'uji', 'uji', 'uji' from fakta.periode p;
  insert into hitung.hasil_harian (versi_id, id_karyawan, tanggal, divisi, regu, kode_jadwal, jenis_hari, status, asal, masuk, pulang,
                                   menit_telat, menit_pulang_cepat, menit_lebih, menit_hadir, lupa_tap, ambigu, tanda)
  select v.id, u.id_karyawan, u.tanggal, u.divisi, u.regu, u.kode_jadwal, u.jenis_hari, u.status, u.asal, u.masuk, u.pulang,
         u.menit_telat, u.menit_pulang_cepat, u.menit_lebih, u.menit_hadir, u.lupa_tap, u.ambigu, u.tanda
  from uji_hari u
  join fakta.periode p on u.tanggal between p.tanggal_awal and p.tanggal_akhir
  join hitung.versi_hitung v on v.periode_id = p.id and v.jenis = 'baca_tap';
$$;
-- Nilai satu komponen / ringkasan seseorang di periode yang dimulai pada tanggal tertentu.
create function pg_temp.r(p_id text, p_komponen text, p_awal date default '2026-03-21') returns bigint language sql as $$
  select coalesce((select r.nominal from hitung.rincian_gaji r join hitung.versi_terakhir v on v.id = r.versi_id
                   join fakta.periode p on p.id = v.periode_id and p.tanggal_awal = p_awal
                   where r.id_karyawan = p_id and r.komponen = p_komponen), 0)
$$;
create function pg_temp.g(p_id text, p_awal date default '2026-03-21') returns hitung.ringkasan_gaji language sql as $$
  select g.* from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
  join fakta.periode p on p.id = v.periode_id and p.tanggal_awal = p_awal where g.id_karyawan = p_id
$$;

create function pg_temp.naik(p_id text, p_pokok bigint) returns void language sql as $$
  update induk.karyawan_riwayat set berlaku_sampai = '2026-04-21' where id_karyawan = p_id and berlaku_sampai is null;
  insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                      bpjs_kesehatan, bpjs_ketenagakerjaan)
  values (p_id, '2026-04-21', 'TL', p_pokok, 500000, 'TK/0', 'transfer', false, false);
$$;
create function pg_temp.ada(p_jenis text, p_id text, p_awal date) returns boolean language sql as $$
  select exists (select 1 from hitung.anomali_gaji((select id from fakta.periode where tanggal_awal = p_awal)) a
                 where a.jenis = p_jenis and (a.id_karyawan = p_id or a.divisi = p_id))
$$;

-- K38, K39, K41: perubahan upah mulai periode kedua. K40: THR di periode kedua.
select pg_temp.orang('G47', 'TL', '2024-01-01');  select pg_temp.hari('G47', 'TL', '2026-03-21', '2026-05-20');
select pg_temp.naik('G47', 4200000);
select pg_temp.orang('G46', 'TL', '2024-01-01');  select pg_temp.hari('G46', 'TL', '2026-03-21', '2026-05-20');
select pg_temp.naik('G46', 4100000);
select pg_temp.orang('GTURUN', 'TL', '2024-01-01');  select pg_temp.hari('GTURUN', 'TL', '2026-03-21', '2026-05-20');
select pg_temp.naik('GTURUN', 2500000);
select pg_temp.orang('GTHR', 'TL', '2024-01-01');  select pg_temp.hari('GTHR', 'TL', '2026-03-21', '2026-05-20');
-- K42: divisi LD, lembur 120 menit lalu 2 x 120 menit. K43: divisi LE, 120 menit dua-duanya.
select pg_temp.orang('LD1', 'LD', '2024-01-01');  select pg_temp.hari('LD1', 'LD', '2026-03-21', '2026-05-20');
update uji_hari set menit_lebih = 120 where id_karyawan = 'LD1' and tanggal in ('2026-04-07', '2026-05-05', '2026-05-06');
select pg_temp.orang('LE1', 'LE', '2024-01-01');  select pg_temp.hari('LE1', 'LE', '2026-03-21', '2026-05-20');
update uji_hari set menit_lebih = 120 where id_karyawan = 'LE1' and tanggal in ('2026-04-07', '2026-05-05');
-- K44: seluruh hari periode kedua sakit dari perintah HRD. K45: sama, tetapi satu hari ada tap mesin.
select pg_temp.orang('SAKIT', 'TL', '2024-01-01');  select pg_temp.hari('SAKIT', 'TL', '2026-03-21', '2026-05-20');
update uji_hari set status = 'sakit', asal = 'perintah', masuk = null, pulang = null
where id_karyawan = 'SAKIT' and tanggal >= '2026-04-21' and status = 'hadir';
select pg_temp.orang('SAKIT1', 'TL', '2024-01-01');  select pg_temp.hari('SAKIT1', 'TL', '2026-03-21', '2026-05-20');
update uji_hari set status = 'sakit', asal = 'perintah', masuk = null, pulang = null
where id_karyawan = 'SAKIT1' and tanggal >= '2026-04-22' and status = 'hadir';
-- K46: periode pertama, sopir tidak wajib tap.
select pg_temp.orang('SOPIR', 'TL', '2024-01-01');  select pg_temp.hari('SOPIR', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set asal = 'tidak_wajib_tap', masuk = null, pulang = null where id_karyawan = 'SOPIR' and status = 'hadir';

select pg_temp.simpan();
select hitung.hitung_gaji(id) from fakta.periode order by tanggal_awal;

select uji.sama('K38: upah 4.000.000 -> 4.700.000 diberi tanda gaji berubah', pg_temp.ada('gaji_berubah', 'G47', '2026-04-21'), true);
select uji.sama('K38: isi tanda nilai lalu dan nilai sekarang',
  (select a.nilai_lalu || '/' || a.nilai_sekarang from hitung.anomali_gaji((select id from fakta.periode where tanggal_awal = '2026-04-21')) a
   where a.jenis = 'gaji_berubah' and a.id_karyawan = 'G47'), '4000000/4700000');
select uji.sama('K39: 4.000.000 -> 4.600.000 (tepat 15%) tanpa tanda', pg_temp.ada('gaji_berubah', 'G46', '2026-04-21'), false);
select uji.sama('K40: THR tidak dibanding', pg_temp.ada('gaji_berubah', 'GTHR', '2026-04-21'), false);
select uji.sama('K40: THR memang dibayar di periode kedua', pg_temp.r('GTHR', 'thr', '2026-04-21') > 0, true);
select uji.sama('K41: 4.000.000 -> 3.000.000 diberi tanda gaji berubah', pg_temp.ada('gaji_berubah', 'GTURUN', '2026-04-21'), true);
select uji.sama('K42: lembur LD 80.925 lalu 161.850', pg_temp.r('LD1', 'lembur') || '/' || pg_temp.r('LD1', 'lembur', '2026-04-21'), '80925/161850');
select uji.sama('K42: divisi LD diberi tanda lembur divisi naik', pg_temp.ada('lembur_divisi_naik', 'LD', '2026-04-21'), true);
select uji.sama('K43: divisi LE lembur sama, tanpa tanda', pg_temp.ada('lembur_divisi_naik', 'LE', '2026-04-21'), false);
select uji.sama('K43: divisi TL tanpa lembur dua periode, tanpa tanda', pg_temp.ada('lembur_divisi_naik', 'TL', '2026-04-21'), false);
select uji.sama('K44: seluruh hari sakit tanpa tap mesin diberi tanda aktif tanpa tap', pg_temp.ada('aktif_tanpa_tap', 'SAKIT', '2026-04-21'), true);
select uji.sama('K45: satu hari tap mesin, tanpa tanda', pg_temp.ada('aktif_tanpa_tap', 'SAKIT1', '2026-04-21'), false);
select uji.sama('K46: periode pertama tanpa tanda gaji berubah atau lembur',
  (select count(*) from hitung.anomali_gaji((select id from fakta.periode where tanggal_awal = '2026-03-21')) a
   where a.jenis in ('gaji_berubah', 'lembur_divisi_naik'))::int, 0);
select uji.sama('K46: periode pertama tetap memeriksa aktif tanpa tap (sopir)', pg_temp.ada('aktif_tanpa_tap', 'SOPIR', '2026-03-21'), true);
select uji.sama('orang biasa tanpa tanda apa pun', 
  (select count(*) from hitung.anomali_gaji((select id from fakta.periode where tanggal_awal = '2026-04-21')) a
   where a.id_karyawan in ('LE1', 'GTHR', 'G46'))::int, 0);
select uji.sama('anomali tidak mengubah angka: gaji bersih G47 = 4.700.000', (pg_temp.g('G47', '2026-04-21')).gaji_bersih, 4700000::bigint);

rollback;
