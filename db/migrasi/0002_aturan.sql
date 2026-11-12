-- 0002_aturan.sql
-- Tabel aturan bertanggal (kontrak data bagian 4, schema aturan).
-- Isi angka aturan pemerintah dan pengaturan perusahaan dimasukkan terpisah, bukan di migrasi.

-- Daftar kunci pengaturan yang sah beserta nilai yang boleh (PRD bagian 11).
create table aturan.daftar_pengaturan (
  kunci text primary key,
  nilai_boleh text[],           -- kosong berarti angka atau teks bebas
  bawaan text not null,
  keterangan text not null
);
insert into aturan.daftar_pengaturan (kunci, nilai_boleh, bawaan, keterangan) values
  ('pola_hari_kerja', array['5_hari', '6_hari_hari_pendek', '6_hari_lebih_dibayar'], '6_hari_hari_pendek', 'Pola hari kerja untuk batas 40 jam seminggu'),
  ('operasi_7_hari', array['ya', 'tidak'], 'tidak', 'Divisi jalan 7 hari dengan libur bergilir'),
  ('lembur', array['otomatis', 'wajib_perintah'], 'otomatis', 'Lembur dihitung otomatis atau wajib ada perintah'),
  ('cuti_bersama', array['dibayar', 'potong_cuti'], 'dibayar', 'Perlakuan cuti bersama'),
  ('pembulatan_tunai', array['100', '500', '1000'], '1000', 'Pembulatan gaji tunai ke bawah, sisa dibawa ke periode berikut'),
  ('premi_hadir', array['hidup', 'mati'], 'mati', 'Premi kehadiran'),
  ('tunjangan_shift_malam', array['hidup', 'mati'], 'mati', 'Tunjangan shift malam'),
  ('uang_makan', array['dihitung', 'di_luar_sistem'], 'dihitung', 'Uang makan dihitung sistem atau dibayar di luar'),
  ('persetujuan_rilis', array['hrd', 'hrd_lalu_bos'], 'hrd', 'Siapa yang menyetujui rilis gaji'),
  ('ambang_tanpa_tap_massal', null, '5000', 'Persen karyawan aktif satu divisi, per-sepuluh-ribu'),
  ('minimal_orang_tanpa_tap_massal', null, '3', 'Ambang hanya berlaku untuk divisi dengan minimal sekian karyawan aktif'),
  ('tanggal_tutup_buku', null, '20', 'Tanggal terakhir periode; 0 berarti akhir bulan'),
  ('tanggal_gajian', null, '25', 'Tanggal bayar gaji'),
  ('kirim_rincian', array['otomatis', 'diminta'], 'otomatis', 'Bawaan pengiriman rincian gaji');

create table aturan.pengaturan (
  id bigint generated always as identity primary key,
  kunci text not null references aturan.daftar_pengaturan (kunci),
  cakupan text not null default 'perusahaan',   -- 'perusahaan', kode divisi, atau 'orang:<id>'
  nilai text not null,
  berlaku_dari date not null,
  berlaku_sampai date,
  oleh text not null default coalesce(nullif(current_setting('app.pengguna', true), ''), current_user),
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (kunci with =, cakupan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

-- Nilai pengaturan harus termasuk daftar nilai yang boleh (PRD bagian 11 aturan 2 dan 3).
create function aturan.cek_nilai_pengaturan() returns trigger
language plpgsql as $$
declare
  v_boleh text[];
begin
  select nilai_boleh into v_boleh from aturan.daftar_pengaturan where kunci = new.kunci;
  if v_boleh is not null and not (new.nilai = any (v_boleh)) then
    raise exception 'Nilai % tidak sah untuk pengaturan %; pilihan: %', new.nilai, new.kunci, array_to_string(v_boleh, ', ')
      using errcode = 'P0001';
  end if;
  if v_boleh is null and new.nilai !~ '^-?[0-9]+$' then
    raise exception 'Pengaturan % harus berupa bilangan bulat', new.kunci using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger cek_nilai before insert on aturan.pengaturan
  for each row execute function aturan.cek_nilai_pengaturan();

create table aturan.jendela_tap (
  id bigint generated always as identity primary key,
  cakupan text not null default 'perusahaan',
  menit_sebelum_masuk integer not null check (menit_sebelum_masuk between 0 and 720),
  menit_sesudah_pulang integer not null check (menit_sesudah_pulang between 0 and 720),
  jarak_minimal_menit integer not null check (jarak_minimal_menit between 0 and 240),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (cakupan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.toleransi (
  id bigint generated always as identity primary key,
  cakupan text not null default 'perusahaan',
  telat_menit integer not null check (telat_menit >= 0),
  pulang_cepat_menit integer not null default 0 check (pulang_cepat_menit >= 0),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (cakupan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.tingkat_denda (
  id bigint generated always as identity primary key,
  cakupan text not null default 'perusahaan',
  jenis text not null check (jenis in ('telat', 'pulang_cepat', 'lupa_tap', 'alpha')),
  dari_menit integer not null default 0 check (dari_menit >= 0),
  sampai_menit integer,
  nominal bigint not null check (nominal >= 0),
  dasar_pasal text not null,    -- celah C2: denda wajib merujuk aturan perusahaan
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  check (sampai_menit is null or sampai_menit > dari_menit),
  exclude using gist (cakupan with =, jenis with =,
                      int4range(dari_menit, sampai_menit, '[)') with &&,
                      daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.lembur (
  id bigint generated always as identity primary key,
  cakupan text not null default 'perusahaan',
  menit_minimal integer not null check (menit_minimal >= 0),
  kelipatan_menit integer not null check (kelipatan_menit between 1 and 60),
  cara_bulat text not null check (cara_bulat in ('bawah', 'terdekat')),
  dasar_upah text not null check (dasar_upah in ('penuh', 'tujuh_puluh_lima')),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (cakupan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.pengali_lembur (
  id bigint generated always as identity primary key,
  jenis_hari text not null check (jenis_hari in ('kerja', 'libur_6_hari', 'libur_6_hari_terpendek', 'libur_5_hari')),
  jam_ke integer not null check (jam_ke between 1 and 24),
  pengali_x10 integer not null check (pengali_x10 > 0),   -- 1,5 kali disimpan 15
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (jenis_hari with =, jam_ke with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.bpjs (
  id bigint generated always as identity primary key,
  program text not null check (program in ('kesehatan', 'jht', 'jp', 'jkk', 'jkm')),
  bagian text not null check (bagian in ('karyawan', 'perusahaan')),
  persen integer not null check (persen between 0 and 10000),
  batas_atas bigint,
  batas_bawah bigint,
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (program with =, bagian with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.tarif_ter (
  id bigint generated always as identity primary key,
  kategori text not null check (kategori in ('A', 'B', 'C')),
  bruto_dari bigint not null check (bruto_dari >= 0),
  bruto_sampai bigint,
  persen integer not null check (persen between 0 and 10000),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  check (bruto_sampai is null or bruto_sampai > bruto_dari),
  exclude using gist (kategori with =, int8range(bruto_dari, bruto_sampai, '[)') with &&,
                      daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.ptkp (
  id bigint generated always as identity primary key,
  status text not null check (status in ('TK/0', 'TK/1', 'TK/2', 'TK/3', 'K/0', 'K/1', 'K/2', 'K/3')),
  kategori_ter text not null check (kategori_ter in ('A', 'B', 'C')),
  nilai_setahun bigint not null check (nilai_setahun > 0),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (status with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.upah_minimum (
  id bigint generated always as identity primary key,
  wilayah text not null,
  nilai bigint not null check (nilai > 0),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (wilayah with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.thr (
  id bigint generated always as identity primary key,
  tanggal_bayar date not null,
  hari_raya date not null,
  cara_prorata text not null check (cara_prorata in ('bulan_penuh', 'hari')),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (tanggal_bayar <= hari_raya),
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.komponen_lain (
  id bigint generated always as identity primary key,
  kode text not null check (kode in ('uang_makan', 'premi_hadir', 'tunjangan_shift_malam', 'uang_transport')),
  cakupan text not null default 'perusahaan',
  nominal bigint not null check (nominal >= 0),
  satuan text not null check (satuan in ('per_hari', 'per_periode')),
  sifat text not null check (sifat in ('tetap', 'tidak_tetap')),  -- menentukan dasar lembur 100% atau 75% (kasus D11)
  syarat text,
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (kode with =, cakupan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.cuti (
  id bigint generated always as identity primary key,
  cakupan text not null default 'perusahaan',
  jatah_hari integer not null check (jatah_hari >= 0),
  berlaku_setelah_bulan integer not null default 12 check (berlaku_setelah_bulan >= 0),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (cakupan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table aturan.batas_potongan (
  id bigint generated always as identity primary key,
  persen integer not null check (persen between 0 and 10000),
  komponen text[] not null,
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

-- Penjaga bertanggal dan catatan perubahan untuk seluruh schema aturan.
do $$
declare
  t record;
begin
  for t in select table_schema || '.' || table_name as nama
           from information_schema.columns
           where table_schema = 'aturan' and column_name = 'berlaku_sampai' loop
    execute format('create trigger jaga_bertanggal before update or delete on %s for each row execute function jejak.jaga_bertanggal()', t.nama);
  end loop;
  for t in select table_schema || '.' || table_name as nama
           from information_schema.tables
           where table_schema = 'aturan' and table_type = 'BASE TABLE' loop
    execute format('create trigger catat_perubahan after insert or update or delete on %s for each row execute function jejak.catat_perubahan()', t.nama);
  end loop;
end $$;
