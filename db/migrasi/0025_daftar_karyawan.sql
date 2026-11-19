-- 0025_daftar_karyawan.sql
-- Paket 8a: pendaftaran karyawan lewat bot (docs/rencana-8a.md, ditulis sebelum file ini). PRD v2 celah K1, K8.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- induk.kode_daftar (0001) menyimpan kode apa adanya dan tidak pernah dipakai. Diganti tabel yang menyimpan sidik.
do $$
begin
  if exists (select 1 from induk.kode_daftar) then
    raise exception 'induk.kode_daftar tidak kosong; migrasi 0025 dihentikan' using errcode = 'P0001';
  end if;
end $$;
drop table induk.kode_daftar;

-- Kode daftar: hanya sidik SHA-256 kode yang disimpan; kodenya sendiri hanya ada di pesan Telegram HRD.
create table fakta.kode_daftar (
  id bigint generated always as identity primary key,
  sidik text not null unique check (sidik ~ '^[0-9a-f]{64}$'),
  id_karyawan text not null references induk.karyawan (id),
  dibuat_oleh bigint not null references induk.pengguna (id),
  ganti boolean not null default false,
  dibuat timestamptz not null default now(),
  kedaluwarsa timestamptz not null,
  diminta_oleh_tg bigint,
  diminta_pada timestamptz,
  selesai_pada timestamptz,
  hasil text check (hasil in ('terdaftar', 'dibatalkan', 'diganti')),
  dipakai_oleh bigint references induk.pengguna (id),
  check ((selesai_pada is null) = (hasil is null))
);

-- Setiap /daftar dicatat (berhasil atau salah) untuk batas 5 kode salah per akun Telegram per jam.
create table fakta.percobaan_daftar (
  id bigint generated always as identity primary key,
  telegram_id bigint not null,
  waktu timestamptz not null default now(),
  berhasil boolean not null
);
create index percobaan_daftar_tg on fakta.percobaan_daftar (telegram_id, waktu);

-- Karyawan masih bekerja pada p_hari: status terakhir sampai hari itu bukan 'berhenti' sebelum hari itu
-- (tanggal berhenti = hari kerja terakhir, kasus C11), dan pernah 'mulai'.
create function fakta.karyawan_aktif(p_id text, p_hari date default current_date) returns boolean
language sql stable set search_path = '' as $$
  select coalesce((select not (s.jenis = 'berhenti' and s.tanggal < p_hari)
                   from induk.status_kerja s
                   where s.id_karyawan = p_id and s.tanggal <= p_hari
                   order by s.tanggal desc, s.id desc limit 1), false)
$$;

-- Nama dan divisi sekarang (untuk pesan HRD dan konfirmasi K8; tanpa angka gaji).
create function fakta.identitas_karyawan(p_id text) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', k.id, 'nama', k.nama, 'divisi', coalesce(d.nama, r.divisi))
  from induk.karyawan k
  left join induk.karyawan_riwayat r on r.id_karyawan = k.id
   and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> current_date
  left join induk.divisi d on d.kode = r.divisi
  where k.id = p_id
$$;

-- HRD membuat kode. Masukan: {"telegram_id", "id_karyawan", "ganti", "sidik"}.
-- Keluaran: {"hasil": "dibuat" | "bukan_hrd" | "tidak_ada" | "berhenti" | "sudah_punya_akun", ...}.
create function api.pintu_buat_kode(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id text := upper(trim(p ->> 'id_karyawan'));
  v_ganti boolean := coalesce((p ->> 'ganti')::boolean, false);
  v_sampai timestamptz;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  if not exists (select 1 from induk.karyawan k where k.id = v_id) then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  if not fakta.karyawan_aktif(v_id) then
    return jsonb_build_object('hasil', 'berhenti') || fakta.identitas_karyawan(v_id);
  end if;
  if not v_ganti and exists (select 1 from induk.pengguna u where u.id_karyawan = v_id and u.aktif) then
    return jsonb_build_object('hasil', 'sudah_punya_akun') || fakta.identitas_karyawan(v_id);
  end if;
  -- Kode lama yang belum dipakai untuk ID ini tidak berlaku lagi.
  update fakta.kode_daftar set selesai_pada = now(), hasil = 'diganti'
  where id_karyawan = v_id and selesai_pada is null;
  insert into fakta.kode_daftar (sidik, id_karyawan, dibuat_oleh, ganti, kedaluwarsa)
  values (p ->> 'sidik', v_id, v_hrd, v_ganti, now() + interval '60 minutes')
  returning kedaluwarsa into v_sampai;
  return jsonb_build_object('hasil', 'dibuat', 'ganti', v_ganti, 'berlaku_sampai', v_sampai) || fakta.identitas_karyawan(v_id);
end $$;

-- Karyawan mengetik /daftar. Masukan: {"telegram_id", "sidik"}.
-- Keluaran: {"hasil": "konfirmasi" (+ kode_id, nama, divisi) | "sudah_terdaftar" | "terkunci" (+ sampai) | "salah" (+ sisa)}.
create function api.pintu_daftar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_salah integer;
  v_k fakta.kode_daftar;
begin
  if v_tg is null then
    return jsonb_build_object('hasil', 'salah', 'sisa', 0);
  end if;
  if exists (select 1 from induk.pengguna u where u.telegram_id = v_tg) then
    return jsonb_build_object('hasil', 'sudah_terdaftar');
  end if;
  -- Satu akun Telegram diproses satu per satu, supaya batas 5 kali salah tidak bisa dilewati dengan pesan bersamaan.
  perform pg_advisory_xact_lock(hashtext('fakta.percobaan_daftar'), hashtext(v_tg::text));
  select count(*) into v_salah from fakta.percobaan_daftar
  where telegram_id = v_tg and not berhasil and waktu > now() - interval '1 hour';
  if v_salah >= 5 then
    return jsonb_build_object('hasil', 'terkunci', 'sampai',
      (select min(waktu) + interval '1 hour' from fakta.percobaan_daftar
       where telegram_id = v_tg and not berhasil and waktu > now() - interval '1 hour'));
  end if;
  select k.* into v_k from fakta.kode_daftar k
  where k.sidik = p ->> 'sidik' and k.selesai_pada is null and k.kedaluwarsa > now()
    and (k.diminta_oleh_tg is null or k.diminta_oleh_tg = v_tg)
  for update;
  if v_k.id is null or not fakta.karyawan_aktif(v_k.id_karyawan) then
    insert into fakta.percobaan_daftar (telegram_id, berhasil) values (v_tg, false);
    return jsonb_build_object('hasil', 'salah', 'sisa', greatest(0, 4 - v_salah));
  end if;
  insert into fakta.percobaan_daftar (telegram_id, berhasil) values (v_tg, true);
  update fakta.kode_daftar set diminta_oleh_tg = v_tg, diminta_pada = now() where id = v_k.id;
  return jsonb_build_object('hasil', 'konfirmasi', 'kode_id', v_k.id) || fakta.identitas_karyawan(v_k.id_karyawan);
end $$;

-- Jawaban tombol konfirmasi. Masukan: {"telegram_id", "kode_id", "jawab": "ya" | "bukan"}.
-- Keluaran: {"hasil": "terdaftar" (+ nama, divisi) | "dibatalkan" | "tidak_berlaku" | "sudah_terdaftar" | "sudah_punya_akun"}.
create function api.pintu_daftar_jawab(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_k fakta.kode_daftar;
  v_baru bigint;
begin
  select k.* into v_k from fakta.kode_daftar k
  where k.id = (p ->> 'kode_id')::bigint and k.diminta_oleh_tg = v_tg and k.selesai_pada is null and k.kedaluwarsa > now()
  for update;
  if v_k.id is null then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  if p ->> 'jawab' <> 'ya' then
    update fakta.kode_daftar set selesai_pada = now(), hasil = 'dibatalkan' where id = v_k.id;
    return jsonb_build_object('hasil', 'dibatalkan');
  end if;
  if exists (select 1 from induk.pengguna u where u.telegram_id = v_tg) then
    return jsonb_build_object('hasil', 'sudah_terdaftar');
  end if;
  if not fakta.karyawan_aktif(v_k.id_karyawan) then
    update fakta.kode_daftar set selesai_pada = now(), hasil = 'dibatalkan' where id = v_k.id;
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  perform set_config('app.pengguna', 'daftar-telegram', true);
  if v_k.ganti then
    -- Ganti HP lewat HRD (K1): akun lama dinonaktifkan sesudah akun baru dikonfirmasi.
    update induk.pengguna set aktif = false where id_karyawan = v_k.id_karyawan and aktif;
  elsif exists (select 1 from induk.pengguna u where u.id_karyawan = v_k.id_karyawan and u.aktif) then
    update fakta.kode_daftar set selesai_pada = now(), hasil = 'dibatalkan' where id = v_k.id;
    return jsonb_build_object('hasil', 'sudah_punya_akun');
  end if;
  insert into induk.pengguna (telegram_id, peran, id_karyawan) values (v_tg, 'karyawan', v_k.id_karyawan)
  returning id into v_baru;
  update fakta.kode_daftar set selesai_pada = now(), hasil = 'terdaftar', dipakai_oleh = v_baru where id = v_k.id;
  return jsonb_build_object('hasil', 'terdaftar') || fakta.identitas_karyawan(v_k.id_karyawan);
end $$;

-- Akun apa milik satu akun Telegram (untuk balasan teks). Keluaran: {"peran", "nama"} | {"peran": null}.
create function api.pintu_akun(p jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('peran', u.peran, 'nama', k.nama)
     from induk.pengguna u left join induk.karyawan k on k.id = u.id_karyawan
     where u.telegram_id = (p ->> 'telegram_id')::bigint and u.aktif),
    '{"peran": null}'::jsonb)
$$;

revoke all on function fakta.karyawan_aktif(text, date), fakta.identitas_karyawan(text) from public;
grant execute on function api.pintu_buat_kode(jsonb), api.pintu_daftar(jsonb), api.pintu_daftar_jawab(jsonb),
  api.pintu_akun(jsonb) to pintu;
