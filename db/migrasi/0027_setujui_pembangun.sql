-- 0027_setujui_pembangun.sql
-- Paket 8b-2 (docs/rencana-8b-2.md; keputusan pemilik 19 Nov 2026 16.43 WIB: akun pembangun bisa melakukan semua
-- yang bisa dilakukan akun lain). Akun pembangun boleh menyetujui atau menolak pengajuan rilis seperti bos,
-- tetapi wajib dengan PIN (perintah /setujui <nomor> <PIN> dan /tolak <nomor> <PIN>). Bos tetap memakai tombol.
-- Susunan tabel tidak berubah: langkah status dicatat dengan peran 'bos' (tabel alur hanya mengenal sistem/hrd/bos),
-- pelakunya 'pengguna <id>' dengan alasan "disetujui pembangun"/"ditolak pembangun", dan fakta.persetujuan.catatan
-- berisi 'oleh pembangun'.

-- Persetujuan. Masukan: {"telegram_id", "periode_id", "setuju", "pengajuan_id" (tombol bos), "pin" (pembangun)}.
-- Pembangun tanpa pengajuan_id: pengajuan terakhir periode itu.
-- Keluaran: {"hasil": "disetujui" | "ditolak" | "bukan_bos" | "tidak_berlaku" | "pakai_tombol" | "belum_ada_pin" |
-- "pin_salah" | "terkunci", "oleh": "bos" | "pembangun", "pengaju": telegram_id, ...isi periode}.
create or replace function api.pintu_setujui(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pengguna induk.pengguna;
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_aju fakta.pengajuan_rilis;
  v_setuju boolean := coalesce((p ->> 'setuju')::boolean, false);
  v_pin text;
  v_kata text;
begin
  select u.* into v_pengguna from induk.pengguna u
  where u.telegram_id = (p ->> 'telegram_id')::bigint and u.peran in ('bos', 'pembangun') and u.aktif;
  if v_pengguna.id is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  if v_pengguna.peran = 'pembangun' then
    v_pin := fakta.periksa_pin(v_pengguna.id, p ->> 'pin');
    if v_pin <> 'benar' then
      return jsonb_build_object('hasil', case v_pin when 'belum_ada' then 'belum_ada_pin' when 'salah' then 'pin_salah' else v_pin end);
    end if;
  elsif p ->> 'pengajuan_id' is null then
    -- bos memakai tombol di pesan pengajuan (tanpa PIN)
    return jsonb_build_object('hasil', 'pakai_tombol');
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  select a.* into v_aju from fakta.pengajuan_rilis a where a.periode_id = v_id order by a.id desc limit 1;
  if v_periode.status is distinct from 'diajukan' or v_aju.id is null
     or (p ->> 'pengajuan_id' is not null and v_aju.id is distinct from (p ->> 'pengajuan_id')::bigint)
     or v_aju.versi_gaji is distinct from fakta.versi_gaji_berlaku(v_id) then
    return jsonb_build_object('hasil', 'tidak_berlaku', 'status', v_periode.status);
  end if;
  v_kata := case when v_setuju then 'disetujui ' else 'ditolak ' end || v_pengguna.peran;
  insert into fakta.persetujuan (perihal, rujukan, penyetuju, keputusan, catatan)
  values ('rilis', 'pengajuan_rilis ' || v_aju.id, v_pengguna.id, case when v_setuju then 'setuju' else 'tolak' end,
          case when v_pengguna.peran = 'pembangun' then 'oleh pembangun' end);
  perform fakta.ubah_status_periode(v_id, case when v_setuju then 'disetujui' else 'dihitung' end, 'bos',
                                    'pengguna ' || v_pengguna.id, v_kata);
  return jsonb_build_object('hasil', case when v_setuju then 'disetujui' else 'ditolak' end, 'oleh', v_pengguna.peran,
                            'pengaju', (select u.telegram_id from induk.pengguna u where u.id = v_aju.diajukan_oleh))
         || fakta.isi_periode(v_id);
end $$;

-- Ajukan: sama dengan 0026, ditambah daftar akun pembangun yang ikut menerima pesan pengajuan ("pembangun").
create or replace function api.pintu_ajukan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_versi bigint;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  v_versi := fakta.versi_gaji_berlaku(v_id);
  if v_periode.id is null or v_periode.status <> 'dihitung' or v_versi is null or not hitung.periode_bisa_diajukan(v_id) then
    return jsonb_build_object('hasil', 'tidak_bisa', 'status', v_periode.status);
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

-- Daftar periode: sama dengan 0026, ditambah "pembangun" (akun ini pembangun) supaya bot bisa menampilkan /setujui.
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
    select jsonb_agg(fakta.isi_periode(x.id) order by x.tanggal_awal)
    from fakta.periode x
    where case when p ->> 'untuk' = 'rilis' then x.status in ('diajukan', 'disetujui')
               else x.status = 'dihitung' and fakta.versi_gaji_berlaku(x.id) is not null
                    and hitung.periode_bisa_diajukan(x.id) end), '[]'::jsonb));
end $$;
