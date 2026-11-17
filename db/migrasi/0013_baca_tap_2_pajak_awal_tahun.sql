-- 0013_baca_tap_2_pajak_awal_tahun.sql
-- Paket 4b-5. Aturan: docs/aturan-hitung-gaji.md versi 5 dan permintaan perubahan 02 (ditulis sebelum file ini).
--   1. Pembaca tap versi 2: "belum terdaftar di mesin" melewati hari sakit/izin/cuti/dinas luar dari HRD (kasus F13b).
--   2. Tanda gaji berubah (O2 versi 5): hanya upah tetap dan potongan hari tidak dibayar.
--   3. Isian pajak awal tahun (L6) dan PPh masa terakhir per orang (L2, L3 versi 5); hitung gaji versi 4.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

create function hitung.versi_kode_baca() returns text language sql immutable set search_path = '' as $$
  select 'baca_tap 2 (paket 4b-5)'::text
$$;

create or replace function hitung.versi_kode_gaji() returns text language sql immutable set search_path = '' as $$
  select 'hitung_gaji 4 (paket 4b-5)'::text
$$;

create table induk.pajak_awal_tahun (
  id_karyawan text not null references induk.karyawan (id),
  tahun integer not null check (tahun between 2020 and 2100),
  sampai_bulan integer not null check (sampai_bulan between 1 and 11),
  bulan_kerja integer not null check (bulan_kerja between 1 and 11),
  bruto bigint not null check (bruto >= 0),
  iuran bigint not null default 0 check (iuran >= 0),
  pph bigint not null default 0 check (pph >= 0),
  catatan text,
  check (bulan_kerja <= sampai_bulan),
  primary key (id_karyawan, tahun)
);
create trigger catat_perubahan after insert or update or delete on induk.pajak_awal_tahun
  for each row execute function jejak.catat_perubahan();

create or replace function hitung.baca_tap(p_periode bigint) returns bigint
language plpgsql set search_path = '' set jit = off set client_min_messages = warning set timezone = 'UTC' as $$
declare
  c_versi_kode constant text := hitung.versi_kode_baca();
  c_zona constant text := 'Asia/Jakarta';
  -- Angka tetap (belum ada tabel aturannya; dicatat di laporan Tahap 3):
  c_seperempat constant numeric := 0.25;      -- tap tunggal "dekat jam masuk/pulang" = dalam 1/4 lama shift
  c_menit_cocok_shift constant integer := 60; -- usulan tukar shift: tap masuk dalam 60 menit dari jam masuk shift lain
  c_hari_tap_lama constant integer := 7;      -- tap terakhir file lebih tua dari 7 hari sebelum dikirim
  c_melenceng_min_orang constant integer := 5;
  c_melenceng_maks_menit constant integer := 15;
  c_alpha_beruntun constant integer := 3;
  c_hari_awal_baru constant integer := 2;     -- PRD celah P3: tanda setelah 2-3 hari kerja tanpa tap
  v_awal date;
  v_akhir date;
  v_versi bigint;
  v_nomor integer;
  v_mulai timestamptz := clock_timestamp();
  v_sidik_masukan text;
  v_sidik_hasil text;
begin
  select tanggal_awal, tanggal_akhir into v_awal, v_akhir from fakta.periode where id = p_periode;
  if not found then
    raise exception 'Periode % tidak ada', p_periode using errcode = 'P0001';
  end if;

  -- Perintah HRD yang berlaku (yang tidak dibatalkan perintah lain).
  drop table if exists _perintah;
  create temp table _perintah on commit drop as
  select p.* from fakta.perintah_hrd p
  where p.jenis <> 'batalkan_perintah'
    and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = p.id);
  create index on _perintah (jenis, id_karyawan, tanggal_mulai);
  analyze _perintah;
  -- Perintah bertanggal dipecah per hari supaya bisa digabung langsung dengan jadwal.
  drop table if exists _perintah_hari;
  create temp table _perintah_hari on commit drop as
  select p.id, p.jenis, p.id_karyawan, p.divisi, p.nilai, d::date as tanggal
  from _perintah p
  cross join generate_series(greatest(p.tanggal_mulai, v_awal - 1)::timestamp,
                             least(coalesce(p.tanggal_selesai, p.tanggal_mulai), v_akhir + 1)::timestamp, interval '1 day') d
  where p.tanggal_mulai is not null and p.jenis in ('sakit', 'izin', 'cuti', 'dinas_luar', 'absen_manual', 'tukar_shift', 'tambah_libur');
  create index on _perintah_hari (id_karyawan, tanggal);
  analyze _perintah_hari;

  -- Kiriman yang dipakai: diterima, berisi tap, tidak dibatalkan.
  drop table if exists _kiriman;
  create temp table _kiriman on commit drop as
  select k.* from fakta.kiriman_file k
  where k.hasil = 'diterima' and k.jenis = 'tap_mesin'
    and not exists (select 1 from _perintah p where p.jenis = 'batalkan_kiriman' and p.nilai = k.id::text);

  -- Sidik masukan: berubah bila ada tap, perintah, data induk, atau aturan baru.
  select encode(sha256(convert_to(concat_ws('|',
           (select string_agg(id::text, ',' order by id) from _kiriman),
           (select max(id) from fakta.perintah_hrd),
           (select max(id) from jejak.perubahan),
           v_awal, v_akhir, c_versi_kode), 'UTF8')), 'hex')
  into v_sidik_masukan;

  select coalesce(max(nomor), 0) + 1 into v_nomor from hitung.versi_hitung where periode_id = p_periode and jenis = 'baca_tap';
  insert into hitung.versi_hitung (periode_id, nomor, versi_kode, sidik_masukan)
  values (p_periode, v_nomor, c_versi_kode, v_sidik_masukan)
  returning id into v_versi;

  -- 1. Bakukan. ID mesin -> karyawan lewat pemetaan bertanggal; jam mesin dikoreksi lewat induk.waktu_baku.
  --    Diambil tap yang mungkin milik hari kemarin dari awal periode sampai hari sesudah akhir periode.
  drop table if exists _tap;
  create temp table _tap on commit drop as
  select t.id as tap_id, t.kiriman_id, t.mesin, t.id_mesin, t.status_mesin,
         w.waktu as waktu_baku, (w.waktu at time zone c_zona) as lokal,
         pm.id_karyawan
  from fakta.tap_mentah t
  join _kiriman k on k.id = t.kiriman_id
  cross join lateral (select induk.waktu_baku(t.mesin, t.jam_lokal) as waktu) w
  left join induk.pemetaan_id_mesin pm
    on pm.mesin = t.mesin and pm.id_mesin = t.id_mesin
   and daterange(pm.berlaku_dari, pm.berlaku_sampai, '[)') @> t.jam_lokal::date
  where t.jam_lokal >= (v_awal - 2)::timestamp and t.jam_lokal < (v_akhir + 3)::timestamp;
  delete from _tap where lokal < (v_awal - 1)::timestamp or lokal >= (v_akhir + 2)::timestamp;
  analyze _tap;

  -- 2. Buang dobel: ID karyawan dan waktu yang sama persis dihitung sekali (kasus A06, A07, F07).
  alter table _tap add column peran text, add column tanggal_kerja date;
  update _tap set peran = 'id_tidak_dikenal' where id_karyawan is null;
  update _tap t set peran = 'dobel'
  from (select tap_id, row_number() over (partition by id_karyawan, waktu_baku order by tap_id) as n
        from _tap where id_karyawan is not null) d
  where d.tap_id = t.tap_id and d.n > 1;
  create index on _tap (id_karyawan, waktu_baku);
  create index on _tap (id_karyawan, tanggal_kerja);

  -- Masa aktif karyawan: dari tanggal mulai (atau aktif kembali) sampai tanggal berhenti, termasuk hari berhenti.
  drop table if exists _aktif;
  create temp table _aktif on commit drop as
  select s.id_karyawan, s.tanggal as dari,
         (select min(b.tanggal) from induk.status_kerja b
          where b.id_karyawan = s.id_karyawan and b.jenis = 'berhenti' and b.tanggal >= s.tanggal) as sampai
  from induk.status_kerja s
  where s.jenis in ('mulai', 'aktif_kembali');
  create index on _aktif (id_karyawan);
  analyze _aktif;

  -- 3. Cari jadwal tiap orang aktif untuk hari kemarin awal periode sampai hari sesudah akhir periode.
  drop table if exists _jadwal;
  create temp table _jadwal on commit drop as
  with hari as (
    select d::date as tanggal from generate_series((v_awal - 1)::timestamp, (v_akhir + 1)::timestamp, interval '1 day') d
  ), hari_divisi as materialized (
    -- Nilai yang sama untuk semua orang di satu divisi pada satu tanggal, dihitung sekali.
    select dv.kode as divisi, h.tanggal,
           (select k.jenis from induk.kalender k where k.tanggal = h.tanggal
            order by case k.jenis when 'libur_perusahaan' then 1 when 'libur_nasional' then 2 else 3 end limit 1) as kalender,
           exists (select 1 from _perintah_hari p
                   where p.jenis = 'tambah_libur' and (p.divisi is null or p.divisi = dv.kode) and p.tanggal = h.tanggal) as libur_mendadak,
           aturan.pengaturan_pada('operasi_7_hari', dv.kode, h.tanggal) = 'ya' as operasi_7_hari
    from induk.divisi dv cross join hari h
  ), riwayat as materialized (
    select * from induk.karyawan_riwayat
    where daterange(berlaku_dari, berlaku_sampai, '[)') && daterange(v_awal - 1, v_akhir + 2)
  ), regu as materialized (
    select * from induk.penugasan_regu
    where daterange(berlaku_dari, berlaku_sampai, '[)') && daterange(v_awal - 1, v_akhir + 2)
  ), orang as materialized (
    select a.id_karyawan, h.tanggal, r.divisi, r.wajib_tap, coalesce(pr.regu, 0) as regu
    from _aktif a
    join hari h on h.tanggal >= a.dari and (a.sampai is null or h.tanggal <= a.sampai)
    join riwayat r
      on r.id_karyawan = a.id_karyawan and h.tanggal >= r.berlaku_dari and (r.berlaku_sampai is null or h.tanggal < r.berlaku_sampai)
    left join regu pr
      on pr.id_karyawan = a.id_karyawan and h.tanggal >= pr.berlaku_dari and (pr.berlaku_sampai is null or h.tanggal < pr.berlaku_sampai)
  ), dasar as materialized (
    select o.*, dv.pola, dv.mesin_utama,
           case dv.pola
             when 'rotasi' then rot.siklus[(((o.tanggal - rot.jangkar) + rot.geser_per_regu * o.regu) % rot.n + rot.n) % rot.n + 1]
             else jh.kode
           end as kode_regu,
           -- Tukar shift per orang mengalahkan jadwal regu (kasus B04). Nilai 'libur' berarti libur.
           (select p.nilai from _perintah_hari p
            where p.jenis = 'tukar_shift' and p.id_karyawan = o.id_karyawan and p.tanggal = o.tanggal
            order by p.id desc limit 1) as kode_tukar,
           hd.kalender, hd.libur_mendadak, hd.operasi_7_hari
    from orang o
    join induk.divisi dv on dv.kode = o.divisi
    join hari_divisi hd on hd.divisi = o.divisi and hd.tanggal = o.tanggal
    left join lateral (select pr.siklus, pr.jangkar, pr.geser_per_regu, cardinality(pr.siklus) as n
                       from induk.pola_rotasi pr
                       where pr.divisi = o.divisi and daterange(pr.berlaku_dari, pr.berlaku_sampai, '[)') @> o.tanggal) rot
      on dv.pola = 'rotasi'
    left join induk.jadwal_hari jh
      on dv.pola <> 'rotasi' and jh.divisi = o.divisi and jh.regu = o.regu and jh.hari_ke = extract(isodow from o.tanggal)
     and daterange(jh.berlaku_dari, jh.berlaku_sampai, '[)') @> o.tanggal
  ), kode as (
    select d.*,
           case when d.kode_tukar is not null then nullif(d.kode_tukar, 'libur') else d.kode_regu end as kode_rencana
    from dasar d
  ), akhir as (
    select k.id_karyawan, k.tanggal, k.divisi, k.regu, k.wajib_tap, k.mesin_utama, k.kode_tukar,
           case
             when k.libur_mendadak or k.kalender = 'libur_perusahaan' then null
             when k.kalender is not null and not k.operasi_7_hari then null
             else k.kode_rencana
           end as kode,
           case
             when k.libur_mendadak or k.kalender = 'libur_perusahaan' then 'libur_perusahaan'
             when k.kalender is not null and not k.operasi_7_hari then k.kalender
             when k.kode_rencana is null then 'libur_rutin'
             when k.kalender is not null then k.kalender  -- operasi 7 hari masuk di hari libur nasional/cuti bersama
             else 'kerja'
           end as jenis_hari
    from kode k
  )
  select a.*, kj.jam_masuk, kj.jam_pulang,
         (a.tanggal + kj.jam_masuk) at time zone c_zona as jadwal_masuk,
         (a.tanggal + kj.jam_pulang + case when kj.jam_pulang <= kj.jam_masuk then interval '1 day' else interval '0' end)
           at time zone c_zona as jadwal_pulang,
         jt.menit_sebelum_masuk, jt.menit_sesudah_pulang, jt.jarak_minimal_menit,
         coalesce(tl.telat_menit, 0) as toleransi_telat, coalesce(tl.pulang_cepat_menit, 0) as toleransi_pulang
  from akhir a
  left join induk.kode_jadwal kj on kj.kode = a.kode
  left join lateral (select * from aturan.jendela_tap j
                     where j.cakupan in (a.divisi, 'perusahaan')
                       and daterange(j.berlaku_dari, j.berlaku_sampai, '[)') @> a.tanggal
                     order by (j.cakupan = a.divisi) desc limit 1) jt on true
  left join lateral (select * from aturan.toleransi t
                     where t.cakupan in (a.divisi, 'perusahaan')
                       and daterange(t.berlaku_dari, t.berlaku_sampai, '[)') @> a.tanggal
                     order by (t.cakupan = a.divisi) desc limit 1) tl on true;

  if exists (select 1 from _jadwal where kode is not null and menit_sebelum_masuk is null) then
    raise exception 'Aturan jendela tap belum diisi untuk sebagian tanggal periode ini' using errcode = 'P0001';
  end if;

  alter table _jadwal
    add column jendela_awal timestamptz, add column jendela_akhir timestamptz, add column bertumpuk boolean not null default false;
  update _jadwal set
    jendela_awal = jadwal_masuk - make_interval(mins => menit_sebelum_masuk),
    jendela_akhir = jadwal_pulang + make_interval(mins => menit_sesudah_pulang)
  where kode is not null;
  create index on _jadwal (id_karyawan, tanggal);
  analyze _jadwal;

  -- Jendela bertumpuk dengan hari sebelahnya (kasus B10): kedua hari tetap dibaca, diberi tanda.
  update _jadwal j set bertumpuk = true
  where j.kode is not null and exists (
    select 1 from _jadwal j2
    where j2.id_karyawan = j.id_karyawan and j2.kode is not null and j2.tanggal in (j.tanggal - 1, j.tanggal + 1)
      and tstzrange(j2.jendela_awal, j2.jendela_akhir) && tstzrange(j.jendela_awal, j.jendela_akhir));

  -- 4. Pasang jendela: tiap tap masuk ke jendela hari terjadwal orang itu. Bila jendela bertumpuk, pilih
  --    jam jadwal yang paling dekat. Bila sama dekat (shift malam lalu shift pagi: jam pulang dan jam masuk
  --    sama-sama 07.00), pilih hari yang memakai tap itu sebagai masuk atau pulang (tap paling awal atau
  --    paling akhir di jendelanya); lalu hari yang punya tap lain yang pasti miliknya (hari tanpa tap lain
  --    kemungkinan memang tidak masuk); lalu kolom Status sebagai penentu cadangan (PRD bagian 7);
  --    lalu hari yang lebih awal.
  drop table if exists _calon;
  create temp table _calon on commit drop as
  select t2.tap_id, t2.id_karyawan, j.tanggal, t2.status_mesin,
         least(abs(extract(epoch from t2.waktu_baku - j.jadwal_masuk)), abs(extract(epoch from t2.waktu_baku - j.jadwal_pulang))) as jarak,
         count(*) over (partition by t2.tap_id) as jumlah_calon,
         t2.waktu_baku in (min(t2.waktu_baku) over (partition by t2.id_karyawan, j.tanggal),
                           max(t2.waktu_baku) over (partition by t2.id_karyawan, j.tanggal)) as terpakai
  from _tap t2
  join _jadwal j on j.id_karyawan = t2.id_karyawan and j.kode is not null
                and t2.waktu_baku >= j.jendela_awal and t2.waktu_baku <= j.jendela_akhir
  where t2.peran is null;
  update _tap t set tanggal_kerja = pilih.tanggal
  from (
    select distinct on (c.tap_id) c.tap_id, c.tanggal
    from _calon c
    left join (select id_karyawan, tanggal, count(*) as n from _calon where jumlah_calon = 1 group by id_karyawan, tanggal) pasti
      on pasti.id_karyawan = c.id_karyawan and pasti.tanggal = c.tanggal
    order by c.tap_id, c.jarak, not c.terpakai, (coalesce(pasti.n, 0) = 0),
             case when c.status_mesin = 'Keluar' then c.tanggal end,
             case when c.status_mesin = 'Masuk' then c.tanggal end desc,
             c.tanggal
  ) pilih
  where pilih.tap_id = t.tap_id;

  -- Urutan waktu: pulang hari sebelumnya tidak boleh lebih lambat dari masuk hari berikutnya. Bila dua tap
  -- di jendela bertumpuk tertukar (misalnya shift malam lalu shift pagi karena tukar shift), keduanya ditukar
  -- kembali.
  update _tap t set tanggal_kerja = x.tanggal_baru
  from (
    with per_hari as (
      select id_karyawan, tanggal_kerja as tanggal, min(waktu_baku) as t_awal, max(waktu_baku) as t_akhir,
             (array_agg(tap_id order by waktu_baku, tap_id))[1] as tap_awal,
             (array_agg(tap_id order by waktu_baku desc, tap_id desc))[1] as tap_akhir
      from _tap where peran is null and tanggal_kerja is not null
      group by id_karyawan, tanggal_kerja
    ), silang as (
      select a.tap_akhir as tap_a, a.tanggal as tanggal_a, b.tap_awal as tap_b, b.tanggal as tanggal_b
      from per_hari a
      join per_hari b on b.id_karyawan = a.id_karyawan and b.tanggal = a.tanggal + 1
      where a.t_akhir > b.t_awal and a.t_awal < b.t_awal and b.t_akhir > a.t_akhir
    )
    select tap_a as tap_id, tanggal_b as tanggal_baru from silang
    union all
    select tap_b, tanggal_a from silang
  ) x
  where x.tap_id = t.tap_id;

  -- Tap di luar semua jendela: di hari libur orang itu menjadi lembur hari libur; setelah tanggal berhenti
  -- atau sebelum tanggal mulai tidak dihitung; selain itu tercatat di luar jendela (kasus B09).
  update _tap t set
    tanggal_kerja = case when j.kode is null and j.tanggal is not null then (t.lokal)::date end,
    peran = case
              when j.tanggal is null and exists (select 1 from _aktif a where a.id_karyawan = t.id_karyawan
                                                   and a.sampai is not null and t.lokal::date > a.sampai)
                   and not exists (select 1 from _aktif a where a.id_karyawan = t.id_karyawan and t.lokal::date >= a.dari
                                     and (a.sampai is null or t.lokal::date <= a.sampai)) then 'setelah_berhenti'
              when j.tanggal is null then 'sebelum_mulai'
              when j.kode is null then null
              else 'di_luar_jendela'
            end
  from _tap t0
  left join _jadwal j on j.id_karyawan = t0.id_karyawan and j.tanggal = (t0.lokal)::date
  where t0.tap_id = t.tap_id and t.peran is null and t.tanggal_kerja is null;
  update _tap set tanggal_kerja = lokal::date where peran = 'di_luar_jendela';

  -- 5. Tentukan masuk dan pulang per orang per hari. Tap berjarak kurang dari jarak minimal dihitung satu;
  --    tap paling awal = masuk, paling akhir = pulang, tap di antaranya tercatat tetapi diabaikan.
  drop table if exists _hari;
  create temp table _hari on commit drop as
  select j.id_karyawan, j.tanggal, j.kode, j.jadwal_masuk, j.jadwal_pulang,
         make_interval(mins => j.jarak_minimal_menit) as jarak, t.t_awal, t.t_akhir, t.jumlah, t.tap_awal, t.tap_akhir
  from (select id_karyawan, tanggal_kerja, min(waktu_baku) as t_awal, max(waktu_baku) as t_akhir, count(*) as jumlah,
               (array_agg(tap_id order by waktu_baku, tap_id))[1] as tap_awal,
               (array_agg(tap_id order by waktu_baku desc, tap_id desc))[1] as tap_akhir
        from _tap where peran is null and tanggal_kerja is not null
        group by id_karyawan, tanggal_kerja) t
  join _jadwal j on j.id_karyawan = t.id_karyawan and j.tanggal = t.tanggal_kerja;
  create index on _hari (id_karyawan, tanggal);

  -- Satu tap (atau beberapa tap yang jaraknya kurang dari jarak minimal): dekat jam masuk = masuk + lupa
  -- tap pulang; dekat jam pulang = pulang + lupa tap masuk; di tengah shift = seperti lupa tap pulang,
  -- ditandai ambigu (keputusan v3.1, kasus B06, B07, B08, B15). Di hari libur: masuk + lupa tap pulang.
  alter table _hari add column masuk timestamptz, add column pulang timestamptz,
                    add column lupa_tap text, add column tunggal_tengah boolean not null default false;
  update _hari set
    masuk = case
              when t_akhir - t_awal >= jarak or kode is null then t_awal
              when t_awal <= jadwal_masuk + (jadwal_pulang - jadwal_masuk) * c_seperempat then t_awal
              when t_akhir >= jadwal_pulang - (jadwal_pulang - jadwal_masuk) * c_seperempat then null
              else t_awal
            end,
    pulang = case
               when t_akhir - t_awal >= jarak then t_akhir
               when kode is null then null
               when t_awal <= jadwal_masuk + (jadwal_pulang - jadwal_masuk) * c_seperempat then null
               when t_akhir >= jadwal_pulang - (jadwal_pulang - jadwal_masuk) * c_seperempat then t_akhir
               else null
             end;
  update _hari set
    lupa_tap = case when masuk is null then 'masuk' when pulang is null then 'pulang' end,
    tunggal_tengah = (kode is not null and masuk is not null and pulang is null
                      and t_awal > jadwal_masuk + (jadwal_pulang - jadwal_masuk) * c_seperempat);

  -- Peran tiap tap yang terpakai.
  update _tap t set peran = case
      when h.masuk is not null and h.pulang is not null and t.tap_id = h.tap_awal then 'masuk'
      when h.masuk is not null and h.pulang is not null and t.tap_id = h.tap_akhir then 'pulang'
      when (h.masuk is null or h.pulang is null)
           and t.tap_id = case when h.masuk is not null then h.tap_awal else h.tap_akhir end then 'tunggal'
      else 'diabaikan'
    end
  from _hari h
  where t.peran is null and t.id_karyawan = h.id_karyawan and t.tanggal_kerja = h.tanggal;

  -- 6. Hasil per orang per hari.
  drop table if exists _hasil;
  create temp table _hasil on commit drop as
  select j.id_karyawan, j.tanggal, j.divisi, j.regu, j.kode as kode_jadwal, j.jenis_hari,
         j.jadwal_masuk, j.jadwal_pulang, j.wajib_tap, j.mesin_utama, j.jendela_awal, j.jendela_akhir,
         j.toleransi_telat, j.toleransi_pulang, j.bertumpuk, j.kode_tukar, j.menit_sesudah_pulang,
         h.masuk, h.pulang, h.lupa_tap, coalesce(h.tunggal_tengah, false) as tunggal_tengah, coalesce(h.jumlah, 0) as jumlah_tap,
         (select p.jenis from _perintah_hari p
          where p.jenis in ('sakit', 'izin', 'cuti', 'dinas_luar') and p.id_karyawan = j.id_karyawan and p.tanggal = j.tanggal
          order by p.id desc limit 1) as perintah_pribadi,
         (exists (select 1 from _perintah_hari p
                  where p.jenis = 'absen_manual' and p.id_karyawan = j.id_karyawan and p.tanggal = j.tanggal)
          or exists (select 1 from _perintah_hari p
                     where p.jenis = 'absen_manual' and p.id_karyawan is null and p.divisi = j.divisi and p.tanggal = j.tanggal))
           as absen_manual,
         exists (select 1 from _tap t where t.id_karyawan = j.id_karyawan and t.tanggal_kerja = j.tanggal
                   and t.peran = 'di_luar_jendela') as ada_tap_luar
  from _jadwal j
  left join _hari h on h.id_karyawan = j.id_karyawan and h.tanggal = j.tanggal;
  create index on _hasil (id_karyawan, tanggal);
  analyze _hasil;

  -- Cakupan data per mesin: kiriman membuktikan semua tap sampai jam diterima sudah ada (celah M9, kasus B11).
  drop table if exists _cakupan;
  create temp table _cakupan on commit drop as
  select k.mesin, min(k.tanggal_awal) as dari, max(k.diterima) as sampai
  from _kiriman k group by k.mesin;
  drop table if exists _lubang;
  create temp table _lubang on commit drop as
  select m.kode as mesin, d::date as tanggal
  from induk.mesin m
  cross join generate_series(v_awal::timestamp, v_akhir::timestamp, interval '1 day') d
  where not exists (select 1 from _kiriman k where k.mesin = m.kode
                      and d::date between k.tanggal_awal and (k.diterima at time zone c_zona)::date)
    and exists (select 1 from _jadwal j where j.mesin_utama = m.kode and j.tanggal = d::date and j.kode is not null and j.wajib_tap);

  alter table _hasil add column status text, add column asal text, add column ambigu boolean not null default false,
                     add column tanda text[] not null default '{}';
  update _hasil r set
    status = case
      when r.kode_jadwal is null and r.jumlah_tap > 0 then 'lembur_hari_libur'
      when r.kode_jadwal is null then 'libur'
      when r.perintah_pribadi is not null then r.perintah_pribadi
      when r.wajib_tap and (exists (select 1 from _lubang l where l.mesin = r.mesin_utama and l.tanggal = r.tanggal)
                            or r.jendela_akhir > coalesce((select c.sampai from _cakupan c where c.mesin = r.mesin_utama),
                                                          (select max(c.sampai) from _cakupan c), '-infinity'))
           and not r.absen_manual then 'menunggu'
      when r.jumlah_tap > 0 then 'hadir'
      when not r.wajib_tap then 'hadir'
      when r.absen_manual then 'hadir'
      else 'alpha'
    end,
    asal = case
      when r.kode_jadwal is null and r.jumlah_tap > 0 then 'mesin'
      when r.kode_jadwal is null then 'jadwal'
      when r.perintah_pribadi is not null then 'perintah'
      when r.jumlah_tap > 0 then 'mesin'
      when not r.wajib_tap then 'tidak_wajib_tap'
      when r.absen_manual then 'manual'
      else 'mesin'
    end;
  update _hasil set masuk = jadwal_masuk, pulang = jadwal_pulang
  where status = 'hadir' and asal = 'manual';
  update _hasil set
    ambigu = (tunggal_tengah or ada_tap_luar),
    tanda = array_remove(array[
      case when tunggal_tengah then 'tap_tunggal_tengah' end,
      case when ada_tap_luar then 'tap_di_luar_jendela' end,
      case when bertumpuk then 'jendela_bertumpuk' end,
      case when kode_tukar is not null then 'tukar_shift' end,
      case when perintah_pribadi is not null and jumlah_tap > 0 then 'ada_tap' end,
      case when status = 'menunggu' then 'data_belum_lengkap' end
    ], null);
  -- Tap di luar jendela membuat hari tanpa tap terpakai menjadi ambigu: aturan bawaan tetap alpha (kasus B09).

  -- 7. Hari tanpa tap massal (kasus C06, C14, F08): lebih dari ambang karyawan terjadwal satu divisi
  --    tidak punya tap, di divisi dengan minimal sekian karyawan aktif. Tidak langsung alpha.
  drop table if exists _aktif_divisi;
  create temp table _aktif_divisi on commit drop as
  select divisi, tanggal, count(*) as aktif from _jadwal group by divisi, tanggal;
  drop table if exists _massal;
  create temp table _massal on commit drop as
  select r.divisi, r.tanggal,
         count(*) filter (where r.wajib_tap and r.perintah_pribadi is null) as terjadwal,
         count(*) filter (where r.wajib_tap and r.perintah_pribadi is null and r.jumlah_tap = 0 and not r.ada_tap_luar) as tanpa_tap,
         bool_or(r.absen_manual) as ada_absen_manual,
         (select n.aktif from _aktif_divisi n where n.divisi = r.divisi and n.tanggal = r.tanggal) as aktif,
         aturan.pengaturan_pada('ambang_tanpa_tap_massal', r.divisi, r.tanggal)::integer as ambang,
         aturan.pengaturan_pada('minimal_orang_tanpa_tap_massal', r.divisi, r.tanggal)::integer as minimal
  from _hasil r
  where r.kode_jadwal is not null and r.status <> 'menunggu'
  group by r.divisi, r.tanggal;
  delete from _massal where not (aktif >= minimal and terjadwal > 0 and tanpa_tap::bigint * 10000 > ambang::bigint * terjadwal);
  update _hasil r set status = 'tanpa_tap_massal', tanda = array_append(r.tanda, 'tanpa_tap_massal')
  from _massal m
  where m.divisi = r.divisi and m.tanggal = r.tanggal and r.status = 'alpha';

  -- 8. File kemungkinan terpotong (kasus F02): dari karyawan yang jam jadwalnya jatuh di rentang waktu
  --    file itu dan terdaftar di mesin itu, lebih dari ambang tidak ada di file. Yang hilang tidak dijadikan
  --    alpha; hari-harinya menunggu. Hanya file yang mencakup minimal 24 jam yang dinilai: file pendek
  --    (misalnya tap pagi hari berikutnya saja) memang tidak memuat sebagian besar karyawan.
  drop table if exists _harap;
  create temp table _harap on commit drop as
  select k.id as kiriman_id, k.mesin, r.id_karyawan, r.tanggal,
         exists (select 1 from _tap t where t.kiriman_id = k.id and t.id_karyawan = r.id_karyawan) as ada
  from _kiriman k
  join (select kiriman_id, min(waktu_baku) as dari, max(waktu_baku) as sampai from _tap group by kiriman_id) w
    on w.kiriman_id = k.id and w.sampai - w.dari >= interval '24 hours'
  join _hasil r on r.kode_jadwal is not null and r.wajib_tap and r.perintah_pribadi is null
               and (r.jadwal_masuk between w.dari and w.sampai or r.jadwal_pulang between w.dari and w.sampai)
  where exists (select 1 from induk.pemetaan_id_mesin pm
                where pm.mesin = k.mesin and pm.id_karyawan = r.id_karyawan
                  and daterange(pm.berlaku_dari, pm.berlaku_sampai, '[)') @> r.tanggal);
  drop table if exists _terpotong;
  create temp table _terpotong on commit drop as
  select h.kiriman_id, h.mesin, min(h.tanggal) as tanggal_awal, max(h.tanggal) as tanggal_akhir,
         count(distinct h.id_karyawan) as terdaftar, count(distinct h.id_karyawan) filter (where h.ada) as ada
  from _harap h
  group by h.kiriman_id, h.mesin;
  delete from _terpotong t
  where not (t.terdaftar >= aturan.pengaturan_pada('minimal_orang_tanpa_tap_massal', null, t.tanggal_akhir)::integer
             and (t.terdaftar - t.ada)::bigint * 10000
                 > aturan.pengaturan_pada('ambang_tanpa_tap_massal', null, t.tanggal_akhir)::bigint * t.terdaftar);
  update _hasil r set status = 'menunggu', tanda = array_append(r.tanda, 'file_terpotong')
  from _harap h
  join _terpotong f on f.kiriman_id = h.kiriman_id
  where r.status in ('alpha', 'tanpa_tap_massal') and r.id_karyawan = h.id_karyawan and r.tanggal = h.tanggal
    and not exists (select 1 from _harap h2 where h2.kiriman_id = h.kiriman_id and h2.id_karyawan = h.id_karyawan and h2.ada);

  -- 9. Menit telat, pulang cepat, dan lebih jam dihitung dari jadwal, bukan dari selisih dua tap.
  --    Datang lebih awal tidak menjadi lembur (kasus B05). Rupiah lembur dihitung di Tahap 4.
  alter table _hasil add column menit_telat integer not null default 0, add column menit_pulang_cepat integer not null default 0,
                     add column menit_lebih integer not null default 0, add column menit_hadir integer;
  update _hasil set
    menit_telat = case when masuk is not null
                        and floor(extract(epoch from masuk - jadwal_masuk) / 60) > toleransi_telat
                       then floor(extract(epoch from masuk - jadwal_masuk) / 60)::integer else 0 end,
    menit_pulang_cepat = case when pulang is not null
                               and floor(extract(epoch from jadwal_pulang - pulang) / 60) > toleransi_pulang
                              then floor(extract(epoch from jadwal_pulang - pulang) / 60)::integer else 0 end,
    menit_lebih = case when pulang is not null and pulang > jadwal_pulang
                       then floor(extract(epoch from pulang - jadwal_pulang) / 60)::integer else 0 end
  where status in ('hadir', 'menunggu') and asal = 'mesin' and kode_jadwal is not null;
  update _hasil set menit_hadir = floor(extract(epoch from pulang - masuk) / 60)::integer
  where status = 'lembur_hari_libur' and pulang is not null;
  update _hasil set ambigu = true, tanda = array_append(tanda, 'tap_tunggal')
  where status = 'lembur_hari_libur' and pulang is null;
  -- Lupa tap tidak berlaku untuk hari yang tidak dibaca dari mesin.
  update _hasil set lupa_tap = null where asal <> 'mesin' or status not in ('hadir', 'lembur_hari_libur');

  -- Simpan tap bersih dan hasil. Hari di luar periode tidak disimpan; tapnya bertanda milik periode lain (kasus B12).
  update _tap set peran = 'milik_periode_lain'
  where tanggal_kerja is not null and (tanggal_kerja < v_awal or tanggal_kerja > v_akhir);
  if exists (select 1 from _tap where peran is null) then
    raise exception 'Kesalahan mesin baca tap: ada tap tanpa peran' using errcode = 'P0001';
  end if;
  insert into hitung.tap_bersih (versi_id, tap_id, id_karyawan, waktu_baku, tanggal_kerja, peran)
  select v_versi, tap_id, id_karyawan, waktu_baku, tanggal_kerja, peran
  from _tap
  where tanggal_kerja between v_awal and v_akhir or lokal::date between v_awal and v_akhir;

  insert into hitung.hasil_harian (versi_id, id_karyawan, tanggal, divisi, regu, kode_jadwal, jenis_hari, jadwal_masuk,
                                   jadwal_pulang, status, asal, masuk, pulang, menit_telat, menit_pulang_cepat, menit_lebih,
                                   menit_hadir, lupa_tap, ambigu, tanda)
  select v_versi, id_karyawan, tanggal, divisi, regu, kode_jadwal, jenis_hari, jadwal_masuk, jadwal_pulang, status, asal,
         masuk, pulang, menit_telat, menit_pulang_cepat, menit_lebih, menit_hadir, lupa_tap, ambigu, tanda
  from _hasil
  where tanggal between v_awal and v_akhir;

  -- 10. Anomali untuk HRD (dikirim mulai Tahap 5).
  -- Hari yang sudah ditetapkan HRD lewat absen manual tercatat sebagai selesai (kasus F08).
  insert into hitung.anomali (versi_id, jenis, tingkat, divisi, tanggal, nilai, keterangan, selesai)
  select v_versi, 'tanpa_tap_massal', 'segera', m.divisi, m.tanggal, m.tanpa_tap || '/' || m.terjadwal,
         case when m.ada_absen_manual
              then format('%s dari %s karyawan terjadwal di divisi %s tanpa tap pada %s; sudah ditetapkan absen manual',
                          m.tanpa_tap, m.terjadwal, m.divisi, to_char(m.tanggal, 'DD-MM-YYYY'))
              else format('%s dari %s karyawan terjadwal di divisi %s tanpa tap pada %s; tetapkan libur, absen manual, atau alpha',
                          m.tanpa_tap, m.terjadwal, m.divisi, to_char(m.tanggal, 'DD-MM-YYYY')) end,
         m.ada_absen_manual
  from _massal m where m.tanggal between v_awal and v_akhir;

  insert into hitung.anomali (versi_id, jenis, tingkat, mesin, kiriman_id, tanggal, tanggal_akhir, nilai, keterangan)
  select v_versi, 'file_terpotong', 'segera', f.mesin, f.kiriman_id, f.tanggal_awal, f.tanggal_akhir, f.ada || '/' || f.terdaftar,
         format('File kiriman no. %s dari mesin %s hanya memuat %s dari %s karyawan aktif yang terdaftar; yang tidak ada tidak dijadikan alpha',
                f.kiriman_id, f.mesin, f.ada, f.terdaftar)
  from _terpotong f;

  insert into hitung.anomali (versi_id, jenis, tingkat, mesin, kiriman_id, tanggal, nilai, keterangan)
  select v_versi, 'tap_terakhir_lama', 'segera', k.mesin, k.id, k.tanggal_akhir,
         ((k.diterima at time zone c_zona)::date - k.tanggal_akhir)::text,
         format('Tap terakhir di kiriman no. %s (mesin %s) bertanggal %s, %s hari sebelum dikirim; kemungkinan memori mesin penuh atau mesin mati',
                k.id, k.mesin, to_char(k.tanggal_akhir, 'DD-MM-YYYY'), (k.diterima at time zone c_zona)::date - k.tanggal_akhir)
  from _kiriman k
  where (k.diterima at time zone c_zona)::date - k.tanggal_akhir >= c_hari_tap_lama
    and k.tanggal_akhir >= v_awal - 1 and k.tanggal_awal <= v_akhir + 1;

  insert into hitung.anomali (versi_id, jenis, tingkat, mesin, tanggal, tanggal_akhir, nilai, keterangan)
  select v_versi, 'lubang_cakupan', 'sebelum_rilis', l.mesin, min(l.tanggal), max(l.tanggal), count(*)::text,
         format('Mesin %s: tidak ada kiriman yang mencakup %s hari (%s s.d. %s); periode tidak bisa diajukan sebelum ada file atau keterangan',
                l.mesin, count(*), to_char(min(l.tanggal), 'DD-MM-YYYY'), to_char(max(l.tanggal), 'DD-MM-YYYY'))
  from (select *, tanggal - (row_number() over (partition by mesin order by tanggal))::integer as kelompok from _lubang) l
  group by l.mesin, l.kelompok;

  -- Jam mesin kemungkinan melenceng (kasus F05): pada satu mesin, satu tanggal, satu jadwal,
  -- separuh atau lebih orang telat tipis.
  insert into hitung.anomali (versi_id, jenis, tingkat, mesin, tanggal, nilai, keterangan)
  select v_versi, 'jam_mesin_melenceng', 'segera', x.mesin, x.tanggal, x.telat_tipis || '/' || x.jumlah,
         format('Mesin %s pada %s: %s dari %s orang jadwal %s telat tipis (sampai %s menit); kemungkinan jam mesin melenceng',
                x.mesin, to_char(x.tanggal, 'DD-MM-YYYY'), x.telat_tipis, x.jumlah, x.kode_jadwal, c_melenceng_maks_menit)
  from (
    select t.mesin, r.tanggal, r.kode_jadwal, count(*) as jumlah,
           count(*) filter (where r.menit_telat between 1 and c_melenceng_maks_menit) as telat_tipis
    from _hasil r
    join _tap t on t.id_karyawan = r.id_karyawan and t.tanggal_kerja = r.tanggal and t.peran = 'masuk'
    where r.tanggal between v_awal and v_akhir and r.masuk is not null
    group by t.mesin, r.tanggal, r.kode_jadwal
  ) x
  where x.jumlah >= c_melenceng_min_orang and x.telat_tipis * 2 >= x.jumlah;

  -- Karyawan baru belum didaftar di mesin (kasus F13): hari-hari kerja pertamanya tanpa tap sama sekali.
  -- Versi 2 (kasus F13b, permintaan perubahan 02): hari sakit, izin, cuti, dinas luar dari perintah HRD dilewati.
  insert into hitung.anomali (versi_id, jenis, tingkat, id_karyawan, divisi, tanggal, tanggal_akhir, keterangan)
  select v_versi, 'belum_terdaftar_mesin', 'segera', x.id_karyawan, x.divisi, x.dari, x.sampai,
         format('Karyawan baru %s tanpa tap di %s hari kerja pertamanya (mulai %s); belum didaftar di mesin?',
                x.id_karyawan, c_hari_awal_baru, to_char(x.mulai, 'DD-MM-YYYY'))
  from (
    select r.id_karyawan, r.divisi, a.dari as mulai, min(r.tanggal) as dari, max(r.tanggal) as sampai,
           count(*) filter (where r.status in ('alpha', 'tanpa_tap_massal')) as tanpa_tap
    from _aktif a
    join lateral (select * from _hasil h
                  where h.id_karyawan = a.id_karyawan and h.kode_jadwal is not null and h.wajib_tap and h.tanggal >= a.dari
                    and not (h.asal = 'perintah' and h.status in ('sakit', 'izin', 'cuti', 'dinas_luar'))
                  order by h.tanggal limit c_hari_awal_baru) r on true
    where a.dari between v_awal - c_hari_awal_baru and v_akhir
    group by r.id_karyawan, r.divisi, a.dari
  ) x
  where x.tanpa_tap = c_hari_awal_baru and x.sampai between v_awal and v_akhir;

  -- Alpha beruntun (kasus C13): alpha di hari kerja berturut-turut orang itu (hari libur dilewati).
  insert into hitung.anomali (versi_id, jenis, tingkat, id_karyawan, divisi, tanggal, tanggal_akhir, nilai, keterangan)
  select v_versi, 'alpha_beruntun', 'harian', g.id_karyawan, g.divisi, min(g.tanggal), max(g.tanggal), count(*)::text,
         format('%s alpha %s hari kerja berturut-turut (%s s.d. %s)', g.id_karyawan, count(*),
                to_char(min(g.tanggal), 'DD-MM-YYYY'), to_char(max(g.tanggal), 'DD-MM-YYYY'))
  from (
    select k.*, k.urut - row_number() over (partition by k.id_karyawan order by k.tanggal) as kelompok
    from (select r.id_karyawan, r.divisi, r.tanggal, r.status,
                 row_number() over (partition by r.id_karyawan order by r.tanggal) as urut
          from _hasil r where r.kode_jadwal is not null and r.tanggal between v_awal and v_akhir) k
    where k.status = 'alpha'
  ) g
  group by g.id_karyawan, g.divisi, g.kelompok
  having count(*) >= c_alpha_beruntun;

  insert into hitung.anomali (versi_id, jenis, tingkat, mesin, tanggal, tanggal_akhir, nilai, keterangan)
  select v_versi, 'id_tidak_dikenal', 'harian', t.mesin, min(t.lokal::date), max(t.lokal::date), t.id_mesin,
         format('ID mesin %s di mesin %s tidak terdaftar pada tanggal tap (%s tap, %s s.d. %s); tidak dihitung',
                t.id_mesin, t.mesin, count(*), to_char(min(t.lokal::date), 'DD-MM-YYYY'), to_char(max(t.lokal::date), 'DD-MM-YYYY'))
  from _tap t
  where t.peran = 'id_tidak_dikenal' and t.lokal >= v_awal::timestamp and t.lokal < (v_akhir + 1)::timestamp
  group by t.mesin, t.id_mesin;

  insert into hitung.anomali (versi_id, jenis, tingkat, id_karyawan, tanggal, tanggal_akhir, nilai, keterangan)
  select v_versi, 'tap_setelah_berhenti', 'harian', t.id_karyawan, min(t.lokal::date), max(t.lokal::date), count(*)::text,
         format('%s punya %s tap setelah tanggal berhenti (%s s.d. %s); tidak dihitung', t.id_karyawan, count(*),
                to_char(min(t.lokal::date), 'DD-MM-YYYY'), to_char(max(t.lokal::date), 'DD-MM-YYYY'))
  from _tap t
  where t.peran = 'setelah_berhenti' and t.lokal >= v_awal::timestamp and t.lokal < (v_akhir + 1)::timestamp
  group by t.id_karyawan;

  -- Usulan tukar shift (kasus F11): hari yang terbaca janggal, padahal tapnya cocok dengan shift lain.
  --    Hasil tetap mengikuti jadwal sampai HRD menyetujui (perintah tukar_shift), lalu dihitung ulang.
  insert into hitung.anomali (versi_id, jenis, tingkat, id_karyawan, divisi, tanggal, nilai, keterangan)
  select v_versi, 'usulan_tukar_shift', 'harian', u.id_karyawan, u.divisi, u.tanggal, u.kode_lain,
         format('%s tanggal %s terjadwal %s, tetapi tapnya cocok shift %s; setujui tukar shift?',
                u.id_karyawan, to_char(u.tanggal, 'DD-MM-YYYY'), u.kode_jadwal, u.kode_lain)
  from (
    select distinct on (r.id_karyawan, r.tanggal) r.id_karyawan, r.divisi, r.tanggal, r.kode_jadwal, kj.kode as kode_lain
    from _hasil r
    join induk.kode_jadwal kj on kj.kode <> r.kode_jadwal
    where r.tanggal between v_awal and v_akhir and r.kode_jadwal is not null and r.kode_tukar is null
      and r.perintah_pribadi is null and r.wajib_tap
      and (r.status = 'alpha' or r.lupa_tap is not null or r.ada_tap_luar or r.menit_telat > c_menit_cocok_shift
           or r.menit_pulang_cepat > c_menit_cocok_shift)
      -- Shift lain yang dipakai divisi itu
      and (kj.kode in (select unnest(pr.siklus) from induk.pola_rotasi pr where pr.divisi = r.divisi)
           or kj.kode in (select jh.kode from induk.jadwal_hari jh where jh.divisi = r.divisi))
      and exists (select 1 from _tap t
                  where t.id_karyawan = r.id_karyawan and t.peran not in ('dobel', 'id_tidak_dikenal')
                    and t.waktu_baku between ((r.tanggal + kj.jam_masuk) at time zone c_zona) - make_interval(mins => c_menit_cocok_shift)
                                         and ((r.tanggal + kj.jam_masuk) at time zone c_zona) + make_interval(mins => c_menit_cocok_shift))
      -- dan ada tap pulang sesudahnya di dalam jendela shift lain itu (pulang lambat atau cepat tetap cocok)
      and exists (select 1 from _tap t
                  where t.id_karyawan = r.id_karyawan and t.peran not in ('dobel', 'id_tidak_dikenal')
                    and t.waktu_baku > ((r.tanggal + kj.jam_masuk) at time zone c_zona) + make_interval(mins => c_menit_cocok_shift)
                    and t.waktu_baku <= ((r.tanggal + kj.jam_pulang + case when kj.jam_pulang <= kj.jam_masuk
                                           then interval '1 day' else interval '0' end) at time zone c_zona)
                                        + make_interval(mins => coalesce(r.menit_sesudah_pulang, 360)))
    order by r.id_karyawan, r.tanggal, kj.kode
  ) u;

  insert into hitung.anomali (versi_id, jenis, tingkat, id_karyawan, divisi, tanggal, nilai, keterangan)
  select v_versi, 'tap_ambigu', 'harian', r.id_karyawan, r.divisi, r.tanggal, array_to_string(r.tanda, ','),
         format('%s tanggal %s: tap ambigu (%s); aturan bawaan dipakai, gaji tidak tertahan',
                r.id_karyawan, to_char(r.tanggal, 'DD-MM-YYYY'), array_to_string(r.tanda, ', '))
  from _hasil r
  where r.ambigu and r.tanggal between v_awal and v_akhir;

  -- Sidik hasil: dua kali hitung dengan masukan sama harus menghasilkan sidik yang sama.
  select encode(sha256(convert_to(
           coalesce((select string_agg(concat_ws('|', h.id_karyawan, h.tanggal, h.divisi, h.regu, h.kode_jadwal, h.jenis_hari,
                                                 h.jadwal_masuk, h.jadwal_pulang, h.status, h.asal, h.masuk, h.pulang, h.menit_telat,
                                                 h.menit_pulang_cepat, h.menit_lebih, h.menit_hadir, h.lupa_tap, h.ambigu,
                                                 array_to_string(h.tanda, ',')), E'\n' order by h.id_karyawan, h.tanggal)
                     from hitung.hasil_harian h where h.versi_id = v_versi), '')
           || E'\n#\n' ||
           coalesce((select string_agg(concat_ws('|', b.tap_id, b.id_karyawan, b.waktu_baku, b.tanggal_kerja, b.peran), E'\n'
                                       order by b.tap_id)
                     from hitung.tap_bersih b where b.versi_id = v_versi), '')
           || E'\n#\n' ||
           coalesce((select string_agg(concat_ws('|', a.jenis, a.tingkat, a.id_karyawan, a.divisi, a.mesin, a.kiriman_id, a.tanggal,
                                                 a.tanggal_akhir, a.nilai, a.keterangan, a.selesai), E'\n'
                                       order by a.jenis, a.tanggal, a.id_karyawan, a.divisi, a.mesin, a.nilai)
                     from hitung.anomali a where a.versi_id = v_versi), ''),
           'UTF8')), 'hex')
  into v_sidik_hasil;

  update hitung.versi_hitung
  set sidik_hasil = v_sidik_hasil,
      lama_ms = (extract(epoch from clock_timestamp() - v_mulai) * 1000)::integer
  where id = v_versi;

  return v_versi;
end $$;

create or replace function hitung.anomali_gaji(p_periode bigint)
returns table (jenis text, id_karyawan text, divisi text, nilai_lalu bigint, nilai_sekarang bigint, keterangan text)
language sql stable set search_path = '' as $$
  with ini as (
    select v.id as versi, p.tanggal_awal, v.versi_sumber
    from fakta.periode p
    join hitung.versi_terakhir v on v.periode_id = p.id and v.jenis = 'hitung_gaji'
    where p.id = p_periode
  ),
  -- O1: periode lalu = tanggal awal terbesar sebelum P yang punya versi gaji.
  lalu as (
    select v.id as versi
    from fakta.periode p
    join hitung.versi_terakhir v on v.periode_id = p.id and v.jenis = 'hitung_gaji'
    where p.tanggal_awal < (select tanggal_awal from ini)
    order by p.tanggal_awal desc
    limit 1
  ),
  banding as (
    select r.versi_id, r.id_karyawan,
           -- O2 versi 5: upah tetap dan potongan hari tidak dibayar saja.
           coalesce(sum(r.nominal) filter (where r.komponen in ('gaji_pokok', 'tunjangan_tetap', 'potongan_tidak_dibayar')), 0)::bigint as nilai,
           coalesce(sum(r.nominal) filter (where r.komponen = 'lembur'), 0)::bigint as lembur
    from hitung.rincian_gaji r
    where r.versi_id in (select versi from ini union all select versi from lalu)
    group by r.versi_id, r.id_karyawan
  ),
  -- Divisi orang = divisi di hari terakhirnya di hasil harian periode itu (sumber baca tap versi gaji).
  divisi_orang as (
    select distinct on (v.id, h.id_karyawan) v.id as versi, h.id_karyawan, h.divisi
    from hitung.versi_hitung v
    join hitung.hasil_harian h on h.versi_id = v.versi_sumber
    where v.id in (select versi from ini union all select versi from lalu)
    order by v.id, h.id_karyawan, h.tanggal desc
  ),
  lembur_divisi as (
    select d.versi, d.divisi, sum(b.lembur)::bigint as lembur
    from divisi_orang d join banding b on b.versi_id = d.versi and b.id_karyawan = d.id_karyawan
    group by d.versi, d.divisi
  )
  -- O2: gaji berubah lebih dari 15%.
  select 'gaji_berubah', s.id_karyawan, null::text, l.nilai, s.nilai,
         format('Upah tetap dikurangi potongan hari tidak dibayar berubah dari Rp%s menjadi Rp%s (%s%%)', l.nilai, s.nilai,
                round((s.nilai - l.nilai) * 100.0 / l.nilai, 1))
  from banding s
  join banding l on l.id_karyawan = s.id_karyawan and l.versi_id = (select versi from lalu)
  where s.versi_id = (select versi from ini) and l.nilai > 0 and abs(s.nilai - l.nilai) * 100 > 15 * l.nilai
  union all
  -- O3: lembur divisi naik lebih dari 30%.
  select 'lembur_divisi_naik', null, s.divisi, coalesce(l.lembur, 0), s.lembur,
         format('Lembur divisi %s naik dari Rp%s menjadi Rp%s', s.divisi, coalesce(l.lembur, 0), s.lembur)
  from lembur_divisi s
  left join lembur_divisi l on l.divisi = s.divisi and l.versi = (select versi from lalu)
  where s.versi = (select versi from ini) and exists (select 1 from lalu)
    and s.lembur * 100 > 130 * coalesce(l.lembur, 0)
  union all
  -- O4: gaji dibayar tanpa satu pun hari dengan tap mesin.
  select 'aktif_tanpa_tap', g.id_karyawan, d.divisi, null::bigint, g.gaji_bersih,
         format('%s digaji Rp%s tanpa satu pun tap mesin di periode ini (asal hari: %s)', g.id_karyawan, g.gaji_bersih,
                (select string_agg(distinct h.asal, ', ' order by h.asal) from hitung.hasil_harian h
                 where h.versi_id = (select versi_sumber from ini) and h.id_karyawan = g.id_karyawan))
  from hitung.ringkasan_gaji g
  join divisi_orang d on d.versi = g.versi_id and d.id_karyawan = g.id_karyawan
  where g.versi_id = (select versi from ini) and g.gaji_bersih > 0
    and not exists (select 1 from hitung.hasil_harian h
                    where h.versi_id = (select versi_sumber from ini) and h.id_karyawan = g.id_karyawan and h.asal = 'mesin')
$$;

create or replace function hitung.hitung_gaji(p_periode bigint) returns bigint
language plpgsql set search_path = '' set jit = off set client_min_messages = warning as $$
declare
  c_versi_kode constant text := hitung.versi_kode_gaji();
  -- Angka tetap (dicatat di laporan paket 4b-1):
  c_telat_maks_uang_makan constant integer := 60;  -- syarat uang makan Pabrik A
  c_istirahat_libur constant integer := 60;        -- lembur hari libur tanpa jadwal, bila hadir > 240 menit
  c_batas_hari constant integer := 240;            -- UU 27/2026 Pasal 116 ayat 1c
  c_batas_minggu constant integer := 1080;
  c_mulai_uu27 constant date := '2026-10-28';
  v_awal date;
  v_akhir date;
  v_bayar date;
  v_sumber bigint;
  v_versi bigint;
  v_nomor integer;
  v_batas_hari_pola integer;
  v_pembagi integer;
  v_mulai timestamptz := clock_timestamp();
  v_sidik_masukan text;
  v_sidik_hasil text;
  v_sebelum bigint;   -- versi gaji terakhir periode sebelumnya (sisa pembulatan)
  c_mulai_uu27_cuti constant date := '2026-10-28';  -- UU 27/2026 Pasal 118 ayat 6
begin
  select tanggal_awal, tanggal_akhir, tanggal_bayar into v_awal, v_akhir, v_bayar from fakta.periode where id = p_periode;
  if not found then
    raise exception 'Periode % tidak ada', p_periode using errcode = 'P0001';
  end if;
  select id into v_sumber from hitung.versi_terakhir where periode_id = p_periode and jenis = 'baca_tap';
  if v_sumber is null then
    raise exception 'Periode % belum punya hasil baca tap', p_periode using errcode = 'P0001';
  end if;
  if (select count(*) from aturan.upah_minimum u where daterange(u.berlaku_dari, u.berlaku_sampai, '[)') @> v_bayar) <> 1 then
    raise exception 'Upah minimum pada % harus tepat satu wilayah', v_bayar using errcode = 'P0001';
  end if;

  -- B1: pembagi = hari pola kerja perusahaan dalam periode.
  v_batas_hari_pola := case when aturan.pengaturan_pada('pola_hari_kerja', null, v_akhir) = '5_hari' then 5 else 6 end;
  select count(*) into v_pembagi
  from generate_series(v_awal::timestamp, v_akhir::timestamp, interval '1 day') d
  where extract(isodow from d) <= v_batas_hari_pola;

  -- J1: periode sebelumnya = tanggal akhir terbesar sebelum tanggal awal periode ini.
  select v.id into v_sebelum
  from fakta.periode p join hitung.versi_terakhir v on v.periode_id = p.id and v.jenis = 'hitung_gaji'
  where p.tanggal_akhir < v_awal order by p.tanggal_akhir desc limit 1;
  select encode(sha256(convert_to(concat_ws('|', v_sumber,
           (select max(id) from fakta.perintah_hrd), (select max(id) from jejak.perubahan), (select max(id) from fakta.buku_kasbon),
           (select string_agg(v.id::text, ',' order by v.id) from hitung.versi_terakhir v join fakta.periode p on p.id = v.periode_id
            where v.jenis = 'hitung_gaji' and p.tanggal_akhir < v_awal), c_versi_kode), 'UTF8')), 'hex')
  into v_sidik_masukan;
  select coalesce(max(nomor), 0) + 1 into v_nomor from hitung.versi_hitung where periode_id = p_periode and jenis = 'hitung_gaji';
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, versi_sumber)
  values (p_periode, 'hitung_gaji', v_nomor, c_versi_kode, v_sidik_masukan, v_sumber)
  returning id into v_versi;

  -- Perintah HRD yang berlaku (tidak dibatalkan).
  drop table if exists _perintah;
  create temp table _perintah on commit drop as
  select p.jenis, p.id_karyawan, p.divisi, p.tanggal_mulai, coalesce(p.tanggal_selesai, p.tanggal_mulai) as tanggal_selesai
  from fakta.perintah_hrd p
  where p.jenis in ('setujui_lembur', 'batalkan_lembur') and p.tanggal_mulai is not null
    and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = p.id);

  -- Hari per orang dengan upah dan pengaturan yang berlaku pada tanggal itu.
  drop table if exists _hari;
  create temp table _hari on commit drop as
  select h.*, r.gaji_pokok, r.tunjangan_tetap,
         extract(isodow from h.tanggal)::integer <= v_batas_hari_pola as hari_pola,
         aturan.pengaturan_pada('izin_dibayar', h.divisi, h.tanggal) as izin_dibayar,
         aturan.pengaturan_pada('uang_makan', h.divisi, h.tanggal) as atur_makan,
         aturan.pengaturan_pada('tunjangan_shift_malam', h.divisi, h.tanggal) as atur_shift,
         aturan.pengaturan_pada('lembur', h.divisi, h.tanggal) as atur_lembur,
         aturan.pengaturan_pada('pola_hari_kerja', h.divisi, h.tanggal) as pola_divisi,
         aturan.pengaturan_pada('cuti_bersama', h.divisi, h.tanggal) as atur_cuti_bersama,
         k.jam_pulang <= k.jam_masuk as shift_malam
  from hitung.hasil_harian h
  join induk.karyawan_riwayat r on r.id_karyawan = h.id_karyawan
   and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> h.tanggal
  left join induk.kode_jadwal k on k.kode = h.kode_jadwal
  where h.versi_id = v_sumber;
  if (select count(*) from _hari) <> (select count(*) from hitung.hasil_harian where versi_id = v_sumber) then
    raise exception 'Ada hari kerja tanpa data gaji karyawan yang berlaku' using errcode = 'P0001';
  end if;
  create index on _hari (id_karyawan, tanggal);
  analyze _hari;

  -- B4, C1, C2, D1-D7 per hari.
  alter table _hari add column tidak_dibayar boolean not null default false, add column makan bigint not null default 0,
    add column shift bigint not null default 0, add column menit_lembur integer, add column jenis_lembur text,
    add column menit_bayar integer not null default 0, add column boleh boolean not null default false,
    add column satuan bigint not null default 0, add column tanda_gaji text[] not null default '{}';
  update _hari set tidak_dibayar = (status = 'alpha' or (status = 'izin' and izin_dibayar = 'tidak'))
                                   and jenis_hari in ('kerja', 'cuti_bersama'),
    tanda_gaji = case when status = 'alpha' and jenis_hari = 'libur_nasional' then array['alpha_di_hari_libur_tidak_dipotong']
                 when status in ('menunggu', 'tanpa_tap_massal') then array['belum_pasti']
                 else '{}'::text[] end;
  update _hari set makan = coalesce((select k.nominal from aturan.komponen_lain k
                            where k.kode = 'uang_makan' and k.cakupan = 'perusahaan'
                              and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> _hari.tanggal), 0)
  where status = 'hadir' and atur_makan = 'dihitung' and menit_telat <= c_telat_maks_uang_makan;
  update _hari set shift = coalesce((select k.nominal from aturan.komponen_lain k
                            where k.kode = 'tunjangan_shift_malam' and k.cakupan = 'perusahaan'
                              and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> _hari.tanggal), 0)
  where status = 'hadir' and atur_shift = 'hidup' and shift_malam;

  update _hari set menit_lembur = menit_lebih, jenis_lembur = 'kerja'
  where status = 'hadir' and jenis_hari in ('kerja', 'cuti_bersama');
  update _hari set menit_lembur = case when menit_hadir > c_batas_hari then menit_hadir - c_istirahat_libur else menit_hadir end,
                   jenis_lembur = 'libur'
  where status = 'lembur_hari_libur' and pulang is not null;
  update _hari set tanda_gaji = array_append(tanda_gaji, 'lembur_hari_libur_tanpa_tap_pulang')
  where status = 'lembur_hari_libur' and pulang is null;
  update _hari set menit_lembur = greatest(hitung.lama_kerja(kode_jadwal) - menit_telat - menit_pulang_cepat
                                           + case when lupa_tap is null then menit_lebih else 0 end, 0),
                   jenis_lembur = 'libur',
                   tanda_gaji = case when lupa_tap is not null then array_append(tanda_gaji, 'lembur_libur_lupa_tap') else tanda_gaji end
  where status = 'hadir' and jenis_hari = 'libur_nasional' and kode_jadwal is not null;
  update _hari set jenis_lembur = case when pola_divisi = '5_hari' then 'libur_5_hari'
                                       when hitung.hari_terpendek(divisi, regu, tanggal) then 'libur_6_hari_terpendek'
                                       else 'libur_6_hari' end
  where jenis_lembur = 'libur';
  update _hari set menit_bayar = hitung.menit_lembur_dibayar(menit_lembur, tanggal)
  where menit_lembur is not null;
  update _hari set boleh = case when atur_lembur = 'wajib_perintah'
                                then exists (select 1 from _perintah p where p.jenis = 'setujui_lembur'
                                               and _hari.tanggal between p.tanggal_mulai and p.tanggal_selesai
                                               and (p.id_karyawan = _hari.id_karyawan
                                                    or (p.id_karyawan is null and p.divisi = _hari.divisi)))
                                else not exists (select 1 from _perintah p where p.jenis = 'batalkan_lembur'
                                                   and _hari.tanggal between p.tanggal_mulai and p.tanggal_selesai
                                                   and (p.id_karyawan = _hari.id_karyawan
                                                        or (p.id_karyawan is null and p.divisi = _hari.divisi))) end
  where menit_bayar > 0;
  update _hari set satuan = hitung.satuan_lembur(jenis_lembur, menit_bayar, tanggal),
                   tanda_gaji = tanda_gaji
                     || case when menit_bayar < menit_lembur then array['pembulatan_lembur_ke_bawah'] else '{}'::text[] end
                     || case when hitung.lewat_tabel_lembur(jenis_lembur, menit_bayar, tanggal)
                             then array['lembur_lewat_tabel'] else '{}'::text[] end
                     || case when jenis_lembur = 'kerja' and menit_bayar > c_batas_hari then array['lembur_lewat_4_jam'] else '{}'::text[] end
                     || case when jenis_lembur = 'kerja' and menit_bayar >= c_batas_hari then array['wajib_makan'] else '{}'::text[] end
  where menit_bayar > 0 and boleh;
  update _hari set tanda_gaji = array_append(tanda_gaji, 'lembur_tidak_dibayar_tanpa_izin') where menit_bayar > 0 and not boleh;
  -- M1: cuti bersama yang memotong cuti hanya sebelum 28 Okt 2026.
  update _hari set tanda_gaji = array_append(tanda_gaji, 'potong_cuti_tidak_berlaku_uu27')
  where status = 'libur' and jenis_hari = 'cuti_bersama' and atur_cuti_bersama = 'potong_cuti' and tanggal >= c_mulai_uu27_cuti;

  -- Per orang.
  drop table if exists _orang;
  create temp table _orang on commit drop as
  select h.id_karyawan,
         (array_agg(h.divisi order by h.tanggal desc))[1] as divisi_akhir,
         max(h.tanggal) as hari_akhir,
         (sum(h.gaji_pokok) filter (where h.hari_pola))::bigint as sum_pokok,
         coalesce(sum(h.tunjangan_tetap) filter (where h.hari_pola), 0)::bigint as sum_tetap,
         count(*) filter (where h.hari_pola) as hari_aktif,
         coalesce(sum(h.gaji_pokok + h.tunjangan_tetap) filter (where h.tidak_dibayar), 0)::bigint as sum_tidak_dibayar,
         count(*) filter (where h.tidak_dibayar) as hari_tidak_dibayar,
         count(*) filter (where h.tidak_dibayar and h.status = 'alpha') as hari_alpha,
         count(*) filter (where h.tidak_dibayar and h.status = 'izin') as hari_izin,
         sum(h.makan)::bigint as makan, count(*) filter (where h.makan > 0) as hari_makan,
         sum(h.shift)::bigint as shift, count(*) filter (where h.shift > 0) as hari_shift,
         bool_or(h.status = 'alpha') or bool_or(h.menit_telat > 0) as premi_hangus,
         (count(*) filter (where h.status = 'cuti')
          + count(*) filter (where h.status = 'libur' and h.jenis_hari = 'cuti_bersama' and h.atur_cuti_bersama = 'potong_cuti'
                               and h.tanggal < c_mulai_uu27_cuti))::integer as cuti_terpakai,
         bool_or(h.boleh and h.menit_bayar > 0 and h.tanggal >= c_mulai_uu27) as lembur_sesudah_uu27,
         (select array_agg(distinct t) from _hari h2, unnest(h2.tanda_gaji) t where h2.id_karyawan = h.id_karyawan) as tanda_hari
  from _hari h
  group by h.id_karyawan;
  alter table _orang add column pokok bigint, add column tetap bigint, add column ptkp text, add column ikut_kes boolean,
    add column ikut_tk boolean, add column mulai date, add column premi bigint not null default 0, add column dasar bigint,
    add column lembur bigint not null default 0, add column menit_lembur_bayar bigint not null default 0,
    add column lewat_minggu boolean not null default false, add column menit_libur_bayar bigint not null default 0,
    add column cara_bayar text, add column thr bigint not null default 0, add column thr_bukti text,
    add column denda_minta bigint not null default 0, add column kasbon_saldo bigint not null default 0,
    add column kasbon_minta bigint not null default 0, add column batas bigint, add column denda bigint not null default 0,
    add column kasbon bigint not null default 0;
  update _orang o set pokok = r.gaji_pokok, tetap = r.tunjangan_tetap, ikut_kes = r.bpjs_kesehatan, ikut_tk = r.bpjs_ketenagakerjaan,
                      cara_bayar = r.cara_bayar
  from induk.karyawan_riwayat r
  where r.id_karyawan = o.id_karyawan
    and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> (case when exists (
          select 1 from induk.karyawan_riwayat r2 where r2.id_karyawan = o.id_karyawan
            and daterange(r2.berlaku_dari, r2.berlaku_sampai, '[)') @> v_akhir) then v_akhir else o.hari_akhir end);
  update _orang o set mulai = (select min(s.tanggal) from induk.status_kerja s where s.id_karyawan = o.id_karyawan and s.jenis = 'mulai');
  update _orang o set ptkp = coalesce(
    (select r.ptkp from induk.karyawan_riwayat r where r.id_karyawan = o.id_karyawan
       and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> greatest(make_date(extract(year from v_bayar)::integer, 1, 1),
                                                                        coalesce(o.mulai, make_date(extract(year from v_bayar)::integer, 1, 1)))),
    (select r.ptkp from induk.karyawan_riwayat r where r.id_karyawan = o.id_karyawan
       and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> o.hari_akhir));
  update _orang o set premi = (select k.nominal from aturan.komponen_lain k
                               where k.kode = 'premi_hadir' and k.cakupan = 'perusahaan'
                                 and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> v_akhir)
  where aturan.pengaturan_pada('premi_hadir', o.divisi_akhir, v_akhir) = 'hidup' and not o.premi_hangus;
  update _orang set premi = 0 where premi is null;
  update _orang set dasar = hitung.dasar_lembur(pokok + tetap, makan + shift + premi);
  update _orang o set lembur = x.rupiah, menit_lembur_bayar = x.menit, menit_libur_bayar = x.menit_libur
  from (select h.id_karyawan, sum(hitung.rupiah_lembur(h.satuan, o2.dasar)) as rupiah, sum(h.menit_bayar) as menit,
               coalesce(sum(h.menit_bayar) filter (where h.jenis_lembur <> 'kerja'), 0) as menit_libur
        from _hari h join _orang o2 on o2.id_karyawan = h.id_karyawan
        where h.boleh and h.menit_bayar > 0 group by h.id_karyawan) x
  where x.id_karyawan = o.id_karyawan;
  update _orang o set lewat_minggu = true
  where exists (select 1 from _hari h where h.id_karyawan = o.id_karyawan and h.boleh and h.jenis_lembur = 'kerja'
                group by date_trunc('week', h.tanggal) having sum(h.menit_bayar) > c_batas_minggu);

  -- H. THR: aturan THR yang tanggal bayarnya di dalam periode; penerima = aktif pada tanggal bayar THR.
  update _orang o set thr = x.thr, thr_bukti = x.bukti
  from (select h.id_karyawan,
               sum(case when t.cara_prorata = 'hari'
                        then case when t.hari_raya - o2.mulai >= 30
                                  then hitung.bulat((r.gaji_pokok + r.tunjangan_tetap) * least(t.hari_raya - o2.mulai, 365)::numeric, 365)
                                  else 0 end
                        else case when b.bulan >= 1
                                  then hitung.bulat((r.gaji_pokok + r.tunjangan_tetap) * least(b.bulan, 12)::numeric, 12)
                                  else 0 end end)::bigint as thr,
               string_agg(format('THR hari raya %s: masa kerja %s bulan, upah Rp%s', t.hari_raya, b.bulan,
                                 r.gaji_pokok + r.tunjangan_tetap), '; ') as bukti
        from aturan.thr t
        join _hari h on h.tanggal = t.tanggal_bayar
        join _orang o2 on o2.id_karyawan = h.id_karyawan
        join induk.karyawan_riwayat r on r.id_karyawan = h.id_karyawan
         and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> t.tanggal_bayar
        cross join lateral (select (extract(year from age(t.hari_raya, o2.mulai)) * 12
                                    + extract(month from age(t.hari_raya, o2.mulai)))::integer as bulan) b
        where t.tanggal_bayar between v_awal and v_akhir
        group by h.id_karyawan) x
  where x.id_karyawan = o.id_karyawan;

  -- I1. Denda dari tingkat denda yang berlaku (setiap baris wajib punya dasar pasal).
  update _orang o set denda_minta = x.nominal
  from (select h.id_karyawan, sum(d.nominal)::bigint as nominal
        from _hari h
        join aturan.tingkat_denda d on d.cakupan = 'perusahaan' and daterange(d.berlaku_dari, d.berlaku_sampai, '[)') @> h.tanggal
         and case d.jenis
               when 'telat' then h.menit_telat > 0 and int4range(d.dari_menit, d.sampai_menit, '[)') @> h.menit_telat
               when 'pulang_cepat' then h.menit_pulang_cepat > 0 and int4range(d.dari_menit, d.sampai_menit, '[)') @> h.menit_pulang_cepat
               when 'lupa_tap' then h.lupa_tap is not null
               when 'alpha' then h.status = 'alpha' end
        group by h.id_karyawan) x
  where x.id_karyawan = o.id_karyawan;

  -- I2. Saldo kasbon sebelum periode ini dan yang diminta dipotong.
  update _orang o set kasbon_saldo = x.saldo, kasbon_minta = least(coalesce(x.cicilan, x.saldo), x.saldo)
  from (select k.id_karyawan,
               (coalesce(sum(k.jumlah) filter (where k.jenis = 'pinjam'), 0)
                - coalesce(sum(k.jumlah) filter (where k.jenis = 'pelunasan'), 0)
                + coalesce((select sum(r.nominal) from hitung.rincian_gaji r
                            join hitung.versi_terakhir v on v.id = r.versi_id and v.jenis = 'hitung_gaji'
                            join fakta.periode p on p.id = v.periode_id and p.tanggal_akhir < v_awal
                            where r.id_karyawan = k.id_karyawan and r.komponen = 'kasbon'), 0))::bigint as saldo,
               (select k2.jumlah from fakta.buku_kasbon k2
                where k2.id_karyawan = k.id_karyawan and k2.jenis = 'cicilan' and (k2.dibuat at time zone 'Asia/Jakarta')::date <= v_akhir
                order by k2.id desc limit 1) as cicilan
        from fakta.buku_kasbon k
        where (k.dibuat at time zone 'Asia/Jakarta')::date <= v_akhir
        group by k.id_karyawan) x
  where x.id_karyawan = o.id_karyawan and x.saldo > 0;

  -- I3-I4. Batas potongan dari pendapatan tanpa THR; denda dulu, lalu kasbon.
  update _orang o set batas = case when bp.persen is null then x.dasar else x.dasar * bp.persen / 10000 end
  from (select o2.id_karyawan,
               greatest(0, hitung.bulat(o2.sum_pokok, v_pembagi) + hitung.bulat(o2.sum_tetap, v_pembagi)
                           - hitung.bulat(o2.sum_tidak_dibayar, v_pembagi) + o2.makan + o2.shift + o2.premi + o2.lembur) as dasar
        from _orang o2) x
  left join aturan.batas_potongan bp on daterange(bp.berlaku_dari, bp.berlaku_sampai, '[)') @> v_akhir
  where x.id_karyawan = o.id_karyawan;
  update _orang set denda = least(denda_minta, batas);
  update _orang set kasbon = greatest(0, least(kasbon_minta, batas - denda));

  -- Rincian.
  drop table if exists _rincian;
  create temp table _rincian (id_karyawan text, komponen text, kelompok text, nominal bigint, bukti text) on commit drop;
  insert into _rincian
  select o.id_karyawan, 'gaji_pokok', 'pendapatan', hitung.bulat(o.sum_pokok, v_pembagi),
         case when o.hari_aktif = v_pembagi and o.sum_pokok = o.pokok * v_pembagi then format('Gaji pokok Rp%s sebulan penuh', o.pokok)
              else format('Gaji pokok %s dari %s hari kerja periode (prorata menurut tanggal berlaku)', o.hari_aktif, v_pembagi) end
  from _orang o
  union all
  select o.id_karyawan, 'tunjangan_tetap', 'pendapatan', hitung.bulat(o.sum_tetap, v_pembagi),
         format('Tunjangan tetap %s dari %s hari kerja periode', o.hari_aktif, v_pembagi)
  from _orang o where o.sum_tetap > 0
  union all
  select o.id_karyawan, 'potongan_tidak_dibayar', 'pendapatan', -hitung.bulat(o.sum_tidak_dibayar, v_pembagi),
         format('%s hari tidak dibayar (alpha %s, izin %s) x (gaji pokok + tunjangan tetap) / %s hari', o.hari_tidak_dibayar,
                o.hari_alpha, o.hari_izin, v_pembagi)
  from _orang o where o.hari_tidak_dibayar > 0
  union all
  select o.id_karyawan, 'uang_makan', 'pendapatan', o.makan, format('Uang makan %s hari hadir', o.hari_makan)
  from _orang o where o.makan > 0
  union all
  select o.id_karyawan, 'tunjangan_shift_malam', 'pendapatan', o.shift, format('Tunjangan shift malam %s hari', o.hari_shift)
  from _orang o where o.shift > 0
  union all
  select o.id_karyawan, 'premi_hadir', 'pendapatan', o.premi, 'Premi hadir: tanpa alpha dan tanpa telat'
  from _orang o where o.premi > 0
  union all
  select o.id_karyawan, 'lembur', 'pendapatan', o.lembur,
         format('Lembur %s menit dibayar (di hari libur %s menit); dasar upah Rp%s / 173 per jam', o.menit_lembur_bayar,
                o.menit_libur_bayar, o.dasar)
  from _orang o where o.lembur > 0
  union all
  select o.id_karyawan, 'thr', 'pendapatan', o.thr, o.thr_bukti
  from _orang o where o.thr > 0
  union all
  select o.id_karyawan, 'denda', 'potongan', -o.denda,
         format('Denda Rp%s%s (batas potongan Rp%s)', o.denda_minta,
                case when o.denda < o.denda_minta then format(', dipotong Rp%s; kelebihan hangus', o.denda) else '' end, o.batas)
  from _orang o where o.denda > 0
  union all
  select o.id_karyawan, 'kasbon', 'potongan', -o.kasbon,
         format('Kasbon: saldo Rp%s, diminta Rp%s, dipotong Rp%s (batas potongan Rp%s, sesudah denda); sisa saldo Rp%s',
                o.kasbon_saldo, o.kasbon_minta, o.kasbon, o.batas, o.kasbon_saldo - o.kasbon)
  from _orang o where o.kasbon > 0;

  insert into _rincian
  select o.id_karyawan, 'bpjs_' || b.program || '_' || b.bagian,
         case when b.bagian = 'karyawan' then 'potongan' else 'perusahaan' end,
         case when b.bagian = 'karyawan' then -1 else 1 end * hitung.iuran_bpjs(b.program, b.bagian, o.pokok + o.tetap, v_bayar),
         format('%s%% x upah Rp%s (batas berlaku %s)', trim_scale(b.persen / 100.0), o.pokok + o.tetap, v_bayar)
  from _orang o
  join aturan.bpjs b on daterange(b.berlaku_dari, b.berlaku_sampai, '[)') @> v_bayar
  where case when b.program = 'kesehatan' then o.ikut_kes else o.ikut_tk end;

  -- PPh 21: TER (F1-F4), atau hitung ulang setahun di masa terakhir (L1-L6, versi 5: per orang, dengan isian awal tahun).
  drop table if exists _pajak;
  create temp table _pajak on commit drop as
  select o.id_karyawan, o.ptkp,
         coalesce((select sum(r.nominal) from _rincian r where r.id_karyawan = o.id_karyawan
                     and (r.kelompok = 'pendapatan'
                          or r.komponen in ('bpjs_jkk_perusahaan', 'bpjs_jkm_perusahaan', 'bpjs_kesehatan_perusahaan'))), 0)::bigint as bruto,
         coalesce((select -sum(r.nominal) from _rincian r where r.id_karyawan = o.id_karyawan
                     and r.komponen in ('bpjs_jht_karyawan', 'bpjs_jp_karyawan')), 0)::bigint as iuran,
         (extract(month from v_bayar) = 12
          or exists (select 1 from induk.status_kerja s where s.id_karyawan = o.id_karyawan and s.jenis = 'berhenti'
                       and s.tanggal between v_awal and v_akhir)) as terakhir,
         coalesce(i.sampai_bulan, 0) as batas, coalesce(i.bulan_kerja, 0) as isi_n, coalesce(i.bruto, 0) as isi_bruto,
         coalesce(i.iuran, 0) as isi_iuran, coalesce(i.pph, 0) as isi_pph, false as lengkap,
         0::bigint as prev_bruto, 0::bigint as prev_iuran, 0::bigint as prev_pph, 0 as prev_n,
         0::bigint as setahun, 0::bigint as pph, 0::bigint as kembali
  from _orang o
  left join induk.pajak_awal_tahun i on i.id_karyawan = o.id_karyawan and i.tahun = extract(year from v_bayar)::integer;
  -- L2: setiap bulan sebelum bulan bayar tercakup isian, atau ada periode bergaji yang dibayar di bulan itu.
  update _pajak k set lengkap = not exists (
    select 1 from generate_series(k.batas + 1, extract(month from v_bayar)::integer - 1) m
    where not exists (select 1 from fakta.periode p join hitung.versi_terakhir v on v.periode_id = p.id and v.jenis = 'hitung_gaji'
                      where extract(year from p.tanggal_bayar) = extract(year from v_bayar)
                        and extract(month from p.tanggal_bayar) = m))
  where k.terakhir;
  -- L3: isian ditambah periode sistem yang dibayar sesudah bulan terakhir isian.
  update _pajak k set (prev_bruto, prev_iuran, prev_pph, prev_n) = (
    select k.isi_bruto + coalesce(sum(g.bruto_pajak), 0)::bigint, k.isi_iuran + coalesce(sum(z.iuran), 0)::bigint,
           k.isi_pph + coalesce(sum(z.pph), 0)::bigint, k.isi_n + count(g.*)::integer
    from hitung.ringkasan_gaji g
    join hitung.versi_terakhir v on v.id = g.versi_id and v.jenis = 'hitung_gaji'
    join fakta.periode p on p.id = v.periode_id
    cross join lateral (
      select coalesce(-sum(r.nominal) filter (where r.komponen in ('bpjs_jht_karyawan', 'bpjs_jp_karyawan')), 0) as iuran,
             coalesce(-sum(r.nominal) filter (where r.komponen = 'pph21'), 0)
             - coalesce(sum(r.nominal) filter (where r.komponen = 'pengembalian_pph21'), 0) as pph
      from hitung.rincian_gaji r where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan) z
    where g.id_karyawan = k.id_karyawan
      and extract(year from p.tanggal_bayar) = extract(year from v_bayar) and p.tanggal_bayar < v_bayar and p.id <> p_periode
      and extract(month from p.tanggal_bayar) > k.batas)
  where k.terakhir and k.lengkap;
  update _pajak set setahun = hitung.pph21_setahun(prev_bruto + bruto, prev_iuran + iuran, ptkp, prev_n + 1, v_bayar)
  where terakhir and lengkap;
  update _pajak set pph = case when not terakhir then coalesce(hitung.pph21_ter(bruto, ptkp, v_bayar), 0)
                               when not lengkap then 0
                               else greatest(0, setahun - prev_pph) end,
                    kembali = case when terakhir and lengkap then greatest(0, prev_pph - setahun) else 0 end;
  insert into _rincian
  select k.id_karyawan, 'pph21', 'potongan', -k.pph,
         case when not k.terakhir then format('TER %s x bruto pajak Rp%s', k.ptkp, k.bruto)
              when not k.lengkap then 'PPh masa terakhir belum dihitung: data gaji setahun belum lengkap'
              else format('Masa terakhir: bruto setahun Rp%s (%s bulan), iuran JHT+JP Rp%s, %s, PPh setahun Rp%s, sudah dipotong Rp%s',
                          k.prev_bruto + k.bruto, k.prev_n + 1, k.prev_iuran + k.iuran, k.ptkp, k.setahun, k.prev_pph) end
  from _pajak k
  union all
  select k.id_karyawan, 'pengembalian_pph21', 'pendapatan', k.kembali,
         format('Kelebihan PPh dikembalikan: sudah dipotong Rp%s, PPh setahun Rp%s', k.prev_pph, k.setahun)
  from _pajak k where k.kembali > 0;

  insert into hitung.rincian_gaji (versi_id, id_karyawan, komponen, kelompok, nominal, bukti)
  select v_versi, id_karyawan, komponen, kelompok, nominal, bukti from _rincian;

  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih,
                                     sisa_lalu, dibayar, sisa_pembulatan, cuti_terpakai, saldo_cuti, peringatan)
  select v_versi, o.id_karyawan, s.bruto, s.pendapatan, s.potongan, s.pendapatan + s.potongan, l.sisa,
         case when s.pendapatan + s.potongan + l.sisa < 0 then 0
              when o.cara_bayar = 'tunai' then (s.pendapatan + s.potongan + l.sisa)::bigint / l.kel * l.kel
              else s.pendapatan + s.potongan + l.sisa end,
         case when s.pendapatan + s.potongan + l.sisa < 0 then s.pendapatan + s.potongan + l.sisa
              when o.cara_bayar = 'tunai' then (s.pendapatan + s.potongan + l.sisa)::bigint % l.kel
              else 0 end,
         o.cuti_terpakai, c.saldo,
         array(select distinct t from unnest(
           coalesce(o.tanda_hari, '{}')
           || case when o.mulai > v_akhir - interval '12 months' and o.pokok + o.tetap < (
                     select u.nilai from aturan.upah_minimum u where daterange(u.berlaku_dari, u.berlaku_sampai, '[)') @> v_akhir)
                   then array['di_bawah_umk'] else '{}'::text[] end
           || case when o.pokok * 10000 < 7500 * (o.pokok + o.tetap) then array['pokok_di_bawah_75'] else '{}'::text[] end
           || case when o.dasar <> o.pokok + o.tetap and o.lembur_sesudah_uu27
                   then array['dasar_lembur_75_perlu_konfirmasi_hrd'] else '{}'::text[] end
           || case when o.lewat_minggu then array['lembur_lewat_18_jam'] else '{}'::text[] end
           || case when exists (select 1 from _pajak k where k.id_karyawan = o.id_karyawan and k.terakhir and not k.lengkap)
                   then array['pph_masa_terakhir_tertahan'] else '{}'::text[] end
           || case when s.pendapatan + s.potongan < 0 then array['gaji_bersih_negatif'] else '{}'::text[] end
           || case when o.denda < o.denda_minta then array['denda_melewati_batas_potongan'] else '{}'::text[] end
           || case when o.kasbon < o.kasbon_minta then array['kasbon_tidak_terpotong_penuh'] else '{}'::text[] end
         ) t order by t)
  from _orang o
  cross join lateral (select coalesce((select g.sisa_pembulatan from hitung.ringkasan_gaji g
                                       where g.versi_id = v_sebelum and g.id_karyawan = o.id_karyawan), 0) as sisa,
                             aturan.pengaturan_pada('pembulatan_tunai', null, v_akhir)::bigint as kel) l
  -- M2-M3: saldo cuti dari saldo awal, bila periode dari tanggal saldo awal sampai periode ini bersambung.
  cross join lateral (
    select case when a.tanggal is null then null
                when not (select min(p.tanggal_awal) = a.tanggal
                                 and bool_and(p.sebelum is null or p.tanggal_awal = p.sebelum + 1)
                          from (select p2.tanggal_awal, lag(p2.tanggal_akhir) over (order by p2.tanggal_awal) as sebelum
                                from fakta.periode p2 where p2.tanggal_awal between a.tanggal and v_awal) p) then null
                else a.hari
                     + cu.jatah_hari * (select count(*) from generate_series(0, 100) n
                                        where (o.mulai + make_interval(months => cu.berlaku_setelah_bulan + 12 * n))::date > a.tanggal
                                          and (o.mulai + make_interval(months => cu.berlaku_setelah_bulan + 12 * n))::date <= v_akhir)
                     - o.cuti_terpakai
                     - coalesce((select sum(g.cuti_terpakai) from hitung.ringkasan_gaji g
                                 join hitung.versi_terakhir v on v.id = g.versi_id and v.jenis = 'hitung_gaji'
                                 join fakta.periode p on p.id = v.periode_id
                                 where g.id_karyawan = o.id_karyawan and p.tanggal_awal >= a.tanggal and p.tanggal_awal < v_awal), 0)
           end::integer as saldo
    from (select null::date as tanggal, null::integer as hari) kosong
    left join lateral (select s.tanggal, s.hari from induk.saldo_cuti_awal s
                       where s.id_karyawan = o.id_karyawan and s.tanggal <= v_awal order by s.tanggal desc limit 1) a on true
    left join aturan.cuti cu on cu.cakupan = 'perusahaan' and daterange(cu.berlaku_dari, cu.berlaku_sampai, '[)') @> v_akhir) c
  join (select r.id_karyawan,
               sum(r.nominal) filter (where r.kelompok = 'pendapatan') as pendapatan,
               coalesce(sum(r.nominal) filter (where r.kelompok = 'potongan'), 0) as potongan,
               sum(r.nominal) filter (where (r.kelompok = 'pendapatan' and r.komponen <> 'pengembalian_pph21')
                                      or r.komponen in ('bpjs_jkk_perusahaan', 'bpjs_jkm_perusahaan', 'bpjs_kesehatan_perusahaan')) as bruto
        from _rincian r group by r.id_karyawan) s on s.id_karyawan = o.id_karyawan;

  select encode(sha256(convert_to(coalesce(string_agg(concat_ws('|', r.id_karyawan, r.komponen, r.kelompok, r.nominal, r.bukti),
                                                      E'\n' order by r.id_karyawan, r.komponen), '')
                                  || coalesce((select string_agg(concat_ws('|', g.id_karyawan, g.bruto_pajak, g.gaji_bersih,
                                                                           g.sisa_lalu, g.dibayar, g.sisa_pembulatan,
                                                                           g.cuti_terpakai, g.saldo_cuti,
                                                                           array_to_string(g.peringatan, ',')),
                                                                 E'\n' order by g.id_karyawan)
                                               from hitung.ringkasan_gaji g where g.versi_id = v_versi), ''), 'UTF8')), 'hex')
  into v_sidik_hasil
  from hitung.rincian_gaji r where r.versi_id = v_versi;

  update hitung.versi_hitung
  set sidik_hasil = v_sidik_hasil, lama_ms = (extract(epoch from clock_timestamp() - v_mulai) * 1000)::integer
  where id = v_versi;
  return v_versi;
end $$;
