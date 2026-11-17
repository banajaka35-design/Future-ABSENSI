-- Uji paket 4b-3 terhadap kunci K28-K37 (docs/aturan-hitung-gaji.md versi 3): PPh masa terakhir, data setahun
-- belum lengkap, cuti bersama dan saldo cuti, pecahan uang tunai. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

-- K28-K29: ilustrasi PMK 168/2023 (Tuan A, K/0): bruto setahun 401.920.000, iuran pegawai 3.600.000.
select uji.sama('K28: PPh setahun Tuan A = 52.455.000', hitung.pph21_setahun(401920000, 3600000, 'K/0', 12, '2026-12-25'), 52455000::bigint);
select uji.sama('K29: PPh Desember Tuan A = 52.455.000 - (10 x 3.920.800 + 9.028.800) = 4.218.200',
  hitung.pph21_setahun(401920000, 3600000, 'K/0', 12, '2026-12-25') - (10 * 3920800 + 9028800), 4218200::bigint);
select uji.sama('Pasal 17: PKP 60.000.000 = 3.000.000', hitung.pph_pasal17(60000000, '2026-12-25'), 3000000::bigint);
select uji.sama('Pasal 17: PKP 0 = 0', hitung.pph_pasal17(0, '2026-12-25'), 0::bigint);
select uji.sama('Pasal 17: lapisan 35% di atas 5 miliar', hitung.pph_pasal17(6000000000, '2026-12-25'),
  (3000000 + 28500000 + 62500000 + 1350000000 + 350000000)::bigint);
select uji.sama('biaya jabatan dibatasi 500.000 x banyak bulan (6 bulan = 3.000.000)',
  hitung.pph21_setahun(160000000, 0, 'TK/0', 6, '2026-06-25'), hitung.pph_pasal17(160000000 - 3000000 - 54000000, '2026-06-25'));

insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j
union all select 'libur_6_hari', j, case when j <= 7 then 20 when j = 8 then 30 else 40 end, date '2021-02-02' from generate_series(1, 11) j;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into aturan.cuti (jatah_hari, berlaku_setelah_bulan, berlaku_dari) values (12, 12, '2020-01-01');
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values ('cuti_bersama', 'TL', 'potong_cuti', '2026-01-01');

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values ('TL', 'Uji 6 hari', 'mingguan', 1, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select 'TL', 0, h, case when h = 7 then null else 'P' end, '2026-01-01' from generate_series(1, 7) h;
-- 13 periode bersambung: bayar Jan 2026 sampai Jan 2027; lalu Desember 2027 tanpa periode sebelumnya di tahun itu.
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar)
select (date '2025-12-21' + make_interval(months => n))::date, (date '2026-01-20' + make_interval(months => n))::date,
       (date '2026-01-25' + make_interval(months => n))::date
from generate_series(0, 12) n
union all select '2027-11-21', '2027-12-20', '2027-12-25';

create function pg_temp.orang(p_id text, p_divisi text, p_mulai date, p_pokok bigint default 3500000,
                              p_tetap bigint default 500000, p_bayar text default 'transfer') returns void language sql as $$
  insert into induk.karyawan (id, nama) values (p_id, 'Uji ' || p_id);
  insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                      bpjs_kesehatan, bpjs_ketenagakerjaan)
  values (p_id, least(p_mulai, '2024-01-01'), p_divisi, p_pokok, p_tetap, 'TK/0', p_bayar, false, false);
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


-- K30 (E11): gaji tetap 4.000.000 setahun penuh.
select pg_temp.orang('E11A', 'TL', '2024-01-01');  select pg_temp.hari('E11A', 'TL', '2025-12-21', '2026-12-20');
-- K31 (E11): gaji 10.000.000 setahun penuh.
select pg_temp.orang('E11B', 'TL', '2024-01-01', 10000000, 0);  select pg_temp.hari('E11B', 'TL', '2025-12-21', '2027-01-20');
-- K32 (E12): gaji 10.000.000, berhenti 20 Jun 2026 (hari terakhir periode Juni).
select pg_temp.orang('E12B', 'TL', '2024-01-01', 10000000, 0);  select pg_temp.hari('E12B', 'TL', '2025-12-21', '2026-06-20');
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('E12B', 'berhenti', '2026-06-20');
-- K33: Desember 2027 tanpa data Januari-November 2027.
select pg_temp.orang('TAHAN', 'TL', '2024-01-01', 10000000, 0);  select pg_temp.hari('TAHAN', 'TL', '2027-11-21', '2027-12-20');
-- K34-K35 (C02, C02b): cuti bersama 16 Feb 2026 dan 24 Des 2026, pengaturan potong cuti.
select pg_temp.orang('CB1', 'TL', '2024-01-01');  select pg_temp.hari('CB1', 'TL', '2026-01-21', '2027-01-20');
update uji_hari set jenis_hari = 'cuti_bersama', status = 'libur', asal = 'jadwal', masuk = null, pulang = null
where id_karyawan = 'CB1' and tanggal in ('2026-02-16', '2026-12-24');
-- K36: mulai 1 Mar 2024, saldo awal 5 hari pada 21 Feb 2026, cuti 2 hari, ulang tahun kerja 1 Mar 2026.
select pg_temp.orang('SALDO', 'TL', '2024-03-01');  select pg_temp.hari('SALDO', 'TL', '2026-02-21', '2026-04-20');
update uji_hari set status = 'cuti', asal = 'perintah', masuk = null, pulang = null
where id_karyawan = 'SALDO' and tanggal in ('2026-03-03', '2026-03-04');
insert into induk.saldo_cuti_awal (id_karyawan, tanggal, hari) values ('SALDO', '2026-02-21', 5);
-- Tanpa saldo awal: saldo kosong.
select pg_temp.orang('KOSONG', 'TL', '2024-01-01');  select pg_temp.hari('KOSONG', 'TL', '2026-02-21', '2026-03-20');
-- K37 (U12): dibayar tunai 3.847.000.
select pg_temp.orang('TUNAI', 'TL', '2024-01-01', 3847263, 0, 'tunai');  select pg_temp.hari('TUNAI', 'TL', '2025-12-21', '2026-01-20');

select pg_temp.simpan();
select hitung.hitung_gaji(id) from fakta.periode order by tanggal_awal;

-- PPh masa terakhir
select uji.sama('K30 (E11): gaji 4.000.000, PPh Desember 0', pg_temp.r('E11A', 'pph21', '2026-11-21'), 0::bigint);
select uji.sama('K30: tanpa pengembalian', pg_temp.r('E11A', 'pengembalian_pph21', '2026-11-21'), 0::bigint);
select uji.sama('K31: TER Januari-November 2% x 10.000.000 = 200.000', pg_temp.r('E11B', 'pph21', '2026-10-21'), -200000::bigint);
select uji.sama('K31 (E11): PPh Desember 3.000.000 - 2.200.000 = 800.000', pg_temp.r('E11B', 'pph21', '2026-11-21'), -800000::bigint);
select uji.sama('K31: jumlah PPh setahun = 3.000.000',
  (select -sum(r.nominal) from hitung.rincian_gaji r join hitung.versi_terakhir v on v.id = r.versi_id
   join fakta.periode p on p.id = v.periode_id and extract(year from p.tanggal_bayar) = 2026
   where r.id_karyawan = 'E11B' and r.komponen = 'pph21'), 3000000::numeric);
select uji.sama('K31: masa Januari 2027 kembali memakai TER', pg_temp.r('E11B', 'pph21', '2026-12-21'), -200000::bigint);
select uji.sama('K32 (E12): berhenti Juni, PPh 21 masa itu 0', pg_temp.r('E12B', 'pph21', '2026-05-21'), 0::bigint);
select uji.sama('K32 (E12): pengembalian 1.000.000 - 150.000 = 850.000', pg_temp.r('E12B', 'pengembalian_pph21', '2026-05-21'), 850000::bigint);
select uji.sama('K32: pengembalian tidak masuk bruto pajak', (pg_temp.g('E12B', '2026-05-21')).bruto_pajak, 10000000::bigint);
select uji.sama('K32: pengembalian menambah gaji bersih', (pg_temp.g('E12B', '2026-05-21')).gaji_bersih, 10850000::bigint);
select uji.sama('K33: Desember tanpa data setahun, PPh 0', pg_temp.r('TAHAN', 'pph21', '2027-11-21'), 0::bigint);
select uji.sama('K33: tanda PPh masa terakhir tertahan', 'pph_masa_terakhir_tertahan' = any((pg_temp.g('TAHAN', '2027-11-21')).peringatan), true);
select uji.sama('K33: periode itu tidak bisa diajukan',
  hitung.periode_bisa_diajukan((select id from fakta.periode where tanggal_awal = '2027-11-21')), false);
select uji.sama('K33: Desember 2026 yang datanya lengkap bisa diajukan',
  hitung.periode_bisa_diajukan((select id from fakta.periode where tanggal_awal = '2026-11-21')), true);
select uji.sama('periode tanpa hasil gaji tidak bisa diajukan', hitung.periode_bisa_diajukan(-1), false);

-- Cuti
select uji.sama('K34 (C02): cuti bersama 16 Feb potong cuti, terpakai 1', (pg_temp.g('CB1', '2026-01-21')).cuti_terpakai, 1);
select uji.sama('K34: hari cuti bersama tetap dibayar penuh',
  pg_temp.r('CB1', 'gaji_pokok', '2026-01-21') + pg_temp.r('CB1', 'tunjangan_tetap', '2026-01-21'), 4000000::bigint);
select uji.sama('K35 (C02b): cuti bersama 24 Des sesudah UU 27, terpakai 0', (pg_temp.g('CB1', '2026-12-21')).cuti_terpakai, 0);
select uji.sama('K35: tanda potong cuti tidak berlaku',
  'potong_cuti_tidak_berlaku_uu27' = any((pg_temp.g('CB1', '2026-12-21')).peringatan), true);
select uji.sama('K36: cuti terpakai 2', (pg_temp.g('SALDO', '2026-02-21')).cuti_terpakai, 2);
select uji.sama('K36: saldo 5 + 12 - 2 = 15', (pg_temp.g('SALDO', '2026-02-21')).saldo_cuti, 15);
select uji.sama('K36: saldo dibawa ke periode berikutnya', (pg_temp.g('SALDO', '2026-03-21')).saldo_cuti, 15);
select uji.sama('tanpa saldo awal: saldo kosong', (pg_temp.g('KOSONG', '2026-02-21')).saldo_cuti is null, true);

-- Pecahan tunai
select uji.sama('K37 (U12): dibayar 3.847.000', (pg_temp.g('TUNAI', '2025-12-21')).dibayar, 3847000::bigint);
select uji.sama('K37 (U12): pecahan 38 x 100.000, 2 x 20.000, 1 x 5.000, 1 x 2.000',
  (select string_agg(t.pecahan || 'x' || t.lembar, ' ' order by t.pecahan desc)
   from hitung.pecahan_tunai((select v.id from hitung.versi_terakhir v join fakta.periode p on p.id = v.periode_id
                              where v.jenis = 'hitung_gaji' and p.tanggal_awal = '2025-12-21')) t where t.lembar > 0),
  '100000x38 20000x2 5000x1 2000x1');
select uji.sama('K37: jumlah pecahan = jumlah dibayar tunai',
  (select sum(t.jumlah) from hitung.pecahan_tunai((select v.id from hitung.versi_terakhir v join fakta.periode p on p.id = v.periode_id
                              where v.jenis = 'hitung_gaji' and p.tanggal_awal = '2025-12-21')) t), 3847000::numeric);
select uji.sama('versi kode gaji 3', hitung.versi_kode_gaji(), 'hitung_gaji 3 (paket 4b-3)');

rollback;
