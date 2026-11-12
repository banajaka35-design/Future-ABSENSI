-- Uji akses lewat katalog (PRD celah K6, migrasi 0005): peran tanpa login dan pengguna login biasa
-- tidak punya izin apa pun di skema proyek, termasuk menjalankan fungsi, sekarang maupun untuk fungsi baru.
begin;

select uji.sama('akses katalog: tidak ada celah untuk anon dan authenticated',
  (select count(*) from (
    with skema as (
      select oid, nspname from pg_namespace where nspname in ('induk', 'aturan', 'fakta', 'hitung', 'jejak', 'api')
    ), peran as (
      select oid, rolname from pg_roles where rolname in ('anon', 'authenticated')
    )
    select 1 from skema s, peran p where has_schema_privilege(p.oid, s.oid, 'usage')
    union all
    select 1 from pg_class c join skema s on s.oid = c.relnamespace, peran p
    where c.relkind in ('r', 'p', 'v', 'm') and has_table_privilege(p.oid, c.oid, 'select, insert, update, delete, truncate')
    union all
    select 1 from pg_proc f join skema s on s.oid = f.pronamespace, peran p
    where has_function_privilege(p.oid, f.oid, 'execute')
  ) x)::int, 0);

-- Fungsi yang dibuat setelah 0005 juga tertutup (aturan bawaan dicabut).
create function hitung.fungsi_coba_akses() returns int language sql as 'select 1';
select uji.sama('akses katalog: fungsi baru tidak bisa dijalankan anon',
  has_function_privilege('anon', 'hitung.fungsi_coba_akses()', 'execute'), false);
select uji.sama('akses katalog: fungsi baru tidak bisa dijalankan authenticated',
  has_function_privilege('authenticated', 'hitung.fungsi_coba_akses()', 'execute'), false);

-- Pemicu tetap berjalan setelah izin fungsi dicabut. Diuji dengan peran biasa (bukan superuser),
-- yang hanya diberi izin menulis tabel, tanpa izin menjalankan fungsi pemicunya.
create role coba_tulis nologin;
grant usage on schema induk, jejak to coba_tulis;
grant insert on induk.karyawan to coba_tulis;
grant insert on jejak.perubahan to coba_tulis;
grant usage on all sequences in schema jejak to coba_tulis;
select uji.sama('akses katalog: peran coba tidak punya izin menjalankan fungsi pemicu',
  has_function_privilege('coba_tulis', 'jejak.catat_perubahan()', 'execute'), false);
create temp table jejak_sebelum as select count(*) as n from jejak.perubahan;
grant select on jejak_sebelum to coba_tulis;
set local role coba_tulis;
insert into induk.karyawan (id, nama) values ('99901', 'Coba Pemicu');
reset role;
select uji.sama('akses katalog: pemicu tetap mencatat jejak tanpa izin menjalankan fungsi',
  (select count(*) from jejak.perubahan) - (select n from jejak_sebelum), 1::bigint);

rollback;
