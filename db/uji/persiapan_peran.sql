-- Membuat peran yang ada di Supabase supaya uji akses di database sementara sama dengan kenyataan.
do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin', r);
    end if;
  end loop;
end $$;
-- Di Supabase, kedua peran ini bisa memakai schema public; tirukan supaya uji tidak lulus karena alasan yang salah.
grant usage on schema public to anon, authenticated;
