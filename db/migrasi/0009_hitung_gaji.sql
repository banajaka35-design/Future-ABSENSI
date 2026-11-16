-- 0009_hitung_gaji.sql
-- Paket 4b-1: mesin hitung gaji Pabrik A (tanpa THR, kasbon, denda, pembulatan tunai, saldo cuti, PPh Desember).
-- Aturan yang diikuti: docs/aturan-hitung-gaji.md (ditulis sebelum file ini). Dasar hukum: docs/cek-aturan-hukum.md.
-- Migrasi hanya maju; file ini tidak boleh diedit setelah dipasang.

-- ---------------------------------------------------------------------------
-- Pengaturan baru (isian, bukan kode)
-- ---------------------------------------------------------------------------
insert into aturan.daftar_pengaturan (kunci, nilai_boleh, bawaan, keterangan) values
  ('izin_dibayar', array['ya', 'tidak'], 'tidak',
   'Izin di luar alasan UU 27/2026 Pasal 149 ayat 2 dibayar atau tidak'),
  ('pembulatan_pph21', array['bawah', 'terdekat'], 'bawah',
   'Pembulatan nominal PPh 21 TER ke rupiah (aturan pembulatan resmi belum ditemukan)');

-- ---------------------------------------------------------------------------
-- Tabel hasil
-- ---------------------------------------------------------------------------
alter table hitung.versi_hitung drop constraint versi_hitung_jenis_check;
alter table hitung.versi_hitung add constraint versi_hitung_jenis_check check (jenis in ('baca_tap', 'hitung_gaji'));
alter table hitung.versi_hitung add column versi_sumber bigint references hitung.versi_hitung (id);
-- Tampilan versi terakhir dibuat ulang supaya kolom baru ikut (kolom tampilan dibekukan saat dibuat).
create or replace view hitung.versi_terakhir as
  select distinct on (periode_id, jenis) *
  from hitung.versi_hitung
  where sidik_hasil is not null
  order by periode_id, jenis, nomor desc;

create table hitung.rincian_gaji (
  versi_id bigint not null references hitung.versi_hitung (id),
  id_karyawan text not null,
  komponen text not null,
  kelompok text not null check (kelompok in ('pendapatan', 'potongan', 'perusahaan')),
  nominal bigint not null,
  bukti text not null,
  primary key (versi_id, id_karyawan, komponen),
  check (kelompok <> 'potongan' or nominal <= 0),
  check (kelompok <> 'perusahaan' or nominal >= 0)
);

create table hitung.ringkasan_gaji (
  versi_id bigint not null references hitung.versi_hitung (id),
  id_karyawan text not null,
  bruto_pajak bigint not null,
  total_pendapatan bigint not null,
  total_potongan bigint not null,
  gaji_bersih bigint not null,
  dibayar bigint not null,
  sisa_pembulatan bigint not null default 0,
  peringatan text[] not null default '{}',
  primary key (versi_id, id_karyawan),
  check (gaji_bersih = total_pendapatan + total_potongan)
);

do $$
declare
  t text;
begin
  foreach t in array array['hitung.rincian_gaji', 'hitung.ringkasan_gaji'] loop
    execute format('create trigger tolak_ubah before update or delete on %s for each row execute function jejak.tolak_ubah()', t);
    execute format('create trigger tolak_kosongkan before truncate on %s for each statement execute function jejak.tolak_ubah()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Fungsi bagian (dipakai hitung_gaji dan diuji langsung)
-- ---------------------------------------------------------------------------

-- Setengah ke atas ke rupiah terdekat untuk pecahan positif (kontrak data bagian 7).
create function hitung.bulat(p_pembilang numeric, p_penyebut numeric default 1) returns bigint
language sql immutable set search_path = '' as $$
  select round(p_pembilang / p_penyebut)::bigint
$$;

-- Menit kerja satu kode jadwal, tanpa istirahat yang tidak dibayar.
create function hitung.lama_kerja(p_kode text) returns integer
language sql stable set search_path = '' as $$
  select (extract(epoch from k.jam_pulang - k.jam_masuk)::integer / 60
          + case when k.jam_pulang <= k.jam_masuk then 1440 else 0 end
          - case when k.istirahat_dibayar then 0 else k.istirahat_menit end)
  from induk.kode_jadwal k where k.kode = p_kode
$$;

-- Aturan D4: di bawah menit minimal -> 0; selebihnya dibulatkan ke bawah per kelipatan.
create function hitung.menit_lembur_dibayar(p_menit integer, p_tanggal date) returns integer
language sql stable set search_path = '' as $$
  select case when p_menit < l.menit_minimal then 0
              when l.cara_bulat = 'bawah' then p_menit / l.kelipatan_menit * l.kelipatan_menit
              else round(p_menit::numeric / l.kelipatan_menit)::integer * l.kelipatan_menit end
  from aturan.lembur l
  where l.cakupan = 'perusahaan' and daterange(l.berlaku_dari, l.berlaku_sampai, '[)') @> p_tanggal
$$;

-- Aturan D7: satuan = jumlah (pengali x10 jam ke-k x menit di jam ke-k). Menit di luar tabel memakai jam terakhir.
create function hitung.satuan_lembur(p_jenis text, p_menit integer, p_tanggal date) returns bigint
language sql stable set search_path = '' as $$
  with tabel as (
    select jam_ke, pengali_x10 from aturan.pengali_lembur
    where jenis_hari = p_jenis and daterange(berlaku_dari, berlaku_sampai, '[)') @> p_tanggal
  ), jam as (
    select k, least(60, p_menit - 60 * (k - 1)) as menit
    from generate_series(1, (greatest(p_menit, 0) + 59) / 60) k
  )
  select coalesce(sum(j.menit * coalesce(t.pengali_x10,
                    (select pengali_x10 from tabel order by jam_ke desc limit 1))), 0)::bigint
  from jam j left join tabel t on t.jam_ke = j.k
$$;

-- Apakah menit lembur melewati jam terakhir tabel pengali.
create function hitung.lewat_tabel_lembur(p_jenis text, p_menit integer, p_tanggal date) returns boolean
language sql stable set search_path = '' as $$
  select p_menit > 60 * coalesce(max(jam_ke), 0) from aturan.pengali_lembur
  where jenis_hari = p_jenis and daterange(berlaku_dari, berlaku_sampai, '[)') @> p_tanggal
$$;

-- Aturan D9 (kontrak data bagian 7 ayat 3).
create function hitung.rupiah_lembur(p_satuan bigint, p_dasar bigint) returns bigint
language sql immutable set search_path = '' as $$
  select hitung.bulat(p_satuan::numeric * p_dasar, 173 * 60 * 10)
$$;

-- Aturan D8: dasar upah lembur dari upah tetap bulanan dan tunjangan tidak tetap periode itu.
create function hitung.dasar_lembur(p_tetap bigint, p_tidak_tetap bigint) returns bigint
language sql immutable set search_path = '' as $$
  select case when p_tetap * 10000 < 7500 * (p_tetap + p_tidak_tetap)
              then hitung.bulat(75 * (p_tetap + p_tidak_tetap)::numeric, 100) else p_tetap end
$$;

-- Aturan E2-E3: iuran satu program dan bagian. Kesehatan memakai UMK sebagai batas bawah.
create function hitung.iuran_bpjs(p_program text, p_bagian text, p_upah bigint, p_tanggal date) returns bigint
language sql stable set search_path = '' as $$
  select hitung.bulat(
           greatest(least(p_upah, coalesce(b.batas_atas, p_upah)),
                    case when p_program = 'kesehatan'
                         then (select u.nilai from aturan.upah_minimum u
                               where daterange(u.berlaku_dari, u.berlaku_sampai, '[)') @> p_tanggal)
                         else coalesce(b.batas_bawah, 0) end)::numeric * b.persen, 10000)
  from aturan.bpjs b
  where b.program = p_program and b.bagian = p_bagian and daterange(b.berlaku_dari, b.berlaku_sampai, '[)') @> p_tanggal
$$;

-- Aturan F3-F4: PPh 21 TER bulanan.
create function hitung.pph21_ter(p_bruto bigint, p_ptkp text, p_tanggal date) returns bigint
language sql stable set search_path = '' as $$
  select case when p_bruto <= 0 then 0
              when aturan.pengaturan_pada('pembulatan_pph21', null, p_tanggal) = 'terdekat'
                then hitung.bulat(p_bruto::numeric * t.persen, 10000)
              else p_bruto * t.persen / 10000 end
  from aturan.ptkp p
  join aturan.tarif_ter t on t.kategori = p.kategori_ter
   and daterange(t.berlaku_dari, t.berlaku_sampai, '[)') @> p_tanggal
   and int8range(t.bruto_dari, t.bruto_sampai, '[)') @> p_bruto
  where p.status = p_ptkp and daterange(p.berlaku_dari, p.berlaku_sampai, '[)') @> p_tanggal
$$;

-- Aturan D6: hari kerja terpendek jadwal mingguan orang itu (divisi rotasi tidak punya).
create function hitung.hari_terpendek(p_divisi text, p_regu integer, p_tanggal date) returns boolean
language sql stable set search_path = '' as $$
  with minggu as (
    select j.hari_ke, hitung.lama_kerja(j.kode) as lama
    from induk.jadwal_hari j join induk.divisi d on d.kode = j.divisi and d.pola <> 'rotasi'
    where j.divisi = p_divisi and j.regu = p_regu and j.kode is not null
      and daterange(j.berlaku_dari, j.berlaku_sampai, '[)') @> p_tanggal
  )
  select coalesce((select m.lama = min(x.lama) and m.lama < max(x.lama)
                   from minggu m, minggu x where m.hari_ke = extract(isodow from p_tanggal)
                   group by m.lama), false)
$$;

-- ---------------------------------------------------------------------------
-- Mesin hitung gaji
-- ---------------------------------------------------------------------------
create function hitung.hitung_gaji(p_periode bigint) returns bigint
language plpgsql set search_path = '' set jit = off set client_min_messages = warning as $$
declare
  c_versi_kode constant text := 'hitung_gaji 1 (paket 4b-1)';
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

  select encode(sha256(convert_to(concat_ws('|', v_sumber,
           (select max(id) from fakta.perintah_hrd), (select max(id) from jejak.perubahan), c_versi_kode), 'UTF8')), 'hex')
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
  update _hari set makan = (select k.nominal from aturan.komponen_lain k
                            where k.kode = 'uang_makan' and k.cakupan = 'perusahaan'
                              and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> _hari.tanggal)
  where status = 'hadir' and atur_makan = 'dihitung' and menit_telat <= c_telat_maks_uang_makan;
  update _hari set shift = (select k.nominal from aturan.komponen_lain k
                            where k.kode = 'tunjangan_shift_malam' and k.cakupan = 'perusahaan'
                              and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> _hari.tanggal)
  where status = 'hadir' and atur_shift = 'hidup' and shift_malam;
  update _hari set makan = coalesce(makan, 0), shift = coalesce(shift, 0) where makan is null or shift is null;

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
                     || case when menit_bayar > c_batas_hari then array['lembur_lewat_4_jam'] else '{}'::text[] end
                     || case when menit_bayar >= c_batas_hari then array['wajib_makan'] else '{}'::text[] end
  where menit_bayar > 0 and boleh;
  update _hari set tanda_gaji = array_append(tanda_gaji, 'lembur_tidak_dibayar_tanpa_izin') where menit_bayar > 0 and not boleh;

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
         bool_or(h.boleh and h.menit_bayar > 0 and h.tanggal >= c_mulai_uu27) as lembur_sesudah_uu27,
         (select array_agg(distinct t) from _hari h2, unnest(h2.tanda_gaji) t where h2.id_karyawan = h.id_karyawan) as tanda_hari
  from _hari h
  group by h.id_karyawan;
  alter table _orang add column pokok bigint, add column tetap bigint, add column ptkp text, add column ikut_kes boolean,
    add column ikut_tk boolean, add column mulai date, add column premi bigint not null default 0, add column dasar bigint,
    add column lembur bigint not null default 0, add column menit_lembur_bayar bigint not null default 0,
    add column lewat_minggu boolean not null default false;
  update _orang o set pokok = r.gaji_pokok, tetap = r.tunjangan_tetap, ikut_kes = r.bpjs_kesehatan, ikut_tk = r.bpjs_ketenagakerjaan
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
  update _orang o set lembur = x.rupiah, menit_lembur_bayar = x.menit
  from (select h.id_karyawan, sum(hitung.rupiah_lembur(h.satuan, o2.dasar)) as rupiah, sum(h.menit_bayar) as menit
        from _hari h join _orang o2 on o2.id_karyawan = h.id_karyawan
        where h.boleh and h.menit_bayar > 0 group by h.id_karyawan) x
  where x.id_karyawan = o.id_karyawan;
  update _orang o set lewat_minggu = true
  where exists (select 1 from _hari h where h.id_karyawan = o.id_karyawan and h.boleh
                group by date_trunc('week', h.tanggal) having sum(h.menit_bayar) > c_batas_minggu);

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
         format('Lembur %s menit dibayar; dasar upah Rp%s / 173 per jam', o.menit_lembur_bayar, o.dasar)
  from _orang o where o.lembur > 0;

  insert into _rincian
  select o.id_karyawan, 'bpjs_' || b.program || '_' || b.bagian,
         case when b.bagian = 'karyawan' then 'potongan' else 'perusahaan' end,
         case when b.bagian = 'karyawan' then -1 else 1 end * hitung.iuran_bpjs(b.program, b.bagian, o.pokok + o.tetap, v_bayar),
         format('%s%% x upah Rp%s (batas berlaku %s)', trim_scale(b.persen / 100.0), o.pokok + o.tetap, v_bayar)
  from _orang o
  join aturan.bpjs b on daterange(b.berlaku_dari, b.berlaku_sampai, '[)') @> v_bayar
  where case when b.program = 'kesehatan' then o.ikut_kes else o.ikut_tk end;

  -- PPh 21 (F1-F4).
  insert into _rincian
  select x.id_karyawan, 'pph21', 'potongan',
         -case when extract(month from v_bayar) = 12 then 0 else hitung.pph21_ter(x.bruto, x.ptkp, v_bayar) end,
         case when extract(month from v_bayar) = 12 then 'PPh 21 masa Desember (hitung ulang setahun) belum dihitung'
              else format('TER %s x bruto pajak Rp%s', x.ptkp, x.bruto) end
  from (select o.id_karyawan, o.ptkp,
               coalesce((select sum(r.nominal) from _rincian r where r.id_karyawan = o.id_karyawan
                           and (r.kelompok = 'pendapatan'
                                or r.komponen in ('bpjs_jkk_perusahaan', 'bpjs_jkm_perusahaan', 'bpjs_kesehatan_perusahaan'))), 0)::bigint as bruto
        from _orang o) x;

  insert into hitung.rincian_gaji (versi_id, id_karyawan, komponen, kelompok, nominal, bukti)
  select v_versi, id_karyawan, komponen, kelompok, nominal, bukti from _rincian;

  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih,
                                     dibayar, peringatan)
  select v_versi, o.id_karyawan, s.bruto, s.pendapatan, s.potongan, s.pendapatan + s.potongan, s.pendapatan + s.potongan,
         array(select distinct t from unnest(
           coalesce(o.tanda_hari, '{}')
           || case when o.mulai > v_akhir - interval '12 months' and o.pokok + o.tetap < (
                     select u.nilai from aturan.upah_minimum u where daterange(u.berlaku_dari, u.berlaku_sampai, '[)') @> v_akhir)
                   then array['di_bawah_umk'] else '{}'::text[] end
           || case when o.pokok * 10000 < 7500 * (o.pokok + o.tetap) then array['pokok_di_bawah_75'] else '{}'::text[] end
           || case when o.dasar <> o.pokok + o.tetap and o.lembur_sesudah_uu27
                   then array['dasar_lembur_75_perlu_konfirmasi_hrd'] else '{}'::text[] end
           || case when o.lewat_minggu then array['lembur_lewat_18_jam'] else '{}'::text[] end
           || case when extract(month from v_bayar) = 12 then array['pph_desember_belum_dihitung'] else '{}'::text[] end
           || case when s.pendapatan + s.potongan < 0 then array['gaji_bersih_negatif'] else '{}'::text[] end
         ) t order by t)
  from _orang o
  join (select r.id_karyawan,
               sum(r.nominal) filter (where r.kelompok = 'pendapatan') as pendapatan,
               coalesce(sum(r.nominal) filter (where r.kelompok = 'potongan'), 0) as potongan,
               sum(r.nominal) filter (where r.kelompok = 'pendapatan'
                                      or r.komponen in ('bpjs_jkk_perusahaan', 'bpjs_jkm_perusahaan', 'bpjs_kesehatan_perusahaan')) as bruto
        from _rincian r group by r.id_karyawan) s on s.id_karyawan = o.id_karyawan;

  select encode(sha256(convert_to(coalesce(string_agg(concat_ws('|', r.id_karyawan, r.komponen, r.kelompok, r.nominal, r.bukti),
                                                      E'\n' order by r.id_karyawan, r.komponen), '')
                                  || coalesce((select string_agg(concat_ws('|', g.id_karyawan, g.bruto_pajak, g.gaji_bersih,
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
