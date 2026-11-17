-- 0019_unggah_web.sql
-- Paket 5d: unggah cadangan lewat web dengan tautan dari bot (docs/unggah-web.md, ditulis sebelum file ini).
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- Asal kiriman: telegram (bot), web (halaman unggah), lain (dimuat skrip, misalnya data simulasi).
-- Tabel kiriman hanya boleh ditambah, jadi asal diisi saat baris dibuat, dari pengaturan sesi app.asal_kiriman.
-- Baris sebelum migrasi ini tidak diubah: asal kosong (yang punya nomor_pesan berasal dari bot).
alter table fakta.kiriman_file add column asal text check (asal in ('telegram', 'web', 'lain'));
alter table fakta.kiriman_file alter column asal set default coalesce(nullif(current_setting('app.asal_kiriman', true), ''), 'lain');

-- Tautan unggah: hanya sidik SHA-256 kode yang disimpan; kodenya sendiri hanya ada di pesan Telegram.
create table fakta.tautan_unggah (
  id bigint generated always as identity primary key,
  sidik text not null unique check (sidik ~ '^[0-9a-f]{64}$'),
  pengguna bigint not null references induk.pengguna (id),
  dibuat timestamptz not null default now(),
  berlaku_sampai timestamptz not null,
  jumlah_pakai integer not null default 0,
  terakhir_dipakai timestamptz
);

-- Pemilik tautan bila tautan sah: ada, belum lewat waktu (ditambah p_tambahan), akun aktif hrd atau pembangun.
create function fakta.pemilik_tautan(p_sidik text, p_tambahan interval default '0') returns induk.pengguna
language sql stable set search_path = '' as $$
  select u.* from fakta.tautan_unggah t join induk.pengguna u on u.id = t.pengguna
  where t.sidik = p_sidik and now() < t.berlaku_sampai + p_tambahan
    and u.aktif and u.peran in ('hrd', 'pembangun')
$$;

-- Buat tautan untuk akun Telegram. Masukan: {"telegram_id", "sidik"}. Keluaran: {"hasil", "berlaku_sampai"}.
create function api.pintu_buat_tautan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pengguna bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_sampai timestamptz;
begin
  if v_pengguna is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Akun Anda belum terdaftar untuk mengirim file.');
  end if;
  insert into fakta.tautan_unggah (sidik, pengguna, berlaku_sampai)
  values (p ->> 'sidik', v_pengguna, now() + interval '15 minutes')
  returning berlaku_sampai into v_sampai;
  return jsonb_build_object('hasil', 'dibuat', 'berlaku_sampai', v_sampai);
end $$;

-- Periksa tautan (halaman unggah dibuka). Masukan: {"kode_sidik"}. Keluaran: {"sah", "berlaku_sampai", "mesin"}.
create function api.pintu_periksa_tautan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u induk.pengguna := fakta.pemilik_tautan(p ->> 'kode_sidik');
begin
  if v_u.id is null then
    return jsonb_build_object('sah', false);
  end if;
  return jsonb_build_object(
    'sah', true,
    'berlaku_sampai', (select t.berlaku_sampai from fakta.tautan_unggah t where t.sidik = p ->> 'kode_sidik'),
    'mesin', coalesce((select jsonb_agg(m.kode order by m.kode) from induk.mesin m), '[]'::jsonb));
end $$;

-- Terima file mesin, sekarang dengan asal kiriman. Isi sama dengan versi 0015, ditambah "asal" (bawaan telegram).
create or replace function api.pintu_terima_file(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pengguna bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_hasil jsonb;
  v_awal date;
  v_akhir date;
  v_periode jsonb;
begin
  if v_pengguna is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Akun Anda belum terdaftar sebagai HRD.', 'dicatat', false);
  end if;
  if not exists (select 1 from induk.mesin m where m.kode = p ->> 'mesin') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Mesin %s tidak dikenal.', p ->> 'mesin'), 'dicatat', false);
  end if;
  perform set_config('app.pengguna', coalesce(p ->> 'asal', 'telegram') || ':' || (p ->> 'telegram_id'), true);
  perform set_config('app.asal_kiriman', case when p ->> 'asal' = 'web' then 'web' else 'telegram' end, true);
  v_hasil := fakta.terima_kiriman(p ->> 'nama_file', p ->> 'sidik', p ->> 'mesin', p -> 'tap', p ->> 'alasan',
                                   now(), (p ->> 'update_id')::bigint, v_pengguna);
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

-- Terima file dari halaman unggah. Pengirim diambil dari tautan oleh database, bukan dari Edge Function.
-- Masukan: {"kode_sidik", "nama_file", "sidik", "mesin", "tap", "alasan"}. Keluaran: hasil pintu_terima_file + "telegram_id",
-- atau {"tautan": false}.
create function api.pintu_terima_web(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u induk.pengguna := fakta.pemilik_tautan(p ->> 'kode_sidik');
begin
  if v_u.id is null then
    return jsonb_build_object('tautan', false);
  end if;
  update fakta.tautan_unggah set jumlah_pakai = jumlah_pakai + 1, terakhir_dipakai = now() where sidik = p ->> 'kode_sidik';
  return api.pintu_terima_file((p - 'kode_sidik' - 'update_id')
           || jsonb_build_object('telegram_id', v_u.telegram_id, 'asal', 'web'))
         || jsonb_build_object('tautan', true, 'telegram_id', v_u.telegram_id);
end $$;

-- Status satu kiriman untuk halaman unggah: hanya pemilik tautan yang mengirimnya, sampai 60 menit sesudah tautan habis.
-- Masukan: {"kode_sidik", "kiriman_id"}. Keluaran: {"tautan", "kiriman", "periode": [{awal, akhir, status, hasil, galat}], "selesai"}.
create function api.pintu_status_kiriman(p jsonb) returns jsonb
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
                                                             'status', a.status, 'hasil', a.hasil, 'galat', a.galat)
                                          order by x.tanggal_awal, a.id)
                         from fakta.antrean_kerja a join fakta.periode x on x.id = a.periode_id
                         where a.kiriman_id = v_k.id), '[]'::jsonb),
    'selesai', not exists (select 1 from fakta.antrean_kerja a where a.kiriman_id = v_k.id and a.status = 'menunggu'));
end $$;

grant execute on function api.pintu_buat_tautan(jsonb), api.pintu_periksa_tautan(jsonb), api.pintu_terima_web(jsonb),
  api.pintu_status_kiriman(jsonb) to pintu;
