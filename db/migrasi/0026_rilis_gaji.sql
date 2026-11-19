-- 0026_rilis_gaji.sql
-- Paket 8b: rilis gaji dengan PIN (docs/rencana-8b.md, ditulis sebelum file ini). PRD v2 celah K5; kontrak data bagian 6.
-- Juga: status periode sesudah hitung, periode dirilis tidak dihitung ulang, daftar karyawan sebelum tanggal mulai.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Status periode
-- ---------------------------------------------------------------------------

-- Satu perpindahan bisa dilakukan lebih dari satu peran (diajukan -> dihitung: HRD membatalkan, sistem menghitung ulang,
-- bos menolak), jadi kunci tabel alur menjadi (dari, ke, peran).
alter table fakta.alur_status_periode drop constraint alur_status_periode_pkey;
alter table fakta.alur_status_periode add primary key (dari, ke, peran);

-- Langkah sistem baru: periode yang sudah punya hasil hitung menjadi 'dihitung'; pengajuan yang dihitung ulang kembali
-- ke 'dihitung'; bos menolak -> 'dihitung'.
insert into fakta.alur_status_periode (dari, ke, peran) values
  ('terbuka', 'dihitung', 'sistem'), ('diajukan', 'dihitung', 'sistem'), ('disetujui', 'dihitung', 'sistem'),
  ('diajukan', 'dihitung', 'bos')
on conflict do nothing;

-- Penjaga: periode 'dirilis' atau 'dikunci' tidak boleh mendapat versi hitung baru (angka yang dirilis tidak berubah diam-diam).
create function hitung.jaga_versi_periode() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_status text := (select p.status from fakta.periode p where p.id = new.periode_id);
begin
  if tg_op = 'INSERT' and tg_when = 'BEFORE' then
    if v_status in ('dirilis', 'dikunci') then
      raise exception 'Periode % sudah %; tidak dihitung ulang', new.periode_id, v_status using errcode = 'P0001';
    end if;
    return new;
  end if;
  -- Sesudah hitung gaji: status menjadi 'dihitung' (pengajuan yang ada batal karena angkanya berubah).
  if new.jenis = 'hitung_gaji' and v_status in ('terbuka', 'menunggu_data', 'diajukan', 'disetujui') then
    perform fakta.ubah_status_periode(new.periode_id, 'dihitung', 'sistem', 'sistem',
      case when v_status in ('diajukan', 'disetujui') then 'dihitung ulang; pengajuan batal' else 'gaji dihitung' end);
  end if;
  return null;
end $$;
create trigger jaga_periode_sebelum before insert on hitung.versi_hitung
  for each row execute function hitung.jaga_versi_periode();
create trigger status_sesudah_hitung after insert on hitung.versi_hitung
  for each row execute function hitung.jaga_versi_periode();

-- Periode yang sudah punya hasil hitung gaji tetapi masih 'terbuka' (sebelum paket ini) menjadi 'dihitung'.
do $$
declare
  r record;
begin
  for r in select p.id from fakta.periode p where p.status in ('terbuka', 'menunggu_data')
             and exists (select 1 from hitung.versi_hitung v where v.periode_id = p.id and v.jenis = 'hitung_gaji')
           order by p.tanggal_awal loop
    perform fakta.ubah_status_periode(r.id, 'dihitung', 'sistem', 'sistem', 'paket 8b: status sesudah hitung');
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Pengajuan, persetujuan, rilis (hanya bertambah)
-- ---------------------------------------------------------------------------

create table fakta.pengajuan_rilis (
  id bigint generated always as identity primary key,
  periode_id bigint not null references fakta.periode (id),
  versi_gaji bigint not null references hitung.versi_hitung (id),
  diajukan_oleh bigint not null references induk.pengguna (id),
  waktu timestamptz not null default now()
);
create table fakta.rilis_gaji (
  id bigint generated always as identity primary key,
  periode_id bigint not null unique references fakta.periode (id),
  versi_gaji bigint not null references hitung.versi_hitung (id),
  pengajuan_id bigint not null references fakta.pengajuan_rilis (id),
  dirilis_oleh bigint not null references induk.pengguna (id),
  waktu timestamptz not null default now()
);
create table fakta.percobaan_pin (
  id bigint generated always as identity primary key,
  pengguna bigint not null references induk.pengguna (id),
  waktu timestamptz not null default now(),
  berhasil boolean not null
);
create index percobaan_pin_pengguna on fakta.percobaan_pin (pengguna, waktu);
do $$
declare
  t text;
begin
  foreach t in array array['fakta.pengajuan_rilis', 'fakta.rilis_gaji'] loop
    execute format('create trigger tolak_ubah before update or delete on %s for each row execute function jejak.tolak_ubah()', t);
    execute format('create trigger tolak_kosongkan before truncate on %s for each statement execute function jejak.tolak_ubah()', t);
  end loop;
end $$;

-- Ringkasan untuk HRD dan bos (K5): sama dengan hitung.ringkasan_terlihat (tanpa orang rahasia, aturan F15c),
-- ditambah jumlah dibayar lewat transfer dan tunai (cara bayar yang berlaku di akhir periode).
create function hitung.ringkasan_rilis(p_versi bigint) returns jsonb
language sql stable set search_path = '' as $$
  with v as (
    select x.id, p.tanggal_awal, p.tanggal_akhir
    from hitung.versi_hitung x join fakta.periode p on p.id = x.periode_id
    where x.id = p_versi and x.jenis = 'hitung_gaji'
  ),
  g as (
    select g.gaji_bersih, g.dibayar,
           (select r.cara_bayar from induk.karyawan_riwayat r where r.id_karyawan = g.id_karyawan
              and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v.tanggal_akhir) as cara,
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
                              'rahasia', count(*) filter (where g.rahasia),
                              'transfer', coalesce(sum(g.dibayar) filter (where not g.rahasia and g.cara = 'transfer'), 0),
                              'tunai', coalesce(sum(g.dibayar) filter (where not g.rahasia and g.cara = 'tunai'), 0))
         end
  from g
$$;

-- Versi gaji yang masih berlaku untuk periode: versi gaji terakhir yang dihitung dari baca tap terakhir.
create function fakta.versi_gaji_berlaku(p_periode bigint) returns bigint
language sql stable set search_path = '' as $$
  select g.id from hitung.versi_terakhir g join hitung.versi_terakhir b on b.periode_id = g.periode_id and b.jenis = 'baca_tap'
  where g.periode_id = p_periode and g.jenis = 'hitung_gaji' and g.versi_sumber = b.id
$$;

create function fakta.isi_periode(p_periode bigint) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('periode_id', p.id, 'awal', p.tanggal_awal, 'akhir', p.tanggal_akhir, 'bayar', p.tanggal_bayar,
                            'status', p.status, 'versi_gaji', fakta.versi_gaji_berlaku(p.id),
                            'pengajuan_id', (select max(a.id) from fakta.pengajuan_rilis a where a.periode_id = p.id))
         || coalesce(hitung.ringkasan_rilis(fakta.versi_gaji_berlaku(p.id)), '{}'::jsonb)
  from fakta.periode p where p.id = p_periode
$$;

create function fakta.perlu_bos(p_hari date default current_date) returns boolean
language sql stable set search_path = '' as $$
  select coalesce(aturan.pengaturan_pada('persetujuan_rilis', null, p_hari), 'hrd') = 'hrd_lalu_bos'
$$;

-- PIN: 6 angka, tidak boleh angka sama semua atau berurutan. Disimpan bcrypt di induk.pengguna.pin_tersamar.
create function fakta.pin_lemah(p_pin text) returns boolean
language sql immutable set search_path = '' as $$
  select p_pin !~ '^[0-9]{6}$' or p_pin ~ '^(.)\1{5}$' or position(p_pin in '0123456789') > 0 or position(p_pin in '9876543210') > 0
$$;

-- Memeriksa PIN dengan batas 5 salah per jam per akun. Keluaran: 'benar' | 'salah' | 'terkunci' | 'belum_ada'.
create function fakta.periksa_pin(p_pengguna bigint, p_pin text) returns text
language plpgsql set search_path = '' as $$
declare
  v_tersamar text := (select u.pin_tersamar from induk.pengguna u where u.id = p_pengguna);
begin
  if v_tersamar is null then
    return 'belum_ada';
  end if;
  perform pg_advisory_xact_lock(hashtext('fakta.percobaan_pin'), p_pengguna::integer);
  if (select count(*) from fakta.percobaan_pin p
      where p.pengguna = p_pengguna and not p.berhasil and p.waktu > now() - interval '1 hour') >= 5 then
    return 'terkunci';
  end if;
  if coalesce(p_pin, '') ~ '^[0-9]{6}$' and extensions.crypt(p_pin, v_tersamar) = v_tersamar then
    insert into fakta.percobaan_pin (pengguna, berhasil) values (p_pengguna, true);
    return 'benar';
  end if;
  insert into fakta.percobaan_pin (pengguna, berhasil) values (p_pengguna, false);
  return 'salah';
end $$;

-- /pin. Masukan: {"telegram_id", "pin_baru", "pin_lama"}. Keluaran: {"hasil": "dibuat" | "diganti" | "bukan_hrd" |
-- "lemah" | "perlu_pin_lama" | "salah" | "terkunci"}.
create function api.pintu_atur_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_ada boolean;
  v_cek text;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  v_ada := (select u.pin_tersamar is not null from induk.pengguna u where u.id = v_hrd);
  if v_ada then
    if p ->> 'pin_lama' is null then
      return jsonb_build_object('hasil', 'perlu_pin_lama');
    end if;
    v_cek := fakta.periksa_pin(v_hrd, p ->> 'pin_lama');
    if v_cek <> 'benar' then
      return jsonb_build_object('hasil', v_cek);
    end if;
  end if;
  if fakta.pin_lemah(coalesce(p ->> 'pin_baru', '')) then
    return jsonb_build_object('hasil', 'lemah');
  end if;
  perform set_config('app.pengguna', 'pin-telegram', true);
  update induk.pengguna set pin_tersamar = extensions.crypt(p ->> 'pin_baru', extensions.gen_salt('bf', 10)) where id = v_hrd;
  return jsonb_build_object('hasil', case when v_ada then 'diganti' else 'dibuat' end);
end $$;

-- Daftar periode untuk /ajukan ('ajukan': dihitung dan bisa diajukan) atau /rilis ('rilis': diajukan atau disetujui).
-- Masukan: {"telegram_id", "untuk"}. Keluaran: {"hasil": "ada" | "bukan_hrd", "perlu_bos", "periode": [...]}.
create function api.pintu_daftar_periode(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if api.pintu_hrd((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  return jsonb_build_object('hasil', 'ada', 'perlu_bos', fakta.perlu_bos(), 'periode', coalesce((
    select jsonb_agg(fakta.isi_periode(x.id) order by x.tanggal_awal)
    from fakta.periode x
    where case when p ->> 'untuk' = 'rilis' then x.status in ('diajukan', 'disetujui')
               else x.status = 'dihitung' and fakta.versi_gaji_berlaku(x.id) is not null
                    and hitung.periode_bisa_diajukan(x.id) end), '[]'::jsonb));
end $$;

-- Ajukan. Masukan: {"telegram_id", "periode_id", "versi_gaji"}. Keluaran: {"hasil": "diajukan" | "bukan_hrd" |
-- "tidak_bisa" | "versi_berubah", "perlu_bos", "bos": [telegram_id...], ...isi periode}.
create function api.pintu_ajukan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_versi bigint;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  v_versi := fakta.versi_gaji_berlaku(v_id);
  if v_periode.id is null or v_periode.status <> 'dihitung' or v_versi is null or not hitung.periode_bisa_diajukan(v_id) then
    return jsonb_build_object('hasil', 'tidak_bisa', 'status', v_periode.status);
  end if;
  if v_versi <> (p ->> 'versi_gaji')::bigint then
    return jsonb_build_object('hasil', 'versi_berubah') || fakta.isi_periode(v_id);
  end if;
  insert into fakta.pengajuan_rilis (periode_id, versi_gaji, diajukan_oleh) values (v_id, v_versi, v_hrd);
  perform fakta.ubah_status_periode(v_id, 'diajukan', 'hrd', 'pengguna ' || v_hrd, 'diajukan lewat Telegram');
  return jsonb_build_object('hasil', 'diajukan', 'perlu_bos', fakta.perlu_bos(),
                            'bos', to_jsonb(fakta.penerima(array['bos']))) || fakta.isi_periode(v_id);
end $$;

-- Bos menyetujui atau menolak (pengaturan persetujuan_rilis = hrd_lalu_bos).
-- Masukan: {"telegram_id", "periode_id", "pengajuan_id", "setuju"}.
-- Keluaran: {"hasil": "disetujui" | "ditolak" | "bukan_bos" | "tidak_berlaku", "pengaju": telegram_id, ...isi periode}.
create function api.pintu_setujui(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_bos bigint := (select u.id from induk.pengguna u where u.telegram_id = (p ->> 'telegram_id')::bigint
                   and u.peran = 'bos' and u.aktif);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_aju fakta.pengajuan_rilis;
  v_setuju boolean := coalesce((p ->> 'setuju')::boolean, false);
begin
  if v_bos is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  select a.* into v_aju from fakta.pengajuan_rilis a where a.periode_id = v_id order by a.id desc limit 1;
  if v_periode.status is distinct from 'diajukan' or v_aju.id is distinct from (p ->> 'pengajuan_id')::bigint
     or v_aju.versi_gaji is distinct from fakta.versi_gaji_berlaku(v_id) then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  insert into fakta.persetujuan (perihal, rujukan, penyetuju, keputusan)
  values ('rilis', 'pengajuan_rilis ' || v_aju.id, v_bos, case when v_setuju then 'setuju' else 'tolak' end);
  perform fakta.ubah_status_periode(v_id, case when v_setuju then 'disetujui' else 'dihitung' end, 'bos', 'pengguna ' || v_bos,
                                    case when v_setuju then 'disetujui bos' else 'ditolak bos' end);
  return jsonb_build_object('hasil', case when v_setuju then 'disetujui' else 'ditolak' end,
                            'pengaju', (select u.telegram_id from induk.pengguna u where u.id = v_aju.diajukan_oleh))
         || fakta.isi_periode(v_id);
end $$;

-- Rilis dengan PIN (konfirmasi kedua, K5). Masukan: {"telegram_id", "periode_id", "pin"}.
-- Keluaran: {"hasil": "dirilis" | "bukan_hrd" | "belum_ada_pin" | "pin_salah" | "terkunci" | "belum_disetujui" |
-- "tidak_bisa" | "versi_berubah", ...isi periode}.
create function api.pintu_rilis(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id bigint := (p ->> 'periode_id')::bigint;
  v_periode fakta.periode;
  v_aju fakta.pengajuan_rilis;
  v_pin text;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  v_pin := fakta.periksa_pin(v_hrd, p ->> 'pin');
  if v_pin <> 'benar' then
    return jsonb_build_object('hasil', case v_pin when 'belum_ada' then 'belum_ada_pin' when 'salah' then 'pin_salah' else v_pin end);
  end if;
  select x.* into v_periode from fakta.periode x where x.id = v_id for update;
  if v_periode.id is null or v_periode.status not in ('diajukan', 'disetujui') then
    return jsonb_build_object('hasil', 'tidak_bisa', 'status', v_periode.status);
  end if;
  if fakta.perlu_bos() and v_periode.status <> 'disetujui' then
    return jsonb_build_object('hasil', 'belum_disetujui') || fakta.isi_periode(v_id);
  end if;
  select a.* into v_aju from fakta.pengajuan_rilis a where a.periode_id = v_id order by a.id desc limit 1;
  if v_aju.versi_gaji is distinct from fakta.versi_gaji_berlaku(v_id) or not hitung.periode_bisa_diajukan(v_id) then
    return jsonb_build_object('hasil', 'versi_berubah') || fakta.isi_periode(v_id);
  end if;
  insert into fakta.rilis_gaji (periode_id, versi_gaji, pengajuan_id, dirilis_oleh) values (v_id, v_aju.versi_gaji, v_aju.id, v_hrd);
  perform fakta.ubah_status_periode(v_id, 'dirilis', 'hrd', 'pengguna ' || v_hrd, 'dirilis lewat Telegram dengan PIN');
  return jsonb_build_object('hasil', 'dirilis') || fakta.isi_periode(v_id);
end $$;

-- ---------------------------------------------------------------------------
-- Antrean: periode dirilis dilewati; pemberitahuan segera
-- ---------------------------------------------------------------------------

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
  -- Paket 8b: periode yang sudah dirilis tidak dihitung ulang; tap baru tetap tersimpan, HRD diberi tahu (kejadian segera).
  if v_periode.status in ('dirilis', 'dikunci') then
    v_hasil := jsonb_build_object('dilewati', v_periode.status);
    update fakta.antrean_kerja set status = 'selesai', selesai = clock_timestamp(), hasil = v_hasil where id = v_id;
    return jsonb_build_object('periode', jsonb_build_object('id', v_periode.id, 'awal', v_periode.tanggal_awal,
                                                            'akhir', v_periode.tanggal_akhir),
                              'hasil', v_hasil,
                              'sisa', (select count(*) from fakta.antrean_kerja where status = 'menunggu'));
  end if;
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
    v_hasil := v_hasil || coalesce(hitung.ringkasan_terlihat(v_versi), '{}'::jsonb)
               || case when v_periode.status in ('diajukan', 'disetujui') then '{"pengajuan_batal": true}'::jsonb else '{}'::jsonb end;
  exception when others then
    update fakta.antrean_kerja set status = 'gagal', selesai = clock_timestamp(), galat = sqlerrm where id = v_id;
    v_hasil := jsonb_build_object('galat', sqlerrm);
  end;
  return jsonb_build_object('periode', jsonb_build_object('id', v_periode.id, 'awal', v_periode.tanggal_awal,
                                                          'akhir', v_periode.tanggal_akhir),
                            'hasil', v_hasil,
                            'sisa', (select count(*) from fakta.antrean_kerja where status = 'menunggu'));
end $$;

-- Hasil antrean untuk halaman unggah (0024): baris yang dilewati dikembalikan apa adanya.
create or replace function fakta.hasil_antrean_tampil(p_hasil jsonb) returns jsonb
language sql stable set search_path = '' as $$
  select case
    when p_hasil is null then null
    when p_hasil ? 'dilewati' then p_hasil
    when p_hasil ? 'versi_gaji' then
      (p_hasil - 'versi_gaji') || coalesce(hitung.ringkasan_terlihat((p_hasil ->> 'versi_gaji')::bigint),
                                           '{"angka_dihapus": true}'::jsonb)
    else (p_hasil - 'orang' - 'bersih') || '{"angka_dihapus": true}'::jsonb
  end
$$;

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
  union all
  -- Paket 8b: file baru menyentuh periode yang sudah dirilis; tap disimpan, periode tidak dihitung ulang.
  select 'dilewati|' || a.id, 'periode_dirilis_kena_file',
         jsonb_build_object('periode_id', a.periode_id, 'awal', p.tanggal_awal, 'akhir', p.tanggal_akhir,
                            'kiriman_id', a.kiriman_id, 'nama_file', k.nama_file)
  from fakta.antrean_kerja a join fakta.periode p on p.id = a.periode_id
  left join fakta.kiriman_file k on k.id = a.kiriman_id
  where a.hasil ? 'dilewati'
$$;

-- ---------------------------------------------------------------------------
-- Daftar karyawan sebelum tanggal mulai (keputusan pemilik 19 Nov 2026)
-- ---------------------------------------------------------------------------

-- Boleh didaftarkan: status terakhir (tanggal berapa pun, termasuk mulai di masa depan) bukan 'berhenti' sebelum hari ini.
create function fakta.boleh_daftar(p_id text) returns boolean
language sql stable set search_path = '' as $$
  select coalesce((select not (s.jenis = 'berhenti' and s.tanggal < current_date)
                   from induk.status_kerja s where s.id_karyawan = p_id
                   order by s.tanggal desc, s.id desc limit 1), false)
$$;

-- HRD membuat kode. Masukan: {"telegram_id", "id_karyawan", "ganti", "sidik"}.
-- Keluaran: {"hasil": "dibuat" | "bukan_hrd" | "tidak_ada" | "berhenti" | "sudah_punya_akun", ...}.
create or replace function api.pintu_buat_kode(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id text := upper(trim(p ->> 'id_karyawan'));
  v_ganti boolean := coalesce((p ->> 'ganti')::boolean, false);
  v_sampai timestamptz;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  if not exists (select 1 from induk.karyawan k where k.id = v_id) then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  if not fakta.boleh_daftar(v_id) then
    return jsonb_build_object('hasil', 'berhenti') || fakta.identitas_karyawan(v_id);
  end if;
  if not v_ganti and exists (select 1 from induk.pengguna u where u.id_karyawan = v_id and u.aktif) then
    return jsonb_build_object('hasil', 'sudah_punya_akun') || fakta.identitas_karyawan(v_id);
  end if;
  -- Kode lama yang belum dipakai untuk ID ini tidak berlaku lagi.
  update fakta.kode_daftar set selesai_pada = now(), hasil = 'diganti'
  where id_karyawan = v_id and selesai_pada is null;
  insert into fakta.kode_daftar (sidik, id_karyawan, dibuat_oleh, ganti, kedaluwarsa)
  values (p ->> 'sidik', v_id, v_hrd, v_ganti, now() + interval '60 minutes')
  returning kedaluwarsa into v_sampai;
  return jsonb_build_object('hasil', 'dibuat', 'ganti', v_ganti, 'berlaku_sampai', v_sampai) || fakta.identitas_karyawan(v_id);
end $$;

-- Karyawan mengetik /daftar. Masukan: {"telegram_id", "sidik"}.
-- Keluaran: {"hasil": "konfirmasi" (+ kode_id, nama, divisi) | "sudah_terdaftar" | "terkunci" (+ sampai) | "salah" (+ sisa)}.
create or replace function api.pintu_daftar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_salah integer;
  v_k fakta.kode_daftar;
begin
  if v_tg is null then
    return jsonb_build_object('hasil', 'salah', 'sisa', 0);
  end if;
  if exists (select 1 from induk.pengguna u where u.telegram_id = v_tg) then
    return jsonb_build_object('hasil', 'sudah_terdaftar');
  end if;
  -- Satu akun Telegram diproses satu per satu, supaya batas 5 kali salah tidak bisa dilewati dengan pesan bersamaan.
  perform pg_advisory_xact_lock(hashtext('fakta.percobaan_daftar'), hashtext(v_tg::text));
  select count(*) into v_salah from fakta.percobaan_daftar
  where telegram_id = v_tg and not berhasil and waktu > now() - interval '1 hour';
  if v_salah >= 5 then
    return jsonb_build_object('hasil', 'terkunci', 'sampai',
      (select min(waktu) + interval '1 hour' from fakta.percobaan_daftar
       where telegram_id = v_tg and not berhasil and waktu > now() - interval '1 hour'));
  end if;
  select k.* into v_k from fakta.kode_daftar k
  where k.sidik = p ->> 'sidik' and k.selesai_pada is null and k.kedaluwarsa > now()
    and (k.diminta_oleh_tg is null or k.diminta_oleh_tg = v_tg)
  for update;
  if v_k.id is null or not fakta.boleh_daftar(v_k.id_karyawan) then
    insert into fakta.percobaan_daftar (telegram_id, berhasil) values (v_tg, false);
    return jsonb_build_object('hasil', 'salah', 'sisa', greatest(0, 4 - v_salah));
  end if;
  insert into fakta.percobaan_daftar (telegram_id, berhasil) values (v_tg, true);
  update fakta.kode_daftar set diminta_oleh_tg = v_tg, diminta_pada = now() where id = v_k.id;
  return jsonb_build_object('hasil', 'konfirmasi', 'kode_id', v_k.id) || fakta.identitas_karyawan(v_k.id_karyawan);
end $$;

-- Jawaban tombol konfirmasi. Masukan: {"telegram_id", "kode_id", "jawab": "ya" | "bukan"}.
-- Keluaran: {"hasil": "terdaftar" (+ nama, divisi) | "dibatalkan" | "tidak_berlaku" | "sudah_terdaftar" | "sudah_punya_akun"}.
create or replace function api.pintu_daftar_jawab(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_k fakta.kode_daftar;
  v_baru bigint;
begin
  select k.* into v_k from fakta.kode_daftar k
  where k.id = (p ->> 'kode_id')::bigint and k.diminta_oleh_tg = v_tg and k.selesai_pada is null and k.kedaluwarsa > now()
  for update;
  if v_k.id is null then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  if p ->> 'jawab' <> 'ya' then
    update fakta.kode_daftar set selesai_pada = now(), hasil = 'dibatalkan' where id = v_k.id;
    return jsonb_build_object('hasil', 'dibatalkan');
  end if;
  if exists (select 1 from induk.pengguna u where u.telegram_id = v_tg) then
    return jsonb_build_object('hasil', 'sudah_terdaftar');
  end if;
  if not fakta.boleh_daftar(v_k.id_karyawan) then
    update fakta.kode_daftar set selesai_pada = now(), hasil = 'dibatalkan' where id = v_k.id;
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  perform set_config('app.pengguna', 'daftar-telegram', true);
  if v_k.ganti then
    -- Ganti HP lewat HRD (K1): akun lama dinonaktifkan sesudah akun baru dikonfirmasi.
    update induk.pengguna set aktif = false where id_karyawan = v_k.id_karyawan and aktif;
  elsif exists (select 1 from induk.pengguna u where u.id_karyawan = v_k.id_karyawan and u.aktif) then
    update fakta.kode_daftar set selesai_pada = now(), hasil = 'dibatalkan' where id = v_k.id;
    return jsonb_build_object('hasil', 'sudah_punya_akun');
  end if;
  insert into induk.pengguna (telegram_id, peran, id_karyawan) values (v_tg, 'karyawan', v_k.id_karyawan)
  returning id into v_baru;
  update fakta.kode_daftar set selesai_pada = now(), hasil = 'terdaftar', dipakai_oleh = v_baru where id = v_k.id;
  return jsonb_build_object('hasil', 'terdaftar') || fakta.identitas_karyawan(v_k.id_karyawan);
end $$;

revoke all on function hitung.ringkasan_rilis(bigint), fakta.versi_gaji_berlaku(bigint), fakta.isi_periode(bigint),
  fakta.perlu_bos(date), fakta.pin_lemah(text), fakta.periksa_pin(bigint, text), fakta.boleh_daftar(text),
  hitung.jaga_versi_periode() from public;
grant execute on function api.pintu_atur_pin(jsonb), api.pintu_daftar_periode(jsonb), api.pintu_ajukan(jsonb),
  api.pintu_setujui(jsonb), api.pintu_rilis(jsonb) to pintu;
