-- Daftar celah akses untuk peran tanpa login (anon) dan pengguna login biasa (authenticated)
-- di skema milik proyek. Hasil kosong = tidak ada celah. Hanya membaca katalog database.
-- Dipakai oleh db/uji_akses_supabase.sh (cadangan malam) dan uji otomatis db/uji/030_akses_katalog.sql.
with skema as (
  select oid, nspname from pg_namespace where nspname in ('induk', 'aturan', 'fakta', 'hitung', 'jejak', 'api')
), peran as (
  select oid, rolname from pg_roles where rolname in ('anon', 'authenticated')
)
select p.rolname as peran, 'boleh masuk skema' as celah, s.nspname as objek
from skema s, peran p where has_schema_privilege(p.oid, s.oid, 'usage')
union all
select p.rolname, 'boleh baca/ubah tabel', s.nspname || '.' || c.relname
from pg_class c join skema s on s.oid = c.relnamespace, peran p
where c.relkind in ('r', 'p', 'v', 'm')
  and has_table_privilege(p.oid, c.oid, 'select, insert, update, delete, truncate')
union all
select p.rolname, 'boleh jalankan fungsi', s.nspname || '.' || f.proname
from pg_proc f join skema s on s.oid = f.pronamespace, peran p
where has_function_privilege(p.oid, f.oid, 'execute')
union all
-- Paket 6f (celah S2): fungsi SECURITY DEFINER di skema public (terbuka lewat API Supabase /rest/v1/rpc), termasuk
-- bawaan Supabase seperti public.rls_auto_enable, tidak boleh bisa dijalankan tanpa login.
select p.rolname, 'boleh jalankan fungsi SECURITY DEFINER', 'public.' || f.proname
from pg_proc f join pg_namespace n on n.oid = f.pronamespace and n.nspname = 'public', peran p
where f.prosecdef and has_function_privilege(p.oid, f.oid, 'execute')
order by 1, 2, 3;
