-- 0024_total_tanpa_rahasia.sql
-- Paket G1-3 (docs/rencana-g1-3.md, ditulis sebelum file ini). Kasus F15b dan F15c.
-- T1: total gaji di balasan bot dan halaman unggah tanpa orang rahasia.
-- C1: kolom fakta.antrean_kerja.hasil tidak lagi menyimpan rupiah; total dihitung saat dibaca, supaya orang yang
--     dijadikan rahasia sesudah file diproses ikut disembunyikan ("rahasia sekarang").
-- C1b: baris lama yang sudah menyimpan total termasuk orang rahasia dibersihkan.
-- C3: hitung.ringkasan_terlihat ada di skema hitung (peran pintu tidak punya akses) dan hanya mengembalikan jumlah.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- Jumlah untuk satu versi gaji, tanpa orang rahasia. Aturan F15c (sama dengan web/buat_data.py): gaji satu periode
-- disembunyikan bila orang itu rahasia pada hari mana pun di periode itu, atau rahasia sekarang (status terakhir).
-- Keluaran: {"orang", "bersih", "rahasia"} | null bila versi bukan versi hitung gaji.
create function hitung.ringkasan_terlihat(p_versi bigint) returns jsonb
language sql stable set search_path = '' as $$
  with v as (
    select x.id, p.tanggal_awal, p.tanggal_akhir
    from hitung.versi_hitung x join fakta.periode p on p.id = x.periode_id
    where x.id = p_versi and x.jenis = 'hitung_gaji'
  ),
  g as (
    select g.gaji_bersih,
           (exists (select 1 from induk.karyawan_riwayat r
                    where r.id_karyawan = g.id_karyawan and r.gaji_rahasia
                      and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') && daterange(v.tanggal_awal, v.tanggal_akhir, '[]'))
            or coalesce((select r.gaji_rahasia from induk.karyawan_riwayat r where r.id_karyawan = g.id_karyawan
                         order by r.berlaku_dari desc limit 1), false)) as rahasia
    from v join hitung.ringkasan_gaji g on g.versi_id = v.id
  )
  select case when exists (select 1 from v) then
           jsonb_build_object('orang', count(*) filter (where not g.rahasia),
                              'bersih', coalesce(sum(g.gaji_bersih) filter (where not g.rahasia), 0),
                              'rahasia', count(*) filter (where g.rahasia))
         end
  from g
$$;
revoke all on function hitung.ringkasan_terlihat(bigint) from public;

-- Sama dengan migrasi 0015, kecuali isi hasil: yang disimpan hanya versi_gaji, bisa_diajukan, segera (tanpa rupiah);
-- jawaban untuk bot ditambah orang/bersih/rahasia yang dihitung saat ini.
create or replace function api.pintu_kerjakan() returns jsonb
language plpgsql security definer set search_path = '' set jit = off as $$
declare
  v_id bigint;
  v_periode fakta.periode;
  v_hasil jsonb;
  v_versi bigint;
begin
  if not pg_try_advisory_xact_lock(hashtext('fakta.antrean_kerja')) then
    return jsonb_build_object('sibuk', true);
  end if;
  select a.id into v_id
  from fakta.antrean_kerja a join fakta.periode p on p.id = a.periode_id
  where a.status = 'menunggu' order by p.tanggal_awal, a.id limit 1;
  if v_id is null then
    return jsonb_build_object('kosong', true);
  end if;
  select p.* into v_periode from fakta.periode p join fakta.antrean_kerja a on a.periode_id = p.id where a.id = v_id;
  update fakta.antrean_kerja set mulai = clock_timestamp() where id = v_id;
  begin
    perform set_config('app.pengguna', 'antrean', true);
    perform hitung.baca_tap(v_periode.id);
    v_versi := hitung.hitung_gaji(v_periode.id);
    v_hasil := jsonb_build_object(
      'versi_gaji', v_versi,
      'bisa_diajukan', hitung.periode_bisa_diajukan(v_periode.id),
      'segera', (select count(*) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id
                 where v.periode_id = v_periode.id and v.jenis = 'baca_tap' and a.tingkat = 'segera'));
    update fakta.antrean_kerja set status = 'selesai', selesai = clock_timestamp(), hasil = v_hasil where id = v_id;
    v_hasil := v_hasil || coalesce(hitung.ringkasan_terlihat(v_versi), '{}'::jsonb);
  exception when others then
    update fakta.antrean_kerja set status = 'gagal', selesai = clock_timestamp(), galat = sqlerrm where id = v_id;
    v_hasil := jsonb_build_object('galat', sqlerrm);
  end;
  return jsonb_build_object('periode', jsonb_build_object('id', v_periode.id, 'awal', v_periode.tanggal_awal,
                                                          'akhir', v_periode.tanggal_akhir),
                            'hasil', v_hasil,
                            'sisa', (select count(*) from fakta.antrean_kerja where status = 'menunggu'));
end $$;

-- Hasil satu baris antrean untuk ditampilkan: total dihitung saat dibaca (C1). Baris tanpa versi_gaji (dibuat sebelum
-- paket ini) dikembalikan tanpa angka. Di skema fakta (tanpa izin untuk pintu).
create function fakta.hasil_antrean_tampil(p_hasil jsonb) returns jsonb
language sql stable set search_path = '' as $$
  select case
    when p_hasil is null then null
    when p_hasil ? 'versi_gaji' then
      (p_hasil - 'versi_gaji') || coalesce(hitung.ringkasan_terlihat((p_hasil ->> 'versi_gaji')::bigint),
                                           '{"angka_dihapus": true}'::jsonb)
    else (p_hasil - 'orang' - 'bersih') || '{"angka_dihapus": true}'::jsonb
  end
$$;
revoke all on function fakta.hasil_antrean_tampil(jsonb) from public;

-- Sama dengan migrasi 0019, kecuali hasil periode lewat fakta.hasil_antrean_tampil.
create or replace function api.pintu_status_kiriman(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u induk.pengguna := fakta.pemilik_tautan(p ->> 'kode_sidik', interval '60 minutes');
  v_k fakta.kiriman_file;
begin
  if v_u.id is null then
    return jsonb_build_object('tautan', false);
  end if;
  select k.* into v_k from fakta.kiriman_file k where k.id = (p ->> 'kiriman_id')::bigint and k.pengirim = v_u.id;
  if v_k.id is null then
    return jsonb_build_object('tautan', true, 'kiriman', null);
  end if;
  return jsonb_build_object(
    'tautan', true,
    'kiriman', jsonb_build_object('id', v_k.id, 'nama_file', v_k.nama_file, 'hasil', v_k.hasil, 'alasan', v_k.alasan,
                                  'jumlah_tap', v_k.jumlah_baris, 'tanggal_awal', v_k.tanggal_awal,
                                  'tanggal_akhir', v_k.tanggal_akhir, 'asal', v_k.asal),
    'periode', coalesce((select jsonb_agg(jsonb_build_object('awal', x.tanggal_awal, 'akhir', x.tanggal_akhir,
                                                             'status', a.status,
                                                             'hasil', fakta.hasil_antrean_tampil(a.hasil),
                                                             'galat', a.galat)
                                          order by x.tanggal_awal, a.id)
                         from fakta.antrean_kerja a join fakta.periode x on x.id = a.periode_id
                         where a.kiriman_id = v_k.id), '[]'::jsonb),
    'selesai', not exists (select 1 from fakta.antrean_kerja a where a.kiriman_id = v_k.id and a.status = 'menunggu'));
end $$;

-- C1b: baris lama yang menyimpan total (termasuk orang rahasia) dibersihkan. Tabel ini tidak punya pemicu jejak,
-- jadi angka lama tidak tertinggal di jejak.perubahan.
update fakta.antrean_kerja
set hasil = (hasil - 'orang' - 'bersih') || '{"angka_dihapus": true}'::jsonb
where hasil ? 'bersih' or hasil ? 'orang';
