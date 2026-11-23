-- 0040_coba_aturan.sql
-- Paket 9c (docs/rencana-9c.md): coba aturan dari web HRD. Aturan untuk rentang periode diganti di dalam sub-transaksi,
-- baca tap dan hitung gaji dijalankan dengan mesin yang sama, hasilnya dibandingkan dengan versi gaji yang berlaku,
-- lalu SEMUA dibatalkan (K1). Yang keluar hanya perbandingan tanpa orang rahasia (K3) dan satu catatan di
-- fakta.coba_aturan. Migrasi hanya maju; jangan diedit setelah dipasang.

create table fakta.coba_aturan (
  id bigint generated always as identity primary key,
  waktu timestamptz not null default now(),
  pengguna bigint not null references induk.pengguna (id),
  periode_id bigint not null references fakta.periode (id),
  aturan jsonb not null,
  hasil text not null check (hasil in ('selesai', 'gagal')),
  ringkasan jsonb,
  galat text,
  lama_ms integer
);
create trigger tolak_ubah before update or delete on fakta.coba_aturan for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.coba_aturan for each statement execute function jejak.tolak_ubah();

-- Nilai aturan yang berlaku di tanggal akhir periode (cakupan perusahaan), untuk mengisi awal isian halaman.
create function fakta.aturan_sekarang(p_periode bigint) returns jsonb
language sql stable set search_path = '' as $$
  with p as (select * from fakta.periode where id = p_periode)
  select jsonb_build_object(
    'periode', (select jsonb_build_object('id', p.id, 'awal', p.tanggal_awal, 'akhir', p.tanggal_akhir, 'status', p.status) from p),
    'boleh', (select p.status not in ('dirilis', 'dikunci')
                     and exists (select 1 from hitung.versi_terakhir g where g.periode_id = p.id and g.jenis = 'hitung_gaji') from p),
    'telat_menit', (select t.telat_menit from aturan.toleransi t, p where t.cakupan = 'perusahaan'
                      and daterange(t.berlaku_dari, t.berlaku_sampai, '[)') @> p.tanggal_akhir),
    'lembur_minimal', (select l.menit_minimal from aturan.lembur l, p where l.cakupan = 'perusahaan'
                      and daterange(l.berlaku_dari, l.berlaku_sampai, '[)') @> p.tanggal_akhir),
    'lembur_kelipatan', (select l.kelipatan_menit from aturan.lembur l, p where l.cakupan = 'perusahaan'
                      and daterange(l.berlaku_dari, l.berlaku_sampai, '[)') @> p.tanggal_akhir),
    'lembur_bulat', (select l.cara_bulat from aturan.lembur l, p where l.cakupan = 'perusahaan'
                      and daterange(l.berlaku_dari, l.berlaku_sampai, '[)') @> p.tanggal_akhir),
    'uang_makan', (select k.nominal from aturan.komponen_lain k, p where k.kode = 'uang_makan' and k.cakupan = 'perusahaan'
                      and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> p.tanggal_akhir),
    'premi_hadir', (select k.nominal from aturan.komponen_lain k, p where k.kode = 'premi_hadir' and k.cakupan = 'perusahaan'
                      and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> p.tanggal_akhir),
    'shift_malam', (select k.nominal from aturan.komponen_lain k, p where k.kode = 'tunjangan_shift_malam' and k.cakupan = 'perusahaan'
                      and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> p.tanggal_akhir),
    'hari_ini', (select count(*) from fakta.coba_aturan c
                 where (c.waktu at time zone 'Asia/Jakarta')::date = (now() at time zone 'Asia/Jakarta')::date),
    'batas_hari', 20)
$$;

-- Aturan bertanggal hanya boleh diganti dengan menutup baris terbuka lalu menambah baris baru (jejak.jaga_bertanggal).
-- Percobaan mengikuti cara itu: setiap baris yang menyentuh periode harus terbuka dan mulai sebelum periode; baris ditutup
-- di tanggal awal periode, lalu baris percobaan (terbuka) ditambahkan mulai tanggal awal. Bila tidak bisa (aturan
-- berganti di tengah periode atau baris sudah tertutup), percobaan ditolak (CB002). Hanya dipanggil di dalam
-- sub-transaksi percobaan yang selalu dibatalkan.
create function fakta.coba_tutup_baris(p_tabel text, p_id bigint, p_dari date, p_sampai date, p_awal date) returns void
language plpgsql set search_path = '' as $$
begin
  if p_sampai is not null or p_dari >= p_awal then
    raise exception 'Aturan % berganti di tengah periode ini; tidak bisa dicoba', p_tabel using errcode = 'CB002';
  end if;
  execute format('update aturan.%I set berlaku_sampai = $1 where id = $2', p_tabel) using p_awal, p_id;
end $$;

create function fakta.coba_ganti_toleransi(p_telat integer, p_awal date, p_akhir date) returns void
language plpgsql set search_path = '' as $$
declare r aturan.toleransi;
begin
  for r in select * from aturan.toleransi where daterange(berlaku_dari, berlaku_sampai, '[)') && daterange(p_awal, p_akhir, '[]') loop
    perform fakta.coba_tutup_baris('toleransi', r.id, r.berlaku_dari, r.berlaku_sampai, p_awal);
    insert into aturan.toleransi (cakupan, telat_menit, pulang_cepat_menit, berlaku_dari)
    values (r.cakupan, p_telat, r.pulang_cepat_menit, p_awal);
  end loop;
end $$;

create function fakta.coba_ganti_lembur(p_minimal integer, p_kelipatan integer, p_bulat text, p_awal date, p_akhir date) returns void
language plpgsql set search_path = '' as $$
declare r aturan.lembur;
begin
  for r in select * from aturan.lembur where daterange(berlaku_dari, berlaku_sampai, '[)') && daterange(p_awal, p_akhir, '[]') loop
    perform fakta.coba_tutup_baris('lembur', r.id, r.berlaku_dari, r.berlaku_sampai, p_awal);
    insert into aturan.lembur (cakupan, menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari)
    values (r.cakupan, coalesce(p_minimal, r.menit_minimal), coalesce(p_kelipatan, r.kelipatan_menit), coalesce(p_bulat, r.cara_bulat),
            r.dasar_upah, p_awal);
  end loop;
end $$;

create function fakta.coba_ganti_komponen(p_kode text, p_nominal bigint, p_awal date, p_akhir date) returns void
language plpgsql set search_path = '' as $$
declare
  r aturan.komponen_lain;
  v_ada boolean := false;
begin
  for r in select * from aturan.komponen_lain where kode = p_kode and cakupan = 'perusahaan'
             and daterange(berlaku_dari, berlaku_sampai, '[)') && daterange(p_awal, p_akhir, '[]') loop
    v_ada := true;
    perform fakta.coba_tutup_baris('komponen_lain', r.id, r.berlaku_dari, r.berlaku_sampai, p_awal);
    insert into aturan.komponen_lain (kode, cakupan, nominal, satuan, sifat, syarat, berlaku_dari)
    values (r.kode, r.cakupan, p_nominal, r.satuan, r.sifat, r.syarat, p_awal);
  end loop;
  if not v_ada then
    insert into aturan.komponen_lain (kode, nominal, satuan, sifat, syarat, berlaku_dari, berlaku_sampai)
    values (p_kode, p_nominal, case when p_kode = 'premi_hadir' then 'per_periode' else 'per_hari' end, 'tidak_tetap',
            'percobaan', p_awal, p_akhir + 1);
  end if;
end $$;

-- Keluaran: {"hasil": "ok", "data": {...}} | {"hasil": "tidak_boleh" | "antrean" | "isian_salah" | "tanpa_perubahan" |
-- "sibuk" | "batas_harian" | "gagal", "alasan"}.
create function fakta.coba_aturan_jalankan(p_pengguna bigint, p_periode bigint, p_aturan jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_p fakta.periode;
  v_sekarang jsonb := fakta.aturan_sekarang(p_periode);
  v_a jsonb := '{}'::jsonb;
  v_kunci text;
  v_nilai text;
  v_batas jsonb := '{"telat_menit": [0, 240], "lembur_minimal": [0, 480], "lembur_kelipatan": [1, 60],
                     "uang_makan": [0, 1000000], "premi_hadir": [0, 10000000], "shift_malam": [0, 1000000]}';
  v_lama bigint;
  v_baru bigint;
  v_hasil jsonb;
  v_galat text;
  v_mulai timestamptz := clock_timestamp();
  v_lama_ms integer;
begin
  select x.* into v_p from fakta.periode x where x.id = p_periode;
  if not coalesce((v_sekarang ->> 'boleh')::boolean, false) then
    return jsonb_build_object('hasil', 'tidak_boleh', 'alasan', 'Percobaan hanya untuk periode yang sudah dihitung dan belum dirilis.');
  end if;
  -- K2: pembanding harus versi terbaru.
  if exists (select 1 from fakta.antrean_kerja a where a.periode_id = p_periode and a.status = 'menunggu') then
    return jsonb_build_object('hasil', 'antrean', 'alasan', 'Periode ini masih menunggu hitung ulang. Coba lagi setelah selesai.');
  end if;
  -- Isian: hanya kunci yang dikenal, dalam batas; yang sama dengan nilai sekarang diabaikan.
  for v_kunci, v_nilai in select key, value #>> '{}' from jsonb_each(p_aturan) loop
    if v_kunci = 'lembur_bulat' then
      if v_nilai not in ('bawah', 'terdekat') then
        return jsonb_build_object('hasil', 'isian_salah', 'alasan', 'Cara pembulatan lembur harus bawah atau terdekat.');
      end if;
      if v_nilai is distinct from v_sekarang ->> v_kunci then v_a := v_a || jsonb_build_object(v_kunci, v_nilai); end if;
    elsif v_batas ? v_kunci then
      if v_nilai is null or v_nilai !~ '^\d{1,8}$'
         or v_nilai::bigint < (v_batas -> v_kunci ->> 0)::bigint or v_nilai::bigint > (v_batas -> v_kunci ->> 1)::bigint then
        return jsonb_build_object('hasil', 'isian_salah', 'kunci', v_kunci,
          'alasan', format('Isian %s harus angka %s sampai %s.', v_kunci, v_batas -> v_kunci ->> 0, v_batas -> v_kunci ->> 1));
      end if;
      if v_nilai::bigint is distinct from (v_sekarang ->> v_kunci)::bigint then
        v_a := v_a || jsonb_build_object(v_kunci, v_nilai::bigint);
      end if;
    else
      return jsonb_build_object('hasil', 'isian_salah', 'alasan', 'Aturan ' || v_kunci || ' tidak bisa dicoba.');
    end if;
  end loop;
  if v_a = '{}'::jsonb then
    return jsonb_build_object('hasil', 'tanpa_perubahan', 'alasan', 'Tidak ada aturan yang berbeda dari nilai sekarang.');
  end if;
  -- K4: satu percobaan dalam satu waktu, 20 per hari.
  if not pg_try_advisory_xact_lock(hashtext('fakta.coba_aturan')) then
    return jsonb_build_object('hasil', 'sibuk', 'alasan', 'Ada percobaan lain yang sedang berjalan. Coba lagi sebentar.');
  end if;
  if (v_sekarang ->> 'hari_ini')::integer >= 20 then
    return jsonb_build_object('hasil', 'batas_harian', 'alasan', 'Batas 20 percobaan per hari sudah tercapai.');
  end if;

  v_lama := (select g.id from hitung.versi_terakhir g where g.periode_id = p_periode and g.jenis = 'hitung_gaji');
  begin
    if v_a ? 'telat_menit' then
      perform fakta.coba_ganti_toleransi((v_a ->> 'telat_menit')::integer, v_p.tanggal_awal, v_p.tanggal_akhir);
    end if;
    if v_a ?| array['lembur_minimal', 'lembur_kelipatan', 'lembur_bulat'] then
      perform fakta.coba_ganti_lembur((v_a ->> 'lembur_minimal')::integer, (v_a ->> 'lembur_kelipatan')::integer, v_a ->> 'lembur_bulat',
                                      v_p.tanggal_awal, v_p.tanggal_akhir);
    end if;
    if v_a ? 'uang_makan' then
      perform fakta.coba_ganti_komponen('uang_makan', (v_a ->> 'uang_makan')::bigint, v_p.tanggal_awal, v_p.tanggal_akhir);
    end if;
    if v_a ? 'premi_hadir' then
      perform fakta.coba_ganti_komponen('premi_hadir', (v_a ->> 'premi_hadir')::bigint, v_p.tanggal_awal, v_p.tanggal_akhir);
    end if;
    if v_a ? 'shift_malam' then
      perform fakta.coba_ganti_komponen('tunjangan_shift_malam', (v_a ->> 'shift_malam')::bigint, v_p.tanggal_awal, v_p.tanggal_akhir);
    end if;
    perform hitung.baca_tap(p_periode);
    v_baru := hitung.hitung_gaji(p_periode);

    -- Perbandingan dibuat di dalam sub-transaksi (versi baru hilang saat dibatalkan); tanpa orang rahasia (K3).
    with o as (
      select coalesce(a.id_karyawan, b.id_karyawan) as id, a.gaji_bersih as lama, b.gaji_bersih as baru,
             fakta.rahasia_di_periode(coalesce(a.id_karyawan, b.id_karyawan), p_periode) as rahasia
      from (select * from hitung.ringkasan_gaji where versi_id = v_lama) a
      full join (select * from hitung.ringkasan_gaji where versi_id = v_baru) b on b.id_karyawan = a.id_karyawan
    ),
    t as (select o.*, coalesce(o.baru, 0) - coalesce(o.lama, 0) as selisih from o where not o.rahasia),
    k as (
      select coalesce(a.id_karyawan, b.id_karyawan) as id, coalesce(a.komponen, b.komponen) as komponen,
             a.nominal as lama, b.nominal as baru
      from (select * from hitung.rincian_gaji where versi_id = v_lama) a
      full join (select * from hitung.rincian_gaji where versi_id = v_baru) b on b.id_karyawan = a.id_karyawan and b.komponen = a.komponen
      where a.nominal is distinct from b.nominal
    )
    select jsonb_build_object(
      'aturan', v_a,
      'ringkasan', jsonb_build_object(
        'orang', (select count(*) from t), 'naik', (select count(*) from t where selisih > 0),
        'turun', (select count(*) from t where selisih < 0), 'sama', (select count(*) from t where selisih = 0),
        'total_lama', (select coalesce(sum(lama), 0) from t), 'total_baru', (select coalesce(sum(baru), 0) from t),
        'selisih', (select coalesce(sum(selisih), 0) from t), 'rahasia', (select count(*) from o where o.rahasia)),
      'daftar', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', t.id, 'nama', n.nama, 'lama', t.lama, 'baru', t.baru, 'selisih', t.selisih,
                 'komponen', (select jsonb_agg(jsonb_build_object('komponen', k.komponen, 'lama', k.lama, 'baru', k.baru) order by k.komponen)
                              from k where k.id = t.id)) order by abs(t.selisih) desc, t.id)
        from t join induk.karyawan n on n.id = t.id
        where t.selisih <> 0 or exists (select 1 from k where k.id = t.id)), '[]'::jsonb))
    into v_hasil;
    raise exception 'coba aturan dibatalkan' using errcode = 'CB001';
  exception
    when sqlstate 'CB001' then null;
    when sqlstate 'CB002' then v_galat := sqlerrm;
    when others then v_galat := sqlerrm;
  end;
  v_lama_ms := (extract(epoch from clock_timestamp() - v_mulai) * 1000)::integer;
  insert into fakta.coba_aturan (pengguna, periode_id, aturan, hasil, ringkasan, galat, lama_ms)
  values (p_pengguna, p_periode, v_a, case when v_galat is null then 'selesai' else 'gagal' end,
          v_hasil -> 'ringkasan', v_galat, v_lama_ms);
  if v_galat is not null then
    return jsonb_build_object('hasil', 'gagal', 'alasan', 'Percobaan gagal dihitung: ' || v_galat);
  end if;
  return jsonb_build_object('hasil', 'ok', 'data', v_hasil || jsonb_build_object('lama_ms', v_lama_ms));
end $$;

create or replace function api.web_hrd(p jsonb) returns jsonb
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
  -- Paket 9c: coba aturan (nilai sekarang, lalu percobaan yang selalu dibatalkan).
  if v_aksi in ('aturan_sekarang', 'coba_aturan') then
    v_periode := (select x.id from fakta.periode x where x.id::text = p ->> 'periode_id');
    if v_periode is null then
      return jsonb_build_object('hasil', 'tidak_ada');
    end if;
    if v_aksi = 'aturan_sekarang' then
      return jsonb_build_object('hasil', 'ok', 'data', fakta.aturan_sekarang(v_periode));
    end if;
    return fakta.coba_aturan_jalankan(v_s.pengguna, v_periode, coalesce(p -> 'aturan', '{}'::jsonb));
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


revoke all on function fakta.aturan_sekarang(bigint), fakta.coba_ganti_komponen(text, bigint, date, date),
  fakta.coba_tutup_baris(text, bigint, date, date, date), fakta.coba_ganti_toleransi(integer, date, date),
  fakta.coba_ganti_lembur(integer, integer, text, date, date),
  fakta.coba_aturan_jalankan(bigint, bigint, jsonb) from public;
