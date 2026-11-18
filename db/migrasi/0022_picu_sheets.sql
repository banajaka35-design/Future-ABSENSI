-- 0022_picu_sheets.sql
-- Paket 6e: catatan pemicu "Isi Sheets" dari Edge Function sesudah file masuk, dan kejadian tingkat segera
-- 'sheets_tidak_terpicu' bila pemicu gagal atau belum disiapkan. Rancangan: docs/pintu-telegram.md bagian
-- "Pemicu Sheets" dan docs/rencana-sheets-otomatis.md (ditulis sebelum file ini).
-- Migrasi hanya maju; jangan diedit setelah dipasang.

create table fakta.picu_sheets (
  id bigint generated always as identity primary key,
  waktu timestamptz not null default now(),
  asal text not null check (asal in ('telegram', 'web')),
  hasil text not null check (hasil in ('terkirim', 'gagal', 'belum_disiapkan')),
  alasan text check (length(alasan) <= 300),
  waktu_file timestamptz
);

-- Dicatat oleh Edge Function (peran pintu). Masukan: {"asal", "hasil", "alasan", "waktu_file"}.
create function api.pintu_catat_picu(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into fakta.picu_sheets (asal, hasil, alasan, waktu_file)
  values (p ->> 'asal', p ->> 'hasil', left(p ->> 'alasan', 300), (p ->> 'waktu_file')::timestamptz)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

grant execute on function api.pintu_catat_picu(jsonb) to pintu;

-- Kejadian segera: sama dengan 0018, ditambah pemicu Sheets yang tidak terkirim.
create or replace function fakta.kejadian_segera() returns table (kunci text, jenis text, isi jsonb)
language sql stable set search_path = '' as $$
  select 'kiriman|' || k.id, fakta.jenis_tolak_segera(k.alasan),
         jsonb_build_object('kiriman_id', k.id, 'nama_file', k.nama_file, 'mesin', k.mesin, 'alasan', k.alasan,
                            'diterima', k.diterima)
  from fakta.kiriman_file k
  where k.hasil = 'ditolak' and fakta.jenis_tolak_segera(k.alasan) is not null
  union all
  (select distinct on (x.kunci) x.kunci, x.jenis, x.isi
  from (
    select concat_ws('|', 'anomali', a.jenis, coalesce(a.mesin, ''), coalesce(a.divisi, ''), coalesce(a.id_karyawan, ''),
                     coalesce(a.kiriman_id::text, ''), coalesce(a.tanggal::text, ''), coalesce(a.tanggal_akhir::text, '')) as kunci,
           a.jenis,
           jsonb_build_object('keterangan', a.keterangan, 'mesin', a.mesin, 'divisi', a.divisi, 'id_karyawan', a.id_karyawan,
                              'kiriman_id', a.kiriman_id, 'tanggal', a.tanggal, 'tanggal_akhir', a.tanggal_akhir,
                              'nilai', a.nilai, 'periode_id', v.periode_id) as isi,
           a.tanggal, a.id
    from hitung.anomali a
    join hitung.versi_terakhir v on v.id = a.versi_id and v.jenis = 'baca_tap'
    where a.tingkat = 'segera' and not a.selesai
  ) x
  order by x.kunci, x.id)
  union all
  -- Paket 6e: pemicu Sheets gagal atau belum disiapkan (docs/pintu-telegram.md).
  select 'sheets|' || s.id, 'sheets_tidak_terpicu',
         jsonb_build_object('hasil', s.hasil, 'alasan', s.alasan, 'asal', s.asal,
                            'waktu', to_char(s.waktu at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI'))
  from fakta.picu_sheets s
  where s.hasil <> 'terkirim'
$$;
