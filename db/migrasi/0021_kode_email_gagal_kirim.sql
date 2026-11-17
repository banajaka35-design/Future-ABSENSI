-- 0021_kode_email_gagal_kirim.sql
-- Paket 5e-2: kode email yang gagal dikirim (Brevo menolak) tidak menghabiskan jatah 3 kode per email per 15 menit
-- dan tidak bisa dipakai. Tetap dihitung dalam batas 50 kode per jam seluruh pemasangan, supaya Brevo yang mati
-- tidak dipanggil terus-menerus. Temuan uji nyata 17 Nov 2026 (docs/laporan-tahap-5e.md temuan 2).
-- Migrasi hanya maju; jangan diedit setelah dipasang.

alter table fakta.kode_email add column gagal_kirim timestamptz;

create or replace function api.pintu_minta_kode_email(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(p ->> 'email'));
  v_u induk.pengguna;
  v_id bigint;
begin
  perform pg_advisory_xact_lock(hashtext('fakta.kode_email'));
  select u.* into v_u from induk.pengguna u
  where lower(u.email) = v_email and u.aktif and u.peran in ('hrd', 'pembangun');
  if v_u.id is null then
    return jsonb_build_object('kirim', false);
  end if;
  if (select count(*) from fakta.kode_email k
      where k.email = v_email and k.dibuat > now() - interval '15 minutes' and k.gagal_kirim is null) >= 3
     or (select count(*) from fakta.kode_email k where k.dibuat > now() - interval '1 hour') >= 50 then
    return jsonb_build_object('kirim', false, 'batas', true);
  end if;
  insert into fakta.kode_email (pengguna, email, sidik, berlaku_sampai)
  values (v_u.id, v_email, p ->> 'sidik', now() + interval '10 minutes')
  returning id into v_id;
  return jsonb_build_object('kirim', true, 'email', v_email, 'id', v_id);
end $$;

-- Tandai kode yang gagal dikirim. Masukan: {"id", "email"} (keduanya harus cocok). Keluaran: {"ditandai": jumlah}.
create function api.pintu_kode_email_gagal(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_jumlah integer;
begin
  update fakta.kode_email set gagal_kirim = now()
  where id = (p ->> 'id')::bigint and email = lower(trim(p ->> 'email')) and gagal_kirim is null and dipakai is null;
  get diagnostics v_jumlah = row_count;
  return jsonb_build_object('ditandai', v_jumlah);
end $$;

-- Tukar kode: kode yang gagal dikirim dilewati (tidak pernah sampai ke siapa pun); selain itu sama dengan 0020.
create or replace function api.pintu_tukar_kode_email(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(p ->> 'email'));
  v_k fakta.kode_email;
  v_sampai timestamptz;
begin
  select k.* into v_k from fakta.kode_email k
  where k.email = v_email and k.gagal_kirim is null
  order by k.dibuat desc, k.id desc limit 1 for update;
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

grant execute on function api.pintu_kode_email_gagal(jsonb) to pintu;
