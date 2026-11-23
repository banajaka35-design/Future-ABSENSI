-- 0038_keberatan.sql
-- Paket 8e (docs/rencana-8e.md): keberatan karyawan lewat bot. Karyawan mengirim keberatan atas satu tanggal kerja
-- beserta salinan bukti dari gudang (hasil harian dan tap hari itu, tanpa angka rupiah); HRD atau pembangun
-- menerima atau menolak (tolak wajib beralasan). Keputusan pemilik 23 Nov 2026: batas 14 hari sesudah tanggal bayar;
-- keberatan diterima tidak mengubah gaji (periode dirilis: selisih dibayar HRD di luar sistem); bos tidak diberi tahu.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

create table fakta.keberatan (
  id bigint generated always as identity primary key,
  waktu timestamptz not null default now(),
  pengguna bigint not null references induk.pengguna (id),
  id_karyawan text not null references induk.karyawan (id),
  tanggal date not null,
  alasan text not null check (length(trim(alasan)) between 1 and 300),
  bukti jsonb not null,
  periode_id bigint not null references fakta.periode (id),
  versi_baca bigint references hitung.versi_hitung (id)
);
create index keberatan_orang on fakta.keberatan (id_karyawan, tanggal);
create trigger tolak_ubah before update or delete on fakta.keberatan for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.keberatan for each statement execute function jejak.tolak_ubah();

create table fakta.keputusan_keberatan (
  keberatan_id bigint primary key references fakta.keberatan (id),
  hasil text not null check (hasil in ('diterima', 'ditolak')),
  catatan text check (catatan is null or length(catatan) <= 300),
  oleh bigint not null references induk.pengguna (id),
  waktu timestamptz not null default now(),
  check (hasil = 'diterima' or length(trim(coalesce(catatan, ''))) > 0)
);
create trigger tolak_ubah before update or delete on fakta.keputusan_keberatan for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.keputusan_keberatan for each statement execute function jejak.tolak_ubah();

-- Draf: karyawan melihat bukti dulu, lalu Kirim atau Batal (berlaku 10 menit).
create table fakta.draf_keberatan (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  pengguna bigint not null references induk.pengguna (id),
  id_karyawan text not null references induk.karyawan (id),
  tanggal date not null,
  alasan text not null check (length(trim(alasan)) between 1 and 300),
  bukti jsonb not null,
  periode_id bigint not null references fakta.periode (id),
  versi_baca bigint references hitung.versi_hitung (id),
  kedaluwarsa timestamptz not null,
  selesai_pada timestamptz,
  hasil text check (hasil in ('dikirim', 'dibatalkan')),
  keberatan_id bigint references fakta.keberatan (id),
  check ((selesai_pada is null) = (hasil is null)),
  check ((hasil = 'dikirim') = (keberatan_id is not null))
);

-- Bukti satu orang di satu tanggal dari baca tap terakhir periode itu. Tanpa angka rupiah.
create function fakta.bukti_keberatan(p_id text, p_tanggal date, p_versi bigint) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'hari', (select jsonb_build_object('status', h.status, 'asal', h.asal, 'jenis_hari', h.jenis_hari, 'kode_jadwal', h.kode_jadwal,
                                       'jadwal_masuk', h.jadwal_masuk, 'jadwal_pulang', h.jadwal_pulang, 'masuk', h.masuk,
                                       'pulang', h.pulang, 'menit_telat', h.menit_telat, 'menit_pulang_cepat', h.menit_pulang_cepat,
                                       'menit_lebih', h.menit_lebih, 'lupa_tap', h.lupa_tap, 'tanda', to_jsonb(h.tanda))
             from hitung.hasil_harian h where h.versi_id = p_versi and h.id_karyawan = p_id and h.tanggal = p_tanggal),
    'tap', coalesce((select jsonb_agg(jsonb_build_object('waktu', t.waktu_baku, 'peran', t.peran) order by t.waktu_baku)
                     from hitung.tap_bersih t where t.versi_id = p_versi and t.id_karyawan = p_id and t.tanggal_kerja = p_tanggal),
                    '[]'::jsonb))
$$;

-- Keberatan masih terbuka (belum diputuskan) untuk orang dan tanggal itu.
create function fakta.keberatan_terbuka(p_id text, p_tanggal date) returns bigint
language sql stable set search_path = '' as $$
  select k.id from fakta.keberatan k
  where k.id_karyawan = p_id and k.tanggal = p_tanggal
    and not exists (select 1 from fakta.keputusan_keberatan d where d.keberatan_id = k.id)
  order by k.id limit 1
$$;

-- Pemeriksaan bersama siapkan dan kirim. Keluaran null bila boleh, atau {"hasil": alasan tolak, ...}.
create function fakta.periksa_keberatan(p_id text, p_tanggal date) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_hari_ini date := (now() at time zone 'Asia/Jakarta')::date;
  v_p fakta.periode := fakta.periode_tanggal(p_tanggal);
  v_ada bigint;
begin
  if p_tanggal > v_hari_ini then
    return jsonb_build_object('hasil', 'tanggal_depan');
  end if;
  if v_p.id is null then
    return jsonb_build_object('hasil', 'tanpa_periode');
  end if;
  if not exists (select 1 from hitung.versi_terakhir g where g.periode_id = v_p.id and g.jenis = 'baca_tap') then
    return jsonb_build_object('hasil', 'belum_dihitung');
  end if;
  if v_hari_ini > v_p.tanggal_bayar + 14 then
    return jsonb_build_object('hasil', 'lewat_batas', 'batas', v_p.tanggal_bayar + 14);
  end if;
  v_ada := fakta.keberatan_terbuka(p_id, p_tanggal);
  if v_ada is not null then
    return jsonb_build_object('hasil', 'sudah_ada', 'keberatan_id', v_ada);
  end if;
  if (select count(*) from fakta.keberatan k
      where k.id_karyawan = p_id and (k.waktu at time zone 'Asia/Jakarta')::date = v_hari_ini) >= 5 then
    return jsonb_build_object('hasil', 'terlalu_banyak');
  end if;
  return null;
end $$;

-- Masukan: {"telegram_id", "tanggal", "alasan"}. Keluaran: {"hasil": "siap" | "bukan_karyawan" | "alasan_kosong" |
-- "alasan_panjang" | "tanggal_depan" | "tanpa_periode" | "belum_dihitung" | "lewat_batas" | "sudah_ada" | "terlalu_banyak",
-- "draf_id", "id_karyawan", "nama", "tanggal", "alasan", "bukti", "periode": {...}}.
create function api.pintu_keberatan_siapkan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u induk.pengguna;
  v_tanggal date := (p ->> 'tanggal')::date;
  v_alasan text := trim(coalesce(p ->> 'alasan', ''));
  v_cek jsonb;
  v_p fakta.periode;
  v_versi bigint;
  v_bukti jsonb;
  v_draf bigint;
begin
  select u.* into v_u from induk.pengguna u
  where u.telegram_id = (p ->> 'telegram_id')::bigint and u.peran = 'karyawan' and u.aktif and u.id_karyawan is not null;
  if v_u.id is null then
    return jsonb_build_object('hasil', 'bukan_karyawan');
  end if;
  if v_alasan = '' then
    return jsonb_build_object('hasil', 'alasan_kosong');
  end if;
  if length(v_alasan) > 300 then
    return jsonb_build_object('hasil', 'alasan_panjang');
  end if;
  v_cek := fakta.periksa_keberatan(v_u.id_karyawan, v_tanggal);
  if v_cek is not null then
    return v_cek;
  end if;
  v_p := fakta.periode_tanggal(v_tanggal);
  v_versi := (select g.id from hitung.versi_terakhir g where g.periode_id = v_p.id and g.jenis = 'baca_tap');
  v_bukti := fakta.bukti_keberatan(v_u.id_karyawan, v_tanggal, v_versi);
  perform set_config('app.pengguna', 'keberatan-telegram', true);
  update fakta.draf_keberatan set selesai_pada = now(), hasil = 'dibatalkan' where pengguna = v_u.id and selesai_pada is null;
  insert into fakta.draf_keberatan (pengguna, id_karyawan, tanggal, alasan, bukti, periode_id, versi_baca, kedaluwarsa)
  values (v_u.id, v_u.id_karyawan, v_tanggal, v_alasan, v_bukti, v_p.id, v_versi, now() + interval '10 minutes')
  returning id into v_draf;
  return jsonb_build_object('hasil', 'siap', 'draf_id', v_draf, 'id_karyawan', v_u.id_karyawan,
    'nama', (select k.nama from induk.karyawan k where k.id = v_u.id_karyawan), 'tanggal', v_tanggal, 'alasan', v_alasan,
    'bukti', v_bukti, 'periode', jsonb_build_object('id', v_p.id, 'awal', v_p.tanggal_awal, 'akhir', v_p.tanggal_akhir,
                                                    'bayar', v_p.tanggal_bayar, 'status', v_p.status));
end $$;

-- Masukan: {"telegram_id", "draf_id", "ya"}. Keluaran: {"hasil": "dikirim" | "dibatalkan" | "tidak_ada" | alasan tolak,
-- "keberatan_id", "id_karyawan", "nama", "tanggal", "alasan", "bukti", "periode", "dirilis", "penerima": [telegram]}.
create function api.pintu_keberatan_kirim(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u induk.pengguna;
  v_d fakta.draf_keberatan;
  v_cek jsonb;
  v_id bigint;
  v_p fakta.periode;
begin
  select u.* into v_u from induk.pengguna u
  where u.telegram_id = (p ->> 'telegram_id')::bigint and u.peran = 'karyawan' and u.aktif;
  select d.* into v_d from fakta.draf_keberatan d
  where d.id = (p ->> 'draf_id')::bigint and d.pengguna = v_u.id for update;
  if v_u.id is null or v_d.id is null or v_d.selesai_pada is not null or v_d.kedaluwarsa < now() then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  perform set_config('app.pengguna', 'keberatan-telegram', true);
  if not coalesce((p ->> 'ya')::boolean, false) then
    update fakta.draf_keberatan set selesai_pada = now(), hasil = 'dibatalkan' where id = v_d.id;
    return jsonb_build_object('hasil', 'dibatalkan');
  end if;
  perform pg_advisory_xact_lock(hashtext('fakta.keberatan'), hashtext(v_d.id_karyawan));
  v_cek := fakta.periksa_keberatan(v_d.id_karyawan, v_d.tanggal);
  if v_cek is not null then
    update fakta.draf_keberatan set selesai_pada = now(), hasil = 'dibatalkan' where id = v_d.id;
    return v_cek;
  end if;
  insert into fakta.keberatan (pengguna, id_karyawan, tanggal, alasan, bukti, periode_id, versi_baca)
  values (v_u.id, v_d.id_karyawan, v_d.tanggal, v_d.alasan, v_d.bukti, v_d.periode_id, v_d.versi_baca)
  returning id into v_id;
  update fakta.draf_keberatan set selesai_pada = now(), hasil = 'dikirim', keberatan_id = v_id where id = v_d.id;
  select x.* into v_p from fakta.periode x where x.id = v_d.periode_id;
  return jsonb_build_object('hasil', 'dikirim', 'keberatan_id', v_id, 'id_karyawan', v_d.id_karyawan,
    'nama', (select k.nama from induk.karyawan k where k.id = v_d.id_karyawan), 'tanggal', v_d.tanggal, 'alasan', v_d.alasan,
    'bukti', v_d.bukti, 'periode', jsonb_build_object('id', v_p.id, 'awal', v_p.tanggal_awal, 'akhir', v_p.tanggal_akhir,
                                                      'bayar', v_p.tanggal_bayar, 'status', v_p.status),
    'dirilis', v_p.status in ('dirilis', 'dikunci'), 'penerima', to_jsonb(fakta.penerima(array['hrd', 'pembangun'])));
end $$;

-- Masukan: {"telegram_id", "keberatan_id", "terima", "catatan"}. Keluaran: {"hasil": "diputuskan" | "bukan_hrd" |
-- "tidak_ada" | "sudah_diputuskan" | "alasan_wajib" | "catatan_panjang", "keputusan", "catatan", "keberatan_id",
-- "id_karyawan", "nama", "tanggal", "dirilis", "periode", "karyawan_telegram", "penerima": [telegram HRD/pembangun lain]}.
create function api.pintu_keberatan_putuskan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_oleh bigint := api.pintu_hrd(v_tg);
  v_k fakta.keberatan;
  v_lama fakta.keputusan_keberatan;
  v_terima boolean := coalesce((p ->> 'terima')::boolean, false);
  v_catatan text := nullif(trim(coalesce(p ->> 'catatan', '')), '');
  v_p fakta.periode;
begin
  if v_oleh is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select k.* into v_k from fakta.keberatan k where k.id = (p ->> 'keberatan_id')::bigint for update;
  if v_k.id is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  select d.* into v_lama from fakta.keputusan_keberatan d where d.keberatan_id = v_k.id;
  if v_lama.keberatan_id is not null then
    return jsonb_build_object('hasil', 'sudah_diputuskan', 'keberatan_id', v_k.id, 'keputusan', v_lama.hasil,
      'oleh', (select coalesce(u.email, 'Telegram ...' || right(u.telegram_id::text, 4)) from induk.pengguna u where u.id = v_lama.oleh));
  end if;
  if not v_terima and v_catatan is null then
    return jsonb_build_object('hasil', 'alasan_wajib', 'keberatan_id', v_k.id);
  end if;
  if length(coalesce(v_catatan, '')) > 300 then
    return jsonb_build_object('hasil', 'catatan_panjang', 'keberatan_id', v_k.id);
  end if;
  perform set_config('app.pengguna', 'keberatan-telegram', true);
  insert into fakta.keputusan_keberatan (keberatan_id, hasil, catatan, oleh)
  values (v_k.id, case when v_terima then 'diterima' else 'ditolak' end, v_catatan, v_oleh);
  select x.* into v_p from fakta.periode x where x.id = v_k.periode_id;
  return jsonb_build_object('hasil', 'diputuskan', 'keputusan', case when v_terima then 'diterima' else 'ditolak' end,
    'catatan', v_catatan, 'keberatan_id', v_k.id, 'id_karyawan', v_k.id_karyawan,
    'nama', (select k.nama from induk.karyawan k where k.id = v_k.id_karyawan), 'tanggal', v_k.tanggal,
    'dirilis', v_p.status in ('dirilis', 'dikunci'),
    'periode', jsonb_build_object('id', v_p.id, 'awal', v_p.tanggal_awal, 'akhir', v_p.tanggal_akhir, 'status', v_p.status),
    'karyawan_telegram', fakta.akun_karyawan(v_k.id_karyawan),
    'penerima', to_jsonb(array(select t from unnest(fakta.penerima(array['hrd', 'pembangun'])) t where t <> v_tg)));
end $$;

-- Masukan: {"telegram_id"}. Karyawan: 10 keberatan terakhirnya. HRD/pembangun: keberatan yang belum diputuskan (paling
-- lama dulu, paling banyak 20). Keluaran: {"hasil": "karyawan" | "hrd" | "bukan_akun", "daftar": [...], "jumlah"}.
create function api.pintu_keberatan_daftar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_id text := (select u.id_karyawan from induk.pengguna u where u.telegram_id = v_tg and u.peran = 'karyawan' and u.aktif);
begin
  if v_id is not null then
    return jsonb_build_object('hasil', 'karyawan', 'daftar', coalesce((
      select jsonb_agg(x order by (x ->> 'keberatan_id')::bigint desc) from (
        select jsonb_build_object('keberatan_id', k.id, 'tanggal', k.tanggal, 'alasan', k.alasan,
                                  'keputusan', d.hasil, 'catatan', d.catatan) as x
        from fakta.keberatan k left join fakta.keputusan_keberatan d on d.keberatan_id = k.id
        where k.id_karyawan = v_id order by k.id desc limit 10) s), '[]'::jsonb));
  end if;
  if api.pintu_hrd(v_tg) is not null then
    return jsonb_build_object('hasil', 'hrd',
      'jumlah', (select count(*) from fakta.keberatan k
                 where not exists (select 1 from fakta.keputusan_keberatan d where d.keberatan_id = k.id)),
      'daftar', coalesce((
        select jsonb_agg(x order by (x ->> 'keberatan_id')::bigint) from (
          select jsonb_build_object('keberatan_id', k.id, 'id_karyawan', k.id_karyawan, 'nama', n.nama, 'tanggal', k.tanggal,
                                    'alasan', k.alasan, 'waktu', k.waktu) as x
          from fakta.keberatan k join induk.karyawan n on n.id = k.id_karyawan
          where not exists (select 1 from fakta.keputusan_keberatan d where d.keberatan_id = k.id)
          order by k.id limit 20) s), '[]'::jsonb));
  end if;
  return jsonb_build_object('hasil', 'bukan_akun');
end $$;

-- ---------------------------------------------------------------------------
-- Hak akses
-- ---------------------------------------------------------------------------
revoke all on function fakta.bukti_keberatan(text, date, bigint), fakta.keberatan_terbuka(text, date),
  fakta.periksa_keberatan(text, date) from public;
grant execute on function api.pintu_keberatan_siapkan(jsonb), api.pintu_keberatan_kirim(jsonb),
  api.pintu_keberatan_putuskan(jsonb), api.pintu_keberatan_daftar(jsonb) to pintu;
