-- 0039_web_hrd.sql
-- Paket 9a (docs/rencana-9a.md): web HRD lihat saja. Masuk dengan kode email (5e) menghasilkan sesi web 2 jam
-- (berakhir bila 30 menit tidak dipakai); semua bacaan lewat satu pintu api.web_hrd yang memeriksa sesi dan akun
-- setiap kali. Angka sama dengan Sheets (versi gaji terakhir, baca tap versi_sumber, orang rahasia tanpa angka F15b/F15c).
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- ---------------------------------------------------------------------------
-- C5: pemeriksaan kode email di satu tempat (dipakai unggah dan web HRD).
-- Keluaran: {"hasil": "masuk", "pengguna"} | {"hasil": "salah", "sisa"} | {"hasil": "tidak_berlaku"}.
-- ---------------------------------------------------------------------------
create function fakta.pakai_kode_email(p_email text, p_sidik text) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_email text := lower(trim(p_email));
  v_k fakta.kode_email;
begin
  select k.* into v_k from fakta.kode_email k
  where k.email = v_email and k.gagal_kirim is null
  order by k.dibuat desc, k.id desc limit 1 for update;
  if v_k.id is null or v_k.dipakai is not null or v_k.berlaku_sampai <= now() or v_k.salah >= 5
     or not exists (select 1 from induk.pengguna u where u.id = v_k.pengguna and u.aktif and u.peran in ('hrd', 'pembangun')) then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  if v_k.sidik <> p_sidik then
    update fakta.kode_email set salah = salah + 1 where id = v_k.id;
    return case when v_k.salah + 1 >= 5 then jsonb_build_object('hasil', 'tidak_berlaku')
                else jsonb_build_object('hasil', 'salah', 'sisa', 5 - v_k.salah - 1) end;
  end if;
  update fakta.kode_email set dipakai = now() where id = v_k.id;
  return jsonb_build_object('hasil', 'masuk', 'pengguna', v_k.pengguna);
end $$;

-- Sama dengan 0021, kini memakai fakta.pakai_kode_email.
create or replace function api.pintu_tukar_kode_email(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_r jsonb := fakta.pakai_kode_email(p ->> 'email', p ->> 'sidik_kode');
  v_sampai timestamptz;
begin
  if v_r ->> 'hasil' <> 'masuk' then
    return v_r;
  end if;
  insert into fakta.tautan_unggah (sidik, pengguna, berlaku_sampai)
  values (p ->> 'sidik_tautan', (v_r ->> 'pengguna')::bigint, now() + interval '15 minutes')
  returning berlaku_sampai into v_sampai;
  return jsonb_build_object('hasil', 'masuk', 'berlaku_sampai', v_sampai);
end $$;

-- ---------------------------------------------------------------------------
-- Sesi web (C3, C4, C8, C11, C14). Kode sesi tidak disimpan; hanya sidiknya.
-- ---------------------------------------------------------------------------
create table fakta.sesi_web (
  id bigint generated always as identity primary key,
  sidik text not null unique check (sidik ~ '^[0-9a-f]{64}$'),
  pengguna bigint not null references induk.pengguna (id),
  dibuat timestamptz not null default now(),
  berlaku_sampai timestamptz not null,
  terakhir_dipakai timestamptz not null default now(),
  berakhir timestamptz,
  alasan_berakhir text check (alasan_berakhir in ('keluar', 'akun_dicabut')),
  jendela_mulai timestamptz not null default now(),
  jumlah_jendela integer not null default 0,
  jumlah_permintaan integer not null default 0
);
create index sesi_web_pengguna on fakta.sesi_web (pengguna) where berakhir is null;

-- C8: akun dinonaktifkan (misalnya /cabutakun) -> semua sesinya berakhir.
create function fakta.akhiri_sesi_akun() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.aktif and not new.aktif then
    update fakta.sesi_web set berakhir = now(), alasan_berakhir = 'akun_dicabut' where pengguna = new.id and berakhir is null;
  end if;
  return new;
end $$;
create trigger akhiri_sesi_akun after update of aktif on induk.pengguna
  for each row execute function fakta.akhiri_sesi_akun();

-- Masukan: {"email", "sidik_kode", "sidik_sesi"}. Keluaran: {"hasil": "masuk", "berlaku_sampai", "peran", "label"} |
-- {"hasil": "salah", "sisa"} | {"hasil": "tidak_berlaku"}.
create function api.web_sesi_buat(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_r jsonb := fakta.pakai_kode_email(p ->> 'email', p ->> 'sidik_kode');
  v_u induk.pengguna;
  v_sampai timestamptz;
begin
  if v_r ->> 'hasil' <> 'masuk' then
    return v_r;
  end if;
  select u.* into v_u from induk.pengguna u where u.id = (v_r ->> 'pengguna')::bigint;
  insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai)
  values (p ->> 'sidik_sesi', v_u.id, now() + interval '2 hours')
  returning berlaku_sampai into v_sampai;
  return jsonb_build_object('hasil', 'masuk', 'berlaku_sampai', v_sampai, 'peran', v_u.peran,
                            'label', coalesce(v_u.email, 'akun ' || v_u.id));
end $$;

-- ---------------------------------------------------------------------------
-- Bacaan (C1, C9, C10). Semua tanpa angka orang rahasia.
-- ---------------------------------------------------------------------------
-- Versi yang ditampilkan per periode: gaji terakhir dan baca tap yang dipakainya; tanpa gaji -> baca tap terakhir.
create function fakta.web_versi(p_periode bigint, out versi_gaji bigint, out versi_baca bigint)
language sql stable set search_path = '' as $$
  select g.id, coalesce(g.versi_sumber, (select b.id from hitung.versi_terakhir b where b.periode_id = p_periode and b.jenis = 'baca_tap'))
  from (select 1) x left join hitung.versi_terakhir g on g.periode_id = p_periode and g.jenis = 'hitung_gaji'
$$;

create function fakta.web_ringkasan() returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(x order by (x ->> 'awal')), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', p.id, 'awal', p.tanggal_awal, 'akhir', p.tanggal_akhir, 'bayar', p.tanggal_bayar, 'status', p.status,
      'status_rilis', fakta.status_rilis_teks(p.id),
      'ada_gaji', g.id is not null,
      'bisa_diajukan', case when g.id is not null then hitung.periode_bisa_diajukan(p.id) end,
      'kode_gaji', g.versi_kode,
      'orang', count(r.id_karyawan) filter (where not r.rahasia),
      'rahasia', count(r.id_karyawan) filter (where r.rahasia),
      'pendapatan', coalesce(sum(r.total_pendapatan) filter (where not r.rahasia), 0),
      'potongan', coalesce(sum(r.total_potongan) filter (where not r.rahasia), 0),
      'bersih', coalesce(sum(r.gaji_bersih) filter (where not r.rahasia), 0),
      'dibayar', coalesce(sum(r.dibayar) filter (where not r.rahasia), 0),
      'transfer', coalesce(sum(r.dibayar) filter (where not r.rahasia and r.cara_bayar = 'transfer'), 0),
      'tunai', coalesce(sum(r.dibayar) filter (where not r.rahasia and r.cara_bayar = 'tunai'), 0)) as x
    from fakta.periode p
    left join hitung.versi_terakhir g on g.periode_id = p.id and g.jenis = 'hitung_gaji'
    left join lateral (
      select s.*, fakta.rahasia_di_periode(s.id_karyawan, p.id) as rahasia,
             (select k.cara_bayar from induk.karyawan_riwayat k where k.id_karyawan = s.id_karyawan
                and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> p.tanggal_akhir) as cara_bayar
      from hitung.ringkasan_gaji s where s.versi_id = g.id) r on true
    group by p.id, g.id, g.versi_kode) t
$$;

create function fakta.web_gaji(p_periode bigint) returns jsonb
language sql stable set search_path = '' as $$
  with v as (select * from fakta.web_versi(p_periode)),
  p as (select * from fakta.periode where id = p_periode)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id_karyawan, 'nama', k.nama, 'rahasia', s.rahasia,
           'divisi', (select h.divisi from hitung.hasil_harian h, v where h.versi_id = v.versi_baca and h.id_karyawan = s.id_karyawan
                      order by h.tanggal desc limit 1),
           'cara', (select r.cara_bayar from induk.karyawan_riwayat r, p where r.id_karyawan = s.id_karyawan
                      and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> p.tanggal_akhir),
           'bersih', case when not s.rahasia then s.gaji_bersih end,
           'dibayar', case when not s.rahasia then s.dibayar end,
           'peringatan', case when not s.rahasia then to_jsonb(s.peringatan) end) order by s.id_karyawan), '[]'::jsonb)
  from (select g.*, fakta.rahasia_di_periode(g.id_karyawan, p_periode) as rahasia
        from hitung.ringkasan_gaji g, v where g.versi_id = v.versi_gaji) s
  join induk.karyawan k on k.id = s.id_karyawan
$$;

create function fakta.web_orang(p_periode bigint, p_id text) returns jsonb
language sql stable set search_path = '' as $$
  with v as (select * from fakta.web_versi(p_periode)),
  p as (select * from fakta.periode where id = p_periode),
  r as (select fakta.rahasia_di_periode(p_id, p_periode) as rahasia),
  g as (select s.* from hitung.ringkasan_gaji s, v where s.versi_id = v.versi_gaji and s.id_karyawan = p_id)
  select jsonb_build_object(
    'id', k.id, 'nama', k.nama, 'rahasia', r.rahasia,
    'periode', (select jsonb_build_object('id', p.id, 'awal', p.tanggal_awal, 'akhir', p.tanggal_akhir, 'status', p.status) from p),
    'gaji', case when r.rahasia then null else (select jsonb_build_object(
              'pendapatan', g.total_pendapatan, 'potongan', g.total_potongan, 'bersih', g.gaji_bersih, 'sisa_lalu', g.sisa_lalu,
              'dibayar', g.dibayar, 'sisa', g.sisa_pembulatan, 'peringatan', to_jsonb(g.peringatan)) from g) end,
    'komponen', case when r.rahasia then null else coalesce((
              select jsonb_agg(jsonb_build_object('komponen', x.komponen, 'kelompok', x.kelompok, 'nominal', x.nominal, 'bukti', x.bukti)
                               order by x.kelompok, x.komponen)
              from hitung.rincian_gaji x, v where x.versi_id = v.versi_gaji and x.id_karyawan = p_id), '[]'::jsonb) end,
    'harian', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'tanggal', h.tanggal, 'divisi', h.divisi, 'kode_jadwal', h.kode_jadwal, 'jenis_hari', h.jenis_hari,
                       'jadwal_masuk', h.jadwal_masuk, 'jadwal_pulang', h.jadwal_pulang, 'status', h.status, 'asal', h.asal,
                       'masuk', h.masuk, 'pulang', h.pulang, 'menit_telat', h.menit_telat, 'menit_pulang_cepat', h.menit_pulang_cepat,
                       'menit_lebih', h.menit_lebih, 'lupa_tap', h.lupa_tap, 'tanda', to_jsonb(h.tanda)) order by h.tanggal)
              from hitung.hasil_harian h, v where h.versi_id = v.versi_baca and h.id_karyawan = p_id), '[]'::jsonb),
    -- C9: tanpa kolom nilai (jumlah kasbon dan sebagainya).
    'perintah', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'id', x.id, 'jenis', x.jenis, 'mulai', x.tanggal_mulai, 'selesai', coalesce(x.tanggal_selesai, x.tanggal_mulai),
                       'asal', x.asal,
                       'dibatalkan', exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = x.id))
                     order by x.tanggal_mulai, x.id)
              from fakta.perintah_hrd x, p
              where x.id_karyawan = p_id and x.jenis <> 'batalkan_perintah'
                and x.tanggal_mulai <= p.tanggal_akhir and coalesce(x.tanggal_selesai, x.tanggal_mulai) >= p.tanggal_awal), '[]'::jsonb))
  from induk.karyawan k, r where k.id = p_id
$$;

create function fakta.web_perlu_dicek(p_periode bigint) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'jenis', a.jenis, 'tingkat', a.tingkat, 'id_karyawan', a.id_karyawan, 'nama', k.nama, 'divisi', a.divisi,
           'mesin', a.mesin, 'tanggal', a.tanggal, 'tanggal_akhir', a.tanggal_akhir, 'keterangan', a.keterangan)
         order by a.tingkat, a.jenis, a.tanggal, a.id), '[]'::jsonb)
  from hitung.anomali a cross join fakta.web_versi(p_periode) v
  left join induk.karyawan k on k.id = a.id_karyawan
  where a.versi_id = v.versi_baca
$$;

create function fakta.web_keberatan() returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(x order by (x ->> 'terbuka')::boolean desc, (x ->> 'keberatan_id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('keberatan_id', b.id, 'waktu', b.waktu, 'id_karyawan', b.id_karyawan, 'nama', k.nama,
                              'tanggal', b.tanggal, 'alasan', b.alasan, 'periode_id', b.periode_id, 'bukti', b.bukti,
                              'terbuka', d.keberatan_id is null, 'keputusan', d.hasil, 'catatan', d.catatan, 'diputuskan', d.waktu) as x
    from fakta.keberatan b join induk.karyawan k on k.id = b.id_karyawan
    left join fakta.keputusan_keberatan d on d.keberatan_id = b.id
    order by b.id desc limit 200) t
$$;

-- Pintu satu-satunya untuk halaman. Masukan: {"sidik_sesi", "aksi", "periode_id", "id_karyawan"}.
-- Keluaran: {"hasil": "ok", "data": ...} | {"hasil": "sesi_tidak_berlaku"} | {"hasil": "terlalu_banyak"} |
-- {"hasil": "tidak_ada"} | {"hasil": "aksi_salah"} | {"hasil": "keluar"}.
create function api.web_hrd(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_s fakta.sesi_web;
  v_aksi text := coalesce(p ->> 'aksi', '');
  v_periode bigint;
begin
  select s.* into v_s from fakta.sesi_web s where s.sidik = p ->> 'sidik_sesi' for update;
  if v_s.id is null or v_s.berakhir is not null or v_s.berlaku_sampai <= now() or v_s.terakhir_dipakai <= now() - interval '30 minutes'
     or not exists (select 1 from induk.pengguna u where u.id = v_s.pengguna and u.aktif and u.peran in ('hrd', 'pembangun')) then
    return jsonb_build_object('hasil', 'sesi_tidak_berlaku');
  end if;
  if v_aksi = 'keluar' then
    update fakta.sesi_web set berakhir = now(), alasan_berakhir = 'keluar' where id = v_s.id;
    return jsonb_build_object('hasil', 'keluar');
  end if;
  if v_s.jendela_mulai <= now() - interval '1 hour' then
    update fakta.sesi_web set jendela_mulai = now(), jumlah_jendela = 0 where id = v_s.id;
    v_s.jumlah_jendela := 0;
  end if;
  if v_s.jumlah_jendela >= 300 then
    return jsonb_build_object('hasil', 'terlalu_banyak');
  end if;
  update fakta.sesi_web set terakhir_dipakai = now(), jumlah_jendela = jumlah_jendela + 1, jumlah_permintaan = jumlah_permintaan + 1
  where id = v_s.id;
  if v_aksi = 'ringkasan' then
    return jsonb_build_object('hasil', 'ok', 'data', fakta.web_ringkasan());
  end if;
  if v_aksi = 'keberatan' then
    return jsonb_build_object('hasil', 'ok', 'data', fakta.web_keberatan());
  end if;
  if v_aksi not in ('gaji', 'orang', 'perlu_dicek') then
    return jsonb_build_object('hasil', 'aksi_salah');
  end if;
  v_periode := (select x.id from fakta.periode x where x.id::text = p ->> 'periode_id');
  if v_periode is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  if v_aksi = 'gaji' then
    return jsonb_build_object('hasil', 'ok', 'data', fakta.web_gaji(v_periode));
  end if;
  if v_aksi = 'perlu_dicek' then
    return jsonb_build_object('hasil', 'ok', 'data', fakta.web_perlu_dicek(v_periode));
  end if;
  if not exists (select 1 from induk.karyawan k where k.id = p ->> 'id_karyawan') then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  return jsonb_build_object('hasil', 'ok', 'data', fakta.web_orang(v_periode, p ->> 'id_karyawan'));
end $$;

-- ---------------------------------------------------------------------------
-- Hak akses
-- ---------------------------------------------------------------------------
revoke all on function fakta.pakai_kode_email(text, text), fakta.web_versi(bigint), fakta.web_ringkasan(), fakta.web_gaji(bigint),
  fakta.web_orang(bigint, text), fakta.web_perlu_dicek(bigint), fakta.web_keberatan(), fakta.akhiri_sesi_akun() from public;
grant execute on function api.web_sesi_buat(jsonb), api.web_hrd(jsonb) to pintu;
