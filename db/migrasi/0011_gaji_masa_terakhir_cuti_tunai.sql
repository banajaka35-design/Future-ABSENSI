-- 0011_gaji_masa_terakhir_cuti_tunai.sql
-- Paket 4b-3: PPh masa terakhir (hitung ulang setahun, Pasal 17), saldo cuti, pecahan uang tunai.
-- Aturan: docs/aturan-hitung-gaji.md versi 3 (ditulis sebelum file ini). Migrasi hanya maju; jangan diedit setelah dipasang.

create table aturan.tarif_pasal17 (
  id bigint generated always as identity primary key,
  pkp_dari bigint not null check (pkp_dari >= 0),
  pkp_sampai bigint,
  persen integer not null check (persen between 0 and 10000),
  berlaku_dari date not null,
  berlaku_sampai date,
  check (pkp_sampai is null or pkp_sampai > pkp_dari),
  check (berlaku_sampai is null or berlaku_sampai > berlaku_dari),
  exclude using gist (int8range(pkp_dari, pkp_sampai, '[)') with &&, daterange(berlaku_dari, berlaku_sampai, '[)') with &&)
);
create trigger jaga_bertanggal before update or delete on aturan.tarif_pasal17 for each row execute function jejak.jaga_bertanggal();
create trigger catat_perubahan after insert or update or delete on aturan.tarif_pasal17 for each row execute function jejak.catat_perubahan();
-- UU 7/2021 (HPP) Pasal 17 ayat 1 huruf a, berlaku tahun pajak 2022.
insert into aturan.tarif_pasal17 (pkp_dari, pkp_sampai, persen, berlaku_dari) values
  (0, 60000000, 500, '2022-01-01'), (60000000, 250000000, 1500, '2022-01-01'), (250000000, 500000000, 2500, '2022-01-01'),
  (500000000, 5000000000, 3000, '2022-01-01'), (5000000000, null, 3500, '2022-01-01');

-- Saldo cuti awal, diisi HRD saat pemasangan (tanggal = tanggal awal sebuah periode).
create table induk.saldo_cuti_awal (
  id_karyawan text not null references induk.karyawan (id),
  tanggal date not null,
  hari integer not null,
  catatan text,
  primary key (id_karyawan, tanggal)
);
create trigger catat_perubahan after insert or update or delete on induk.saldo_cuti_awal for each row execute function jejak.catat_perubahan();

alter table hitung.ringkasan_gaji add column cuti_terpakai integer not null default 0, add column saldo_cuti integer;

create or replace function hitung.versi_kode_gaji() returns text language sql immutable set search_path = '' as $$
  select 'hitung_gaji 3 (paket 4b-3)'::text
$$;

-- L5: tarif Pasal 17 berlapis, dibulatkan ke bawah ke rupiah.
create function hitung.pph_pasal17(p_pkp bigint, p_tanggal date) returns bigint
language sql stable set search_path = '' as $$
  select coalesce(sum((least(p_pkp, coalesce(t.pkp_sampai, p_pkp)) - t.pkp_dari) * t.persen), 0)::bigint / 10000
  from aturan.tarif_pasal17 t
  where p_pkp > t.pkp_dari and daterange(t.berlaku_dari, t.berlaku_sampai, '[)') @> p_tanggal
$$;

-- L4-L5: PPh setahun dari bruto setahun, iuran pegawai, status PTKP, dan banyak bulan (batas biaya jabatan).
create function hitung.pph21_setahun(p_bruto bigint, p_iuran bigint, p_ptkp text, p_bulan integer, p_tanggal date) returns bigint
language sql stable set search_path = '' as $$
  select hitung.pph_pasal17(
           greatest(0, p_bruto - least(p_bruto * 5 / 100, 500000::bigint * p_bulan) - p_iuran - p.nilai_setahun) / 1000 * 1000,
           p_tanggal)
  from aturan.ptkp p
  where p.status = p_ptkp and daterange(p.berlaku_dari, p.berlaku_sampai, '[)') @> p_tanggal
$$;

-- N1 (U12): lembar per pecahan untuk semua yang dibayar tunai di satu versi gaji.
create function hitung.pecahan_tunai(p_versi bigint) returns table (pecahan bigint, lembar bigint, jumlah bigint)
language plpgsql stable set search_path = '' as $$
declare
  v_pecahan bigint[];
  v_hitung bigint[];
  v_sisa bigint;
  g record;
  i integer;
  v_akhir date;
begin
  select p.tanggal_akhir into v_akhir from hitung.versi_hitung v join fakta.periode p on p.id = v.periode_id where v.id = p_versi;
  select array_agg(d order by d desc) into v_pecahan
  from unnest(array[100000, 50000, 20000, 10000, 5000, 2000, 1000]::bigint[]) d
  where d >= aturan.pengaturan_pada('pembulatan_tunai', null, v_akhir)::bigint;
  v_hitung := array_fill(0::bigint, array[array_length(v_pecahan, 1)]);
  for g in select r.dibayar from hitung.ringkasan_gaji r
           join induk.karyawan_riwayat k on k.id_karyawan = r.id_karyawan
            and daterange(k.berlaku_dari, k.berlaku_sampai, '[)') @> v_akhir
           where r.versi_id = p_versi and k.cara_bayar = 'tunai' and r.dibayar > 0 loop
    v_sisa := g.dibayar;
    for i in 1 .. array_length(v_pecahan, 1) loop
      v_hitung[i] := v_hitung[i] + v_sisa / v_pecahan[i];
      v_sisa := v_sisa % v_pecahan[i];
    end loop;
  end loop;
  return query select v_pecahan[s.k], v_hitung[s.k], v_pecahan[s.k] * v_hitung[s.k] from generate_subscripts(v_pecahan, 1) as s(k);
end $$;

-- L2: periode boleh diajukan bila punya hasil gaji dan tidak ada PPh masa terakhir yang tertahan.
create function hitung.periode_bisa_diajukan(p_periode bigint) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from hitung.versi_terakhir v where v.periode_id = p_periode and v.jenis = 'hitung_gaji')
     and not exists (select 1 from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
                     where v.periode_id = p_periode and v.jenis = 'hitung_gaji'
                       and 'pph_masa_terakhir_tertahan' = any(g.peringatan))
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
  v_lengkap boolean;  -- L2: data gaji setahun lengkap sampai bulan sebelum bulan bayar
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

  -- PPh 21: TER (F1-F4), atau hitung ulang setahun di masa terakhir (L1-L5).
  select not exists (
    select 1 from generate_series(1, extract(month from v_bayar)::integer - 1) m
    where not exists (select 1 from fakta.periode p join hitung.versi_terakhir v on v.periode_id = p.id and v.jenis = 'hitung_gaji'
                      where extract(year from p.tanggal_bayar) = extract(year from v_bayar)
                        and extract(month from p.tanggal_bayar) = m))
  into v_lengkap;
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
         0::bigint as prev_bruto, 0::bigint as prev_iuran, 0::bigint as prev_pph, 0 as prev_n,
         0::bigint as setahun, 0::bigint as pph, 0::bigint as kembali
  from _orang o;
  update _pajak k set prev_bruto = y.bruto, prev_iuran = y.iuran, prev_pph = y.pph, prev_n = y.n
  from (select g.id_karyawan, sum(g.bruto_pajak)::bigint as bruto, count(*)::integer as n,
               coalesce(sum(z.iuran), 0)::bigint as iuran, coalesce(sum(z.pph), 0)::bigint as pph
        from hitung.ringkasan_gaji g
        join hitung.versi_terakhir v on v.id = g.versi_id and v.jenis = 'hitung_gaji'
        join fakta.periode p on p.id = v.periode_id
        cross join lateral (
          select coalesce(-sum(r.nominal) filter (where r.komponen in ('bpjs_jht_karyawan', 'bpjs_jp_karyawan')), 0) as iuran,
                 coalesce(-sum(r.nominal) filter (where r.komponen = 'pph21'), 0)
                 - coalesce(sum(r.nominal) filter (where r.komponen = 'pengembalian_pph21'), 0) as pph
          from hitung.rincian_gaji r where r.versi_id = g.versi_id and r.id_karyawan = g.id_karyawan) z
        where extract(year from p.tanggal_bayar) = extract(year from v_bayar) and p.tanggal_bayar < v_bayar and p.id <> p_periode
        group by g.id_karyawan) y
  where y.id_karyawan = k.id_karyawan and k.terakhir and v_lengkap;
  update _pajak set setahun = hitung.pph21_setahun(prev_bruto + bruto, prev_iuran + iuran, ptkp, prev_n + 1, v_bayar)
  where terakhir and v_lengkap;
  update _pajak set pph = case when not terakhir then coalesce(hitung.pph21_ter(bruto, ptkp, v_bayar), 0)
                               when not v_lengkap then 0
                               else greatest(0, setahun - prev_pph) end,
                    kembali = case when terakhir and v_lengkap then greatest(0, prev_pph - setahun) else 0 end;
  insert into _rincian
  select k.id_karyawan, 'pph21', 'potongan', -k.pph,
         case when not k.terakhir then format('TER %s x bruto pajak Rp%s', k.ptkp, k.bruto)
              when not v_lengkap then 'PPh masa terakhir belum dihitung: data gaji setahun belum lengkap'
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
           || case when exists (select 1 from _pajak k where k.id_karyawan = o.id_karyawan and k.terakhir and not v_lengkap)
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
