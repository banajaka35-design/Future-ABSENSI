-- 0035_lembur_chat.sql
-- Paket 7c-1 (docs/rencana-tahap-7.md bagian 9; PRD v2 B4; kasus D04, D05, F12): setujui atau batalkan lembur lewat
-- chat, per orang atau per divisi. Mesin hitung gaji TIDAK diubah: efek setujui_lembur/batalkan_lembur sudah ada sejak
-- 4b-1 (aturan D5). Fungsi bot 0034 diganti supaya menerima perintah lembur dan sasaran divisi.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

-- ---------------------------------------------------------------------------
-- Draf: sasaran orang atau divisi (divisi hanya untuk perintah lembur dan pembatalannya)
-- ---------------------------------------------------------------------------
alter table fakta.draf_perintah alter column id_karyawan drop not null;
alter table fakta.draf_perintah add column divisi text references induk.divisi (kode);
alter table fakta.draf_perintah drop constraint draf_perintah_jenis_check;
alter table fakta.draf_perintah add constraint draf_perintah_jenis_check
  check (jenis in ('sakit', 'izin', 'cuti', 'batalkan_perintah', 'kasbon', 'setujui_lembur', 'batalkan_lembur'));
alter table fakta.draf_perintah add constraint draf_perintah_sasaran_check
  check (num_nonnulls(id_karyawan, divisi) = 1
         and (divisi is null or jenis in ('setujui_lembur', 'batalkan_lembur', 'batalkan_perintah')));

-- ---------------------------------------------------------------------------
-- Pembantu
-- ---------------------------------------------------------------------------

-- Identitas sasaran: orang (id, nama, divisi) atau divisi (divisi_kode, divisi).
create function fakta.identitas_sasaran(p_id text, p_divisi text) returns jsonb
language sql stable set search_path = '' as $$
  select case when p_id is not null then fakta.identitas_karyawan(p_id)
              else (select jsonb_build_object('divisi_kode', d.kode, 'divisi', d.nama) from induk.divisi d where d.kode = p_divisi) end
$$;

-- Pemeriksaan perintah lembur. Orang: aturan sama dengan izin (fakta.periksa_perintah). Divisi: divisi harus ada,
-- tanggal di periode yang tercatat dan belum dirilis/dikunci, rentang paling panjang 31 hari.
create function fakta.periksa_lembur(p_jenis text, p_id text, p_divisi text, p_mulai date, p_selesai date) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_hari date;
  v_p fakta.periode;
  v_periode jsonb := '[]'::jsonb;
  v_ulang jsonb;
begin
  if p_jenis is null or p_jenis not in ('setujui_lembur', 'batalkan_lembur', 'batalkan_perintah') then
    return jsonb_build_object('hasil', 'jenis_salah');
  end if;
  if p_id is not null then
    return fakta.periksa_perintah(case when p_jenis = 'batalkan_perintah' then p_jenis else 'izin' end, p_id, p_mulai, p_selesai);
  end if;
  if p_divisi is null or not exists (select 1 from induk.divisi d where d.kode = p_divisi) then
    return jsonb_build_object('hasil', 'divisi_tidak_ada', 'divisi_kode', p_divisi);
  end if;
  if p_mulai is null or p_selesai is null or p_selesai < p_mulai then
    return jsonb_build_object('hasil', 'tanggal_salah');
  end if;
  if p_selesai - p_mulai + 1 > 31 then
    return jsonb_build_object('hasil', 'terlalu_panjang', 'hari', p_selesai - p_mulai + 1);
  end if;
  for v_hari in select d::date from generate_series(p_mulai::timestamp, p_selesai::timestamp, interval '1 day') d loop
    v_p := fakta.periode_tanggal(v_hari);
    if v_p.id is null then
      return jsonb_build_object('hasil', 'tanpa_periode', 'tanggal', v_hari);
    end if;
    if v_p.status in ('dirilis', 'dikunci') then
      return jsonb_build_object('hasil', 'periode_dirilis', 'tanggal', v_hari,
        'periode', jsonb_build_object('id', v_p.id, 'awal', v_p.tanggal_awal, 'akhir', v_p.tanggal_akhir, 'status', v_p.status));
    end if;
    if not v_periode @> jsonb_build_array(jsonb_build_object('id', v_p.id)) then
      v_periode := v_periode || jsonb_build_array(jsonb_build_object('id', v_p.id, 'awal', v_p.tanggal_awal,
                                                                      'akhir', v_p.tanggal_akhir, 'status', v_p.status));
    end if;
  end loop;
  v_ulang := fakta.periode_hitung_ulang(p_mulai, p_selesai);
  return jsonb_build_object('hasil', 'siap', 'periode', v_periode, 'periode_ulang', v_ulang,
    'pengajuan_batal', exists (select 1 from jsonb_array_elements(v_ulang) x where x ->> 'status' in ('diajukan', 'disetujui')));
end $$;

-- Per hari: pengaturan lembur dan keadaan dari baca tap terakhir.
--   Orang: status, menit lebih (lewat jam pulang jadwal). Divisi: jumlah orang dengan menit lebih 60 atau lebih.
--   'perintah': perintah lembur yang berlaku sekarang untuk sasaran itu di hari itu (tidak dibatalkan; orang juga
--   kena perintah divisinya).
create function fakta.hari_lembur(p_id text, p_divisi text, p_mulai date, p_selesai date) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(x order by x ->> 'tanggal'), '[]'::jsonb) from (
    select jsonb_build_object(
      'tanggal', d::date,
      'pengaturan', aturan.pengaturan_pada('lembur', coalesce(p_divisi, h.divisi,
                      (select r.divisi from induk.karyawan_riwayat r where r.id_karyawan = p_id
                         and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> d::date limit 1)), d::date),
      'status', h.status, 'menit_lebih', h.menit_lebih,
      'orang_lembur', case when p_divisi is not null then
        (select count(*) from hitung.hasil_harian x join hitung.versi_terakhir v on v.id = x.versi_id and v.jenis = 'baca_tap'
         where x.divisi = p_divisi and x.tanggal = d::date and x.menit_lebih >= 60) end,
      'perintah', (select jsonb_agg(jsonb_build_object('id', p.id, 'jenis', p.jenis) order by p.id)
                   from fakta.perintah_hrd p
                   where p.jenis in ('setujui_lembur', 'batalkan_lembur')
                     and d::date between p.tanggal_mulai and coalesce(p.tanggal_selesai, p.tanggal_mulai)
                     and (p.id_karyawan = p_id or p.divisi = coalesce(p_divisi, h.divisi))
                     and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = p.id))) as x
    from generate_series(p_mulai::timestamp, p_selesai::timestamp, interval '1 day') d
    left join lateral (select hh.* from hitung.hasil_harian hh join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
                       where p_id is not null and hh.id_karyawan = p_id and hh.tanggal = d::date limit 1) h on true) t
$$;

-- Lembur (rupiah) sasaran di periode yang memuat rentang, dari versi gaji terakhir. Orang rahasia tidak dimasukkan
-- (hanya dihitung jumlahnya, F15/F15b). Divisi: orang yang tercatat di divisi itu pada salah satu tanggal rentang.
create function fakta.lembur_target(p_id text, p_divisi text, p_mulai date, p_selesai date) returns jsonb
language sql stable set search_path = '' as $$
  with per as (select p.id from fakta.periode p where p.tanggal_awal <= p_selesai and p.tanggal_akhir >= p_mulai),
  orang as (
    select distinct per.id as periode_id, hh.id_karyawan from per
    join hitung.versi_terakhir v on v.periode_id = per.id and v.jenis = 'baca_tap'
    join hitung.hasil_harian hh on hh.versi_id = v.id
    where hh.tanggal between p_mulai and p_selesai
      and ((p_id is not null and hh.id_karyawan = p_id) or (p_id is null and hh.divisi = p_divisi))),
  nilai as (
    select o.periode_id, o.id_karyawan, fakta.rahasia_di_periode(o.id_karyawan, o.periode_id) as rahasia,
           coalesce((select sum(r.nominal) from hitung.rincian_gaji r
                     join hitung.versi_terakhir g on g.id = r.versi_id and g.jenis = 'hitung_gaji' and g.periode_id = o.periode_id
                     where r.id_karyawan = o.id_karyawan and r.komponen = 'lembur'), 0) as lembur
    from orang o)
  select jsonb_build_object(
    'rahasia', (select count(*) from nilai where rahasia),
    'daftar', coalesce((select jsonb_agg(jsonb_build_object('periode', periode_id, 'id', id_karyawan, 'lembur', lembur)
                                         order by periode_id, id_karyawan)
                        from nilai where not rahasia), '[]'::jsonb))
$$;

-- ---------------------------------------------------------------------------
-- Siapkan perintah lembur. Masukan: {"telegram_id", "jenis": setujui_lembur|batalkan_lembur, "sasaran" (ID karyawan
-- atau kode divisi), "mulai", "selesai", "catatan"}. Keluaran: {"hasil": "siap" | "bukan_hrd" | "jenis_salah" |
-- "tidak_ada" | "divisi_tidak_ada" | penolakan tanggal, ...}.
-- ---------------------------------------------------------------------------
create function api.pintu_lembur_siapkan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_sasaran text := upper(trim(p ->> 'sasaran'));
  v_id text;
  v_divisi text;
  v_mulai date;
  v_selesai date;
  v_cek jsonb;
  v_draf bigint;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  if p ->> 'jenis' is null or p ->> 'jenis' not in ('setujui_lembur', 'batalkan_lembur') then
    return jsonb_build_object('hasil', 'jenis_salah');
  end if;
  if exists (select 1 from induk.karyawan k where k.id = v_sasaran) then
    v_id := v_sasaran;
  elsif exists (select 1 from induk.divisi d where d.kode = v_sasaran) then
    v_divisi := v_sasaran;
  elsif v_sasaran ~ '^[0-9]+$' then
    return jsonb_build_object('hasil', 'tidak_ada', 'id', v_sasaran);
  else
    return jsonb_build_object('hasil', 'divisi_tidak_ada', 'divisi_kode', v_sasaran);
  end if;
  begin
    v_mulai := (p ->> 'mulai')::date;
    v_selesai := coalesce((p ->> 'selesai')::date, v_mulai);
  exception when others then
    return jsonb_build_object('hasil', 'tanggal_salah');
  end;
  v_cek := fakta.periksa_lembur(p ->> 'jenis', v_id, v_divisi, v_mulai, v_selesai);
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, divisi, tanggal_mulai, tanggal_selesai, catatan, kedaluwarsa)
  values (v_hrd, p ->> 'jenis', v_id, v_divisi, v_mulai, v_selesai, nullif(left(trim(p ->> 'catatan'), 200), ''), now() + interval '15 minutes')
  returning id into v_draf;
  return v_cek || jsonb_build_object('draf_id', v_draf, 'jenis', p ->> 'jenis', 'mulai', v_mulai, 'selesai', v_selesai,
    'catatan', nullif(left(trim(p ->> 'catatan'), 200), ''), 'hari', fakta.hari_lembur(v_id, v_divisi, v_mulai, v_selesai))
    || fakta.identitas_sasaran(v_id, v_divisi);
end $$;

-- Diganti dari 0034/0033: ditambah perintah lembur (orang atau divisi).
create or replace function api.pintu_batal_siapkan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_x fakta.perintah_hrd;
  v_selesai date;
  v_batal bigint;
  v_cek jsonb;
  v_draf bigint;
  v_k jsonb;
  v_lembur boolean;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  begin
    select x.* into v_x from fakta.perintah_hrd x where x.id = (p ->> 'perintah_id')::bigint;
  exception when others then
    v_x := null;
  end;
  if v_x.id is null then
    return jsonb_build_object('hasil', 'tidak_ada_perintah', 'perintah_id', p ->> 'perintah_id');
  end if;
  v_lembur := v_x.jenis in ('setujui_lembur', 'batalkan_lembur');
  if v_x.jenis not in ('sakit', 'izin', 'cuti', 'kasbon', 'setujui_lembur', 'batalkan_lembur') or v_x.tanggal_mulai is null
     or (v_x.id_karyawan is null and not (v_lembur and v_x.divisi is not null))
     or (v_x.jenis = 'kasbon' and not exists (select 1 from fakta.buku_kasbon k where k.perintah_id = v_x.id)) then
    return jsonb_build_object('hasil', 'jenis_tidak_bisa', 'perintah_id', v_x.id, 'jenis', v_x.jenis);
  end if;
  select b.id into v_batal from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = v_x.id order by b.id limit 1;
  if v_batal is not null then
    return jsonb_build_object('hasil', 'sudah_dibatalkan', 'perintah_id', v_x.id, 'oleh_perintah', v_batal);
  end if;
  v_selesai := coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai);
  v_cek := case when v_lembur then fakta.periksa_lembur('batalkan_perintah', v_x.id_karyawan, v_x.divisi, v_x.tanggal_mulai, v_selesai)
                else fakta.periksa_perintah('batalkan_perintah', v_x.id_karyawan, v_x.tanggal_mulai, v_selesai) end;
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek || jsonb_build_object('perintah_id', v_x.id);
  end if;
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, divisi, tanggal_mulai, tanggal_selesai, membatalkan, kedaluwarsa)
  values (v_hrd, 'batalkan_perintah', v_x.id_karyawan, v_x.divisi, v_x.tanggal_mulai, v_selesai, v_x.id, now() + interval '15 minutes')
  returning id into v_draf;
  if v_x.jenis = 'kasbon' then
    v_k := fakta.keadaan_kasbon(v_x.id_karyawan, (v_cek -> 'periode' -> 0 ->> 'id')::bigint);
  end if;
  return v_cek || jsonb_build_object('draf_id', v_draf, 'jenis', 'batalkan_perintah', 'mulai', v_x.tanggal_mulai, 'selesai', v_selesai,
    'dibatalkan', jsonb_build_object('id', v_x.id, 'jenis', v_x.jenis, 'asal', v_x.asal, 'alasan', v_x.alasan,
      'kasbon', case when v_x.jenis = 'kasbon' then (select jsonb_agg(jsonb_build_object('jenis', k.jenis, 'jumlah', k.jumlah) order by k.id)
                                                     from fakta.buku_kasbon k where k.perintah_id = v_x.id) end),
    'kasbon', case when v_k is null then null when (v_k ->> 'rahasia')::boolean then jsonb_build_object('rahasia', true) else v_k end,
    'hari', case when v_lembur then fakta.hari_lembur(v_x.id_karyawan, v_x.divisi, v_x.tanggal_mulai, v_selesai)
                 when v_x.jenis = 'kasbon' then '[]'::jsonb else fakta.hari_perintah(v_x.id_karyawan, v_x.tanggal_mulai, v_selesai) end)
    || fakta.identitas_sasaran(v_x.id_karyawan, v_x.divisi);
end $$;

-- Diganti dari 0034/0033: ditambah perintah lembur (orang atau divisi).
create or replace function api.pintu_perintah_simpan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_d fakta.draf_perintah;
  v_cek jsonb;
  v_perintah bigint;
  v_sebelum jsonb;
  v_batal bigint;
  v_kasbon_target boolean := false;
  v_lembur boolean := false;
  v_k jsonb;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select d.* into v_d from fakta.draf_perintah d where d.id = (p ->> 'draf_id')::bigint for update;
  if v_d.id is null or v_d.pengguna <> v_hrd or v_d.hasil is not null or v_d.kedaluwarsa < now() then
    return jsonb_build_object('hasil', 'tidak_berlaku');
  end if;
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  if not coalesce((p ->> 'ya')::boolean, false) then
    update fakta.draf_perintah set selesai_pada = now(), hasil = 'dibatalkan' where id = v_d.id;
    return jsonb_build_object('hasil', 'dibatalkan');
  end if;
  if v_d.jenis = 'batalkan_perintah' then
    perform 1 from fakta.perintah_hrd x where x.id = v_d.membatalkan for update;
    select b.id into v_batal from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = v_d.membatalkan limit 1;
    if v_batal is not null then
      return jsonb_build_object('hasil', 'sudah_dibatalkan', 'perintah_id', v_d.membatalkan, 'oleh_perintah', v_batal);
    end if;
    v_kasbon_target := exists (select 1 from fakta.perintah_hrd x where x.id = v_d.membatalkan and x.jenis = 'kasbon');
    v_lembur := exists (select 1 from fakta.perintah_hrd x where x.id = v_d.membatalkan and x.jenis in ('setujui_lembur', 'batalkan_lembur'));
  end if;
  v_lembur := v_lembur or v_d.jenis in ('setujui_lembur', 'batalkan_lembur');
  v_cek := case when v_lembur then fakta.periksa_lembur(v_d.jenis, v_d.id_karyawan, v_d.divisi, v_d.tanggal_mulai, v_d.tanggal_selesai)
                else fakta.periksa_perintah(case when v_d.jenis = 'kasbon' then 'izin' else v_d.jenis end,
                                            v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai) end;
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  if v_d.jenis = 'kasbon' or v_kasbon_target then
    -- satu kunci per orang supaya dua catatan kasbon bersamaan tidak sama-sama lolos pemeriksaan saldo
    perform pg_advisory_xact_lock(hashtext('kasbon:' || v_d.id_karyawan));
    v_k := fakta.keadaan_kasbon(v_d.id_karyawan, (v_cek -> 'periode' -> 0 ->> 'id')::bigint);
    if v_d.kasbon_jenis = 'pelunasan' and v_d.jumlah > (v_k ->> 'saldo')::bigint then
      return jsonb_build_object('hasil', 'melebihi_saldo', 'rahasia', v_k -> 'rahasia',
        'saldo', case when (v_k ->> 'rahasia')::boolean then null else (v_k ->> 'saldo')::bigint end) || fakta.identitas_karyawan(v_d.id_karyawan);
    end if;
    if v_d.kasbon_jenis = 'cicilan' and (v_k ->> 'saldo')::bigint <= 0 then
      return jsonb_build_object('hasil', 'tanpa_saldo') || fakta.identitas_karyawan(v_d.id_karyawan);
    end if;
  end if;
  v_sebelum := case when v_lembur then fakta.hari_lembur(v_d.id_karyawan, v_d.divisi, v_d.tanggal_mulai, v_d.tanggal_selesai)
                    when v_d.jenis = 'kasbon' or v_kasbon_target then '[]'::jsonb
                    else fakta.hari_perintah(v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai) end;
  insert into fakta.perintah_hrd (oleh, asal, jenis, id_karyawan, divisi, tanggal_mulai, tanggal_selesai, alasan, membatalkan, nilai)
  values (v_hrd, 'chat', v_d.jenis, v_d.id_karyawan, v_d.divisi, v_d.tanggal_mulai, v_d.tanggal_selesai, v_d.catatan, v_d.membatalkan,
          case when v_d.jenis = 'kasbon' then concat_ws(':', v_d.kasbon_jenis, v_d.jumlah, v_d.cicilan) end)
  returning id into v_perintah;
  if v_d.jenis = 'kasbon' then
    insert into fakta.buku_kasbon (id_karyawan, jenis, jumlah, perintah_id)
    select v_d.id_karyawan, j, n, v_perintah
    from (values (1, v_d.kasbon_jenis, v_d.jumlah), (2, 'cicilan', v_d.cicilan)) t(urut, j, n)
    where n is not null
    order by urut;
  end if;
  update fakta.draf_perintah set selesai_pada = now(), hasil = 'disimpan', perintah_id = v_perintah where id = v_d.id;
  insert into fakta.antrean_kerja (periode_id, perintah_id)
  select (x ->> 'id')::bigint, v_perintah from jsonb_array_elements(v_cek -> 'periode_ulang') x
  on conflict (periode_id) where status = 'menunggu' do nothing;
  return v_cek || jsonb_build_object('hasil', 'disimpan', 'perintah_id', v_perintah, 'jenis', v_d.jenis,
    'mulai', v_d.tanggal_mulai, 'selesai', v_d.tanggal_selesai, 'membatalkan', v_d.membatalkan, 'hari_sebelum', v_sebelum,
    'kasbon_jenis', v_d.kasbon_jenis, 'jumlah', v_d.jumlah, 'cicilan', v_d.cicilan,
    'kasbon_sebelum', case when v_k is null then null when (v_k ->> 'rahasia')::boolean then jsonb_build_object('rahasia', true) else v_k end,
    'lembur_sebelum', case when v_lembur then fakta.lembur_target(v_d.id_karyawan, v_d.divisi, v_d.tanggal_mulai, v_d.tanggal_selesai) end)
    || fakta.identitas_sasaran(v_d.id_karyawan, v_d.divisi);
end $$;

-- Diganti dari 0034/0033: ditambah perintah lembur (orang atau divisi).
create or replace function api.pintu_perintah_hasil(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_x fakta.perintah_hrd;
  v_kasbon boolean;
  v_lembur boolean;
  v_k jsonb;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select x.* into v_x from fakta.perintah_hrd x where x.id = (p ->> 'perintah_id')::bigint and x.asal = 'chat';
  if v_x.id is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  v_kasbon := v_x.jenis = 'kasbon' or exists (select 1 from fakta.perintah_hrd t where t.id = v_x.membatalkan and t.jenis = 'kasbon');
  v_lembur := v_x.jenis in ('setujui_lembur', 'batalkan_lembur')
              or exists (select 1 from fakta.perintah_hrd t where t.id = v_x.membatalkan and t.jenis in ('setujui_lembur', 'batalkan_lembur'));
  if v_kasbon then
    v_k := fakta.keadaan_kasbon(v_x.id_karyawan, (fakta.periode_tanggal(v_x.tanggal_mulai)).id);
    if (v_k ->> 'rahasia')::boolean then
      v_k := jsonb_build_object('rahasia', true);
    end if;
  end if;
  return jsonb_build_object('hasil', 'ada', 'perintah_id', v_x.id, 'jenis', v_x.jenis, 'membatalkan', v_x.membatalkan,
    'mulai', v_x.tanggal_mulai, 'selesai', coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai),
    'hari', case when v_lembur then fakta.hari_lembur(v_x.id_karyawan, v_x.divisi, v_x.tanggal_mulai, coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai))
                 when v_kasbon then '[]'::jsonb
                 else fakta.hari_perintah(v_x.id_karyawan, v_x.tanggal_mulai, coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai)) end,
    'kasbon', v_k, 'periode_kasbon', (fakta.periode_tanggal(v_x.tanggal_mulai)).id,
    'lembur', case when v_lembur then fakta.lembur_target(v_x.id_karyawan, v_x.divisi, v_x.tanggal_mulai, coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai)) end,
    'selesai_dihitung', not exists (select 1 from fakta.antrean_kerja a where a.perintah_id = v_x.id and a.status = 'menunggu'),
    'gagal', exists (select 1 from fakta.antrean_kerja a where a.perintah_id = v_x.id and a.status = 'gagal'))
    || fakta.identitas_sasaran(v_x.id_karyawan, v_x.divisi);
end $$;

-- Diganti dari 0034/0033: ditambah perintah lembur (orang atau divisi).
create or replace function api.pintu_perintah_terakhir(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  return jsonb_build_object('hasil', 'ada', 'daftar', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id, 'jenis', x.jenis, 'id_karyawan', x.id_karyawan, 'nama', k.nama, 'divisi', x.divisi,
      'mulai', x.tanggal_mulai, 'selesai', coalesce(x.tanggal_selesai, x.tanggal_mulai),
      'membatalkan', x.membatalkan, 'oleh', u.peran, 'saya', u.id = v_hrd,
      'dibuat', to_char(x.dibuat at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI'),
      'dibatalkan_oleh', (select min(b.id) from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = x.id))
      order by x.id desc)
    from (select * from fakta.perintah_hrd where asal = 'chat' order by id desc limit 10) x
    left join induk.karyawan k on k.id = x.id_karyawan
    left join induk.pengguna u on u.id = x.oleh), '[]'::jsonb));
end $$;


revoke all on function fakta.identitas_sasaran(text, text), fakta.periksa_lembur(text, text, text, date, date),
  fakta.hari_lembur(text, text, date, date), fakta.lembur_target(text, text, date, date) from public;
grant execute on function api.pintu_lembur_siapkan(jsonb) to pintu;
