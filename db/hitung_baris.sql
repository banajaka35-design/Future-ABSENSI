-- Jumlah baris setiap tabel di skema milik proyek, satu baris per tabel: "skema.tabel|jumlah".
-- Dipakai untuk membandingkan Supabase dengan hasil pemulihan cadangan, dan sebagai laporan setelah pemasangan.
-- Hanya membaca.
select n.nspname || '.' || c.relname as tabel,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text::bigint as baris
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'p')
  and not c.relispartition
  and n.nspname in ('induk', 'aturan', 'fakta', 'hitung', 'jejak', 'api')
order by 1;
