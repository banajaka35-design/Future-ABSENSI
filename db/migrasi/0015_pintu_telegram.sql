-- 0015_pintu_telegram.sql
-- Paket 5b: pintu Telegram (docs/pintu-telegram.md, ditulis sebelum file ini).
--   Pesan Telegram yang sudah diproses (kasus A10), file yang menunggu pilihan mesin, antrean kerja (prinsip F6),
--   fungsi api untuk Edge Function, dan peran database `pintu` yang hanya boleh menjalankan fungsi itu.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- Nomor pesan Telegram (update_id) yang sudah diterima. Telegram mengirim ulang bila balasan terlambat.
create table fakta.pesan_telegram (
  update_id bigint primary key,
  telegram_id bigint,
  jenis text not null,
  diterima timestamptz not null default now()
);

-- File yang menunggu HRD memilih mesin (perusahaan dengan lebih dari satu mesin, tanpa kode mesin di keterangan).
create table fakta.file_tertunda (
  update_id bigint primary key,
  telegram_id bigint not null,
  file_id text not null,
  nama_file text not null,
  dibuat timestamptz not null default now()
);

-- Antrean kerja: satu baris per periode yang perlu dibaca ulang dan dihitung ulang.
create table fakta.antrean_kerja (
  id bigint generated always as identity primary key,
  periode_id bigint not null references fakta.periode (id),
  kiriman_id bigint references fakta.kiriman_file (id),
  status text not null default 'menunggu' check (status in ('menunggu', 'selesai', 'gagal')),
  dibuat timestamptz not null default now(),
  mulai timestamptz,
  selesai timestamptz,
  hasil jsonb,
  galat text
);
create unique index antrean_kerja_satu_menunggu on fakta.antrean_kerja (periode_id) where status = 'menunggu';

-- Pengguna HRD aktif dari ID Telegram, atau null.
create function api.pintu_hrd(p_telegram_id bigint) returns bigint
language sql stable security definer set search_path = '' as $$
  select u.id from induk.pengguna u where u.telegram_id = p_telegram_id and u.peran = 'hrd' and u.aktif
$$;

-- Langkah pertama setiap pesan: catat update_id (sekali saja) dan kenali pengirim.
-- Masukan: {"update_id", "telegram_id", "jenis"}. Keluaran: {"baru", "hrd", "mesin": [kode...]}.
create function api.pintu_pesan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_baru boolean;
begin
  insert into fakta.pesan_telegram (update_id, telegram_id, jenis)
  values ((p ->> 'update_id')::bigint, (p ->> 'telegram_id')::bigint, coalesce(p ->> 'jenis', 'lain'))
  on conflict (update_id) do nothing;
  v_baru := found;
  return jsonb_build_object(
    'baru', v_baru,
    'hrd', api.pintu_hrd((p ->> 'telegram_id')::bigint) is not null,
    'mesin', coalesce((select jsonb_agg(m.kode order by m.kode) from induk.mesin m), '[]'::jsonb));
end $$;

-- Simpan file yang menunggu pilihan mesin. Masukan: {"update_id", "telegram_id", "file_id", "nama_file"}.
create function api.pintu_tunda(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if api.pintu_hrd((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Akun Anda belum terdaftar sebagai HRD.');
  end if;
  insert into fakta.file_tertunda (update_id, telegram_id, file_id, nama_file)
  values ((p ->> 'update_id')::bigint, (p ->> 'telegram_id')::bigint, p ->> 'file_id', p ->> 'nama_file')
  on conflict (update_id) do nothing;
  return jsonb_build_object('hasil', 'disimpan');
end $$;

-- Ambil (dan hapus) file yang menunggu, hanya oleh HRD yang sama. Masukan: {"update_id", "telegram_id"}.
create function api.pintu_ambil_tunda(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r fakta.file_tertunda;
begin
  if api.pintu_hrd((p ->> 'telegram_id')::bigint) is null then
    return null;
  end if;
  delete from fakta.file_tertunda
  where update_id = (p ->> 'update_id')::bigint and telegram_id = (p ->> 'telegram_id')::bigint
  returning * into r;
  if r.update_id is null then
    return null;
  end if;
  return jsonb_build_object('update_id', r.update_id, 'file_id', r.file_id, 'nama_file', r.nama_file);
end $$;

-- Terima satu file hasil urai. Masukan: {"update_id", "telegram_id", "nama_file", "sidik", "mesin", "tap", "alasan"}.
-- Diterima -> periode yang terkena (dan periode sesudahnya yang sudah punya gaji) masuk antrean.
create function api.pintu_terima_file(p jsonb) returns jsonb
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
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  v_hasil := fakta.terima_kiriman(p ->> 'nama_file', p ->> 'sidik', p ->> 'mesin', p -> 'tap', p ->> 'alasan',
                                   now(), (p ->> 'update_id')::bigint, v_pengguna);
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

-- Kerjakan satu baris antrean (periode paling awal lebih dulu): baca tap lalu hitung gaji.
-- Hanya satu pekerja pada satu waktu (kunci advisory). Keluaran: {"sibuk"} | {"kosong"} | {"periode", "hasil", "sisa"}.
create function api.pintu_kerjakan() returns jsonb
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
    select jsonb_build_object(
             'orang', count(*), 'bersih', sum(g.gaji_bersih),
             'bisa_diajukan', hitung.periode_bisa_diajukan(v_periode.id),
             'segera', (select count(*) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id
                        where v.periode_id = v_periode.id and v.jenis = 'baca_tap' and a.tingkat = 'segera'))
    into v_hasil
    from hitung.ringkasan_gaji g where g.versi_id = v_versi;
    update fakta.antrean_kerja set status = 'selesai', selesai = clock_timestamp(), hasil = v_hasil where id = v_id;
  exception when others then
    update fakta.antrean_kerja set status = 'gagal', selesai = clock_timestamp(), galat = sqlerrm where id = v_id;
    v_hasil := jsonb_build_object('galat', sqlerrm);
  end;
  return jsonb_build_object('periode', jsonb_build_object('id', v_periode.id, 'awal', v_periode.tanggal_awal,
                                                          'akhir', v_periode.tanggal_akhir),
                            'hasil', v_hasil,
                            'sisa', (select count(*) from fakta.antrean_kerja where status = 'menunggu'));
end $$;

-- Peran untuk Edge Function: hanya menjalankan fungsi api di atas. Kata sandi diisi workflow pemasangan.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'pintu') then
    create role pintu login noinherit;
  end if;
end $$;
revoke all on schema induk, aturan, fakta, hitung, jejak from pintu;
grant usage on schema api to pintu;
grant execute on function api.pintu_pesan(jsonb), api.pintu_tunda(jsonb), api.pintu_ambil_tunda(jsonb),
  api.pintu_terima_file(jsonb), api.pintu_kerjakan() to pintu;
