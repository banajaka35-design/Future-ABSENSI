-- Uji aturan pondasi (kontrak data bagian 1) dan kasus jebakan yang menyentuh pondasi.
-- Seluruh uji berjalan dalam satu transaksi yang dibatalkan di akhir, jadi database tetap bersih.
begin;

set local app.pengguna = 'uji-otomatis';

insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang pabrik'), ('MA2', 'Kantor');
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('PRD', 'Produksi', 'rotasi', 4, 'MA1'), ('KTR', 'Kantor', 'mingguan', 1, 'MA2');
insert into induk.karyawan (id, nama) values ('10001', 'Andi Lubis'), ('10002', 'Budi Siregar');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar)
values ('10001', '2026-01-01', 'PRD', 3500000, 500000, 'TK/0', 'transfer');

-- Aturan 4: bertanggal
select uji.harus_ditolak('bertanggal: rentang tumpang tindih ditolak',
  $$insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar)
    values ('10001', '2026-02-01', 'PRD', 3800000, 'TK/0', 'transfer')$$);
select uji.harus_ditolak('bertanggal: nilai lama tidak boleh diubah',
  $$update induk.karyawan_riwayat set gaji_pokok = 9000000 where id_karyawan = '10001'$$);
select uji.harus_ditolak('bertanggal: baris tidak boleh dihapus',
  $$delete from induk.karyawan_riwayat where id_karyawan = '10001'$$);
select uji.harus_diterima('bertanggal: kenaikan gaji = tutup baris lama lalu tambah baris baru (kasus E02)',
  $$update induk.karyawan_riwayat set berlaku_sampai = '2026-02-14' where id_karyawan = '10001';
    insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar)
    values ('10001', '2026-02-14', 'PRD', 4500000, 500000, 'TK/0', 'transfer')$$);
select uji.sama('bertanggal: gaji pada 13 Feb masih yang lama', (induk.karyawan_pada('10001', '2026-02-13')).gaji_pokok, 3500000::bigint);
select uji.sama('bertanggal: gaji pada 14 Feb sudah yang baru', (induk.karyawan_pada('10001', '2026-02-14')).gaji_pokok, 4500000::bigint);
select uji.harus_ditolak('bertanggal: baris yang sudah ditutup tidak boleh dibuka lagi',
  $$update induk.karyawan_riwayat set berlaku_sampai = null where id_karyawan = '10001' and berlaku_sampai is not null$$);

-- Catatan perubahan
select uji.sama('jejak: perubahan gaji tercatat dengan nama pengubah',
  (select count(*) from jejak.perubahan where tabel = 'induk.karyawan_riwayat' and oleh = 'uji-otomatis')::int, 3);
select uji.harus_ditolak('jejak: catatan perubahan tidak boleh diubah',
  $$update jejak.perubahan set oleh = 'orang lain'$$);

-- Aturan 2: fakta hanya bertambah
insert into fakta.kiriman_file (nama_file, sidik, jenis, mesin, hasil, nomor_pesan)
values ('absen.xls', repeat('a', 64), 'tap_mesin', 'MA1', 'diterima', 501);
insert into fakta.tap_mentah (kiriman_id, mesin, id_mesin, jam_lokal, status_mesin, baris_asal)
select id, 'MA1', '198001012010011001', '2026-02-02 07:05:23', 'C/Keluar', 2 from fakta.kiriman_file;
select uji.harus_ditolak('fakta: tap tidak boleh diubah', $$update fakta.tap_mentah set jam_lokal = jam_lokal + interval '1 hour'$$);
select uji.harus_ditolak('fakta: tap tidak boleh dihapus', $$delete from fakta.tap_mentah$$);
select uji.harus_ditolak('fakta: tabel tap tidak boleh dikosongkan', $$truncate fakta.tap_mentah cascade$$);
select uji.sama('kasus A05: ID 18 digit tersimpan utuh sebagai teks',
  (select id_mesin from fakta.tap_mentah limit 1), '198001012010011001'::text);
select uji.sama('kasus A01: status mesin disimpan apa adanya',
  (select status_mesin from fakta.tap_mentah limit 1), 'C/Keluar'::text);
select uji.harus_ditolak('kasus A07: file dengan sidik sama ditolak',
  $$insert into fakta.kiriman_file (nama_file, sidik, jenis, hasil) values ('absen (1).xls', repeat('a', 64), 'tap_mesin', 'diterima')$$);
select uji.harus_ditolak('kasus L1: pesan Telegram yang sama ditolak',
  $$insert into fakta.kiriman_file (nama_file, sidik, jenis, hasil, nomor_pesan) values ('lain.xls', repeat('b', 64), 'tap_mesin', 'diterima', 501)$$);
select uji.harus_diterima('kiriman ditolak boleh dicatat berulang dengan alasan',
  $$insert into fakta.kiriman_file (nama_file, sidik, jenis, hasil, alasan) values ('absen.xls', repeat('a', 64), 'tap_mesin', 'ditolak', 'file dobel');
    insert into fakta.kiriman_file (nama_file, sidik, jenis, hasil, alasan) values ('absen.xls', repeat('a', 64), 'tap_mesin', 'ditolak', 'file dobel')$$);
select uji.harus_ditolak('kiriman ditolak wajib punya alasan',
  $$insert into fakta.kiriman_file (nama_file, sidik, jenis, hasil) values ('x.xls', repeat('c', 64), 'tap_mesin', 'ditolak')$$);
select uji.harus_ditolak('perintah penyesuaian wajib beralasan (celah N2)',
  $$insert into fakta.perintah_hrd (asal, jenis, id_karyawan, nilai) values ('chat', 'penyesuaian', '10001', '200000')$$);
select uji.harus_diterima('perintah sakit lalu pembatalannya dicatat sebagai baris baru',
  $$insert into fakta.perintah_hrd (asal, jenis, id_karyawan, tanggal_mulai, tanggal_selesai) values ('chat', 'sakit', '10001', '2026-02-19', '2026-02-19');
    insert into fakta.perintah_hrd (asal, jenis, membatalkan, alasan) select 'chat', 'batalkan_perintah', max(id), 'salah orang' from fakta.perintah_hrd$$);

-- Pemetaan ID mesin (celah M5, M6; kasus F06, F07)
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA1', '10001', '10001', '2026-01-01');
select uji.harus_diterima('kasus F07: satu karyawan boleh punya dua ID mesin',
  $$insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA1', '90001', '10001', '2026-03-01')$$);
select uji.harus_ditolak('satu ID mesin tidak boleh dipakai dua karyawan pada waktu yang sama',
  $$insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA1', '90001', '10002', '2026-03-05')$$);

-- Aturan 6: waktu mesin dan koreksi jam (kasus F04)
insert into induk.koreksi_jam_mesin (mesin, selisih_menit, berlaku_dari, berlaku_sampai) values ('MA2', 4, '2026-03-01', '2026-03-11');
select uji.sama('kasus F04: jam mesin 07:08 dengan koreksi 4 menit menjadi 07:04 WIB',
  induk.waktu_baku('MA2', '2026-03-05 07:08:00'), '2026-03-05 07:04:00+07'::timestamptz);
select uji.sama('koreksi jam tidak berlaku di luar rentangnya',
  induk.waktu_baku('MA2', '2026-03-11 07:08:00'), '2026-03-11 07:08:00+07'::timestamptz);
insert into induk.mesin (kode, nama, zona) values ('MW', 'Cabang WITA', 'Asia/Makassar');
select uji.sama('mesin WITA: 08:00 lokal = 07:00 WIB',
  induk.waktu_baku('MW', '2026-03-05 08:00:00'), '2026-03-05 07:00:00+07'::timestamptz);

-- Aturan 5: uang bilangan bulat, pembulatan sekali di akhir (kasus jebakan D)
select uji.sama('kasus D01: lembur 2 jam hari kerja = Rp80.925',
  hitung.bagi_bulat((15 * 60 + 20 * 60)::numeric * 4000000, 173 * 60 * 10), 80925::bigint);
select uji.sama('kasus D03: lembur 90 menit = Rp57.803',
  hitung.bagi_bulat((15 * 60 + 20 * 30)::numeric * 4000000, 173 * 60 * 10), 57803::bigint);
select uji.sama('kasus D06: lembur libur 8 jam pola 6 hari = Rp393.064',
  hitung.bagi_bulat((20 * 7 * 60 + 30 * 60)::numeric * 4000000, 173 * 60 * 10), 393064::bigint);
select uji.sama('kasus D08: lembur libur 10 jam pola 5 hari = Rp531.792',
  hitung.bagi_bulat((20 * 8 * 60 + 30 * 60 + 40 * 60)::numeric * 4000000, 173 * 60 * 10), 531792::bigint);
select uji.sama('kasus D11: dasar 75% (Rp3.000.000), lembur 2 jam = Rp60.694',
  hitung.bagi_bulat((15 * 60 + 20 * 60)::numeric * hitung.persen_dari(4000000, 7500), 173 * 60 * 10), 60694::bigint);
select uji.sama('kasus E05: BPJS Kesehatan 1% dari batas Rp12.000.000 = Rp120.000',
  hitung.persen_dari(least(15000000, 12000000), 100), 120000::bigint);
select uji.sama('kasus E04: PPh 21 TER 2,5% dari bruto Rp10.454.000 = Rp261.350',
  hitung.persen_dari(10454000, 250), 261350::bigint);
select uji.sama('pembulatan tepat setengah naik', hitung.bagi_bulat(5, 2), 3::bigint);
select uji.sama('pembulatan setengah negatif menjauhi nol', hitung.bagi_bulat(-5, 2), -3::bigint);

-- Alur status periode (kontrak data bagian 6)
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2026-01-21', '2026-02-20', '2026-02-25');
select uji.harus_ditolak('periode: tidak boleh langsung dirilis dari terbuka',
  $$select fakta.ubah_status_periode((select id from fakta.periode), 'dirilis', 'hrd', 'uji')$$);
select uji.harus_ditolak('periode: status tidak boleh diubah langsung tanpa fungsi',
  $$update fakta.periode set status = 'dikunci'$$);
select uji.harus_ditolak('periode: HRD tidak boleh menjalankan langkah milik sistem',
  $$select fakta.ubah_status_periode((select id from fakta.periode), 'menunggu_data', 'hrd', 'uji')$$);
select uji.harus_diterima('periode: alur sah terbuka → menunggu_data → dihitung → diajukan → disetujui → dirilis → dikunci',
  $$select fakta.ubah_status_periode((select id from fakta.periode), 'menunggu_data', 'sistem', 'uji');
    select fakta.ubah_status_periode((select id from fakta.periode), 'dihitung', 'sistem', 'uji');
    select fakta.ubah_status_periode((select id from fakta.periode), 'diajukan', 'hrd', 'uji');
    select fakta.ubah_status_periode((select id from fakta.periode), 'disetujui', 'bos', 'uji');
    select fakta.ubah_status_periode((select id from fakta.periode), 'dirilis', 'hrd', 'uji');
    select fakta.ubah_status_periode((select id from fakta.periode), 'dikunci', 'sistem', 'uji')$$);
select uji.sama('periode: setiap perpindahan status tercatat', (select count(*) from fakta.riwayat_status_periode)::int, 6);
select uji.harus_ditolak('periode yang sudah dikunci tidak bisa dibuka lagi',
  $$select fakta.ubah_status_periode((select id from fakta.periode), 'dihitung', 'hrd', 'uji')$$);
select uji.harus_ditolak('periode tidak boleh tumpang tindih',
  $$insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2026-02-20', '2026-03-20', '2026-03-25')$$);

-- Aturan pengaturan (PRD bagian 11)
select uji.harus_ditolak('pengaturan: nilai di luar pilihan ditolak',
  $$insert into aturan.pengaturan (kunci, nilai, berlaku_dari) values ('lembur', 'kadang-kadang', '2026-01-01')$$);
select uji.harus_ditolak('pengaturan: kunci yang tidak terdaftar ditolak',
  $$insert into aturan.pengaturan (kunci, nilai, berlaku_dari) values ('gaji_dobel', 'ya', '2026-01-01')$$);
select uji.harus_ditolak('pengaturan angka harus bilangan bulat',
  $$insert into aturan.pengaturan (kunci, nilai, berlaku_dari) values ('ambang_tanpa_tap_massal', 'separuh', '2026-01-01')$$);
select uji.harus_diterima('pengaturan sah per divisi',
  $$insert into aturan.pengaturan (kunci, cakupan, nilai, berlaku_dari) values ('lembur', 'PRD', 'wajib_perintah', '2026-01-01')$$);
select uji.harus_ditolak('denda tanpa dasar pasal ditolak (celah C2)',
  $$insert into aturan.tingkat_denda (jenis, dari_menit, sampai_menit, nominal, berlaku_dari) values ('telat', 6, 30, 15000, '2026-01-01')$$);
select uji.harus_ditolak('tarif TER dengan rentang penghasilan tumpang tindih ditolak',
  $$insert into aturan.tarif_ter (kategori, bruto_dari, bruto_sampai, persen, berlaku_dari) values ('A', 0, 5400001, 0, '2026-01-01');
    insert into aturan.tarif_ter (kategori, bruto_dari, bruto_sampai, persen, berlaku_dari) values ('A', 5000000, 5650001, 25, '2026-01-01')$$);
select uji.harus_ditolak('THR tidak boleh dibayar setelah hari raya',
  $$insert into aturan.thr (tanggal_bayar, hari_raya, cara_prorata, berlaku_dari) values ('2026-03-25', '2026-03-21', 'bulan_penuh', '2026-01-01')$$);

rollback;
