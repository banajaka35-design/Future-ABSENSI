-- 0001_pondasi.sql
-- Pondasi gudang data sesuai docs/kontrak-data.md v1.0:
-- schema, akses tertutup, catatan perubahan, fakta hanya bertambah,
-- pola bertanggal, tabel induk dan fakta, alur status periode, fungsi dasar.
-- Migrasi hanya maju; file ini tidak boleh diedit setelah dipasang.

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;

create schema induk;
create schema aturan;
create schema fakta;
create schema hitung;
create schema jejak;
create schema api;

-- Aturan dasar 7: tidak ada tabel yang terbuka langsung ke internet.
revoke all on schema induk, aturan, fakta, hitung, jejak from public;
do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on schema induk, aturan, fakta, hitung, jejak from %I', r);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Catatan perubahan dan penjaga
-- ---------------------------------------------------------------------------

create table jejak.perubahan (
  id bigint generated always as identity primary key,
  waktu timestamptz not null default now(),
  oleh text not null default coalesce(nullif(current_setting('app.pengguna', true), ''), current_user),
  tabel text not null,
  aksi text not null,
  data_lama jsonb,
  data_baru jsonb
);

create function jejak.catat_perubahan() returns trigger
language plpgsql as $$
begin
  insert into jejak.perubahan (tabel, aksi, data_lama, data_baru)
  values (tg_table_schema || '.' || tg_table_name, tg_op,
          case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

-- Aturan dasar 2: fakta hanya bertambah.
create function jejak.tolak_ubah() returns trigger
language plpgsql as $$
begin
  raise exception 'Tabel %.% hanya boleh ditambah; koreksi dicatat sebagai baris baru', tg_table_schema, tg_table_name
    using errcode = 'P0001';
end $$;

-- Aturan dasar 4: baris bertanggal hanya boleh ditutup (mengisi berlaku_sampai), tidak diubah atau dihapus.
create function jejak.jaga_bertanggal() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Baris bertanggal di %.% tidak boleh dihapus; tutup dengan berlaku_sampai', tg_table_schema, tg_table_name
      using errcode = 'P0001';
  end if;
  if old.berlaku_sampai is not null then
    raise exception 'Baris bertanggal yang sudah ditutup tidak boleh diubah' using errcode = 'P0001';
  end if;
  if (to_jsonb(new) - 'berlaku_sampai') is distinct from (to_jsonb(old) - 'berlaku_sampai') then
    raise exception 'Baris bertanggal hanya boleh diubah dengan mengisi berlaku_sampai; nilai baru dicatat sebagai baris baru'
      using errcode = 'P0001';
  end if;
  if new.berlaku_sampai is null then
    raise exception 'berlaku_sampai yang sudah diisi tidak boleh dikosongkan lagi' using errcode = 'P0001';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Schema induk
-- ---------------------------------------------------------------------------

create table induk.mesin (
  kode text primary key,
  nama text not null,
  zona text not null default 'Asia/Jakarta',
  penerjemah text not null default 'ekspor_aplikasi_v1'
);

create table induk.divisi (
  kode text primary key,
  nama text not null,
  pola text not null check (pola in ('rotasi', 'mingguan')),
  jumlah_regu integer not null default 1 check (jumlah_regu >= 1),
  mesin_utama text references induk.mesin (kode)
);

create table induk.karyawan (
  id text primary key check (id ~ '^[0-9A-Za-z]+$'),
  nama text not null check (length(trim(nama)) > 0),
  dibuat timestamptz not null default now()
);

create table induk.karyawan_riwayat (
  id bigint generated always as identity primary key,
  id_karyawan text not null references induk.karyawan (id),
  berlaku_dari date not null,
  berlaku_sampai date,
  divisi text not null references induk.divisi (kode),
  jabatan text,
  tipe_upah text not null default 'bulanan' check (tipe_upah in ('bulanan', 'harian', 'borongan')),
  gaji_pokok bigint not null check (gaji_pokok >= 0),
  tunjangan_tetap bigint not null default 0 check (tunjangan_tetap >= 0),
  ptkp text not null check (ptkp in ('TK/0', 'TK/1', 'TK/2', 'TK/3', 'K/0', 'K/1', 'K/2', 'K/3')),
  cara_bayar text not null check (cara_bayar in ('tunai', 'transfer')),
  rekening_terenkripsi bytea,
  wajib_tap boolean not null default true,
  gaji_rahasia boolean not null default false,
  bpjs_kesehatan boolean not null default true,
  bpjs_ketenagakerjaan boolean not null default true,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (id_karyawan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table induk.status_kerja (
  id bigint generated always as identity primary key,
  id_karyawan text not null references induk.karyawan (id),
  jenis text not null check (jenis in ('mulai', 'berhenti', 'aktif_kembali')),
  tanggal date not null,
  alasan text,
  dibuat timestamptz not null default now()
);

create table induk.pemetaan_id_mesin (
  id bigint generated always as identity primary key,
  mesin text not null references induk.mesin (kode),
  id_mesin text not null check (id_mesin ~ '^[0-9A-Za-z]+$'),
  id_karyawan text not null references induk.karyawan (id),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (mesin with =, id_mesin with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table induk.koreksi_jam_mesin (
  id bigint generated always as identity primary key,
  mesin text not null references induk.mesin (kode),
  selisih_menit integer not null check (selisih_menit between -720 and 720),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (mesin with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table induk.kode_jadwal (
  kode text primary key,
  jam_masuk time not null,
  jam_pulang time not null,
  istirahat_menit integer not null default 60 check (istirahat_menit >= 0),
  istirahat_dibayar boolean not null default false
);

create table induk.pola_rotasi (
  id bigint generated always as identity primary key,
  divisi text not null references induk.divisi (kode),
  siklus text[] not null check (cardinality(siklus) between 1 and 31),
  jangkar date not null,
  geser_per_regu integer not null default 0,
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (divisi with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table induk.jadwal_hari (
  id bigint generated always as identity primary key,
  divisi text not null references induk.divisi (kode),
  regu integer not null default 0,
  hari_ke smallint not null check (hari_ke between 1 and 7),  -- 1 Senin ... 7 Minggu
  kode text references induk.kode_jadwal (kode),             -- kosong berarti libur rutin
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (divisi with =, regu with =, hari_ke with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table induk.penugasan_regu (
  id bigint generated always as identity primary key,
  id_karyawan text not null references induk.karyawan (id),
  regu integer not null check (regu >= 0),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (id_karyawan with =, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);

create table induk.kalender (
  tanggal date not null,
  jenis text not null check (jenis in ('libur_nasional', 'cuti_bersama', 'libur_perusahaan')),
  keterangan text not null,
  primary key (tanggal, jenis)
);

create table induk.pengguna (
  id bigint generated always as identity primary key,
  telegram_id bigint unique,
  peran text not null check (peran in ('hrd', 'bos', 'karyawan', 'demo', 'pembangun')),
  id_karyawan text references induk.karyawan (id),
  pin_tersamar text,
  aktif boolean not null default true,
  dibuat timestamptz not null default now()
);

create table induk.kode_daftar (
  kode text primary key check (length(kode) >= 8),
  id_karyawan text not null references induk.karyawan (id),
  kedaluwarsa timestamptz not null,
  dipakai_pada timestamptz,
  dipakai_oleh bigint references induk.pengguna (id)
);

-- ---------------------------------------------------------------------------
-- Schema fakta
-- ---------------------------------------------------------------------------

create table fakta.kiriman_file (
  id bigint generated always as identity primary key,
  diterima timestamptz not null default now(),
  nama_file text not null,
  sidik text not null check (sidik ~ '^[0-9a-f]{64}$'),
  pengirim bigint references induk.pengguna (id),
  nomor_pesan bigint,
  jenis text not null check (jenis in ('tap_mesin', 'data_karyawan', 'perintah_lembur', 'kasbon', 'absen_manual')),
  mesin text references induk.mesin (kode),
  tanggal_awal date,
  tanggal_akhir date,
  jumlah_baris integer check (jumlah_baris >= 0),
  hasil text not null check (hasil in ('diterima', 'ditolak')),
  alasan text,
  check (hasil = 'diterima' or alasan is not null)
);
-- Kasus A07 dan L1: file yang sama atau pesan Telegram yang sama hanya diterima sekali.
create unique index kiriman_file_sidik_diterima on fakta.kiriman_file (sidik) where hasil = 'diterima';
create unique index kiriman_file_nomor_pesan on fakta.kiriman_file (nomor_pesan) where nomor_pesan is not null and hasil = 'diterima';

create table fakta.tap_mentah (
  id bigint generated always as identity primary key,
  kiriman_id bigint not null references fakta.kiriman_file (id),
  mesin text not null references induk.mesin (kode),
  id_mesin text not null,
  jam_lokal timestamp not null,
  status_mesin text,
  baris_asal integer not null,
  unique (kiriman_id, baris_asal)
);
create index tap_mentah_cari on fakta.tap_mentah (mesin, id_mesin, jam_lokal);

create table fakta.perintah_hrd (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  oleh bigint references induk.pengguna (id),
  asal text not null check (asal in ('chat', 'file', 'sistem')),
  jenis text not null check (jenis in (
    'sakit', 'izin', 'cuti', 'dinas_luar', 'absen_manual', 'tukar_shift', 'batalkan_lembur', 'setujui_lembur',
    'penyesuaian', 'kasbon', 'tambah_libur', 'batalkan_kiriman', 'berhenti', 'aktif_kembali', 'karyawan_baru',
    'mutasi', 'ubah_gaji', 'batalkan_perintah')),
  id_karyawan text references induk.karyawan (id),
  divisi text references induk.divisi (kode),
  tanggal_mulai date,
  tanggal_selesai date,
  nilai text,
  alasan text,
  membatalkan bigint references fakta.perintah_hrd (id),
  check (tanggal_selesai is null or tanggal_mulai is null or tanggal_selesai >= tanggal_mulai),
  check (jenis <> 'penyesuaian' or alasan is not null),
  check (jenis <> 'batalkan_perintah' or membatalkan is not null)
);

create table fakta.persetujuan (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  perihal text not null check (perihal in ('tukar_shift', 'lembur', 'penyesuaian', 'rilis', 'ganti_rekening')),
  rujukan text not null,
  penyetuju bigint not null references induk.pengguna (id),
  keputusan text not null check (keputusan in ('setuju', 'tolak')),
  catatan text
);

create table fakta.buku_kasbon (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  id_karyawan text not null references induk.karyawan (id),
  jenis text not null check (jenis in ('pinjam', 'cicilan', 'pelunasan')),
  jumlah bigint not null check (jumlah > 0),
  perintah_id bigint references fakta.perintah_hrd (id)
);

-- Alur status periode (kontrak data bagian 6), disimpan sebagai data supaya bisa diuji.
create table fakta.alur_status_periode (
  dari text not null,
  ke text not null,
  peran text not null check (peran in ('sistem', 'hrd', 'bos')),
  primary key (dari, ke)
);
insert into fakta.alur_status_periode (dari, ke, peran) values
  ('terbuka', 'menunggu_data', 'sistem'),
  ('menunggu_data', 'dihitung', 'sistem'),
  ('dihitung', 'diajukan', 'hrd'),
  ('diajukan', 'dihitung', 'hrd'),
  ('diajukan', 'disetujui', 'bos'),
  ('diajukan', 'dirilis', 'hrd'),
  ('disetujui', 'dirilis', 'hrd'),
  ('dirilis', 'dikunci', 'sistem');

create table fakta.periode (
  id bigint generated always as identity primary key,
  tanggal_awal date not null,
  tanggal_akhir date not null,
  tanggal_bayar date not null,
  status text not null default 'terbuka'
    check (status in ('terbuka', 'menunggu_data', 'dihitung', 'diajukan', 'disetujui', 'dirilis', 'dikunci')),
  check (tanggal_akhir >= tanggal_awal),
  exclude using gist (daterange(tanggal_awal, tanggal_akhir, '[]') with &&)
);

create table fakta.riwayat_status_periode (
  id bigint generated always as identity primary key,
  periode_id bigint not null references fakta.periode (id),
  status_lama text,
  status_baru text not null,
  oleh text not null,
  waktu timestamptz not null default now(),
  alasan text
);

create function fakta.jaga_periode() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Periode tidak boleh dihapus' using errcode = 'P0001';
  end if;
  if coalesce(current_setting('app.ubah_status_periode', true), '') <> 'ya' then
    raise exception 'Status periode hanya boleh diubah lewat fakta.ubah_status_periode()' using errcode = 'P0001';
  end if;
  if (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status') then
    raise exception 'Hanya status periode yang boleh berubah' using errcode = 'P0001';
  end if;
  return new;
end $$;

create function fakta.ubah_status_periode(p_periode bigint, p_status text, p_peran text, p_oleh text, p_alasan text default null)
returns void
language plpgsql as $$
declare
  v_lama text;
begin
  select status into v_lama from fakta.periode where id = p_periode for update;
  if not found then
    raise exception 'Periode % tidak ada', p_periode using errcode = 'P0001';
  end if;
  if not exists (select 1 from fakta.alur_status_periode where dari = v_lama and ke = p_status and peran = p_peran) then
    raise exception 'Status periode tidak boleh berpindah dari % ke % oleh %', v_lama, p_status, p_peran using errcode = 'P0001';
  end if;
  perform set_config('app.ubah_status_periode', 'ya', true);
  update fakta.periode set status = p_status where id = p_periode;
  perform set_config('app.ubah_status_periode', '', true);
  insert into fakta.riwayat_status_periode (periode_id, status_lama, status_baru, oleh, alasan)
  values (p_periode, v_lama, p_status, p_oleh, p_alasan);
end $$;

-- ---------------------------------------------------------------------------
-- Fungsi dasar (kontrak data bagian 7 dan 8)
-- ---------------------------------------------------------------------------

-- Waktu baku = jam lokal mesin dikurangi koreksi jam mesin, dibaca di zona mesin.
create function induk.waktu_baku(p_mesin text, p_jam_lokal timestamp) returns timestamptz
language sql stable as $$
  select (p_jam_lokal - make_interval(mins => coalesce(k.selisih_menit, 0))) at time zone m.zona
  from induk.mesin m
  left join induk.koreksi_jam_mesin k
    on k.mesin = m.kode and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> p_jam_lokal::date
  where m.kode = p_mesin
$$;

-- Nilai riwayat karyawan yang berlaku pada tanggal tertentu.
create function induk.karyawan_pada(p_id text, p_tanggal date) returns induk.karyawan_riwayat
language sql stable as $$
  select * from induk.karyawan_riwayat
  where id_karyawan = p_id and daterange(berlaku_dari, berlaku_sampai, '[)') @> p_tanggal
$$;

-- Pembagian bulat setengah menjauhi nol, dilakukan sekali di akhir tiap komponen.
create function hitung.bagi_bulat(p_pembilang numeric, p_penyebut numeric) returns bigint
language sql immutable strict as $$
  select round(p_pembilang / p_penyebut)::bigint
$$;

-- Persen dalam per-sepuluh-ribu: 1% = 100.
create function hitung.persen_dari(p_dasar bigint, p_persen integer) returns bigint
language sql immutable strict as $$
  select hitung.bagi_bulat(p_dasar::numeric * p_persen, 10000)
$$;

-- ---------------------------------------------------------------------------
-- Pemasangan penjaga
-- ---------------------------------------------------------------------------

do $$
declare
  t record;
begin
  -- Fakta hanya bertambah (periode punya penjaga sendiri).
  for t in select unnest(array['fakta.kiriman_file', 'fakta.tap_mentah', 'fakta.perintah_hrd', 'fakta.persetujuan',
                               'fakta.buku_kasbon', 'fakta.riwayat_status_periode', 'induk.status_kerja',
                               'jejak.perubahan']) as nama loop
    execute format('create trigger tolak_ubah before update or delete on %s for each row execute function jejak.tolak_ubah()', t.nama);
    execute format('create trigger tolak_kosongkan before truncate on %s for each statement execute function jejak.tolak_ubah()', t.nama);
  end loop;

  -- Baris bertanggal di schema induk.
  for t in select table_schema || '.' || table_name as nama
           from information_schema.columns
           where table_schema = 'induk' and column_name = 'berlaku_sampai' loop
    execute format('create trigger jaga_bertanggal before update or delete on %s for each row execute function jejak.jaga_bertanggal()', t.nama);
  end loop;

  -- Catatan perubahan untuk seluruh schema induk.
  for t in select table_schema || '.' || table_name as nama
           from information_schema.tables
           where table_schema = 'induk' and table_type = 'BASE TABLE' loop
    execute format('create trigger catat_perubahan after insert or update or delete on %s for each row execute function jejak.catat_perubahan()', t.nama);
  end loop;
end $$;

create trigger jaga_periode before update or delete on fakta.periode
  for each row execute function fakta.jaga_periode();
create trigger tolak_kosongkan before truncate on fakta.periode
  for each statement execute function jejak.tolak_ubah();
