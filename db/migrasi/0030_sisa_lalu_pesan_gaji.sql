-- 0030_sisa_lalu_pesan_gaji.sql
-- Paket 8c-2 (docs/rencana-8c-2.md): isi pesan gaji ikut membawa sisa pembulatan periode lalu (hitung.ringkasan_gaji.sisa_lalu),
-- supaya karyawan bisa mencocokkan: gaji bersih + sisa lalu = dibayar + sisa baru (kasus E09). Selain kolom itu sama dengan 0029.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- Isi pesan gaji satu orang. Versi: yang dirilis bila ada, selain itu versi gaji yang berlaku (untuk contoh).
create or replace function fakta.isi_gaji(p_periode bigint, p_id text) returns jsonb
language sql stable set search_path = '' as $$
  with v as (
    select coalesce((select r.versi_gaji from fakta.rilis_gaji r where r.periode_id = p_periode),
                    fakta.versi_gaji_berlaku(p_periode)) as versi
  ),
  p as (select x.* from fakta.periode x where x.id = p_periode),
  k as (
    select kr.* from induk.karyawan_riwayat kr, p
    where kr.id_karyawan = p_id and kr.berlaku_dari <= p.tanggal_akhir
    order by kr.berlaku_dari desc limit 1
  )
  select jsonb_build_object(
    'periode_id', p.id, 'awal', p.tanggal_awal, 'akhir', p.tanggal_akhir, 'bayar', p.tanggal_bayar,
    'id', p_id, 'nama', (select n.nama from induk.karyawan n where n.id = p_id),
    'divisi', (select d.nama from induk.divisi d, k where d.kode = k.divisi),
    'cara_bayar', (select k.cara_bayar from k), 'rahasia', fakta.rahasia_di_periode(p_id, p_periode),
    'pendapatan', g.total_pendapatan, 'potongan', g.total_potongan, 'bersih', g.gaji_bersih, 'dibayar', g.dibayar,
    'sisa', g.sisa_pembulatan, 'sisa_lalu', g.sisa_lalu,
    'komponen', coalesce((select jsonb_agg(jsonb_build_object('komponen', r.komponen, 'kelompok', r.kelompok,
                                                              'nominal', r.nominal, 'bukti', r.bukti)
                                           order by r.kelompok, r.komponen)
                          from hitung.rincian_gaji r where r.versi_id = v.versi and r.id_karyawan = p_id and r.nominal <> 0),
                         '[]'::jsonb))
  from p, v join hitung.ringkasan_gaji g on g.versi_id = v.versi and g.id_karyawan = p_id
$$;
