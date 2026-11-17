-- 0020_login_email.sql
-- Paket 5e: masuk ke halaman unggah lewat kode email (docs/login-email.md, ditulis sebelum file ini).
-- Hasil masuk adalah tautan unggah yang sama dengan paket 5d (fakta.tautan_unggah).
-- Migrasi hanya maju; jangan diedit setelah dipasang.

alter table induk.pengguna add column email text check (email ~ '^[^@[:space:]]+@[^@[:space:]]+$');
create unique index pengguna_email on induk.pengguna (lower(email)) where email is not null;

-- Kode email: hanya sidik SHA-256 dari (email huruf kecil + ':' + kode) yang disimpan.
create table fakta.kode_email (
  id bigint generated always as identity primary key,
  pengguna bigint not null references induk.pengguna (id),
  email text not null,
  sidik text not null check (sidik ~ '^[0-9a-f]{64}$'),
  dibuat timestamptz not null default now(),
  berlaku_sampai timestamptz not null,
  salah integer not null default 0,
  dipakai timestamptz
);
create index kode_email_cari on fakta.kode_email (email, dibuat desc);

-- Terima file mesin atas nama satu akun (inti yang sama untuk bot dan halaman unggah).
-- p: {"nama_file", "sidik", "mesin", "tap", "alasan", "update_id", "asal", "telegram_id"}.
create function fakta.terima_file_atas_nama(p jsonb, p_pengguna bigint) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_hasil jsonb;
  v_awal date;
  v_akhir date;
  v_periode jsonb;
begin
  if not exists (select 1 from induk.mesin m where m.kode = p ->> 'mesin') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Mesin %s tidak dikenal.', p ->> 'mesin'), 'dicatat', false);
  end if;
  perform set_config('app.pengguna', coalesce(p ->> 'asal', 'telegram') || ':' || coalesce(p ->> 'telegram_id', 'pengguna' || p_pengguna), true);
  perform set_config('app.asal_kiriman', case when p ->> 'asal' = 'web' then 'web' else 'telegram' end, true);
  v_hasil := fakta.terima_kiriman(p ->> 'nama_file', p ->> 'sidik', p ->> 'mesin', p -> 'tap', p ->> 'alasan',
                                   now(), (p ->> 'update_id')::bigint, p_pengguna);
  perform set_config('app.asal_kiriman', '', true);
  if v_hasil ->> 'hasil' = 'diterima' then
    v_awal := (v_hasil ->> 'tanggal_awal')::date;
    v_akhir := (v_hasil ->> 'tanggal_akhir')::date;
    insert into fakta.antrean_kerja (periode_id, kiriman_id)
    select x.id, (v_hasil ->> 'kiriman_id')::bigint
    from fakta.periode x
    where (x.tanggal_awal <= v_akhir + 1 and x.tanggal_akhir >= v_awal - 1)
       or (x.tanggal_awal > v_akhir
           and exists (select 1 from fakta.periode y where y.tanggal_awal <= v_akhir + 1 and y.tanggal_akhir >= v_awal - 1)
           and exists (select 1 from hitung.versi_terakhir g where g.periode_id = x.id and g.jenis = 'hitung_gaji'))
    on conflict (periode_id) where status = 'menunggu' do nothing;
    select jsonb_agg(jsonb_build_object('id', x.id, 'awal', x.tanggal_awal, 'akhir', x.tanggal_akhir) order by x.tanggal_awal)
    into v_periode
    from fakta.periode x where x.tanggal_awal <= v_akhir + 1 and x.tanggal_akhir >= v_awal - 1;
  end if;
  return v_hasil || jsonb_build_object('dicatat', true, 'periode', coalesce(v_periode, '[]'::jsonb));
end $$;

-- Bot: pengirim dikenali dari ID Telegram (perilaku sama dengan 0019).
create or replace function api.pintu_terima_file(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pengguna bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
begin
  if v_pengguna is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Akun Anda belum terdaftar sebagai HRD.', 'dicatat', false);
  end if;
  return fakta.terima_file_atas_nama(p, v_pengguna);
end $$;

-- Halaman unggah: pengirim dari tautan, juga untuk akun tanpa ID Telegram (masuk lewat email).
create or replace function api.pintu_terima_web(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u induk.pengguna := fakta.pemilik_tautan(p ->> 'kode_sidik');
begin
  if v_u.id is null then
    return jsonb_build_object('tautan', false);
  end if;
  update fakta.tautan_unggah set jumlah_pakai = jumlah_pakai + 1, terakhir_dipakai = now() where sidik = p ->> 'kode_sidik';
  return fakta.terima_file_atas_nama(
           (p - 'kode_sidik' - 'update_id' - 'telegram_id')
           || jsonb_build_object('asal', 'web', 'telegram_id', v_u.telegram_id), v_u.id)
         || jsonb_build_object('tautan', true, 'telegram_id', v_u.telegram_id);
end $$;

-- Minta kode email. Masukan: {"email", "sidik"} (sidik dari email huruf kecil + ':' + kode, dihitung Edge Function).
-- Keluaran: {"kirim": true, "email"} hanya bila kode dibuat; selain itu {"kirim": false} (halaman tetap menampilkan
-- pesan yang sama). Batas: 3 kode per email per 15 menit, 50 kode per jam untuk seluruh pemasangan.
create function api.pintu_minta_kode_email(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(p ->> 'email'));
  v_u induk.pengguna;
begin
  perform pg_advisory_xact_lock(hashtext('fakta.kode_email'));
  select u.* into v_u from induk.pengguna u
  where lower(u.email) = v_email and u.aktif and u.peran in ('hrd', 'pembangun');
  if v_u.id is null then
    return jsonb_build_object('kirim', false);
  end if;
  if (select count(*) from fakta.kode_email k where k.email = v_email and k.dibuat > now() - interval '15 minutes') >= 3
     or (select count(*) from fakta.kode_email k where k.dibuat > now() - interval '1 hour') >= 50 then
    return jsonb_build_object('kirim', false, 'batas', true);
  end if;
  insert into fakta.kode_email (pengguna, email, sidik, berlaku_sampai)
  values (v_u.id, v_email, p ->> 'sidik', now() + interval '10 minutes');
  return jsonb_build_object('kirim', true, 'email', v_email);
end $$;

-- Tukar kode email dengan tautan unggah. Masukan: {"email", "sidik_kode", "sidik_tautan"}.
-- Keluaran: {"hasil": "masuk", "berlaku_sampai"} | {"hasil": "salah", "sisa"} | {"hasil": "tidak_berlaku"}.
create function api.pintu_tukar_kode_email(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(p ->> 'email'));
  v_k fakta.kode_email;
  v_sampai timestamptz;
begin
  -- Hanya kode terbaru untuk email itu yang dipertimbangkan.
  select k.* into v_k from fakta.kode_email k where k.email = v_email order by k.dibuat desc, k.id desc limit 1 for update;
  if v_k.id is null or v_k.dipakai is not null or v_k.berlaku_sampai <= now() or v_k.salah >= 5
     or not exists (select 1 from induk.pengguna u where u.id = v_k.pengguna and u.aktif and u.peran in ('hrd', 'pembangun')) then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  if v_k.sidik <> p ->> 'sidik_kode' then
    update fakta.kode_email set salah = salah + 1 where id = v_k.id;
    return case when v_k.salah + 1 >= 5 then jsonb_build_object('hasil', 'tidak_berlaku')
                else jsonb_build_object('hasil', 'salah', 'sisa', 5 - v_k.salah - 1) end;
  end if;
  update fakta.kode_email set dipakai = now() where id = v_k.id;
  insert into fakta.tautan_unggah (sidik, pengguna, berlaku_sampai)
  values (p ->> 'sidik_tautan', v_k.pengguna, now() + interval '15 minutes')
  returning berlaku_sampai into v_sampai;
  return jsonb_build_object('hasil', 'masuk', 'berlaku_sampai', v_sampai);
end $$;

grant execute on function api.pintu_minta_kode_email(jsonb), api.pintu_tukar_kode_email(jsonb) to pintu;
