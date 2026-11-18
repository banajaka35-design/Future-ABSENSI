-- 0023_pengerasan_6f.sql
-- Paket 6f (docs/rencana-pengerasan-6f.md, ditulis sebelum file ini).
-- S1: batas harian kode email (kasus E8b, docs/login-email.md): paling banyak 10 kode per email per 24 jam (kode
--     yang gagal dikirim tidak dihitung) dan 100 kode untuk semua email per 24 jam (termasuk yang gagal dikirim).
--     Paket gratis Brevo hanya 300 email/hari; tanpa batas harian, orang yang tahu satu email HRD bisa memicu
--     288 email/hari. Jawaban ke halaman tetap sama (tidak membuka apakah email terdaftar).
-- S2: cabut izin jalankan fungsi bawaan Supabase public.rls_auto_enable() dari public, anon, authenticated
--     (peringatan keamanan Supabase 18 Nov 2026). Tidak ada di Postgres uji, jadi dilewati bila tidak ada.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

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
     or (select count(*) from fakta.kode_email k where k.dibuat > now() - interval '1 hour') >= 50
     -- 6f (E8b): batas 24 jam
     or (select count(*) from fakta.kode_email k
         where k.email = v_email and k.dibuat > now() - interval '24 hours' and k.gagal_kirim is null) >= 10
     or (select count(*) from fakta.kode_email k where k.dibuat > now() - interval '24 hours') >= 100 then
    return jsonb_build_object('kirim', false, 'batas', true);
  end if;
  insert into fakta.kode_email (pengguna, email, sidik, berlaku_sampai)
  values (v_u.id, v_email, p ->> 'sidik', now() + interval '10 minutes')
  returning id into v_id;
  return jsonb_build_object('kirim', true, 'email', v_email, 'id', v_id);
end $$;

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;
