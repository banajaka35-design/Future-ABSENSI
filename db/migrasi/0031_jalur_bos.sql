-- 0031_jalur_bos.sql
-- Paket 8d (docs/rencana-8d.md; keputusan pemilik 20 Nov 2026: (a) lewat bot dengan PIN, (i) orang rahasia wajib transfer).
-- Bos dan pembangun melihat total lengkap termasuk orang rahasia (F15, F15b) dengan PIN; setiap lihat tercatat.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- ---------------------------------------------------------------------------
-- Orang rahasia wajib transfer: amplop tunai disiapkan HRD, jadi nominalnya terlihat HRD.
-- ---------------------------------------------------------------------------
alter table induk.karyawan_riwayat
  add constraint rahasia_wajib_transfer check (not (gaji_rahasia and cara_bayar = 'tunai'));

-- ---------------------------------------------------------------------------
-- Akun yang punya PIN: HRD, bos, pembangun (bos untuk total lengkap; persetujuan bos tetap tombol tanpa PIN).
-- ---------------------------------------------------------------------------
create function fakta.akun_pin(p_telegram_id bigint) returns bigint
language sql stable set search_path = '' as $$
  select u.id from induk.pengguna u
  where u.telegram_id = p_telegram_id and u.peran in ('hrd', 'bos', 'pembangun') and u.aktif
$$;

create function fakta.bos_atau_pembangun(p_telegram_id bigint) returns bigint
language sql stable set search_path = '' as $$
  select u.id from induk.pengguna u
  where u.telegram_id = p_telegram_id and u.peran in ('bos', 'pembangun') and u.aktif
$$;

-- /pin: sama dengan 0026, akun bos ikut boleh.
create or replace function api.pintu_atur_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := fakta.akun_pin((p ->> 'telegram_id')::bigint);
  v_ada boolean;
  v_cek text;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  v_ada := (select u.pin_tersamar is not null from induk.pengguna u where u.id = v_hrd);
  if v_ada then
    if p ->> 'pin_lama' is null then
      return jsonb_build_object('hasil', 'perlu_pin_lama');
    end if;
    v_cek := fakta.periksa_pin(v_hrd, p ->> 'pin_lama');
    if v_cek <> 'benar' then
      return jsonb_build_object('hasil', v_cek);
    end if;
  end if;
  if fakta.pin_lemah(coalesce(p ->> 'pin_baru', '')) then
    return jsonb_build_object('hasil', 'lemah');
  end if;
  perform set_config('app.pengguna', 'pin-telegram', true);
  update induk.pengguna set pin_tersamar = extensions.crypt(p ->> 'pin_baru', extensions.gen_salt('bf', 10)) where id = v_hrd;
  return jsonb_build_object('hasil', case when v_ada then 'diganti' else 'dibuat' end);
end $$;

-- Daftar dan hapus PIN (0028): akun bos ikut, supaya bos yang lupa PIN bisa ditolong pembangun.
create or replace function api.pintu_daftar_pin(p jsonb) returns jsonb
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
    from induk.pengguna u where u.aktif and u.peran in ('hrd', 'bos', 'pembangun')), '[]'::jsonb));
end $$;

create or replace function api.pintu_hapus_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_oleh bigint := fakta.pembangun((p ->> 'telegram_id')::bigint);
  v_u induk.pengguna;
begin
  if v_oleh is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  select u.* into v_u from induk.pengguna u
  where u.id = (p ->> 'pengguna_id')::bigint and u.aktif and u.peran in ('hrd', 'bos', 'pembangun') for update;
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
-- Total lengkap (termasuk orang rahasia)
-- ---------------------------------------------------------------------------
create table fakta.lihat_rahasia (
  id bigint generated always as identity primary key,
  pengguna bigint not null references induk.pengguna (id),
  periode_id bigint not null references fakta.periode (id),
  versi_gaji bigint not null references hitung.versi_hitung (id),
  waktu timestamptz not null default now()
);
create trigger tolak_ubah before update or delete on fakta.lihat_rahasia for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.lihat_rahasia for each statement execute function jejak.tolak_ubah();

-- Versi untuk dilihat: yang dirilis bila ada, selain itu versi gaji yang berlaku.
create function fakta.versi_untuk_dilihat(p_periode bigint) returns bigint
language sql stable set search_path = '' as $$
  select coalesce((select r.versi_gaji from fakta.rilis_gaji r where r.periode_id = p_periode), fakta.versi_gaji_berlaku(p_periode))
$$;

-- Periode yang punya hitungan gaji, untuk pilihan "Total lengkap". Masukan: {"telegram_id"}.
create function api.pintu_periode_gaji(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if fakta.bos_atau_pembangun((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  return jsonb_build_object('hasil', 'ada', 'periode', coalesce((
    select jsonb_agg(jsonb_build_object('periode_id', x.id, 'awal', x.tanggal_awal, 'akhir', x.tanggal_akhir, 'status', x.status)
                     order by x.tanggal_awal)
    from fakta.periode x where fakta.versi_untuk_dilihat(x.id) is not null), '[]'::jsonb));
end $$;

-- Masukan: {"telegram_id", "periode_id", "pin"}. Keluaran: {"hasil": "ada" | "bukan_bos" | "belum_ada_pin" | "pin_salah" |
-- "terkunci" | "tidak_ada", ...isi periode, "status", "lengkap": {orang, bersih, dibayar, transfer, tunai},
-- "terlihat": {orang, bersih, transfer, tunai}, "daftar_rahasia": [{id, nama, bersih, dibayar, cara_bayar}]}.
create function api.pintu_total_lengkap(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u bigint := fakta.bos_atau_pembangun((p ->> 'telegram_id')::bigint);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_versi bigint;
  v_pin text;
  v_lengkap jsonb;
  v_rahasia jsonb;
begin
  if v_u is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  v_pin := fakta.periksa_pin(v_u, p ->> 'pin');
  if v_pin <> 'benar' then
    return jsonb_build_object('hasil', case v_pin when 'belum_ada' then 'belum_ada_pin' when 'salah' then 'pin_salah' else v_pin end);
  end if;
  v_versi := fakta.versi_untuk_dilihat(v_id);
  if v_versi is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  with g as (
    select g.id_karyawan, g.gaji_bersih, g.dibayar, fakta.rahasia_di_periode(g.id_karyawan, v_id) as rahasia,
           (select r.cara_bayar from induk.karyawan_riwayat r, fakta.periode x where x.id = v_id and r.id_karyawan = g.id_karyawan
              and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> x.tanggal_akhir) as cara
    from hitung.ringkasan_gaji g where g.versi_id = v_versi
  )
  select jsonb_build_object('orang', count(*), 'bersih', coalesce(sum(gaji_bersih), 0), 'dibayar', coalesce(sum(dibayar), 0),
                            'transfer', coalesce(sum(dibayar) filter (where cara = 'transfer'), 0),
                            'tunai', coalesce(sum(dibayar) filter (where cara = 'tunai'), 0)),
         coalesce(jsonb_agg(jsonb_build_object('id', id_karyawan, 'nama', (select k.nama from induk.karyawan k where k.id = g.id_karyawan),
                                               'bersih', gaji_bersih, 'dibayar', dibayar, 'cara_bayar', cara)
                            order by id_karyawan) filter (where rahasia), '[]'::jsonb)
    into v_lengkap, v_rahasia
  from g;
  insert into fakta.lihat_rahasia (pengguna, periode_id, versi_gaji) values (v_u, v_id, v_versi);
  return jsonb_build_object('hasil', 'ada', 'status', (select x.status from fakta.periode x where x.id = v_id),
                            'lengkap', v_lengkap, 'terlihat', hitung.ringkasan_rilis(v_versi), 'daftar_rahasia', v_rahasia)
         || fakta.isi_periode(v_id);
end $$;

-- ---------------------------------------------------------------------------
-- Menunggu PIN (0028): aksi "lengkap" untuk bos dan pembangun.
-- ---------------------------------------------------------------------------
alter table fakta.tunggu_pin drop constraint tunggu_pin_aksi_check;
alter table fakta.tunggu_pin add constraint tunggu_pin_aksi_check check (aksi in ('rilis', 'setujui', 'tolak', 'lengkap'));

create or replace function api.pintu_minta_pin(p jsonb) returns jsonb
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
  if v_aksi = 'lengkap' and fakta.bos_atau_pembangun(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  if v_aksi is null or v_aksi not in ('rilis', 'setujui', 'tolak', 'lengkap')
     or not exists (select 1 from fakta.periode x where x.id = (p ->> 'periode_id')::bigint) then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  insert into fakta.tunggu_pin (telegram_id, aksi, periode_id, batas)
  values (v_tg, v_aksi, (p ->> 'periode_id')::bigint, now() + interval '5 minutes')
  on conflict (telegram_id) do update set aksi = excluded.aksi, periode_id = excluded.periode_id, batas = excluded.batas;
  return jsonb_build_object('hasil', 'menunggu', 'aksi', v_aksi, 'periode_id', (p ->> 'periode_id')::bigint);
end $$;

revoke all on function fakta.akun_pin(bigint), fakta.bos_atau_pembangun(bigint), fakta.versi_untuk_dilihat(bigint) from public;
grant execute on function api.pintu_periode_gaji(jsonb), api.pintu_total_lengkap(jsonb) to pintu;
