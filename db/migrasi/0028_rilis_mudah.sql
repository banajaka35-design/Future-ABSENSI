-- 0028_rilis_mudah.sql
-- Paket 8b-3 (docs/rencana-8b-3.md): urutan rilis, batal pengajuan, hapus PIN, undangan akun HRD/bos,
-- menunggu PIN sesudah tombol, pemberitahuan rilis/batal, pengingat harian ke bos, teks status untuk Sheets dan demo.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- ---------------------------------------------------------------------------
-- Urutan rilis (temuan 1): PPh masa terakhir memakai hasil periode sebelumnya di tahun yang sama (migrasi 0013),
-- jadi periode hanya boleh diajukan dan dirilis bila semua periode sebelumnya sudah dirilis atau dikunci.
-- ---------------------------------------------------------------------------

-- Periode sebelumnya yang paling awal dan belum dirilis/dikunci; null bila tidak ada.
create function fakta.periode_menunggu(p_periode bigint) returns bigint
language sql stable set search_path = '' as $$
  select x.id from fakta.periode x
  where x.tanggal_awal < (select p.tanggal_awal from fakta.periode p where p.id = p_periode)
    and x.status not in ('dirilis', 'dikunci')
  order by x.tanggal_awal limit 1
$$;

-- Teks status rilis satu periode, satu sumber untuk Sheets (kolom "Status rilis") dan halaman demo.
create function fakta.status_rilis_teks(p_periode bigint) returns text
language sql stable set search_path = '' as $$
  select case p.status
           when 'dirilis' then 'Dirilis'
           when 'dikunci' then 'Dikunci'
           when 'disetujui' then 'Disetujui, menunggu rilis'
           when 'diajukan' then case when fakta.perlu_bos() then 'Diajukan, menunggu persetujuan' else 'Diajukan, menunggu rilis' end
           when 'dihitung' then
             case when fakta.periode_menunggu(p.id) is not null
                    then 'Belum bisa diajukan: rilis dulu periode no. ' || fakta.periode_menunggu(p.id)
                  when not hitung.periode_bisa_diajukan(p.id) then 'Belum bisa diajukan: PPh masa terakhir tertahan'
                  else 'Bisa diajukan' end
           else 'Belum dihitung' end
  from fakta.periode p where p.id = p_periode
$$;

-- Daftar periode untuk /ajukan dan /rilis. Sama dengan 0027, ditambah "menunggu" per periode (urutan) dan
-- "tertahan_urutan": periode yang sudah bisa diajukan menurut PPh tetapi menunggu periode sebelumnya.
create or replace function api.pintu_daftar_periode(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if api.pintu_hrd((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  return jsonb_build_object('hasil', 'ada', 'perlu_bos', fakta.perlu_bos(),
    'pembangun', exists (select 1 from induk.pengguna u where u.telegram_id = (p ->> 'telegram_id')::bigint
                         and u.peran = 'pembangun' and u.aktif),
    'periode', coalesce((
      select jsonb_agg(fakta.isi_periode(x.id) || jsonb_build_object('menunggu', fakta.periode_menunggu(x.id))
                       order by x.tanggal_awal)
      from fakta.periode x
      where case when p ->> 'untuk' = 'rilis' then x.status in ('diajukan', 'disetujui')
                 else x.status = 'dihitung' and fakta.versi_gaji_berlaku(x.id) is not null
                      and hitung.periode_bisa_diajukan(x.id) and fakta.periode_menunggu(x.id) is null end), '[]'::jsonb),
    'tertahan_urutan', case when p ->> 'untuk' = 'rilis' then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('periode_id', x.id, 'awal', x.tanggal_awal, 'akhir', x.tanggal_akhir,
                                          'menunggu', fakta.periode_menunggu(x.id)) order by x.tanggal_awal)
      from fakta.periode x
      where x.status = 'dihitung' and fakta.versi_gaji_berlaku(x.id) is not null
        and hitung.periode_bisa_diajukan(x.id) and fakta.periode_menunggu(x.id) is not null), '[]'::jsonb) end);
end $$;

-- Ajukan: sama dengan 0027, ditambah syarat urutan (hasil "tunggu_periode", "menunggu").
create or replace function api.pintu_ajukan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_versi bigint;
  v_tunggu bigint;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  v_versi := fakta.versi_gaji_berlaku(v_id);
  if v_periode.id is null or v_periode.status <> 'dihitung' or v_versi is null or not hitung.periode_bisa_diajukan(v_id) then
    return jsonb_build_object('hasil', 'tidak_bisa', 'status', v_periode.status);
  end if;
  v_tunggu := fakta.periode_menunggu(v_id);
  if v_tunggu is not null then
    return jsonb_build_object('hasil', 'tunggu_periode', 'menunggu', v_tunggu) || fakta.isi_periode(v_id);
  end if;
  if v_versi <> (p ->> 'versi_gaji')::bigint then
    return jsonb_build_object('hasil', 'versi_berubah') || fakta.isi_periode(v_id);
  end if;
  insert into fakta.pengajuan_rilis (periode_id, versi_gaji, diajukan_oleh) values (v_id, v_versi, v_hrd);
  perform fakta.ubah_status_periode(v_id, 'diajukan', 'hrd', 'pengguna ' || v_hrd, 'diajukan lewat Telegram');
  return jsonb_build_object('hasil', 'diajukan', 'perlu_bos', fakta.perlu_bos(),
                            'bos', to_jsonb(fakta.penerima(array['bos'])),
                            'pembangun', to_jsonb(fakta.penerima(array['pembangun']))) || fakta.isi_periode(v_id);
end $$;

-- Akun lain yang diberi kabar (HRD, bos, pembangun), tanpa akun yang sedang bertindak.
create function fakta.penerima_kabar(p_kecuali bigint) returns bigint[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(t order by t), '{}') from unnest(fakta.penerima(array['hrd', 'bos', 'pembangun'])) t
  where t is distinct from p_kecuali
$$;

-- Rilis: sama dengan 0026, ditambah syarat urutan dan daftar penerima kabar ("kabari").
create or replace function api.pintu_rilis(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_hrd bigint := api.pintu_hrd(v_tg);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_aju fakta.pengajuan_rilis;
  v_pin text;
  v_tunggu bigint;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  v_pin := fakta.periksa_pin(v_hrd, p ->> 'pin');
  if v_pin <> 'benar' then
    return jsonb_build_object('hasil', case v_pin when 'belum_ada' then 'belum_ada_pin' when 'salah' then 'pin_salah' else v_pin end);
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  if v_periode.id is null or v_periode.status not in ('diajukan', 'disetujui') then
    return jsonb_build_object('hasil', 'tidak_bisa', 'status', v_periode.status);
  end if;
  if fakta.perlu_bos() and v_periode.status <> 'disetujui' then
    return jsonb_build_object('hasil', 'belum_disetujui') || fakta.isi_periode(v_id);
  end if;
  v_tunggu := fakta.periode_menunggu(v_id);
  if v_tunggu is not null then
    return jsonb_build_object('hasil', 'tunggu_periode', 'menunggu', v_tunggu) || fakta.isi_periode(v_id);
  end if;
  select a.* into v_aju from fakta.pengajuan_rilis a where a.periode_id = v_id order by a.id desc limit 1;
  if v_aju.versi_gaji is distinct from fakta.versi_gaji_berlaku(v_id) or not hitung.periode_bisa_diajukan(v_id) then
    return jsonb_build_object('hasil', 'versi_berubah') || fakta.isi_periode(v_id);
  end if;
  insert into fakta.rilis_gaji (periode_id, versi_gaji, pengajuan_id, dirilis_oleh) values (v_id, v_aju.versi_gaji, v_aju.id, v_hrd);
  perform fakta.ubah_status_periode(v_id, 'dirilis', 'hrd', 'pengguna ' || v_hrd, 'dirilis lewat Telegram dengan PIN');
  return jsonb_build_object('hasil', 'dirilis', 'kabari', to_jsonb(fakta.penerima_kabar(v_tg))) || fakta.isi_periode(v_id);
end $$;

-- ---------------------------------------------------------------------------
-- Batal pengajuan (temuan 5). HRD/pembangun: diajukan atau disetujui -> dihitung.
-- ---------------------------------------------------------------------------
insert into fakta.alur_status_periode (dari, ke, peran) values ('disetujui', 'dihitung', 'hrd');

-- Masukan: {"telegram_id", "periode_id"}. Keluaran: {"hasil": "dibatalkan" | "bukan_hrd" | "tidak_bisa", "kabari", ...}.
create function api.pintu_batal(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_hrd bigint := api.pintu_hrd(v_tg);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_peran text;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  if v_periode.id is null or v_periode.status not in ('diajukan', 'disetujui') then
    return jsonb_build_object('hasil', 'tidak_bisa', 'status', v_periode.status);
  end if;
  v_peran := (select u.peran from induk.pengguna u where u.id = v_hrd);
  perform fakta.ubah_status_periode(v_id, 'dihitung', 'hrd', 'pengguna ' || v_hrd, 'dibatalkan ' || v_peran);
  return jsonb_build_object('hasil', 'dibatalkan', 'oleh', v_peran, 'kabari', to_jsonb(fakta.penerima_kabar(v_tg)))
         || fakta.isi_periode(v_id);
end $$;

-- ---------------------------------------------------------------------------
-- Hapus PIN oleh pembangun (temuan 2). Percobaan PIN salah sebelum dihapus tidak dihitung lagi.
-- ---------------------------------------------------------------------------
create table fakta.hapus_pin (
  id bigint generated always as identity primary key,
  pengguna bigint not null references induk.pengguna (id),
  oleh bigint not null references induk.pengguna (id),
  waktu timestamptz not null default now()
);
create trigger tolak_ubah before update or delete on fakta.hapus_pin for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.hapus_pin for each statement execute function jejak.tolak_ubah();

-- Sama dengan 0026, kecuali percobaan salah dihitung sejak PIN terakhir dihapus.
create or replace function fakta.periksa_pin(p_pengguna bigint, p_pin text) returns text
language plpgsql set search_path = '' as $$
declare
  v_tersamar text := (select u.pin_tersamar from induk.pengguna u where u.id = p_pengguna);
  v_sejak timestamptz := greatest(now() - interval '1 hour',
                                  (select max(h.waktu) from fakta.hapus_pin h where h.pengguna = p_pengguna));
begin
  if v_tersamar is null then
    return 'belum_ada';
  end if;
  perform pg_advisory_xact_lock(hashtext('fakta.percobaan_pin'), p_pengguna::integer);
  if (select count(*) from fakta.percobaan_pin p
      where p.pengguna = p_pengguna and not p.berhasil and p.waktu > v_sejak) >= 5 then
    return 'terkunci';
  end if;
  if coalesce(p_pin, '') ~ '^[0-9]{6}$' and extensions.crypt(p_pin, v_tersamar) = v_tersamar then
    insert into fakta.percobaan_pin (pengguna, berhasil) values (p_pengguna, true);
    return 'benar';
  end if;
  insert into fakta.percobaan_pin (pengguna, berhasil) values (p_pengguna, false);
  return 'salah';
end $$;

create function fakta.pembangun(p_telegram_id bigint) returns bigint
language sql stable set search_path = '' as $$
  select u.id from induk.pengguna u where u.telegram_id = p_telegram_id and u.peran = 'pembangun' and u.aktif
$$;

-- Daftar akun yang punya hak PIN (HRD, pembangun). Masukan: {"telegram_id"}.
-- Keluaran: {"hasil": "ada" | "bukan_pembangun", "akun": [{"id", "peran", "label", "punya_pin", "terkunci"}]}.
create function api.pintu_daftar_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if fakta.pembangun((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  return jsonb_build_object('hasil', 'ada', 'akun', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', u.id, 'peran', u.peran, 'punya_pin', u.pin_tersamar is not null,
             'label', coalesce(u.email, 'Telegram ...' || right(u.telegram_id::text, 4)),
             'sendiri', u.telegram_id = (p ->> 'telegram_id')::bigint) order by u.id)
    from induk.pengguna u where u.aktif and u.peran in ('hrd', 'pembangun')), '[]'::jsonb));
end $$;

-- Masukan: {"telegram_id", "pengguna_id"}. Keluaran: {"hasil": "dihapus" | "bukan_pembangun" | "tidak_ada" | "belum_ada_pin",
-- "telegram_id" (pemilik PIN, untuk diberi tahu), "label"}.
create function api.pintu_hapus_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_oleh bigint := fakta.pembangun((p ->> 'telegram_id')::bigint);
  v_u induk.pengguna;
begin
  if v_oleh is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  select u.* into v_u from induk.pengguna u
  where u.id = (p ->> 'pengguna_id')::bigint and u.aktif and u.peran in ('hrd', 'pembangun') for update;
  if v_u.id is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  if v_u.pin_tersamar is null then
    return jsonb_build_object('hasil', 'belum_ada_pin');
  end if;
  perform set_config('app.pengguna', 'hapus-pin-telegram', true);
  update induk.pengguna set pin_tersamar = null where id = v_u.id;
  insert into fakta.hapus_pin (pengguna, oleh) values (v_u.id, v_oleh);
  return jsonb_build_object('hasil', 'dihapus', 'telegram_id', v_u.telegram_id,
                            'label', coalesce(v_u.email, 'Telegram ...' || right(v_u.telegram_id::text, 4)));
end $$;

-- ---------------------------------------------------------------------------
-- Undangan akun HRD/bos oleh pembangun (temuan 3). Kode sekali pakai 60 menit; hanya sidik SHA-256 disimpan.
-- ---------------------------------------------------------------------------
create table fakta.undangan_akun (
  id bigint generated always as identity primary key,
  sidik text not null unique check (sidik ~ '^[0-9a-f]{64}$'),
  peran text not null check (peran in ('hrd', 'bos')),
  dibuat_oleh bigint not null references induk.pengguna (id),
  dibuat timestamptz not null default now(),
  kedaluwarsa timestamptz not null,
  selesai_pada timestamptz,
  dipakai_oleh bigint references induk.pengguna (id),
  check ((selesai_pada is null) = (dipakai_oleh is null))
);

-- Masukan: {"telegram_id", "peran", "sidik"}. Keluaran: {"hasil": "dibuat" | "bukan_pembangun" | "peran_salah", "berlaku_sampai"}.
create function api.pintu_undang(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_oleh bigint := fakta.pembangun((p ->> 'telegram_id')::bigint);
  v_sampai timestamptz;
begin
  if v_oleh is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  if coalesce(p ->> 'peran', '') not in ('hrd', 'bos') then
    return jsonb_build_object('hasil', 'peran_salah');
  end if;
  insert into fakta.undangan_akun (sidik, peran, dibuat_oleh, kedaluwarsa)
  values (p ->> 'sidik', p ->> 'peran', v_oleh, now() + interval '60 minutes')
  returning kedaluwarsa into v_sampai;
  return jsonb_build_object('hasil', 'dibuat', 'peran', p ->> 'peran', 'berlaku_sampai', v_sampai);
end $$;

-- Masukan: {"telegram_id", "sidik"}. Batas 5 kode salah per jam per akun Telegram, sama dengan /daftar (8a).
-- Keluaran: {"hasil": "terdaftar" (+ peran, pembangun) | "sudah_terdaftar" (+ peran) | "terkunci" | "salah" (+ sisa)}.
create function api.pintu_gabung(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_salah integer;
  v_u fakta.undangan_akun;
  v_baru bigint;
begin
  if v_tg is null then
    return jsonb_build_object('hasil', 'salah', 'sisa', 0);
  end if;
  if exists (select 1 from induk.pengguna u where u.telegram_id = v_tg) then
    return jsonb_build_object('hasil', 'sudah_terdaftar', 'peran', (select u.peran from induk.pengguna u where u.telegram_id = v_tg));
  end if;
  perform pg_advisory_xact_lock(hashtext('fakta.percobaan_daftar'), hashtext(v_tg::text));
  select count(*) into v_salah from fakta.percobaan_daftar
  where telegram_id = v_tg and not berhasil and waktu > now() - interval '1 hour';
  if v_salah >= 5 then
    return jsonb_build_object('hasil', 'terkunci');
  end if;
  select u.* into v_u from fakta.undangan_akun u
  where u.sidik = p ->> 'sidik' and u.selesai_pada is null and u.kedaluwarsa > now() for update;
  if v_u.id is null then
    insert into fakta.percobaan_daftar (telegram_id, berhasil) values (v_tg, false);
    return jsonb_build_object('hasil', 'salah', 'sisa', 4 - v_salah);
  end if;
  insert into fakta.percobaan_daftar (telegram_id, berhasil) values (v_tg, true);
  perform set_config('app.pengguna', 'undangan-telegram', true);
  insert into induk.pengguna (telegram_id, peran) values (v_tg, v_u.peran) returning id into v_baru;
  update fakta.undangan_akun set selesai_pada = now(), dipakai_oleh = v_baru where id = v_u.id;
  return jsonb_build_object('hasil', 'terdaftar', 'peran', v_u.peran,
                            'pembangun', (select u.telegram_id from induk.pengguna u where u.id = v_u.dibuat_oleh));
end $$;

-- ---------------------------------------------------------------------------
-- Menunggu PIN sesudah tombol (temuan 7 dan 8): satu tunggu per akun, berlaku 5 menit.
-- ---------------------------------------------------------------------------
create table fakta.tunggu_pin (
  telegram_id bigint primary key,
  aksi text not null check (aksi in ('rilis', 'setujui', 'tolak')),
  periode_id bigint not null references fakta.periode (id),
  batas timestamptz not null
);

-- Masukan: {"telegram_id", "aksi", "periode_id"}. Keluaran: {"hasil": "menunggu" | "bukan_hrd" | "bukan_pembangun" | "tidak_ada"}.
create function api.pintu_minta_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_aksi text := p ->> 'aksi';
begin
  if v_aksi = 'rilis' and api.pintu_hrd(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  if v_aksi in ('setujui', 'tolak') and fakta.pembangun(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  if v_aksi is null or v_aksi not in ('rilis', 'setujui', 'tolak')
     or not exists (select 1 from fakta.periode x where x.id = (p ->> 'periode_id')::bigint) then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  insert into fakta.tunggu_pin (telegram_id, aksi, periode_id, batas)
  values (v_tg, v_aksi, (p ->> 'periode_id')::bigint, now() + interval '5 minutes')
  on conflict (telegram_id) do update set aksi = excluded.aksi, periode_id = excluded.periode_id, batas = excluded.batas;
  return jsonb_build_object('hasil', 'menunggu', 'aksi', v_aksi, 'periode_id', (p ->> 'periode_id')::bigint);
end $$;

-- Ambil (dan hapus) tunggu PIN yang masih berlaku. Masukan: {"telegram_id"}. Keluaran: {"aksi", "periode_id"} | {}.
create function api.pintu_ambil_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t fakta.tunggu_pin;
begin
  delete from fakta.tunggu_pin t where t.telegram_id = (p ->> 'telegram_id')::bigint returning t.* into v_t;
  delete from fakta.tunggu_pin t where t.batas < now() - interval '1 day';
  if v_t.telegram_id is null or v_t.batas < now() then
    return case when v_t.telegram_id is null then '{}'::jsonb else jsonb_build_object('lewat', true) end;
  end if;
  return jsonb_build_object('aksi', v_t.aksi, 'periode_id', v_t.periode_id);
end $$;

-- ---------------------------------------------------------------------------
-- Pengingat harian ke bos (temuan 5): pengajuan yang masih "diajukan" sejak sebelum hari ini.
-- Dipanggil Edge Function bersama pengingat kirim file (pg_cron 08.00 WIB). Tanpa akun bos -> ke pembangun.
-- Masukan: {"tanggal"}. Keluaran: {"kirim": [{"id", "bos": [..], "pembangun": [..], "pengajuan_id", "sejak", ...isi periode}]}.
-- ---------------------------------------------------------------------------
create function api.pintu_pengingat_rilis(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hari date := coalesce((p ->> 'tanggal')::date, (now() at time zone 'Asia/Jakarta')::date);
  v_bos bigint[] := fakta.penerima(array['bos']);
  v_pembangun bigint[] := case when cardinality(fakta.penerima(array['bos'])) = 0 then fakta.penerima(array['pembangun'])
                               else '{}'::bigint[] end;
  v_kirim jsonb := '[]'::jsonb;
  r record;
  v_id bigint;
begin
  if not fakta.perlu_bos() then
    return jsonb_build_object('kirim', v_kirim);
  end if;
  perform pg_advisory_xact_lock(hashtext('fakta.pemberitahuan'));
  for r in
    select a.id as aju, a.periode_id, (a.waktu at time zone 'Asia/Jakarta')::date as sejak
    from fakta.periode x
    join lateral (select a.* from fakta.pengajuan_rilis a where a.periode_id = x.id order by a.id desc limit 1) a on true
    where x.status = 'diajukan' and (a.waktu at time zone 'Asia/Jakarta')::date < v_hari
    order by x.tanggal_awal
  loop
    insert into fakta.pemberitahuan (kunci, jenis, tingkat, isi, status, penerima)
    values (concat_ws('|', 'pengingat_rilis', r.aju, v_hari), 'pengingat_rilis', 'pengingat',
            jsonb_build_object('pengajuan_id', r.aju, 'periode_id', r.periode_id, 'sejak', r.sejak),
            case when cardinality(v_bos || v_pembangun) > 0 then 'akan_dikirim' else 'dilewati_tanpa_akun_bos' end,
            v_bos || v_pembangun)
    on conflict (kunci) do nothing
    returning id into v_id;
    if v_id is not null and cardinality(v_bos || v_pembangun) > 0 then
      v_kirim := v_kirim || (jsonb_build_object('id', v_id, 'bos', to_jsonb(v_bos), 'pembangun', to_jsonb(v_pembangun),
                                                'sejak', r.sejak) || fakta.isi_periode(r.periode_id));
    end if;
    v_id := null;
  end loop;
  return jsonb_build_object('kirim', v_kirim);
end $$;

-- ---------------------------------------------------------------------------
-- Hak akses
-- ---------------------------------------------------------------------------
revoke all on function fakta.periode_menunggu(bigint), fakta.status_rilis_teks(bigint), fakta.penerima_kabar(bigint),
  fakta.pembangun(bigint) from public;
grant execute on function api.pintu_batal(jsonb), api.pintu_daftar_pin(jsonb), api.pintu_hapus_pin(jsonb),
  api.pintu_undang(jsonb), api.pintu_gabung(jsonb), api.pintu_minta_pin(jsonb),
  api.pintu_ambil_pin(jsonb), api.pintu_pengingat_rilis(jsonb) to pintu;
