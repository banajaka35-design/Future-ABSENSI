-- 0018_pemberitahuan_segera.sql
-- Paket 5c: pemberitahuan tingkat segera (U14) dan pengingat kirim file (A13).
-- Rancangan: docs/pemberitahuan-segera.md (ditulis sebelum file ini).
-- Penjadwal (pg_cron, pg_net, Vault) hanya ada di Supabase, jadi dipasang oleh db/pasang_pintu.sh, bukan di sini.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- Catatan pemberitahuan: satu baris per kejadian (kunci tetap), dicatat sebelum dikirim supaya tidak dikirim dua kali.
create table fakta.pemberitahuan (
  id bigint generated always as identity primary key,
  kunci text not null unique,
  jenis text not null,
  tingkat text not null check (tingkat in ('segera', 'pengingat')),
  isi jsonb not null,
  status text not null check (status in (
    'akan_dikirim', 'terkirim', 'sebagian_gagal', 'gagal',
    'lama_tidak_dikirim', 'dilewati_tanpa_penerima', 'dilewati_tanpa_akun_bos')),
  penerima bigint[] not null default '{}',
  hasil_kirim jsonb,
  dibuat timestamptz not null default now(),
  dikirim timestamptz
);

-- Teks alasan penolakan dari sistem/urai/urai.ts (PESAN.idRusakExcel dan PESAN.formatTidakDikenal).
-- Uji sistem/pintu/uji_pintu.ts memeriksa bahwa kedua awalan ini masih cocok dengan teks di pembaca file.
create function fakta.jenis_tolak_segera(p_alasan text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_alasan like 'No.ID rusak%' then 'file_rusak_excel'
    when p_alasan like 'Format file tidak dikenal%' then 'format_tidak_dikenal'
  end
$$;

-- Semua kejadian tingkat segera yang berlaku sekarang, dengan kunci tetap (docs/pemberitahuan-segera.md).
create function fakta.kejadian_segera() returns table (kunci text, jenis text, isi jsonb)
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
$$;

-- Penerima: akun aktif dengan hak akses yang diminta dan punya ID Telegram.
create function fakta.penerima(p_peran text[]) returns bigint[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(u.telegram_id order by u.telegram_id), '{}')
  from induk.pengguna u
  where u.aktif and u.telegram_id is not null and u.peran = any(p_peran)
$$;

-- Pengaman: kejadian yang sudah ada dicatat sebagai lama, tidak dikirim. Dipanggil migrasi ini dan
-- db/pasang_supabase.sh sesudah pemasangan menghitung ulang (kejadian buatan skrip pasang, bukan dari file HRD).
create function fakta.tandai_kejadian_lama() returns integer
language plpgsql set search_path = '' as $$
declare
  v_jumlah integer;
begin
  insert into fakta.pemberitahuan (kunci, jenis, tingkat, isi, status)
  select k.kunci, k.jenis, 'segera', k.isi, 'lama_tidak_dikirim' from fakta.kejadian_segera() k
  on conflict (kunci) do nothing;
  get diagnostics v_jumlah = row_count;
  return v_jumlah;
end $$;

select fakta.tandai_kejadian_lama();

-- Ambil kejadian segera yang belum pernah dicatat, catat sebagai akan_dikirim, kembalikan bersama penerima.
-- Keluaran: {"kejadian": [{"id", "jenis", "isi"}...], "penerima": [telegram_id...]}.
create function api.pintu_pemberitahuan_ambil() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_penerima bigint[] := fakta.penerima(array['hrd', 'pembangun']);
  v_kejadian jsonb;
begin
  -- Satu pengambil pada satu waktu, supaya dua proses yang berjalan bersamaan tidak mengambil kejadian yang sama.
  perform pg_advisory_xact_lock(hashtext('fakta.pemberitahuan'));
  with baru as (
    insert into fakta.pemberitahuan (kunci, jenis, tingkat, isi, status, penerima)
    select k.kunci, k.jenis, 'segera', k.isi,
           case when cardinality(v_penerima) = 0 then 'dilewati_tanpa_penerima' else 'akan_dikirim' end, v_penerima
    from fakta.kejadian_segera() k
    on conflict (kunci) do nothing
    returning id, jenis, isi
  )
  select jsonb_agg(jsonb_build_object('id', b.id, 'jenis', b.jenis, 'isi', b.isi) order by b.id) into v_kejadian from baru b;
  if cardinality(v_penerima) = 0 then
    v_kejadian := null;
  end if;
  return jsonb_build_object('kejadian', coalesce(v_kejadian, '[]'::jsonb), 'penerima', to_jsonb(v_penerima));
end $$;

-- Tanggal tutup buku terakhir sebelum p_hari, dari pengaturan tanggal_tutup_buku (0 = akhir bulan; tanggal yang
-- melewati panjang bulan menjadi akhir bulan).
create function fakta.tutup_buku_sebelum(p_hari date) returns date
language sql stable set search_path = '' as $$
  select max(c.t)
  from (
    select case when x.n = 0 or x.n >= x.panjang then x.akhir
                else make_date(extract(year from x.b)::int, extract(month from x.b)::int, x.n) end as t
    from (
      select b, aturan.pengaturan_pada('tanggal_tutup_buku', null, b)::int as n,
             (b + interval '1 month - 1 day')::date as akhir,
             extract(day from b + interval '1 month - 1 day')::int as panjang
      from (select (date_trunc('month', p_hari) - make_interval(months => i))::date as b from generate_series(0, 2) i) bulan
    ) x
  ) c
  where c.t < p_hari
$$;

-- Pengingat kirim file (A13). Masukan: {"tanggal": "YYYY-MM-DD"} (boleh kosong: hari ini WIB; tanggal pura-pura untuk uji).
-- Keluaran: {"tanggal", "tutup_buku", "periode_awal", "hari_ke", "kirim": [{"kepada", "id", "mesin", "penerima"}...],
--            "dilewati": [{"kepada", "status", "mesin"}...]}.
create function api.pintu_pengingat(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hari date := coalesce((p ->> 'tanggal')::date, (now() at time zone 'Asia/Jakarta')::date);
  v_tutup date := fakta.tutup_buku_sebelum(v_hari);
  v_awal date := fakta.tutup_buku_sebelum(v_tutup) + 1;
  v_hari_ke integer := v_hari - v_tutup;
  v_mesin text[];
  v_kirim jsonb := '[]'::jsonb;
  v_lewat jsonb := '[]'::jsonb;
  v_kepada text;
  v_penerima bigint[];
  v_status text;
  v_id bigint[];
  v_baru text[];
begin
  perform pg_advisory_xact_lock(hashtext('fakta.pemberitahuan'));
  if v_hari_ke in (1, 2) then
    select coalesce(array_agg(m.kode order by m.kode), '{}') into v_mesin
    from induk.mesin m
    where not exists (select 1 from fakta.kiriman_file k
                      where k.mesin = m.kode and k.hasil = 'diterima' and k.tanggal_akhir >= v_tutup);

    foreach v_kepada in array (case when v_hari_ke = 2 then array['hrd', 'bos'] else array['hrd'] end) loop
      v_penerima := fakta.penerima(case v_kepada when 'hrd' then array['hrd', 'pembangun'] else array['bos'] end);
      v_status := case when cardinality(v_penerima) > 0 then 'akan_dikirim'
                       when v_kepada = 'bos' then 'dilewati_tanpa_akun_bos' else 'dilewati_tanpa_penerima' end;
      with baru as (
        insert into fakta.pemberitahuan (kunci, jenis, tingkat, isi, status, penerima)
        select concat_ws('|', 'pengingat', v_kepada, v_tutup, v_hari_ke, m), 'pengingat_file', 'pengingat',
               jsonb_build_object('mesin', m, 'tutup_buku', v_tutup, 'periode_awal', v_awal,
                                  'hari_ke', v_hari_ke, 'kepada', v_kepada),
               v_status, v_penerima
        from unnest(v_mesin) m
        on conflict (kunci) do nothing
        returning id, isi ->> 'mesin' as mesin
      )
      select array_agg(b.id order by b.mesin), array_agg(b.mesin order by b.mesin) into v_id, v_baru from baru b;
      if v_id is not null then
        if v_status = 'akan_dikirim' then
          v_kirim := v_kirim || jsonb_build_object('kepada', v_kepada, 'id', to_jsonb(v_id), 'mesin', to_jsonb(v_baru),
                                                   'penerima', to_jsonb(v_penerima));
        else
          v_lewat := v_lewat || jsonb_build_object('kepada', v_kepada, 'status', v_status, 'mesin', to_jsonb(v_baru));
        end if;
      end if;
    end loop;
  end if;

  return jsonb_build_object('tanggal', v_hari, 'tutup_buku', v_tutup, 'periode_awal', v_awal,
                            'hari_ke', v_hari_ke, 'kirim', v_kirim, 'dilewati', v_lewat);
end $$;

-- Catat hasil kirim. Masukan: {"id": [..], "hasil": {"<telegram_id>": "ok" | "galat: ..."}}.
-- Hanya baris yang masih akan_dikirim yang diubah.
create function api.pintu_pemberitahuan_hasil(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ok integer := (select count(*) from jsonb_each_text(p -> 'hasil') h where h.value = 'ok');
  v_semua integer := (select count(*) from jsonb_each_text(p -> 'hasil'));
  v_jumlah integer;
begin
  update fakta.pemberitahuan b
  set hasil_kirim = p -> 'hasil',
      dikirim = now(),
      status = case when v_semua > 0 and v_ok = v_semua then 'terkirim' when v_ok > 0 then 'sebagian_gagal' else 'gagal' end
  where b.id in (select x::bigint from jsonb_array_elements_text(p -> 'id') x) and b.status = 'akan_dikirim';
  get diagnostics v_jumlah = row_count;
  return jsonb_build_object('dicatat', v_jumlah);
end $$;

grant execute on function api.pintu_pemberitahuan_ambil(), api.pintu_pengingat(jsonb),
  api.pintu_pemberitahuan_hasil(jsonb) to pintu;
