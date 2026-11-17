-- Uji paket 4b-2 terhadap kunci K19-K27 (docs/aturan-hitung-gaji.md versi 2): THR, denda, kasbon, batas potongan,
-- pembayaran tunai dan sisa, peringatan lembur hanya hari kerja. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

-- Aturan minimum: tanpa BPJS dan tanpa komponen lain, supaya pendapatan = gaji pokok + tunjangan tetap (angka bulat).
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j
union all select 'libur_6_hari', j, case when j <= 7 then 20 when j = 8 then 30 else 40 end, date '2021-02-02' from generate_series(1, 11) j;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into aturan.thr (tanggal_bayar, hari_raya, cara_prorata, berlaku_dari) values ('2026-04-10', '2026-04-17', 'bulan_penuh', '2026-01-01');
insert into aturan.batas_potongan (persen, komponen, berlaku_dari) values (5000, array['denda', 'kasbon', 'ganti_rugi'], '2026-01-01');
insert into aturan.tingkat_denda (jenis, dari_menit, nominal, dasar_pasal, berlaku_dari)
values ('telat', 1, 500000, 'Peraturan perusahaan uji Pasal 1', '2026-01-01');

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('TL', 'Uji 6 hari', 'mingguan', 1, 'MA1'), ('T7', 'Uji operasi 7 hari', 'mingguan', 1, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select d, 0, h, case when d = 'T7' then 'P' when h = 7 then null else 'P' end, '2026-01-01'
from unnest(array['TL', 'T7']) d, generate_series(1, 7) h;
insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values ('operasi_7_hari', 'T7', 'ya', '2026-01-01');
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

-- THR: hari raya 17 Apr 2026, bayar 10 Apr.
select pg_temp.orang('THR24', 'TL', '2024-04-17');  select pg_temp.hari('THR24', 'TL', '2026-03-21', '2026-04-20');
select pg_temp.orang('THR6', 'TL', '2025-10-17');   select pg_temp.hari('THR6', 'TL', '2026-03-21', '2026-04-20');
select pg_temp.orang('THR0', 'TL', '2026-04-01');   select pg_temp.hari('THR0', 'TL', '2026-04-01', '2026-04-20');
select pg_temp.orang('PINDAH', 'TL', '2024-01-01'); select pg_temp.hari('PINDAH', 'TL', '2026-03-21', '2026-04-08');  -- berhenti sebelum THR dibayar
-- K22: denda 500.000 (telat sekali) + kasbon 2.000.000; periode berikutnya sisa kasbon 500.000.
select pg_temp.orang('DK1', 'TL', '2024-01-01');
select pg_temp.hari('DK1', 'TL', '2026-03-21', '2026-05-20');
update uji_hari set menit_telat = 10 where id_karyawan = 'DK1' and tanggal = '2026-04-07';
insert into fakta.buku_kasbon (id_karyawan, jenis, jumlah, dibuat) values ('DK1', 'pinjam', 2000000, '2026-03-25 10:00+07');
-- K23: denda 5 x 500.000 = 2.500.000 melewati batas; kasbon 2.000.000 tidak terpotong.
select pg_temp.orang('DK2', 'TL', '2024-01-01');
select pg_temp.hari('DK2', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set menit_telat = 10 where id_karyawan = 'DK2' and tanggal between '2026-04-06' and '2026-04-10';
insert into fakta.buku_kasbon (id_karyawan, jenis, jumlah, dibuat) values ('DK2', 'pinjam', 2000000, '2026-03-25 10:00+07');
-- Kasbon dengan cicilan 400.000 per periode.
select pg_temp.orang('CIC', 'TL', '2024-01-01');
select pg_temp.hari('CIC', 'TL', '2026-03-21', '2026-05-20');
insert into fakta.buku_kasbon (id_karyawan, jenis, jumlah, dibuat) values
  ('CIC', 'pinjam', 1000000, '2026-03-25 10:00+07'), ('CIC', 'cicilan', 400000, '2026-03-25 10:01+07');
-- K25 (E12): berhenti 4 Apr, 13 dari 26 hari, sisa kasbon 300.000.
select pg_temp.orang('E12', 'TL', '2024-01-01');
select pg_temp.hari('E12', 'TL', '2026-03-21', '2026-04-04');
insert into fakta.buku_kasbon (id_karyawan, jenis, jumlah, dibuat) values ('E12', 'pinjam', 300000, '2026-03-22 10:00+07');
-- K24 (E09): gaji bersih 3.847.263 tunai (periode 2, tanpa THR); TUNAI dua periode untuk sisa yang dibawa.
select pg_temp.orang('E09', 'TL', '2024-01-01', 3847263, 0, 'tunai');
select pg_temp.hari('E09', 'TL', '2026-04-21', '2026-05-20');
select pg_temp.orang('TUNAI', 'TL', '2024-01-01', 3847263, 0, 'tunai');
select pg_temp.hari('TUNAI', 'TL', '2026-03-21', '2026-05-20');
-- K26: shift 7 jam di hari libur nasional dan lembur hari kerja 250 menit.
select pg_temp.orang('LIBUR', 'T7', '2024-01-01');
select pg_temp.hari('LIBUR', 'T7', '2026-03-21', '2026-04-20');
update uji_hari set jenis_hari = 'libur_nasional' where id_karyawan = 'LIBUR' and tanggal = '2026-04-03';
select pg_temp.orang('L250', 'TL', '2024-01-01');
select pg_temp.hari('L250', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set menit_lebih = 250 where id_karyawan = 'L250' and tanggal = '2026-04-07';
select pg_temp.orang('L300', 'TL', '2024-01-01');
select pg_temp.hari('L300', 'TL', '2026-03-21', '2026-04-20');
update uji_hari set menit_lebih = 300 where id_karyawan = 'L300' and tanggal = '2026-04-07';

select pg_temp.simpan();
select hitung.hitung_gaji(id) from fakta.periode order by tanggal_awal;

-- THR
select uji.sama('K19 (E03): THR masa kerja 24 bulan = 1 bulan upah', pg_temp.r('THR24', 'thr'), 4000000::bigint);
select uji.sama('K20 (E03): THR masa kerja 6 bulan = 6/12 upah', pg_temp.r('THR6', 'thr'), 2000000::bigint);
select uji.sama('K21: THR masa kerja kurang dari 1 bulan = 0, tanpa komponen',
  (select count(*) from hitung.rincian_gaji r join hitung.versi_terakhir v on v.id = r.versi_id
   where r.id_karyawan = 'THR0' and r.komponen = 'thr')::int, 0);
select uji.sama('THR: tidak aktif pada tanggal bayar THR = tidak dapat (dicatat sebagai batasan)', pg_temp.r('PINDAH', 'thr'), 0::bigint);
select uji.sama('THR masuk bruto pajak', (pg_temp.g('THR24')).bruto_pajak, 8000000::bigint);
select uji.sama('THR ikut PPh 21 masa itu (TER A x 8.000.000)', pg_temp.r('THR24', 'pph21'), -hitung.pph21_ter(8000000, 'TK/0', '2026-04-25'));
select uji.sama('THR tidak ada di periode tanpa tanggal bayar THR', pg_temp.r('DK1', 'thr', '2026-04-21'), 0::bigint);

-- Denda, kasbon, batas
select uji.sama('K22 (E07): denda 500.000', pg_temp.r('DK1', 'denda'), -500000::bigint);
select uji.sama('K22 (E07): kasbon 1.500.000 (batas 2.000.000 sesudah denda)', pg_temp.r('DK1', 'kasbon'), -1500000::bigint);
select uji.sama('K22 (E07): sisa kasbon 500.000 dipotong periode berikutnya', pg_temp.r('DK1', 'kasbon', '2026-04-21'), -500000::bigint);
select uji.sama('K22: periode berikutnya gaji bersih 4.000.000 - 500.000', (pg_temp.g('DK1', '2026-04-21')).gaji_bersih, 3500000::bigint);
select uji.sama('K23 (E07): denda 2.500.000 dipotong 2.000.000', pg_temp.r('DK2', 'denda'), -2000000::bigint);
select uji.sama('K23 (E07): kasbon tidak terpotong', pg_temp.r('DK2', 'kasbon'), 0::bigint);
select uji.sama('K23: tanda denda melewati batas dan kasbon tidak terpotong',
  (pg_temp.g('DK2')).peringatan @> array['denda_melewati_batas_potongan', 'kasbon_tidak_terpotong_penuh'], true);
select uji.sama('denda dan kasbon tidak mengurangi bruto pajak (4.000.000 + THR 4.000.000)', (pg_temp.g('DK1')).bruto_pajak, 8000000::bigint);
select uji.sama('cicilan 400.000 per periode', pg_temp.r('CIC', 'kasbon') || '/' || pg_temp.r('CIC', 'kasbon', '2026-04-21'), '-400000/-400000');
select uji.sama('K25 (E12): berhenti, prorata 2.000.000', pg_temp.r('E12', 'gaji_pokok') + pg_temp.r('E12', 'tunjangan_tetap'), 2000000::bigint);
select uji.sama('K25 (E12): sisa kasbon 300.000 terpotong penuh', pg_temp.r('E12', 'kasbon'), -300000::bigint);

-- Tunai dan sisa
select uji.sama('K24 (E09): gaji bersih 3.847.263', (pg_temp.g('E09', '2026-04-21')).gaji_bersih, 3847263::bigint);
select uji.sama('K24 (E09): dibayar 3.847.000, sisa 263',
  (pg_temp.g('E09', '2026-04-21')).dibayar || '/' || (pg_temp.g('E09', '2026-04-21')).sisa_pembulatan, '3847000/263');
select uji.sama('K24: periode 1 (gaji + THR - PPh 115.417 = 7.579.109) dibayar 7.579.000, sisa 109',
  (pg_temp.g('TUNAI')).gaji_bersih || '/' || (pg_temp.g('TUNAI')).dibayar || '/' || (pg_temp.g('TUNAI')).sisa_pembulatan,
  '7579109/7579000/109');
select uji.sama('K24: periode berikutnya sisa lalu 109 ikut dibayar: 3.847.263 + 109 -> dibayar 3.847.000, sisa 372',
  (pg_temp.g('TUNAI', '2026-04-21')).sisa_lalu || '/' || (pg_temp.g('TUNAI', '2026-04-21')).dibayar || '/'
  || (pg_temp.g('TUNAI', '2026-04-21')).sisa_pembulatan, '109/3847000/372');
select uji.sama('K27: transfer tidak dibulatkan', (pg_temp.g('DK1')).dibayar = (pg_temp.g('DK1')).gaji_bersih
  and (pg_temp.g('DK1')).sisa_pembulatan = 0, true);

-- Peringatan lembur (versi 2)
select uji.sama('K26: shift 7 jam di hari libur nasional tanpa peringatan lewat 4 jam',
  (pg_temp.g('LIBUR')).peringatan && array['lembur_lewat_4_jam', 'wajib_makan'], false);
select uji.sama('K26: shift hari libur tetap dibayar lembur hari libur', pg_temp.r('LIBUR', 'lembur'), hitung.rupiah_lembur(20 * 60 * 7, 4000000));
select uji.sama('K26: lembur hari kerja 250 menit (dibayar 240) = wajib makan',
  'wajib_makan' = any((pg_temp.g('L250')).peringatan), true);
select uji.sama('K26: lembur hari kerja 300 menit = lewat batas 4 jam', 'lembur_lewat_4_jam' = any((pg_temp.g('L300')).peringatan), true);
select uji.sama('K26: 240 menit belum lewat batas 4 jam', 'lembur_lewat_4_jam' = any((pg_temp.g('L250')).peringatan), false);

-- U3 tetap
select uji.sama('U3: gaji bersih tiap orang = jumlah rinciannya',
  (select count(*) from hitung.ringkasan_gaji g
   where g.gaji_bersih <> (select sum(r.nominal) from hitung.rincian_gaji r
                           where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan and r.kelompok <> 'perusahaan'))::int, 0);
select uji.sama('dibayar + sisa = gaji bersih + sisa lalu',
  (select count(*) from hitung.ringkasan_gaji where dibayar + sisa_pembulatan <> gaji_bersih + sisa_lalu)::int, 0);

rollback;
