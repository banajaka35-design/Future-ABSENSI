-- 0034_kasbon_chat.sql
-- Paket 7b (docs/rencana-tahap-7.md bagian 8; PRD v2 C10): kasbon lewat chat (pinjam + cicilan, ganti cicilan,
-- pelunasan tunai, lihat saldo), dan kasbon bisa dibatalkan dengan /batalperintah (keputusan pemilik (a), 22 Nov 2026).
-- Pencatat terlacak: setiap catatan adalah perintah 'kasbon' (asal chat, oleh = akun) dan baris buku_kasbon dengan
-- perintah_id. Mesin hitung gaji hanya mendapat satu syarat: baris buku_kasbon yang perintahnya dibatalkan tidak dihitung;
-- aturan I2-I4 tidak berubah. Migrasi hanya maju; jangan diedit setelah dipasang.

-- ---------------------------------------------------------------------------
-- Mesin hitung gaji: versi kode 6 (sama dengan versi 5 / 0014 ditambah syarat pembatalan kasbon)
-- ---------------------------------------------------------------------------
create or replace function hitung.versi_kode_gaji() returns text language sql immutable set search_path = '' as $$
  select 'hitung_gaji 6 (paket 7b)'::text
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

  -- Pengaturan per divisi per tanggal, dibaca sekali (paket 5a: sebelumnya 6 kali per hari-orang).
  drop table if exists _atur;
  create temp table _atur on commit drop as
  select x.divisi, x.tanggal,
         aturan.pengaturan_pada('izin_dibayar', x.divisi, x.tanggal) as izin_dibayar,
         aturan.pengaturan_pada('uang_makan', x.divisi, x.tanggal) as atur_makan,
         aturan.pengaturan_pada('tunjangan_shift_malam', x.divisi, x.tanggal) as atur_shift,
         aturan.pengaturan_pada('lembur', x.divisi, x.tanggal) as atur_lembur,
         aturan.pengaturan_pada('pola_hari_kerja', x.divisi, x.tanggal) as pola_divisi,
         aturan.pengaturan_pada('cuti_bersama', x.divisi, x.tanggal) as atur_cuti_bersama
  from (select distinct h.divisi, h.tanggal from hitung.hasil_harian h where h.versi_id = v_sumber) x;

  -- Hari per orang dengan upah dan pengaturan yang berlaku pada tanggal itu.
  drop table if exists _hari;
  create temp table _hari on commit drop as
  select h.*, r.gaji_pokok, r.tunjangan_tetap,
         extract(isodow from h.tanggal)::integer <= v_batas_hari_pola as hari_pola,
         a.izin_dibayar, a.atur_makan, a.atur_shift, a.atur_lembur, a.pola_divisi, a.atur_cuti_bersama,
         k.jam_pulang <= k.jam_masuk as shift_malam
  from hitung.hasil_harian h
  join induk.karyawan_riwayat r on r.id_karyawan = h.id_karyawan
   and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> h.tanggal
  join _atur a on a.divisi = h.divisi and a.tanggal = h.tanggal
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
                  and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = k2.perintah_id)
                order by k2.id desc limit 1) as cicilan
        from fakta.buku_kasbon k
        where (k.dibuat at time zone 'Asia/Jakarta')::date <= v_akhir
          -- Paket 7b: baris kasbon yang perintahnya dibatalkan tidak dihitung.
          and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = k.perintah_id)
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
         coalesce(ri.bruto, 0)::bigint as bruto,
         coalesce(ri.iuran, 0)::bigint as iuran,
         (extract(month from v_bayar) = 12
          or exists (select 1 from induk.status_kerja s where s.id_karyawan = o.id_karyawan and s.jenis = 'berhenti'
                       and s.tanggal between v_awal and v_akhir)) as terakhir,
         coalesce(i.sampai_bulan, 0) as batas, coalesce(i.bulan_kerja, 0) as isi_n, coalesce(i.bruto, 0) as isi_bruto,
         coalesce(i.iuran, 0) as isi_iuran, coalesce(i.pph, 0) as isi_pph, false as lengkap,
         0::bigint as prev_bruto, 0::bigint as prev_iuran, 0::bigint as prev_pph, 0 as prev_n,
         0::bigint as setahun, 0::bigint as pph, 0::bigint as kembali
  from _orang o
  -- Rincian dijumlah sekali per orang (paket 5a: sebelumnya disisir ulang untuk setiap orang).
  left join (select r.id_karyawan,
                    sum(r.nominal) filter (where r.kelompok = 'pendapatan'
                                           or r.komponen in ('bpjs_jkk_perusahaan', 'bpjs_jkm_perusahaan', 'bpjs_kesehatan_perusahaan')) as bruto,
                    -sum(r.nominal) filter (where r.komponen in ('bpjs_jht_karyawan', 'bpjs_jp_karyawan')) as iuran
             from _rincian r group by r.id_karyawan) ri on ri.id_karyawan = o.id_karyawan
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
-- ---------------------------------------------------------------------------
-- Draf kasbon
-- ---------------------------------------------------------------------------
alter table fakta.draf_perintah
  add column kasbon_jenis text check (kasbon_jenis in ('pinjam', 'cicilan', 'pelunasan')),
  add column jumlah bigint check (jumlah > 0 and jumlah <= 10000000000),
  add column cicilan bigint check (cicilan > 0 and cicilan <= 10000000000);
alter table fakta.draf_perintah drop constraint draf_perintah_jenis_check;
alter table fakta.draf_perintah add constraint draf_perintah_jenis_check
  check (jenis in ('sakit', 'izin', 'cuti', 'batalkan_perintah', 'kasbon'));
alter table fakta.draf_perintah add constraint draf_perintah_kasbon_check
  check ((jenis = 'kasbon') = (kasbon_jenis is not null and jumlah is not null)
         and (cicilan is null or kasbon_jenis = 'pinjam') and (kasbon_jenis is distinct from 'pinjam' or cicilan is not null));

-- ---------------------------------------------------------------------------
-- Keadaan kasbon satu orang (tanpa baris yang perintahnya dibatalkan).
--   saldo = pinjam - pelunasan - potongan kasbon di versi gaji terakhir semua periode (termasuk yang sedang berjalan);
--   potongan_periode = potongan kasbon di versi gaji terakhir periode p_periode (null = belum dihitung).
-- ---------------------------------------------------------------------------
create function fakta.keadaan_kasbon(p_id text, p_periode bigint) returns jsonb
language sql stable set search_path = '' as $$
  with k as (
    select k.* from fakta.buku_kasbon k
    where k.id_karyawan = p_id
      and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = k.perintah_id)),
  potong as (
    select v.periode_id, -sum(r.nominal) as jumlah from hitung.rincian_gaji r
    join hitung.versi_terakhir v on v.id = r.versi_id and v.jenis = 'hitung_gaji'
    where r.id_karyawan = p_id and r.komponen = 'kasbon' group by v.periode_id)
  select jsonb_build_object(
    'pinjam', coalesce((select sum(jumlah) from k where jenis = 'pinjam'), 0),
    'pelunasan', coalesce((select sum(jumlah) from k where jenis = 'pelunasan'), 0),
    'terpotong', coalesce((select sum(jumlah) from potong), 0),
    'saldo', coalesce((select sum(jumlah) from k where jenis = 'pinjam'), 0) - coalesce((select sum(jumlah) from k where jenis = 'pelunasan'), 0)
             - coalesce((select sum(jumlah) from potong), 0),
    'cicilan', (select jumlah from k where jenis = 'cicilan' order by id desc limit 1),
    'potongan_periode', case when exists (select 1 from hitung.versi_terakhir v where v.periode_id = p_periode and v.jenis = 'hitung_gaji')
                             then coalesce((select jumlah from potong where periode_id = p_periode), 0) end,
    'rahasia', p_periode is not null and fakta.rahasia_di_periode(p_id, p_periode))
$$;

-- ---------------------------------------------------------------------------
-- Kasbon untuk bot
-- ---------------------------------------------------------------------------

-- Lihat saldo. Masukan: {"telegram_id", "id_karyawan"}. Angka disembunyikan untuk orang rahasia (F15).
create function api.pintu_kasbon_saldo(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id text := upper(trim(p ->> 'id_karyawan'));
  v_hari date := (now() at time zone 'Asia/Jakarta')::date;
  v_k jsonb;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  if not exists (select 1 from induk.karyawan k where k.id = v_id) then
    return jsonb_build_object('hasil', 'tidak_ada', 'id', v_id);
  end if;
  v_k := fakta.keadaan_kasbon(v_id, (fakta.periode_tanggal(v_hari)).id);
  if (v_k ->> 'rahasia')::boolean then
    return jsonb_build_object('hasil', 'rahasia') || fakta.identitas_karyawan(v_id);
  end if;
  return jsonb_build_object('hasil', 'ada', 'kasbon', v_k, 'periode', to_jsonb(fakta.periode_tanggal(v_hari)) - 'dibuat',
    'riwayat', coalesce((select jsonb_agg(jsonb_build_object('jenis', k.jenis, 'jumlah', k.jumlah, 'perintah_id', k.perintah_id,
                          'tanggal', (k.dibuat at time zone 'Asia/Jakarta')::date, 'oleh', u.peran,
                          'dibatalkan', exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = k.perintah_id))
                          order by k.id desc)
                         from (select * from fakta.buku_kasbon where id_karyawan = v_id order by id desc limit 5) k
                         left join fakta.perintah_hrd x on x.id = k.perintah_id
                         left join induk.pengguna u on u.id = x.oleh), '[]'::jsonb))
    || fakta.identitas_karyawan(v_id);
end $$;

-- Siapkan draf kasbon. Masukan: {"telegram_id", "kasbon_jenis": pinjam|cicilan|pelunasan, "id_karyawan", "jumlah",
-- "cicilan" (wajib untuk pinjam), "catatan"}. Tanggal = hari ini (WIB): kasbon mulai berlaku di periode yang memuat hari ini.
-- Keluaran: {"hasil": "siap" | "bukan_hrd" | "jumlah_salah" | "cicilan_wajib" | "tanpa_saldo" | "melebihi_saldo" |
--            penolakan periksa_perintah, ...}.
create function api.pintu_kasbon_siapkan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id text := upper(trim(p ->> 'id_karyawan'));
  v_jenis text := p ->> 'kasbon_jenis';
  v_hari date := (now() at time zone 'Asia/Jakarta')::date;
  v_jumlah bigint;
  v_cicilan bigint;
  v_cek jsonb;
  v_k jsonb;
  v_saldo bigint;
  v_draf bigint;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  if v_jenis is null or v_jenis not in ('pinjam', 'cicilan', 'pelunasan') then
    return jsonb_build_object('hasil', 'jenis_salah');
  end if;
  begin
    v_jumlah := (p ->> 'jumlah')::bigint;
    v_cicilan := (p ->> 'cicilan')::bigint;
  exception when others then
    return jsonb_build_object('hasil', 'jumlah_salah');
  end;
  if v_jumlah is null or v_jumlah <= 0 or v_jumlah > 10000000000 or (v_cicilan is not null and (v_cicilan <= 0 or v_cicilan > 10000000000)) then
    return jsonb_build_object('hasil', 'jumlah_salah');
  end if;
  if v_jenis = 'pinjam' and v_cicilan is null then
    return jsonb_build_object('hasil', 'cicilan_wajib');
  end if;
  if v_jenis <> 'pinjam' then
    v_cicilan := null;
  end if;
  -- aturan tanggal dan aktif sama dengan izin (fakta.periksa_perintah 0033 tidak mengenal jenis kasbon)
  v_cek := fakta.periksa_perintah('izin', v_id, v_hari, v_hari);
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  v_k := fakta.keadaan_kasbon(v_id, (v_cek -> 'periode' -> 0 ->> 'id')::bigint);
  v_saldo := (v_k ->> 'saldo')::bigint;
  if v_jenis = 'cicilan' and v_saldo <= 0 then
    return jsonb_build_object('hasil', 'tanpa_saldo') || fakta.identitas_karyawan(v_id);
  end if;
  if v_jenis = 'pelunasan' and v_jumlah > v_saldo then
    return jsonb_build_object('hasil', 'melebihi_saldo', 'rahasia', v_k -> 'rahasia',
      'saldo', case when (v_k ->> 'rahasia')::boolean then null else v_saldo end) || fakta.identitas_karyawan(v_id);
  end if;
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, catatan, kedaluwarsa,
                                   kasbon_jenis, jumlah, cicilan)
  values (v_hrd, 'kasbon', v_id, v_hari, v_hari, nullif(left(trim(p ->> 'catatan'), 200), ''), now() + interval '15 minutes',
          v_jenis, v_jumlah, v_cicilan)
  returning id into v_draf;
  return v_cek || jsonb_build_object('draf_id', v_draf, 'jenis', 'kasbon', 'kasbon_jenis', v_jenis, 'jumlah', v_jumlah,
    'cicilan', v_cicilan, 'mulai', v_hari, 'selesai', v_hari, 'catatan', nullif(left(trim(p ->> 'catatan'), 200), ''),
    'kasbon', case when (v_k ->> 'rahasia')::boolean then jsonb_build_object('rahasia', true) else v_k end)
    || fakta.identitas_karyawan(v_id);
end $$;

-- ---------------------------------------------------------------------------
-- Batalkan: sama dengan 0033, ditambah perintah kasbon.
-- ---------------------------------------------------------------------------
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
  if v_x.jenis not in ('sakit', 'izin', 'cuti', 'kasbon') or v_x.id_karyawan is null or v_x.tanggal_mulai is null
     or (v_x.jenis = 'kasbon' and not exists (select 1 from fakta.buku_kasbon k where k.perintah_id = v_x.id)) then
    return jsonb_build_object('hasil', 'jenis_tidak_bisa', 'perintah_id', v_x.id, 'jenis', v_x.jenis);
  end if;
  select b.id into v_batal from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = v_x.id order by b.id limit 1;
  if v_batal is not null then
    return jsonb_build_object('hasil', 'sudah_dibatalkan', 'perintah_id', v_x.id, 'oleh_perintah', v_batal);
  end if;
  v_selesai := coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai);
  v_cek := fakta.periksa_perintah('batalkan_perintah', v_x.id_karyawan, v_x.tanggal_mulai, v_selesai);
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek || jsonb_build_object('perintah_id', v_x.id);
  end if;
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, membatalkan, kedaluwarsa)
  values (v_hrd, 'batalkan_perintah', v_x.id_karyawan, v_x.tanggal_mulai, v_selesai, v_x.id, now() + interval '15 minutes')
  returning id into v_draf;
  if v_x.jenis = 'kasbon' then
    v_k := fakta.keadaan_kasbon(v_x.id_karyawan, (v_cek -> 'periode' -> 0 ->> 'id')::bigint);
  end if;
  return v_cek || jsonb_build_object('draf_id', v_draf, 'jenis', 'batalkan_perintah', 'mulai', v_x.tanggal_mulai, 'selesai', v_selesai,
    'dibatalkan', jsonb_build_object('id', v_x.id, 'jenis', v_x.jenis, 'asal', v_x.asal, 'alasan', v_x.alasan,
      'kasbon', case when v_x.jenis = 'kasbon' then (select jsonb_agg(jsonb_build_object('jenis', k.jenis, 'jumlah', k.jumlah) order by k.id)
                                                     from fakta.buku_kasbon k where k.perintah_id = v_x.id) end),
    'kasbon', case when v_k is null then null when (v_k ->> 'rahasia')::boolean then jsonb_build_object('rahasia', true) else v_k end,
    'hari', case when v_x.jenis = 'kasbon' then '[]'::jsonb else fakta.hari_perintah(v_x.id_karyawan, v_x.tanggal_mulai, v_selesai) end)
    || fakta.identitas_karyawan(v_x.id_karyawan);
end $$;

-- ---------------------------------------------------------------------------
-- Simpan (tombol Ya/Batal): sama dengan 0033, ditambah draf kasbon (perintah 'kasbon' + baris buku_kasbon).
-- Keadaan kasbon sebelum dicatat ikut dikembalikan untuk kabar "sebelum -> sesudah".
-- ---------------------------------------------------------------------------
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
  end if;
  v_cek := fakta.periksa_perintah(case when v_d.jenis = 'kasbon' then 'izin' else v_d.jenis end,
                                  v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai);
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
  v_sebelum := case when v_d.jenis = 'kasbon' or v_kasbon_target then '[]'::jsonb
                    else fakta.hari_perintah(v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai) end;
  insert into fakta.perintah_hrd (oleh, asal, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, alasan, membatalkan, nilai)
  values (v_hrd, 'chat', v_d.jenis, v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai, v_d.catatan, v_d.membatalkan,
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
    'kasbon_sebelum', case when v_k is null then null when (v_k ->> 'rahasia')::boolean then jsonb_build_object('rahasia', true) else v_k end)
    || fakta.identitas_karyawan(v_d.id_karyawan);
end $$;

-- ---------------------------------------------------------------------------
-- Hasil sesudah hitung ulang: sama dengan 0032, ditambah keadaan kasbon untuk perintah kasbon atau pembatalannya.
-- ---------------------------------------------------------------------------
create or replace function api.pintu_perintah_hasil(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_x fakta.perintah_hrd;
  v_kasbon boolean;
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
  if v_kasbon then
    v_k := fakta.keadaan_kasbon(v_x.id_karyawan, (fakta.periode_tanggal(v_x.tanggal_mulai)).id);
    if (v_k ->> 'rahasia')::boolean then
      v_k := jsonb_build_object('rahasia', true);
    end if;
  end if;
  return jsonb_build_object('hasil', 'ada', 'perintah_id', v_x.id, 'jenis', v_x.jenis, 'membatalkan', v_x.membatalkan,
    'mulai', v_x.tanggal_mulai, 'selesai', coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai),
    'hari', case when v_kasbon then '[]'::jsonb
                 else fakta.hari_perintah(v_x.id_karyawan, v_x.tanggal_mulai, coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai)) end,
    'kasbon', v_k, 'periode_kasbon', (fakta.periode_tanggal(v_x.tanggal_mulai)).id,
    'selesai_dihitung', not exists (select 1 from fakta.antrean_kerja a where a.perintah_id = v_x.id and a.status = 'menunggu'),
    'gagal', exists (select 1 from fakta.antrean_kerja a where a.perintah_id = v_x.id and a.status = 'gagal'))
    || fakta.identitas_karyawan(v_x.id_karyawan);
end $$;

revoke all on function fakta.keadaan_kasbon(text, bigint) from public;
grant execute on function api.pintu_kasbon_saldo(jsonb), api.pintu_kasbon_siapkan(jsonb) to pintu;
