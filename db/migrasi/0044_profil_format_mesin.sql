-- 0044_profil_format_mesin.sql
-- Paket F2 (docs/rencana-f2-konfirmasi-format.md, di-"buat" 25 Nov 2026 16.46 dengan K1 (a) bot saja, K2 (a) HRD dan pembangun,
-- K3 (a) judul berubah ditanyakan lagi; permintaan perubahan 07 untuk kasus F09):
--   file mesin berbentuk tabel yang judul kolomnya belum dikenal ditahan, HRD yang mengirim memilih kolom sekali lewat bot dengan
--   contoh hasil bacaan, dan pilihannya disimpan sebagai profil format per mesin + sidik judul kolom.
-- Pembaca file (sistem/urai) tetap di Edge Function; database hanya menyimpan percakapan dan profil.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- Profil format file per mesin. Satu profil aktif per (mesin, sidik judul). Profil tidak dihapus: dinonaktifkan dengan
-- mencatat siapa dan kapan (riwayat lengkap juga di jejak.perubahan).
create table induk.profil_file_mesin (
  id bigint generated always as identity primary key,
  mesin text not null references induk.mesin (kode),
  -- Judul kolom yang dinormalkan (huruf kecil, hanya huruf dan angka), dipisah "|" (sistem/urai/urai.ts sidikJudul).
  sidik_judul text not null check (length(sidik_judul) between 1 and 4000),
  judul jsonb not null check (jsonb_typeof(judul) = 'array'),
  kolom_id text not null,
  kolom_waktu text,
  kolom_tanggal text,
  kolom_jam text,
  susunan text not null check (susunan in ('dmy', 'mdy', 'ymd')),
  aktif boolean not null default true,
  disetujui_oleh bigint not null references induk.pengguna (id),
  disetujui timestamptz not null default now(),
  konfirmasi_id bigint,
  dinonaktifkan_oleh bigint references induk.pengguna (id),
  dinonaktifkan timestamptz,
  alasan_nonaktif text,
  check ((kolom_waktu is not null and kolom_tanggal is null and kolom_jam is null)
         or (kolom_waktu is null and kolom_tanggal is not null and kolom_jam is not null)),
  check (aktif = (dinonaktifkan is null))
);
create unique index profil_file_mesin_satu_aktif on induk.profil_file_mesin (mesin, sidik_judul) where aktif;
create trigger catat_perubahan after insert or update or delete on induk.profil_file_mesin
  for each row execute function jejak.catat_perubahan();

-- Penjaga: profil tidak dihapus dan isinya tidak diubah; yang boleh hanya menonaktifkan sekali.
create function induk.jaga_profil_file_mesin() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Profil format mesin tidak boleh dihapus; nonaktifkan' using errcode = 'P0001';
  end if;
  if not old.aktif
     or (to_jsonb(new) - 'aktif' - 'dinonaktifkan_oleh' - 'dinonaktifkan' - 'alasan_nonaktif')
        is distinct from (to_jsonb(old) - 'aktif' - 'dinonaktifkan_oleh' - 'dinonaktifkan' - 'alasan_nonaktif') then
    raise exception 'Profil format mesin hanya boleh dinonaktifkan; pilihan baru disimpan sebagai profil baru' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger jaga_profil before update or delete on induk.profil_file_mesin
  for each row execute function induk.jaga_profil_file_mesin();
create trigger tolak_kosongkan before truncate on induk.profil_file_mesin
  for each statement execute function jejak.tolak_ubah();

-- Percakapan konfirmasi format: satu baris per file yang ditahan. Langkah dan pilihan berubah selama percakapan (seperti
-- antrean kerja); hasil akhirnya (disimpan/ditolak) tetap tercatat.
create table fakta.konfirmasi_format (
  id bigint generated always as identity primary key,
  update_id bigint not null unique,
  telegram_id bigint not null,
  pengguna bigint not null references induk.pengguna (id),
  file_id text not null,
  nama_file text not null,
  mesin text not null references induk.mesin (kode),
  tanggal_kirim date not null,
  judul jsonb not null check (jsonb_typeof(judul) = 'array' and jsonb_array_length(judul) between 2 and 256),
  sidik_judul text not null check (length(sidik_judul) between 1 and 4000),
  analisa jsonb not null default '[]' check (jsonb_typeof(analisa) = 'array'),
  langkah text not null default 'id' check (langkah in ('id', 'waktu', 'tanggal', 'jam', 'susunan', 'contoh', 'selesai')),
  pilihan jsonb not null default '{}' check (jsonb_typeof(pilihan) = 'object'),
  status text not null default 'menunggu' check (status in ('menunggu', 'disimpan', 'ditolak')),
  profil_id bigint references induk.profil_file_mesin (id),
  dibuat timestamptz not null default now(),
  diubah timestamptz not null default now(),
  selesai timestamptz
);
alter table induk.profil_file_mesin add foreign key (konfirmasi_id) references fakta.konfirmasi_format (id);

-- Bentuk profil untuk pembaca (sistem/urai ProfilUrai).
create function fakta.profil_json(p induk.profil_file_mesin) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'mesin', p.mesin, 'sidik_judul', p.sidik_judul, 'judul', p.judul,
                            'kolom_id', p.kolom_id, 'kolom_waktu', p.kolom_waktu, 'kolom_tanggal', p.kolom_tanggal,
                            'kolom_jam', p.kolom_jam, 'susunan', p.susunan)
$$;

create function fakta.konfirmasi_json(k fakta.konfirmasi_format) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', k.id, 'update_id', k.update_id, 'file_id', k.file_id, 'nama_file', k.nama_file,
                            'mesin', k.mesin, 'tanggal_kirim', k.tanggal_kirim, 'judul', k.judul, 'sidik_judul', k.sidik_judul,
                            'analisa', k.analisa, 'langkah', k.langkah, 'pilihan', k.pilihan, 'status', k.status,
                            'profil_id', k.profil_id)
$$;

-- Profil aktif untuk satu mesin dan sidik judul, atau null. Pemanggil: HRD/pembangun lewat bot (telegram_id) atau pemilik tautan
-- unggah yang sah (kode_sidik). Masukan: {"telegram_id" | "kode_sidik", "mesin", "sidik_judul"}.
create function api.pintu_profil_mesin(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_p induk.profil_file_mesin;
begin
  if api.pintu_hrd((p ->> 'telegram_id')::bigint) is null
     and (p ->> 'kode_sidik' is null or (fakta.pemilik_tautan(p ->> 'kode_sidik')).id is null) then
    return null;
  end if;
  select * into v_p from induk.profil_file_mesin x
  where x.mesin = p ->> 'mesin' and x.sidik_judul = p ->> 'sidik_judul' and x.aktif;
  if v_p.id is null then
    return null;
  end if;
  return fakta.profil_json(v_p);
end $$;

-- Mulai percakapan untuk satu file yang ditahan. Masukan: {"update_id", "telegram_id", "file_id", "nama_file", "mesin",
-- "tanggal_kirim", "judul", "sidik_judul", "analisa"}. Keluaran: {"hasil": "mulai" | "sudah_ada" | "ditolak", "konfirmasi",
-- "pembangun": [telegram_id pembangun selain pengirim]}.
create function api.pintu_konfirmasi_mulai(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pengguna bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_k fakta.konfirmasi_format;
begin
  if v_pengguna is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Akun Anda belum terdaftar untuk mengirim file.');
  end if;
  if not exists (select 1 from induk.mesin m where m.kode = p ->> 'mesin') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Mesin %s tidak dikenal.', p ->> 'mesin'));
  end if;
  select * into v_k from fakta.konfirmasi_format k where k.update_id = (p ->> 'update_id')::bigint;
  if v_k.id is not null then
    return jsonb_build_object('hasil', 'sudah_ada', 'konfirmasi', fakta.konfirmasi_json(v_k));
  end if;
  insert into fakta.konfirmasi_format (update_id, telegram_id, pengguna, file_id, nama_file, mesin, tanggal_kirim, judul,
                                       sidik_judul, analisa)
  values ((p ->> 'update_id')::bigint, (p ->> 'telegram_id')::bigint, v_pengguna, p ->> 'file_id', p ->> 'nama_file',
          p ->> 'mesin', (p ->> 'tanggal_kirim')::date, p -> 'judul', p ->> 'sidik_judul', coalesce(p -> 'analisa', '[]'))
  returning * into v_k;
  return jsonb_build_object('hasil', 'mulai', 'konfirmasi', fakta.konfirmasi_json(v_k),
    'pembangun', to_jsonb(array(select t from unnest(fakta.penerima(array['pembangun'])) t
                                where t <> (p ->> 'telegram_id')::bigint)));
end $$;

-- Ambil percakapan milik pengirim. Masukan: {"id", "telegram_id"}. Keluaran: konfirmasi (dengan status), atau null bila bukan
-- milik akun itu atau akun bukan HRD/pembangun lagi.
create function api.pintu_konfirmasi_ambil(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_k fakta.konfirmasi_format;
begin
  if api.pintu_hrd((p ->> 'telegram_id')::bigint) is null then
    return null;
  end if;
  select * into v_k from fakta.konfirmasi_format k
  where k.id = (p ->> 'id')::bigint and k.telegram_id = (p ->> 'telegram_id')::bigint;
  return case when v_k.id is null then null else fakta.konfirmasi_json(v_k) end;
end $$;

-- Pindah langkah (hanya dari langkah yang diharapkan; tombol lama tidak berlaku). Masukan: {"id", "telegram_id",
-- "langkah_lama", "langkah_baru", "pilihan"} (pilihan = seluruh isi pilihan yang baru). Keluaran: {"hasil": "diubah" |
-- "tidak_berlaku", "konfirmasi"}.
create function api.pintu_konfirmasi_ubah(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_k fakta.konfirmasi_format;
begin
  if api.pintu_hrd((p ->> 'telegram_id')::bigint) is null or jsonb_typeof(p -> 'pilihan') is distinct from 'object'
     or coalesce(p ->> 'langkah_baru', '') not in ('id', 'waktu', 'tanggal', 'jam', 'susunan', 'contoh') then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  update fakta.konfirmasi_format k
  set langkah = p ->> 'langkah_baru', pilihan = p -> 'pilihan', diubah = now()
  where k.id = (p ->> 'id')::bigint and k.telegram_id = (p ->> 'telegram_id')::bigint and k.status = 'menunggu'
    and k.langkah = p ->> 'langkah_lama'
  returning * into v_k;
  if v_k.id is null then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  return jsonb_build_object('hasil', 'diubah', 'konfirmasi', fakta.konfirmasi_json(v_k));
end $$;

-- Akhiri percakapan. Masukan: {"id", "telegram_id", "simpan": true | false}.
-- simpan = true (hanya dari langkah contoh hasil bacaan; K2 HRD atau pembangun): profil lama untuk mesin + sidik yang sama
-- dinonaktifkan, profil baru disimpan. simpan = false: percakapan ditolak (file lalu dicatat ditolak oleh Edge Function).
-- Keluaran: {"hasil": "disimpan" | "ditolak" | "tidak_berlaku" | "pilihan_salah", "konfirmasi", "profil",
-- "pembangun": [telegram_id pembangun selain pengirim]}.
create function api.pintu_konfirmasi_selesai(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pengguna bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_k fakta.konfirmasi_format;
  v_pil jsonb;
  v_kolom text[];
  v_p induk.profil_file_mesin;
  v_simpan boolean := coalesce((p ->> 'simpan')::boolean, false);
begin
  if v_pengguna is null then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  select * into v_k from fakta.konfirmasi_format k
  where k.id = (p ->> 'id')::bigint and k.telegram_id = (p ->> 'telegram_id')::bigint and k.status = 'menunggu'
  for update;
  if v_k.id is null or (v_simpan and v_k.langkah <> 'contoh') then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  if v_simpan then
    v_pil := v_k.pilihan;
    v_kolom := array_remove(array[v_pil ->> 'kolom_id', v_pil ->> 'kolom_waktu', v_pil ->> 'kolom_tanggal', v_pil ->> 'kolom_jam'], null);
    -- Kolom harus judul yang ada di file, berbeda satu sama lain, dan lengkap (satu kolom tanggal-jam atau tanggal + jam).
    if v_pil ->> 'kolom_id' is null or coalesce(v_pil ->> 'susunan', '') not in ('dmy', 'mdy', 'ymd')
       or not ((v_pil ? 'kolom_waktu' and not v_pil ? 'kolom_tanggal' and not v_pil ? 'kolom_jam')
               or (not v_pil ? 'kolom_waktu' and v_pil ? 'kolom_tanggal' and v_pil ? 'kolom_jam'))
       or (select count(distinct c) from unnest(v_kolom) c) <> cardinality(v_kolom)
       or exists (select 1 from unnest(v_kolom) c where not v_k.judul ? c) then
      return jsonb_build_object('hasil', 'pilihan_salah');
    end if;
    perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
    update induk.profil_file_mesin x
    set aktif = false, dinonaktifkan_oleh = v_pengguna, dinonaktifkan = now(),
        alasan_nonaktif = format('diganti profil dari konfirmasi no. %s', v_k.id)
    where x.mesin = v_k.mesin and x.sidik_judul = v_k.sidik_judul and x.aktif;
    insert into induk.profil_file_mesin (mesin, sidik_judul, judul, kolom_id, kolom_waktu, kolom_tanggal, kolom_jam, susunan,
                                         disetujui_oleh, konfirmasi_id)
    values (v_k.mesin, v_k.sidik_judul, v_k.judul, v_pil ->> 'kolom_id', v_pil ->> 'kolom_waktu', v_pil ->> 'kolom_tanggal',
            v_pil ->> 'kolom_jam', v_pil ->> 'susunan', v_pengguna, v_k.id)
    returning * into v_p;
    update fakta.konfirmasi_format set status = 'disimpan', langkah = 'selesai', profil_id = v_p.id, selesai = now(), diubah = now()
    where id = v_k.id returning * into v_k;
  else
    update fakta.konfirmasi_format set status = 'ditolak', langkah = 'selesai', selesai = now(), diubah = now()
    where id = v_k.id returning * into v_k;
  end if;
  return jsonb_build_object('hasil', case when v_simpan then 'disimpan' else 'ditolak' end,
    'konfirmasi', fakta.konfirmasi_json(v_k), 'profil', case when v_p.id is null then null else fakta.profil_json(v_p) end,
    'pembangun', to_jsonb(array(select t from unnest(fakta.penerima(array['pembangun'])) t
                                where t <> (p ->> 'telegram_id')::bigint)));
end $$;

-- Daftar profil aktif (hanya pembangun). Masukan: {"telegram_id"}.
-- Keluaran: {"hasil": "ada" | "bukan_pembangun", "profil": [{... profil, "oleh", "disetujui"}]}.
create function api.pintu_profil_daftar(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if fakta.pembangun((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  return jsonb_build_object('hasil', 'ada', 'profil', coalesce((
    select jsonb_agg(fakta.profil_json(x) || jsonb_build_object(
             'oleh', u.peran || ' ' || coalesce(u.email, 'Telegram ...' || right(u.telegram_id::text, 4)),
             'disetujui', to_char(x.disetujui at time zone 'Asia/Jakarta', 'DD-MM-YYYY HH24.MI'))
           order by x.mesin, x.id)
    from induk.profil_file_mesin x join induk.pengguna u on u.id = x.disetujui_oleh
    where x.aktif), '[]'::jsonb));
end $$;

-- Nonaktifkan satu profil (hanya pembangun). File yang sudah dihitung tidak berubah; file berikutnya ditanyakan lagi.
-- Masukan: {"telegram_id", "profil_id"}. Keluaran: {"hasil": "dihapus" | "tidak_ada" | "bukan_pembangun", "profil"}.
create function api.pintu_profil_hapus(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pengguna bigint := fakta.pembangun((p ->> 'telegram_id')::bigint);
  v_p induk.profil_file_mesin;
begin
  if v_pengguna is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  update induk.profil_file_mesin x
  set aktif = false, dinonaktifkan_oleh = v_pengguna, dinonaktifkan = now(), alasan_nonaktif = 'dihapus pembangun (/profilmesin)'
  where x.id = (p ->> 'profil_id')::bigint and x.aktif
  returning * into v_p;
  if v_p.id is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  return jsonb_build_object('hasil', 'dihapus', 'profil', fakta.profil_json(v_p));
end $$;

revoke all on function induk.jaga_profil_file_mesin(), fakta.profil_json(induk.profil_file_mesin),
  fakta.konfirmasi_json(fakta.konfirmasi_format) from public;
grant execute on function api.pintu_profil_mesin(jsonb), api.pintu_konfirmasi_mulai(jsonb), api.pintu_konfirmasi_ambil(jsonb),
  api.pintu_konfirmasi_ubah(jsonb), api.pintu_konfirmasi_selesai(jsonb), api.pintu_profil_daftar(jsonb),
  api.pintu_profil_hapus(jsonb) to pintu;
