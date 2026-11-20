-- 0029_pesan_gaji.sql
-- Paket 8c (docs/rencana-8c.md): pesan rincian gaji ke tiap karyawan sesudah rilis. Antrean kirim per orang,
-- isi pesan dari versi gaji yang dirilis, minta ulang oleh karyawan, contoh pesan untuk HRD/pembangun, dan
-- periode "dikunci" bila antrean selesai (keputusan pemilik 20 Nov 2026: yang belum punya akun dianggap selesai).
-- Penjadwal (pg_cron tiap menit) dibuat oleh db/pasang_pintu.sh karena butuh alamat dan kode rahasia.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

create table fakta.kirim_gaji (
  id bigint generated always as identity primary key,
  periode_id bigint not null references fakta.periode (id),
  versi_gaji bigint not null references hitung.versi_hitung (id),
  id_karyawan text not null references induk.karyawan (id),
  status text not null default 'menunggu'
    check (status in ('menunggu', 'sedang', 'terkirim', 'gagal', 'tanpa_akun')),
  telegram_id bigint,
  percobaan integer not null default 0,
  galat text check (length(galat) <= 300),
  dibuat timestamptz not null default now(),
  diperbarui timestamptz not null default now(),
  unique (periode_id, id_karyawan)
);
create index on fakta.kirim_gaji (status) where status in ('menunggu', 'sedang');

-- Akun Telegram aktif milik seorang karyawan (null bila belum daftar).
create function fakta.akun_karyawan(p_id text) returns bigint
language sql stable set search_path = '' as $$
  select u.telegram_id from induk.pengguna u
  where u.id_karyawan = p_id and u.peran = 'karyawan' and u.aktif and u.telegram_id is not null
  order by u.id desc limit 1
$$;

-- Saat gaji dirilis: satu baris kirim per orang di versi yang dirilis (termasuk orang rahasia: pesannya gajinya sendiri).
create function fakta.antre_kirim_gaji() returns trigger
language plpgsql set search_path = '' as $$
begin
  insert into fakta.kirim_gaji (periode_id, versi_gaji, id_karyawan, status)
  select new.periode_id, new.versi_gaji, g.id_karyawan,
         case when fakta.akun_karyawan(g.id_karyawan) is null then 'tanpa_akun' else 'menunggu' end
  from hitung.ringkasan_gaji g where g.versi_id = new.versi_gaji
  on conflict (periode_id, id_karyawan) do nothing;
  return new;
end $$;

-- Periode 'dirilis' menjadi 'dikunci' bila tidak ada lagi yang menunggu/sedang. Mengembalikan true bila baru dikunci.
create function fakta.kunci_bila_selesai(p_periode bigint) returns boolean
language plpgsql set search_path = '' as $$
begin
  if (select x.status from fakta.periode x where x.id = p_periode) = 'dirilis'
     and not exists (select 1 from fakta.kirim_gaji k where k.periode_id = p_periode and k.status in ('menunggu', 'sedang')) then
    perform fakta.ubah_status_periode(p_periode, 'dikunci', 'sistem', 'pesan gaji', 'antrean pesan gaji selesai');
    return true;
  end if;
  return false;
end $$;

create trigger antre_kirim_gaji after insert on fakta.rilis_gaji for each row execute function fakta.antre_kirim_gaji();

-- Rahasia menurut aturan F15c (sama dengan hitung.ringkasan_terlihat, migrasi 0024): rahasia pada hari mana pun
-- di periode itu, atau rahasia sekarang (riwayat terakhir).
create function fakta.rahasia_di_periode(p_id text, p_periode bigint) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from induk.karyawan_riwayat r, fakta.periode p
                 where p.id = p_periode and r.id_karyawan = p_id and r.gaji_rahasia
                   and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') && daterange(p.tanggal_awal, p.tanggal_akhir, '[]'))
      or coalesce((select r.gaji_rahasia from induk.karyawan_riwayat r where r.id_karyawan = p_id
                   order by r.berlaku_dari desc limit 1), false)
$$;

-- Isi pesan gaji satu orang. Versi: yang dirilis bila ada, selain itu versi gaji yang berlaku (untuk contoh).
create function fakta.isi_gaji(p_periode bigint, p_id text) returns jsonb
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
    'sisa', g.sisa_pembulatan,
    'komponen', coalesce((select jsonb_agg(jsonb_build_object('komponen', r.komponen, 'kelompok', r.kelompok,
                                                              'nominal', r.nominal, 'bukti', r.bukti)
                                           order by r.kelompok, r.komponen)
                          from hitung.rincian_gaji r where r.versi_id = v.versi and r.id_karyawan = p_id and r.nominal <> 0),
                         '[]'::jsonb))
  from p, v join hitung.ringkasan_gaji g on g.versi_id = v.versi and g.id_karyawan = p_id
$$;

-- Ambil antrean untuk dikirim Edge Function (penjadwal tiap menit). Masukan: {"batas"}.
-- Baris 'sedang' lebih dari 10 menit (kiriman terputus) dikembalikan ke 'menunggu'. Yang belum punya akun -> 'tanpa_akun'.
-- Keluaran: {"kirim": [{"kirim_id", "telegram_id", ...isi_gaji}], "selesai": [...ringkasan periode yang baru dikunci]}.
create function api.pintu_kirim_gaji_ambil(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_batas integer := least(greatest(coalesce((p ->> 'batas')::integer, 25), 1), 100);
  v_kirim jsonb := '[]'::jsonb;
  r record;
  v_tg bigint;
  v_periode bigint;
  v_selesai jsonb := '[]'::jsonb;
begin
  update fakta.kirim_gaji set status = 'menunggu', diperbarui = now()
  where status = 'sedang' and diperbarui < now() - interval '10 minutes';
  for r in
    select k.* from fakta.kirim_gaji k where k.status = 'menunggu'
    order by k.periode_id, k.id limit v_batas for update skip locked
  loop
    v_tg := fakta.akun_karyawan(r.id_karyawan);
    if v_tg is null then
      update fakta.kirim_gaji set status = 'tanpa_akun', diperbarui = now() where id = r.id;
    else
      update fakta.kirim_gaji set status = 'sedang', telegram_id = v_tg, percobaan = percobaan + 1, diperbarui = now()
      where id = r.id;
      v_kirim := v_kirim || (jsonb_build_object('kirim_id', r.id, 'telegram_id', v_tg) || fakta.isi_gaji(r.periode_id, r.id_karyawan));
    end if;
  end loop;
  for v_periode in select distinct k.periode_id from fakta.kirim_gaji k join fakta.periode x on x.id = k.periode_id
                   where x.status = 'dirilis' loop
    if fakta.kunci_bila_selesai(v_periode) then
      v_selesai := v_selesai || fakta.ringkasan_kirim(v_periode);
    end if;
  end loop;
  return jsonb_build_object('kirim', v_kirim, 'selesai', v_selesai);
end $$;

create function fakta.ringkasan_kirim(p_periode bigint) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('periode_id', p_periode,
    'terkirim', count(*) filter (where k.status = 'terkirim'),
    'tanpa_akun', count(*) filter (where k.status = 'tanpa_akun'),
    'gagal', count(*) filter (where k.status = 'gagal'),
    'penerima', to_jsonb(fakta.penerima(array['hrd', 'pembangun'])))
  from fakta.kirim_gaji k where k.periode_id = p_periode
$$;

-- Hasil kiriman. Masukan: {"hasil": [{"kirim_id", "ok", "galat"}]}. Gagal: dicoba lagi sampai 3 kali, lalu 'gagal'.
-- Baris yang sudah 'terkirim' tidak diturunkan. Keluaran: {"selesai": [...ringkasan periode yang baru dikunci]}.
create function api.pintu_kirim_gaji_hasil(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  h jsonb;
  v_periode bigint;
  v_selesai jsonb := '[]'::jsonb;
begin
  for h in select * from jsonb_array_elements(coalesce(p -> 'hasil', '[]'::jsonb)) loop
    update fakta.kirim_gaji k set
      status = case when (h ->> 'ok')::boolean then 'terkirim' when k.percobaan >= 3 then 'gagal' else 'menunggu' end,
      galat = case when (h ->> 'ok')::boolean then null else left(h ->> 'galat', 300) end,
      telegram_id = coalesce((h ->> 'telegram_id')::bigint, k.telegram_id),
      diperbarui = now()
    where k.id = (h ->> 'kirim_id')::bigint and k.status <> 'terkirim'
      and ((h ->> 'ok')::boolean or k.status = 'sedang');
  end loop;
  for v_periode in select distinct k.periode_id from fakta.kirim_gaji k
                   where k.id in (select (x ->> 'kirim_id')::bigint from jsonb_array_elements(coalesce(p -> 'hasil', '[]'::jsonb)) x)
  loop
    if fakta.kunci_bila_selesai(v_periode) then
      v_selesai := v_selesai || fakta.ringkasan_kirim(v_periode);
    end if;
  end loop;
  return jsonb_build_object('selesai', v_selesai);
end $$;

-- Minta ulang oleh karyawan (tombol "Gaji saya", /gaji [nomor]). Batas 5 kali per jam per akun.
create table fakta.minta_gaji (
  id bigint generated always as identity primary key,
  telegram_id bigint not null,
  periode_id bigint,
  waktu timestamptz not null default now()
);

-- Masukan: {"telegram_id", "periode_id" (boleh kosong: periode terakhir yang dirilis untuk orang ini), "dari_daftar"}.
-- Keluaran: {"hasil": "ada" (+ kirim_id, isi) | "bukan_karyawan" | "belum_ada" | "terlalu_sering"}.
create function api.pintu_gaji_saya(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_id text := (select u.id_karyawan from induk.pengguna u
                where u.telegram_id = v_tg and u.peran = 'karyawan' and u.aktif);
  v_periode bigint;
  v_kirim bigint;
begin
  if v_id is null then
    return jsonb_build_object('hasil', 'bukan_karyawan');
  end if;
  select k.periode_id, k.id into v_periode, v_kirim from fakta.kirim_gaji k join fakta.periode x on x.id = k.periode_id
  where k.id_karyawan = v_id and x.status in ('dirilis', 'dikunci')
    and (p ->> 'periode_id' is null or k.periode_id = (p ->> 'periode_id')::bigint)
  order by x.tanggal_awal desc limit 1;
  if v_periode is null then
    return jsonb_build_object('hasil', 'belum_ada');
  end if;
  perform pg_advisory_xact_lock(hashtext('fakta.minta_gaji'), hashtext(v_tg::text));
  if (select count(*) from fakta.minta_gaji m where m.telegram_id = v_tg and m.waktu > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('hasil', 'terlalu_sering');
  end if;
  insert into fakta.minta_gaji (telegram_id, periode_id) values (v_tg, v_periode);
  return jsonb_build_object('hasil', 'ada', 'kirim_id', v_kirim) || fakta.isi_gaji(v_periode, v_id);
end $$;

-- Contoh pesan untuk HRD/pembangun. Pembangun: siapa saja (keputusan "pembangun bisa semua"); HRD: bukan orang rahasia.
-- Masukan: {"telegram_id", "id_karyawan", "periode_id"}. Keluaran: {"hasil": "ada" (+ isi) | "bukan_hrd" | "rahasia" | "tidak_ada"}.
create function api.pintu_contoh_gaji(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_isi jsonb;
begin
  if api.pintu_hrd(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  v_isi := fakta.isi_gaji((p ->> 'periode_id')::bigint, trim(p ->> 'id_karyawan'));
  if v_isi is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  if (v_isi ->> 'rahasia')::boolean and fakta.pembangun(v_tg) is null then
    return jsonb_build_object('hasil', 'rahasia');
  end if;
  return jsonb_build_object('hasil', 'ada') || v_isi;
end $$;

-- Teks status rilis (0028), "Dikunci" ditulis lebih jelas.
create or replace function fakta.status_rilis_teks(p_periode bigint) returns text
language sql stable set search_path = '' as $$
  select case p.status
           when 'dirilis' then 'Dirilis, pesan gaji sedang dikirim'
           when 'dikunci' then 'Dirilis, pesan gaji selesai dikirim'
           when 'disetujui' then 'Disetujui, menunggu rilis'
           when 'diajukan' then case when fakta.perlu_bos() then 'Diajukan, menunggu persetujuan' else 'Diajukan, menunggu rilis' end
           when 'dihitung' then
             case when fakta.periode_menunggu(p.id) is not null
                    then 'Belum bisa diajukan: rilis dulu periode no. ' || fakta.periode_menunggu(p.id)
                  when not hitung.periode_bisa_diajukan(p.id) then 'Belum bisa diajukan: PPh masa terakhir tertahan'
                  else 'Bisa diajukan' end
           else 'Belum dihitung' end
  from fakta.periode p where p.id = p_periode
$$;

-- Ada pekerjaan untuk penjadwal? Antrean menunggu, kiriman terputus, atau periode 'dirilis' yang antreannya sudah
-- habis (mis. semua belum punya akun) dan tinggal dikunci + diringkas. Edge Function hanya dipanggil bila perlu.
create function fakta.ada_kirim_gaji() returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from fakta.kirim_gaji k where k.status = 'menunggu'
                 or (k.status = 'sedang' and k.diperbarui < now() - interval '10 minutes'))
      or exists (select 1 from fakta.periode x where x.status = 'dirilis'
                 and not exists (select 1 from fakta.kirim_gaji k where k.periode_id = x.id and k.status in ('menunggu', 'sedang')))
$$;

-- Periode yang sudah dirilis sebelum paket ini: antrean diisi sekarang (pemicu hanya untuk rilis baru).
insert into fakta.kirim_gaji (periode_id, versi_gaji, id_karyawan, status)
select r.periode_id, r.versi_gaji, g.id_karyawan,
       case when fakta.akun_karyawan(g.id_karyawan) is null then 'tanpa_akun' else 'menunggu' end
from fakta.rilis_gaji r join hitung.ringkasan_gaji g on g.versi_id = r.versi_gaji
on conflict (periode_id, id_karyawan) do nothing;
do $$
declare
  v bigint;
begin
  perform set_config('app.pengguna', 'migrasi 0029', true);
  for v in select x.id from fakta.periode x where x.status = 'dirilis' loop
    perform fakta.kunci_bila_selesai(v);
  end loop;
end $$;

revoke all on function fakta.rahasia_di_periode(text, bigint), fakta.akun_karyawan(text), fakta.kunci_bila_selesai(bigint), fakta.isi_gaji(bigint, text),
  fakta.ringkasan_kirim(bigint), fakta.ada_kirim_gaji(), fakta.antre_kirim_gaji() from public;
grant execute on function api.pintu_kirim_gaji_ambil(jsonb), api.pintu_kirim_gaji_hasil(jsonb), api.pintu_gaji_saya(jsonb),
  api.pintu_contoh_gaji(jsonb) to pintu;
