-- Uji paket 4b-5 terhadap kunci K47-K50 (docs/aturan-hitung-gaji.md versi 5): tanda gaji berubah tanpa lembur,
-- isian pajak awal tahun untuk PPh masa terakhir. Kunci K51 (F13b) ada di 040. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j
union all select 'libur_6_hari', j, case when j <= 7 then 20 when j = 8 then 30 else 40 end, date '2021-02-02' from generate_series(1, 11) j;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values ('TL', 'Uji 6 hari', 'mingguan', 1, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select 'TL', 0, h, case when h = 7 then null else 'P' end, '2026-01-01' from generate_series(1, 7) h;
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-03-21', '2026-04-20', '2026-04-25'), ('2026-04-21', '2026-05-20', '2026-05-25'),
  ('2027-10-21', '2027-11-20', '2027-11-25'), ('2027-11-21', '2027-12-20', '2027-12-25');

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

create function pg_temp.ada(p_jenis text, p_id text, p_awal date) returns boolean language sql as $$
  select exists (select 1 from hitung.anomali_gaji((select id from fakta.periode where tanggal_awal = p_awal)) a
                 where a.jenis = p_jenis and (a.id_karyawan = p_id or a.divisi = p_id))
$$;

-- K47: upah tetap sama, lembur naik sepuluh kali.
select pg_temp.orang('LBR', 'TL', '2024-01-01');  select pg_temp.hari('LBR', 'TL', '2026-03-21', '2026-05-20');
update uji_hari set menit_lebih = 120 where id_karyawan = 'LBR'
  and tanggal in ('2026-04-07', '2026-04-22', '2026-04-23', '2026-04-24', '2026-04-25', '2026-04-27', '2026-04-28',
                  '2026-04-29', '2026-04-30', '2026-05-04', '2026-05-05');
-- Gaji turun karena alpha 5 hari tetap bertanda (potongan hari tidak dibayar ikut dibanding).
select pg_temp.orang('ALPHA5', 'TL', '2024-01-01');  select pg_temp.hari('ALPHA5', 'TL', '2026-03-21', '2026-05-20');
update uji_hari set status = 'alpha', asal = 'jadwal', masuk = null, pulang = null
where id_karyawan = 'ALPHA5' and tanggal between '2026-05-04' and '2026-05-08';
-- K48: hanya Desember 2027 di sistem, isian Januari-November.
select pg_temp.orang('ISI11', 'TL', '2024-01-01', 10000000, 0);  select pg_temp.hari('ISI11', 'TL', '2027-11-21', '2027-12-20');
insert into induk.pajak_awal_tahun (id_karyawan, tahun, sampai_bulan, bulan_kerja, bruto, iuran, pph)
values ('ISI11', 2027, 11, 11, 110000000, 0, 2200000);
-- K49: sama, tanpa isian.
select pg_temp.orang('TANPA', 'TL', '2024-01-01', 10000000, 0);  select pg_temp.hari('TANPA', 'TL', '2027-11-21', '2027-12-20');
-- K50: isian Januari-Oktober, periode sistem November dan Desember.
select pg_temp.orang('ISI10', 'TL', '2024-01-01', 10000000, 0);  select pg_temp.hari('ISI10', 'TL', '2027-10-21', '2027-12-20');
insert into induk.pajak_awal_tahun (id_karyawan, tahun, sampai_bulan, bulan_kerja, bruto, iuran, pph)
values ('ISI10', 2027, 10, 10, 100000000, 0, 2000000);

select pg_temp.simpan();
select hitung.hitung_gaji(id) from fakta.periode order by tanggal_awal;

select uji.sama('K47: lembur 80.925 lalu 809.250', pg_temp.r('LBR', 'lembur') || '/' || pg_temp.r('LBR', 'lembur', '2026-04-21'), '80925/809250');
select uji.sama('K47: lembur naik saja tidak memberi tanda gaji berubah', pg_temp.ada('gaji_berubah', 'LBR', '2026-04-21'), false);
select uji.sama('K47: lembur divisi tetap bertanda (O3)', pg_temp.ada('lembur_divisi_naik', 'TL', '2026-04-21'), true);
select uji.sama('O2 versi 5: alpha 5 hari (potongan lebih dari 15%) tetap bertanda', pg_temp.ada('gaji_berubah', 'ALPHA5', '2026-04-21'), true);
select uji.sama('K48: dengan isian Januari-November, PPh Desember 800.000', pg_temp.r('ISI11', 'pph21', '2027-11-21'), -800000::bigint);
select uji.sama('K48: tidak tertahan', 'pph_masa_terakhir_tertahan' = any((pg_temp.g('ISI11', '2027-11-21')).peringatan), false);
select uji.sama('K49: tanpa isian, PPh Desember 0', pg_temp.r('TANPA', 'pph21', '2027-11-21'), 0::bigint);
select uji.sama('K49: tanpa isian, tertahan', 'pph_masa_terakhir_tertahan' = any((pg_temp.g('TANPA', '2027-11-21')).peringatan), true);
select uji.sama('K49: periode tidak bisa diajukan selama ada yang tertahan',
  hitung.periode_bisa_diajukan((select id from fakta.periode where tanggal_awal = '2027-11-21')), false);
select uji.sama('K50: November memakai TER 200.000', pg_temp.r('ISI10', 'pph21', '2027-10-21'), -200000::bigint);
select uji.sama('K50: Desember 800.000 (isian 10 bulan + November + Desember)', pg_temp.r('ISI10', 'pph21', '2027-11-21'), -800000::bigint);
select uji.harus_ditolak('isian pajak awal tahun: sampai bulan harus 1-11',
  $$insert into induk.pajak_awal_tahun (id_karyawan, tahun, sampai_bulan, bulan_kerja, bruto, iuran, pph)
                      values ('TANPA', 2027, 12, 12, 1, 0, 0)$$);
select uji.sama('versi kode gaji terbaru', hitung.versi_kode_gaji(), 'hitung_gaji 5 (paket 5a)');
select uji.sama('versi kode baca tap terbaru', hitung.versi_kode_baca(), 'baca_tap 3 (paket 5b)');

rollback;
