-- Uji mesin hitung gaji (paket 4b-1) terhadap kunci K1-K18 di docs/aturan-hitung-gaji.md dan kasus jebakan C, D, E.
-- Hasil baca tap dibuat langsung (tanpa tap mesin) supaya tiap kasus bisa diatur tepat; baca tap sudah diuji di 040.
-- Seluruh uji berjalan dalam satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

-- ---------------------------------------------------------------------------
-- Aturan uji (sama dengan data awal Pabrik A dan angka resmi yang sudah dicek)
-- ---------------------------------------------------------------------------
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j
union all select 'libur_6_hari', j, case when j <= 7 then 20 when j = 8 then 30 else 40 end, date '2021-02-02' from generate_series(1, 11) j
union all select 'libur_6_hari_terpendek', j, case when j <= 5 then 20 when j = 6 then 30 else 40 end, date '2021-02-02' from generate_series(1, 9) j
union all select 'libur_5_hari', j, case when j <= 8 then 20 when j = 9 then 30 else 40 end, date '2021-02-02' from generate_series(1, 12) j;
insert into aturan.bpjs (program, bagian, persen, batas_atas, berlaku_dari, berlaku_sampai) values
  ('kesehatan', 'karyawan', 100, 12000000, '2021-01-01', null), ('kesehatan', 'perusahaan', 400, 12000000, '2021-01-01', null),
  ('jht', 'karyawan', 200, null, '2021-01-01', null), ('jht', 'perusahaan', 370, null, '2021-01-01', null),
  ('jp', 'karyawan', 100, 10547400, '2025-03-01', '2026-03-01'), ('jp', 'perusahaan', 200, 10547400, '2025-03-01', '2026-03-01'),
  ('jp', 'karyawan', 100, 11086300, '2026-03-01', null), ('jp', 'perusahaan', 200, 11086300, '2026-03-01', null),
  ('jkk', 'perusahaan', 24, null, '2021-01-01', null), ('jkm', 'perusahaan', 30, null, '2021-01-01', null);
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into aturan.komponen_lain (kode, nominal, satuan, sifat, berlaku_dari, berlaku_sampai) values
  ('uang_makan', 15000, 'per_hari', 'tidak_tetap', '2026-01-01', '2026-10-21'),
  ('uang_makan', 60000, 'per_hari', 'tidak_tetap', '2026-10-21', null),   -- dibesarkan untuk kasus D11b
  ('premi_hadir', 100000, 'per_periode', 'tidak_tetap', '2026-01-01', null),
  ('tunjangan_shift_malam', 10000, 'per_hari', 'tidak_tetap', '2026-01-01', null);

-- ---------------------------------------------------------------------------
-- Kunci K1-K13: fungsi bagian
-- ---------------------------------------------------------------------------
select uji.sama('K1 (contoh resmi PMK 168): K/0 bruto 30.160.000 -> Rp3.920.800',
  hitung.pph21_ter(30160000, 'K/0', '2026-01-25'), 3920800::bigint);
select uji.sama('K2 (E04): TK/0 bruto 10.454.000 -> Rp261.350', hitung.pph21_ter(10454000, 'TK/0', '2026-03-25'), 261350::bigint);
select uji.sama('E04: bruto = 10.000.000 + JKK + JKM + Kesehatan perusahaan = 10.454.000',
  10000000 + hitung.iuran_bpjs('jkk', 'perusahaan', 10000000, '2026-03-25') + hitung.iuran_bpjs('jkm', 'perusahaan', 10000000, '2026-03-25')
  + hitung.iuran_bpjs('kesehatan', 'perusahaan', 10000000, '2026-03-25'), 10454000::bigint);
select uji.sama('K3 (D01): lembur hari kerja 120 menit = Rp80.925',
  hitung.rupiah_lembur(hitung.satuan_lembur('kerja', hitung.menit_lembur_dibayar(120, '2026-03-03'), '2026-03-03'), 4000000), 80925::bigint);
select uji.sama('K4 (D02): lembur 59 menit tidak dibayar', hitung.menit_lembur_dibayar(59, '2026-03-03'), 0);
select uji.sama('K5 (D03): lembur 95 menit dibayar 90 menit', hitung.menit_lembur_dibayar(95, '2026-03-03'), 90);
select uji.sama('K5 (D03): 90 menit = Rp57.803',
  hitung.rupiah_lembur(hitung.satuan_lembur('kerja', 90, '2026-03-03'), 4000000), 57803::bigint);
select uji.sama('D12: lebih 116 menit dibayar 90 menit = Rp57.803',
  hitung.rupiah_lembur(hitung.satuan_lembur('kerja', hitung.menit_lembur_dibayar(116, '2026-02-06'), '2026-02-06'), 4000000), 57803::bigint);
select uji.sama('K6 (D06): libur pola 6 hari 8 jam = Rp393.064',
  hitung.rupiah_lembur(hitung.satuan_lembur('libur_6_hari', 480, '2026-03-03'), 4000000), 393064::bigint);
select uji.sama('K7 (D07): libur di hari terpendek 7 jam = Rp393.064',
  hitung.rupiah_lembur(hitung.satuan_lembur('libur_6_hari_terpendek', 420, '2026-03-03'), 4000000), 393064::bigint);
select uji.sama('K8 (D08): libur pola 5 hari 10 jam = Rp531.792',
  hitung.rupiah_lembur(hitung.satuan_lembur('libur_5_hari', 600, '2026-03-03'), 4000000), 531792::bigint);
select uji.sama('K9 (D11): dasar lembur 75% x 4.000.000 = 3.000.000', hitung.dasar_lembur(2500000, 1500000), 3000000::bigint);
select uji.sama('K9 (D11): lembur 2 jam = Rp60.694',
  hitung.rupiah_lembur(hitung.satuan_lembur('kerja', 120, '2026-03-03'), hitung.dasar_lembur(2500000, 1500000)), 60694::bigint);
select uji.sama('dasar lembur tetap 100% bila pokok + tetap >= 75% seluruh upah', hitung.dasar_lembur(4000000, 500000), 4000000::bigint);
select uji.sama('lembur melewati tabel memakai pengali jam terakhir (13 jam hari kerja)',
  hitung.satuan_lembur('kerja', 780, '2026-03-03'), (15 * 60 + 20 * 60 * 12)::bigint);
select uji.sama('K11 (E05): BPJS Kesehatan karyawan upah 15 jt = Rp120.000',
  hitung.iuran_bpjs('kesehatan', 'karyawan', 15000000, '2026-03-25'), 120000::bigint);
select uji.sama('K12 (E06): JP karyawan upah 15 jt, bayar 25 Mar 2026 = Rp110.863',
  hitung.iuran_bpjs('jp', 'karyawan', 15000000, '2026-03-25'), 110863::bigint);
select uji.sama('E06: JP karyawan upah 15 jt, bayar 25 Feb 2026 = Rp105.474 (batas lama)',
  hitung.iuran_bpjs('jp', 'karyawan', 15000000, '2026-02-25'), 105474::bigint);
select uji.sama('K13: BPJS Kesehatan upah 3.000.000 memakai batas bawah UMK = Rp34.029',
  hitung.iuran_bpjs('kesehatan', 'karyawan', 3000000, '2026-03-25'), 34029::bigint);
select uji.sama('JHT tanpa batas atas: 2% x 15 jt = Rp300.000', hitung.iuran_bpjs('jht', 'karyawan', 15000000, '2026-03-25'), 300000::bigint);

-- ---------------------------------------------------------------------------
-- Data uji untuk hitung_gaji
-- ---------------------------------------------------------------------------
insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values
  ('P', '07:00', '15:00', 60), ('M', '23:00', '07:00', 60), ('K', '08:00', '16:00', 60), ('K5', '08:00', '13:00', 0);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('TL', 'Uji 6 hari', 'mingguan', 1, 'MA1'), ('TW', 'Uji wajib perintah', 'mingguan', 1, 'MA1'),
  ('T7', 'Uji operasi 7 hari', 'mingguan', 1, 'MA1'), ('KT', 'Uji kantor hari pendek', 'mingguan', 1, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select d, 0, h, case when d = 'T7' then 'P' when h = 7 then null when d = 'KT' and h = 6 then 'K5' when d = 'KT' then 'K' else 'P' end,
       '2026-01-01'
from unnest(array['TL', 'TW', 'T7', 'KT']) d, generate_series(1, 7) h;
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values
  ('premi_hadir', 'TL', 'hidup', '2026-01-01'), ('tunjangan_shift_malam', 'TL', 'hidup', '2026-01-01'),
  ('lembur', 'TW', 'wajib_perintah', '2026-01-01'), ('operasi_7_hari', 'T7', 'ya', '2026-01-01');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-03-21', '2026-04-20', '2026-04-25'),   -- 26 hari Senin-Sabtu
  ('2026-10-21', '2026-11-20', '2026-11-25'),
  ('2026-11-21', '2026-12-20', '2026-12-25');

create function pg_temp.orang(p_id text, p_divisi text, p_mulai date, p_pokok bigint default 3500000,
                              p_tetap bigint default 500000) returns void language sql as $$
  insert into induk.karyawan (id, nama) values (p_id, 'Uji ' || p_id);
  insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar)
  values (p_id, '2025-01-01', p_divisi, p_pokok, p_tetap, 'TK/0', 'transfer');
  insert into induk.status_kerja (id_karyawan, jenis, tanggal) values (p_id, 'mulai', p_mulai);
$$;

-- Hari uji: jadwal mingguan divisi, hadir tepat waktu di hari kerja, libur rutin di hari Minggu.
create temp table uji_hari (like hitung.hasil_harian including defaults);
alter table uji_hari alter column versi_id drop not null;
create function pg_temp.hari(p_id text, p_divisi text, p_dari date, p_sampai date) returns void language sql as $$
  insert into uji_hari (id_karyawan, tanggal, divisi, regu, kode_jadwal, jenis_hari, status, asal, masuk, pulang, tanda)
  select p_id, d::date, p_divisi, 0, j.kode, case when j.kode is null then 'libur_rutin' else 'kerja' end,
         case when j.kode is null then 'libur' else 'hadir' end, case when j.kode is null then 'jadwal' else 'mesin' end,
         case when j.kode is not null then (d::date + k.jam_masuk) at time zone 'Asia/Jakarta' end,
         case when j.kode is not null then (d::date + k.jam_pulang + case when k.jam_pulang <= k.jam_masuk then interval '1 day' else interval '0' end)
                                           at time zone 'Asia/Jakarta' end,
         '{}'
  from generate_series(p_dari::timestamp, p_sampai::timestamp, interval '1 day') d
  join induk.jadwal_hari j on j.divisi = p_divisi and j.regu = 0 and j.hari_ke = extract(isodow from d)
  left join induk.kode_jadwal k on k.kode = j.kode;
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
-- Komponen dan ringkasan seseorang di periode hitung gaji paling awal yang memuat orang itu.
create function pg_temp.r(p_id text, p_komponen text) returns bigint language sql as $$
  select coalesce((select r.nominal from hitung.rincian_gaji r
                   join hitung.versi_terakhir v on v.id = r.versi_id join fakta.periode p on p.id = v.periode_id
                   where r.id_karyawan = p_id and r.komponen = p_komponen
                     and v.periode_id = (select v2.periode_id from hitung.ringkasan_gaji g2
                                         join hitung.versi_terakhir v2 on v2.id = g2.versi_id
                                         join fakta.periode p2 on p2.id = v2.periode_id
                                         where g2.id_karyawan = p_id order by p2.tanggal_awal limit 1)), 0)
$$;
create function pg_temp.g(p_id text) returns hitung.ringkasan_gaji language sql as $$
  select g.* from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
  join fakta.periode p on p.id = v.periode_id
  where g.id_karyawan = p_id order by p.tanggal_awal limit 1
$$;

-- Periode 21 Mar-20 Apr 2026 (26 hari Senin-Sabtu).
select pg_temp.orang('PENUH', 'TL', '2025-01-01');                          -- premi hidup, tanpa alpha dan telat
select pg_temp.hari('PENUH', 'TL', '2026-03-21', '2026-04-20');
select pg_temp.orang('E01', 'TL', '2026-04-06');                            -- 13 dari 26 hari
select pg_temp.hari('E01', 'TL', '2026-04-06', '2026-04-20');
select pg_temp.orang('E02', 'TL', '2025-01-01');                            -- naik gaji mulai hari ke-14
update induk.karyawan_riwayat set berlaku_sampai = '2026-04-06' where id_karyawan = 'E02';
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar)
values ('E02', '2026-04-06', 'TL', 4500000, 500000, 'TK/0', 'transfer');
select pg_temp.hari('E02', 'TL', '2026-03-21', '2026-04-20');
select pg_temp.orang('E13', 'TL', '2025-01-01');                            -- satu alpha
select pg_temp.hari('E13', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set status = 'alpha', masuk = null, pulang = null where id_karyawan = 'E13' and tanggal = '2026-04-01';
select pg_temp.orang('IZIN', 'TL', '2025-01-01');                           -- izin tidak dibayar, sakit dan cuti dibayar
select pg_temp.hari('IZIN', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set status = 'izin', masuk = null, pulang = null where id_karyawan = 'IZIN' and tanggal = '2026-04-01';
update uji_hari set status = 'sakit', masuk = null, pulang = null where id_karyawan = 'IZIN' and tanggal = '2026-04-02';
update uji_hari set status = 'cuti', masuk = null, pulang = null where id_karyawan = 'IZIN' and tanggal = '2026-04-03';
select pg_temp.orang('D01', 'TL', '2025-01-01');                            -- lembur 120 menit
select pg_temp.hari('D01', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set menit_lebih = 120, pulang = pulang + interval '120 minutes' where id_karyawan = 'D01' and tanggal = '2026-04-07';
select pg_temp.orang('D05', 'TL', '2025-01-01');                            -- lembur dibatalkan lewat chat
select pg_temp.hari('D05', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set menit_lebih = 120 where id_karyawan = 'D05' and tanggal = '2026-04-07';
insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai) values ('chat', 'batalkan_lembur', 'D05', '2026-04-07');
select pg_temp.orang('D04', 'TW', '2025-01-01');                            -- wajib perintah, tanpa perintah
select pg_temp.hari('D04', 'TW', '2026-03-21', '2026-04-20');
update uji_hari set menit_lebih = 120 where id_karyawan = 'D04' and tanggal = '2026-04-07';
select pg_temp.orang('F12', 'TW', '2025-01-01');                            -- wajib perintah, disetujui untuk divisi
select pg_temp.hari('F12', 'TW', '2026-03-21', '2026-04-20');
update uji_hari set menit_lebih = 120 where id_karyawan = 'F12' and tanggal = '2026-04-08';
insert into fakta.perintah_hrd (asal, jenis, divisi, tanggal_mulai) values ('chat', 'setujui_lembur', 'TW', '2026-04-08');
select pg_temp.orang('C05', 'T7', '2025-01-01');                            -- operasi 7 hari masuk shift P di hari libur nasional
select pg_temp.hari('C05', 'T7', '2026-03-21', '2026-04-20');
update uji_hari set jenis_hari = 'libur_nasional' where id_karyawan = 'C05' and tanggal = '2026-04-03';
select pg_temp.orang('LN', 'T7', '2025-01-01');                             -- alpha di hari libur nasional: tidak dipotong
select pg_temp.hari('LN', 'T7', '2026-03-21', '2026-04-20');
update uji_hari set jenis_hari = 'libur_nasional', status = 'alpha', masuk = null, pulang = null
where id_karyawan = 'LN' and tanggal = '2026-04-03';
select pg_temp.orang('D07', 'KT', '2025-01-01');                            -- lembur di hari libur yang jatuh di hari pendek (Sabtu)
select pg_temp.hari('D07', 'KT', '2026-03-21', '2026-04-20');
update uji_hari set kode_jadwal = null, jenis_hari = 'libur_nasional', status = 'lembur_hari_libur', menit_hadir = 480,
                    masuk = '2026-04-04 08:00+07', pulang = '2026-04-04 16:00+07'
where id_karyawan = 'D07' and tanggal = '2026-04-04';
select pg_temp.orang('MALAM', 'TL', '2025-01-01');                          -- shift malam dua hari
select pg_temp.hari('MALAM', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set kode_jadwal = 'M' where id_karyawan = 'MALAM' and tanggal in ('2026-04-07', '2026-04-08');
select pg_temp.orang('D10', 'TL', '2025-01-01');                            -- 5 x 240 menit dalam satu minggu
select pg_temp.hari('D10', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set menit_lebih = 240 where id_karyawan = 'D10' and tanggal between '2026-04-06' and '2026-04-10';
select pg_temp.orang('E08', 'TL', '2025-08-01', 3000000, 300000);            -- 3.300.000, masa kerja 8 bulan
select pg_temp.hari('E08', 'TL', '2026-03-21', '2026-04-20');
select pg_temp.orang('KOMP', 'TL', '2025-01-01', 2000000, 1000000);           -- pokok 66,7% dari pokok + tetap
select pg_temp.hari('KOMP', 'TL', '2026-03-21', '2026-04-20');
-- Periode 21 Okt-20 Nov 2026: kasus D11b (uang makan 60.000 per hari di periode ini).
select pg_temp.orang('D11B', 'TL', '2025-01-01', 2000000, 500000);
select pg_temp.hari('D11B', 'TL', '2026-10-21', '2026-11-20');
update uji_hari set menit_lebih = 120 where id_karyawan = 'D11B' and tanggal = '2026-11-02';
-- Periode 21 Nov-20 Des 2026: PPh Desember belum dihitung.
select pg_temp.hari('PENUH', 'TL', '2026-11-21', '2026-12-20');

select pg_temp.simpan();
select count(hitung.hitung_gaji(id)) from fakta.periode;

-- ---------------------------------------------------------------------------
-- Kunci K14-K18 dan kasus jebakan lewat hitung_gaji
-- ---------------------------------------------------------------------------
select uji.sama('periode penuh: gaji pokok sebulan', pg_temp.r('PENUH', 'gaji_pokok'), 3500000::bigint);
select uji.sama('periode penuh: tunjangan tetap sebulan', pg_temp.r('PENUH', 'tunjangan_tetap'), 500000::bigint);
select uji.sama('premi hadir dibayar bila tanpa alpha dan telat', pg_temp.r('PENUH', 'premi_hadir'), 100000::bigint);
select uji.sama('uang makan 26 hari x 15.000', pg_temp.r('PENUH', 'uang_makan'), 390000::bigint);
select uji.sama('K14 (E01): masuk tengah periode, gaji pokok 13/26', pg_temp.r('E01', 'gaji_pokok'), 1750000::bigint);
select uji.sama('K14 (E01): pokok + tetap = Rp2.000.000', pg_temp.r('E01', 'gaji_pokok') + pg_temp.r('E01', 'tunjangan_tetap'), 2000000::bigint);
select uji.sama('C10: tidak ada potongan untuk hari sebelum mulai kerja', pg_temp.r('E01', 'potongan_tidak_dibayar'), 0::bigint);
select uji.sama('K15 (E02): naik gaji hari ke-14, prorata dua tarif = Rp4.500.000',
  pg_temp.r('E02', 'gaji_pokok') + pg_temp.r('E02', 'tunjangan_tetap'), 4500000::bigint);
select uji.sama('K16 (E13): satu alpha, premi hangus', pg_temp.r('E13', 'premi_hadir'), 0::bigint);
select uji.sama('K16: satu alpha dipotong 4.000.000 / 26', pg_temp.r('E13', 'potongan_tidak_dibayar'), -153846::bigint);
select uji.sama('izin dipotong satu hari, sakit dan cuti dibayar', pg_temp.r('IZIN', 'potongan_tidak_dibayar'), -153846::bigint);
select uji.sama('D01: lembur 120 menit di hari kerja = Rp80.925', pg_temp.r('D01', 'lembur'), 80925::bigint);
select uji.sama('D05: lembur dibatalkan lewat chat = Rp0', pg_temp.r('D05', 'lembur'), 0::bigint);
select uji.sama('D04: wajib perintah tanpa perintah = Rp0', pg_temp.r('D04', 'lembur'), 0::bigint);
select uji.sama('D04: menit lembur tetap tercatat (tanda tanpa izin)',
  'lembur_tidak_dibayar_tanpa_izin' = any((pg_temp.g('D04')).peringatan), true);
select uji.sama('F12: perintah setujui lembur untuk divisi = dibayar Rp80.925', pg_temp.r('F12', 'lembur'), 80925::bigint);
select uji.sama('C05: shift P (7 jam kerja) di hari libur nasional = 7 x 2 x upah sejam',
  pg_temp.r('C05', 'lembur'), hitung.rupiah_lembur(20 * 60 * 7, 4000000));
select uji.sama('C05: gaji pokok tetap penuh', pg_temp.r('C05', 'gaji_pokok'), 3500000::bigint);
select uji.sama('alpha di hari libur nasional tidak dipotong', pg_temp.r('LN', 'potongan_tidak_dibayar'), 0::bigint);
select uji.sama('alpha di hari libur nasional diberi tanda',
  'alpha_di_hari_libur_tidak_dipotong' = any((pg_temp.g('LN')).peringatan), true);
select uji.sama('D07: hadir 480 menit di libur hari pendek, istirahat 60 -> 420 menit = Rp393.064',
  pg_temp.r('D07', 'lembur'), 393064::bigint);
select uji.sama('shift malam 2 hari x 10.000', pg_temp.r('MALAM', 'tunjangan_shift_malam'), 20000::bigint);
select uji.sama('D09/D10: 240 menit per hari = wajib makan', 'wajib_makan' = any((pg_temp.g('D10')).peringatan), true);
select uji.sama('D10: 1.200 menit dalam satu minggu = lewat batas 18 jam', 'lembur_lewat_18_jam' = any((pg_temp.g('D10')).peringatan), true);
select uji.sama('D10: tetap dibayar penuh (5 x 240 menit)',
  pg_temp.r('D10', 'lembur'), 5 * hitung.rupiah_lembur(hitung.satuan_lembur('kerja', 240, '2026-04-06'), 4000000));
select uji.sama('K17 (E08): 3.300.000, masa kerja 8 bulan = tanda di bawah UMK', 'di_bawah_umk' = any((pg_temp.g('E08')).peringatan), true);
select uji.sama('masa kerja lebih dari 12 bulan tidak diberi tanda UMK', 'di_bawah_umk' = any((pg_temp.g('PENUH')).peringatan), false);
select uji.sama('Pasal 150: pokok di bawah 75% diberi tanda', 'pokok_di_bawah_75' = any((pg_temp.g('KOMP')).peringatan), true);
select uji.sama('BPJS Kesehatan karyawan 1% x 4.000.000', pg_temp.r('PENUH', 'bpjs_kesehatan_karyawan'), -40000::bigint);
select uji.sama('BPJS JHT karyawan 2% x 4.000.000', pg_temp.r('PENUH', 'bpjs_jht_karyawan'), -80000::bigint);
select uji.sama('BPJS JP karyawan 1% x 4.000.000', pg_temp.r('PENUH', 'bpjs_jp_karyawan'), -40000::bigint);
select uji.sama('bruto pajak = pendapatan + JKK + JKM + Kesehatan perusahaan',
  (pg_temp.g('PENUH')).bruto_pajak, (3500000 + 500000 + 100000 + 390000 + 9600 + 12000 + 160000)::bigint);
select uji.sama('PPh 21 = TER A x bruto (dibulatkan ke bawah)',
  pg_temp.r('PENUH', 'pph21'), -hitung.pph21_ter((pg_temp.g('PENUH')).bruto_pajak, 'TK/0', '2026-04-25'));
select uji.sama('K10 (D11b): dasar lembur 75% sesudah 28 Okt 2026',
  pg_temp.r('D11B', 'lembur'),
  hitung.rupiah_lembur(2100, hitung.dasar_lembur(2500000, pg_temp.r('D11B', 'uang_makan') + pg_temp.r('D11B', 'premi_hadir'))));
select uji.sama('K10 (D11b): dasar memang 75% (lebih besar dari pokok + tetap)',
  hitung.dasar_lembur(2500000, pg_temp.r('D11B', 'uang_makan') + pg_temp.r('D11B', 'premi_hadir')) > 2500000, true);
select uji.sama('K10 (D11b): tanda perlu dikonfirmasi HRD',
  'dasar_lembur_75_perlu_konfirmasi_hrd' = any((pg_temp.g('D11B')).peringatan), true);
select uji.sama('masa Desember tanpa data Jan-Nov: PPh 21 ditahan (0) dan diberi tanda (aturan v3 L2)',
  (select r.nominal = 0 and 'pph_masa_terakhir_tertahan' = any(g.peringatan)
   from hitung.rincian_gaji r
   join hitung.ringkasan_gaji g on g.versi_id = r.versi_id and g.id_karyawan = r.id_karyawan
   join hitung.versi_terakhir v on v.id = r.versi_id
   join fakta.periode p on p.id = v.periode_id and p.tanggal_bayar = '2026-12-25'
   where r.id_karyawan = 'PENUH' and r.komponen = 'pph21'), true);

-- K18 (U3): gaji bersih = jumlah rincian pendapatan dan potongan, untuk setiap orang dan total.
select uji.sama('K18 (U3): gaji bersih tiap orang = jumlah rinciannya',
  (select count(*) from hitung.ringkasan_gaji g
   where g.gaji_bersih <> (select sum(r.nominal) from hitung.rincian_gaji r
                           where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan and r.kelompok in ('pendapatan', 'potongan')))::int, 0);
select uji.sama('K18 (U3): total gaji bersih = total rincian, selisih 0',
  (select sum(gaji_bersih) from hitung.ringkasan_gaji) - (select sum(nominal) from hitung.rincian_gaji where kelompok <> 'perusahaan'), 0::numeric);

-- Versi dan sidik.
select hitung.hitung_gaji(id) from fakta.periode where tanggal_awal = '2026-03-21';
select uji.sama('dua kali hitung: dua versi dengan sidik hasil sama',
  (select count(*) || '/' || count(distinct v.sidik_hasil) from hitung.versi_hitung v join fakta.periode p on p.id = v.periode_id
   where v.jenis = 'hitung_gaji' and p.tanggal_awal = '2026-03-21'), '2/1');
select uji.harus_ditolak('rincian gaji tidak bisa diubah',
  $$update hitung.rincian_gaji set nominal = 1 where komponen = 'gaji_pokok'$$);
select uji.harus_ditolak('hitung gaji ditolak bila periode belum punya hasil baca tap',
  $$insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2027-01-21', '2027-02-20', '2027-02-25');
    select hitung.hitung_gaji(max(id)) from fakta.periode$$);

-- Akses: tabel gaji tertutup untuk peran tanpa login dan pengguna login biasa.
select uji.sama('tabel gaji tertutup untuk anon dan authenticated',
  (select count(*) from unnest(array['anon', 'authenticated']) peran, unnest(array['hitung.rincian_gaji', 'hitung.ringkasan_gaji']) t
   where has_table_privilege(peran, t, 'select'))::int, 0);
select uji.sama('fungsi hitung gaji tidak bisa dijalankan anon dan authenticated',
  (select count(*) from unnest(array['anon', 'authenticated']) peran
   where has_function_privilege(peran, 'hitung.hitung_gaji(bigint)', 'execute'))::int, 0);

rollback;
