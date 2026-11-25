-- 0043_periode_bulanan.sql
-- Paket P1 (docs/rencana-p1-periode.md, di-"buat" 25 Nov 2026 dengan K1 (a) dan K2 (a)): periode gaji berikutnya dibuat
-- otomatis saat file mesin diterima lewat bot atau halaman unggah, dari pengaturan tanggal_tutup_buku dan tanggal_gajian.
-- Tidak dipanggil dari fakta.terima_kiriman (inti), supaya pemuat data simulasi dan uji tidak bergantung pada tanggal hari ini.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- Tanggal tutup buku pertama yang tidak sebelum p_hari, menurut pengaturan yang berlaku pada p_hari
-- (0 atau tanggal yang melewati panjang bulan = akhir bulan).
create function fakta.tutup_buku_berikut(p_hari date) returns date
language sql stable set search_path = '' as $$
  select min(c.t)
  from (
    select case when n = 0 or n >= extract(day from b + interval '1 month - 1 day')::int then (b + interval '1 month - 1 day')::date
                else make_date(extract(year from b)::int, extract(month from b)::int, n) end as t
    from (select (date_trunc('month', p_hari) + make_interval(months => i))::date as b,
                 aturan.pengaturan_pada('tanggal_tutup_buku', null, p_hari)::int as n
          from generate_series(0, 1) i) x
  ) c
  where c.t >= p_hari
$$;

-- Tanggal gajian pertama sesudah p_akhir (tanggal akhir periode), menurut pengaturan yang berlaku pada p_akhir
-- (tanggal yang melewati panjang bulan = akhir bulan).
create function fakta.gajian_sesudah(p_akhir date) returns date
language sql stable set search_path = '' as $$
  select min(c.t)
  from (
    select make_date(extract(year from b)::int, extract(month from b)::int,
                     least(g, extract(day from b + interval '1 month - 1 day')::int)) as t
    from (select (date_trunc('month', p_akhir) + make_interval(months => i))::date as b,
                 aturan.pengaturan_pada('tanggal_gajian', null, p_akhir)::int as g
          from generate_series(0, 2) i) x
  ) c
  where c.t > p_akhir
$$;

-- Buat periode berurutan sesudah periode terakhir sampai periode yang memuat p_tanggal.
-- Batas (K2): hanya periode yang tanggal awalnya tidak sesudah p_hari_ini, paling banyak 2 periode per panggilan.
-- Tidak pernah membuat periode pertama (database tanpa periode tetap tanpa periode) dan tidak mengubah periode yang ada.
-- Keluaran: [{"id", "awal", "akhir", "bayar"}...] (kosong bila tidak ada yang dibuat).
create function fakta.buat_periode_sampai(p_tanggal date, p_hari_ini date default null, p_alasan text default null)
returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_hari_ini date := coalesce(p_hari_ini, (now() at time zone 'Asia/Jakarta')::date);
  v_terakhir date;
  v_awal date;
  v_akhir date;
  v_bayar date;
  v_id bigint;
  v_baru jsonb := '[]'::jsonb;
begin
  if p_tanggal is null then
    return v_baru;
  end if;
  -- Dua file bersamaan: satu per satu (kunci tumpang tindih tanggal di fakta.periode tetap menjadi pengaman terakhir).
  perform pg_advisory_xact_lock(hashtext('fakta.buat_periode_sampai'));
  for i in 1 .. 2 loop
    select max(p.tanggal_akhir) into v_terakhir from fakta.periode p;
    exit when v_terakhir is null or v_terakhir >= p_tanggal;
    v_awal := v_terakhir + 1;
    exit when v_awal > v_hari_ini;
    v_akhir := fakta.tutup_buku_berikut(v_awal);
    v_bayar := fakta.gajian_sesudah(v_akhir);
    insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values (v_awal, v_akhir, v_bayar)
    returning id into v_id;
    insert into fakta.riwayat_status_periode (periode_id, status_lama, status_baru, oleh, alasan)
    values (v_id, null, 'terbuka', coalesce(nullif(current_setting('app.pengguna', true), ''), current_user),
            coalesce(p_alasan, 'periode dibuat otomatis'));
    v_baru := v_baru || jsonb_build_object('id', v_id, 'awal', v_awal, 'akhir', v_akhir, 'bayar', v_bayar);
  end loop;
  return v_baru;
end $$;

-- Terima file mesin atas nama satu akun (0020), ditambah: periode berikutnya dibuat bila tap melewati periode terakhir.
-- Keluaran sama dengan 0020, ditambah "periode_baru": [{"id", "awal", "akhir", "bayar"}...].
create or replace function fakta.terima_file_atas_nama(p jsonb, p_pengguna bigint) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_hasil jsonb;
  v_awal date;
  v_akhir date;
  v_periode jsonb;
  v_baru jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from induk.mesin m where m.kode = p ->> 'mesin') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Mesin %s tidak dikenal.', p ->> 'mesin'), 'dicatat', false);
  end if;
  perform set_config('app.pengguna', coalesce(p ->> 'asal', 'telegram') || ':' || coalesce(p ->> 'telegram_id', 'pengguna' || p_pengguna), true);
  perform set_config('app.asal_kiriman', case when p ->> 'asal' = 'web' then 'web' else 'telegram' end, true);
  v_hasil := fakta.terima_kiriman(p ->> 'nama_file', p ->> 'sidik', p ->> 'mesin', p -> 'tap', p ->> 'alasan',
                                   now(), (p ->> 'update_id')::bigint, p_pengguna);
  perform set_config('app.asal_kiriman', '', true);
  if v_hasil ->> 'hasil' = 'diterima' then
    v_awal := (v_hasil ->> 'tanggal_awal')::date;
    v_akhir := (v_hasil ->> 'tanggal_akhir')::date;
    -- P1: tanggal pura-pura untuk uji lewat app.hari_ini (hanya bisa diisi di sesi database, bukan dari bot/web).
    v_baru := fakta.buat_periode_sampai(v_akhir, nullif(current_setting('app.hari_ini', true), '')::date,
                                        format('dibuat otomatis dari file mesin (kiriman no. %s)', v_hasil ->> 'kiriman_id'));
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
  return v_hasil || jsonb_build_object('dicatat', true, 'periode', coalesce(v_periode, '[]'::jsonb), 'periode_baru', v_baru);
end $$;

revoke all on function fakta.tutup_buku_berikut(date), fakta.gajian_sesudah(date), fakta.buat_periode_sampai(date, date, text)
  from public;
