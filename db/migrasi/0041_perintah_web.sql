-- 0041_perintah_web.sql
-- Paket 9b-1 (docs/rencana-9b-1.md): perintah lewat web HRD tanpa angka uang: tambah libur, absen manual divisi,
-- berhenti, aktif kembali, mutasi. Alur: isian -> pratinjau (draf 15 menit, tidak mengubah apa pun) -> Simpan
-- (pemeriksaan diulang, perintah dicatat asal 'web', data induk diubah, periode masuk antrean) -> boleh dibatalkan.
-- Keputusan pemilik 25 Nov 2026: "berhenti tanggal X" = hari kerja terakhir (sama dengan mesin hitung, tidak diubah);
-- pembatalan memakai PENGECUALIAN SEMPIT pada penjaga data induk (hanya fungsi pembatalan perintah web, hanya baris
-- yang dibuat/ditutup perintah itu, tercatat di jejak.perubahan).
-- Migrasi hanya maju; jangan diedit setelah dipasang.

alter table fakta.perintah_hrd drop constraint perintah_hrd_asal_check,
  add constraint perintah_hrd_asal_check check (asal in ('chat', 'file', 'sistem', 'web'));

-- ---------------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------------
create table fakta.draf_perintah_web (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  pengguna bigint not null references induk.pengguna (id),
  jenis text not null check (jenis in ('tambah_libur', 'absen_manual', 'berhenti', 'aktif_kembali', 'mutasi')),
  isian jsonb not null,
  kedaluwarsa timestamptz not null,
  selesai_pada timestamptz,
  perintah_id bigint references fakta.perintah_hrd (id)
);

-- Satu baris per perintah web (termasuk pembatalannya): siapa, periode yang dihitung ulang, batas jejak sesudah simpan.
create table fakta.perintah_web (
  perintah_id bigint primary key references fakta.perintah_hrd (id),
  pengguna bigint not null references induk.pengguna (id),
  periode bigint[] not null default '{}',
  jejak_akhir bigint not null,
  ringkas text not null
);

-- Perubahan data induk oleh perintah web: baris yang ditambah dan baris yang ditutup (beserta tanggal tutupnya).
create table fakta.perintah_web_ubah (
  id bigint generated always as identity primary key,
  perintah_id bigint not null references fakta.perintah_hrd (id),
  tabel text not null check (tabel in ('induk.status_kerja', 'induk.karyawan_riwayat', 'induk.penugasan_regu', 'induk.pemetaan_id_mesin')),
  baris bigint not null,
  aksi text not null check (aksi in ('tambah', 'tutup')),
  ditutup_ke date,
  check ((aksi = 'tutup') = (ditutup_ke is not null))
);
create index perintah_web_ubah_perintah on fakta.perintah_web_ubah (perintah_id);

create trigger tolak_ubah before update or delete on fakta.perintah_web for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.perintah_web for each statement execute function jejak.tolak_ubah();
create trigger tolak_ubah before update or delete on fakta.perintah_web_ubah for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.perintah_web_ubah for each statement execute function jejak.tolak_ubah();

-- ---------------------------------------------------------------------------
-- Pengecualian sempit pada penjaga (keputusan pemilik 25 Nov 2026 09.05).
-- Hanya berlaku bila app.batal_perintah_web berisi nomor perintah P, pembatalan P sudah dicatat dalam transaksi ini,
-- dan baris yang disentuh tercatat di fakta.perintah_web_ubah untuk P: hapus baris yang DITAMBAH P, atau buka lagi
-- (berlaku_sampai kembali kosong) baris yang DITUTUP P pada tanggal yang sama, tanpa mengubah isian lain.
-- Semua jalan lain tetap ditolak seperti sebelumnya.
-- ---------------------------------------------------------------------------
create function jejak.boleh_batal_web(p_tabel text, p_baris bigint, p_aksi text, p_sampai_lama date) returns boolean
language plpgsql stable set search_path = '' as $$
declare
  v_teks text := coalesce(current_setting('app.batal_perintah_web', true), '');
  v_p bigint;
begin
  if v_teks !~ '^[0-9]{1,18}$' then
    return false;
  end if;
  v_p := v_teks::bigint;
  return exists (select 1 from fakta.perintah_hrd b
                 where b.jenis = 'batalkan_perintah' and b.asal = 'web' and b.dibuat = now() and b.membatalkan = v_p)
     and exists (select 1 from fakta.perintah_web_ubah u
                 where u.perintah_id = v_p and u.tabel = p_tabel and u.baris = p_baris and u.aksi = p_aksi
                   and (p_aksi = 'tambah' or u.ditutup_ke = p_sampai_lama));
end $$;

create or replace function jejak.tolak_ubah() returns trigger
language plpgsql as $$
begin
  if tg_level = 'ROW' and tg_op = 'DELETE' and tg_table_schema = 'induk' and tg_table_name = 'status_kerja' then
    if jejak.boleh_batal_web('induk.status_kerja', old.id, 'tambah', null) then
      return old;
    end if;
  end if;
  raise exception 'Tabel %.% hanya boleh ditambah; koreksi dicatat sebagai baris baru', tg_table_schema, tg_table_name
    using errcode = 'P0001';
end $$;

create or replace function jejak.jaga_bertanggal() returns trigger
language plpgsql as $$
begin
  if tg_table_schema = 'induk' and tg_table_name in ('karyawan_riwayat', 'penugasan_regu', 'pemetaan_id_mesin') then
    if tg_op = 'DELETE' then
      if jejak.boleh_batal_web('induk.' || tg_table_name, old.id, 'tambah', null) then
        return old;
      end if;
    elsif old.berlaku_sampai is not null and new.berlaku_sampai is null
          and (to_jsonb(new) - 'berlaku_sampai') = (to_jsonb(old) - 'berlaku_sampai') then
      if jejak.boleh_batal_web('induk.' || tg_table_name, old.id, 'tutup', old.berlaku_sampai) then
        return new;
      end if;
    end if;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Baris bertanggal di %.% tidak boleh dihapus; tutup dengan berlaku_sampai', tg_table_schema, tg_table_name
      using errcode = 'P0001';
  end if;
  if old.berlaku_sampai is not null then
    raise exception 'Baris bertanggal yang sudah ditutup tidak boleh diubah' using errcode = 'P0001';
  end if;
  if (to_jsonb(new) - 'berlaku_sampai') is distinct from (to_jsonb(old) - 'berlaku_sampai') then
    raise exception 'Baris bertanggal hanya boleh diubah dengan mengisi berlaku_sampai; nilai baru dicatat sebagai baris baru'
      using errcode = 'P0001';
  end if;
  if new.berlaku_sampai is null then
    raise exception 'berlaku_sampai yang sudah diisi tidak boleh dikosongkan lagi' using errcode = 'P0001';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Bantuan
-- ---------------------------------------------------------------------------
create function fakta.tgl(p date) returns text
language sql immutable set search_path = '' as $$
  select extract(day from p)::int || ' ' ||
         (array['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'])[extract(month from p)::int] || ' ' ||
         extract(year from p)::int
$$;

create function fakta.web_hari_ini() returns date
language sql stable set search_path = '' as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

-- Perintah per hari (tambah libur, absen manual): setiap hari wajib punya periode yang belum dirilis.
create function fakta.web_cek_hari(p_mulai date, p_selesai date) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_hari date;
  v_p fakta.periode;
begin
  for v_hari in select d::date from generate_series(p_mulai::timestamp, p_selesai::timestamp, interval '1 day') d loop
    v_p := fakta.periode_tanggal(v_hari);
    if v_p.id is null then
      return format('Tanggal %s belum masuk periode mana pun.', fakta.tgl(v_hari));
    end if;
    if v_p.status in ('dirilis', 'dikunci') then
      return format('Periode no. %s (%s – %s) sudah dirilis; tanggal %s tidak bisa diubah.', v_p.id, fakta.tgl(v_p.tanggal_awal),
                    fakta.tgl(v_p.tanggal_akhir), fakta.tgl(v_hari));
    end if;
  end loop;
  return null;
end $$;

-- Perubahan data induk berlaku sejak tanggal X: tidak boleh ada periode dirilis pada atau sesudah X (C3).
-- Tanggal sesudah periode terakhir boleh sampai 62 hari dari hari ini (C4, tebakan, keputusan pemilik 25 Nov 08.59).
create function fakta.web_cek_sejak(p_dari date, p_batas_depan boolean) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_p fakta.periode;
  v_akhir date := (select max(p.tanggal_akhir) from fakta.periode p);
begin
  select p.* into v_p from fakta.periode p
  where p.tanggal_akhir >= p_dari and p.status in ('dirilis', 'dikunci') order by p.tanggal_awal limit 1;
  if v_p.id is not null then
    return format('Periode no. %s (%s – %s) sudah dirilis; perubahan yang berlaku sejak %s akan mengubah gaji yang sudah dirilis.',
                  v_p.id, fakta.tgl(v_p.tanggal_awal), fakta.tgl(v_p.tanggal_akhir), fakta.tgl(p_dari));
  end if;
  if p_batas_depan and p_dari > fakta.web_hari_ini() + 62 then
    return format('Tanggal %s lebih dari 62 hari dari hari ini; periksa tahunnya.', fakta.tgl(p_dari));
  end if;
  if (fakta.periode_tanggal(p_dari)).id is null and (v_akhir is null or p_dari <= v_akhir) then
    return format('Tanggal %s tidak masuk periode mana pun.', fakta.tgl(p_dari));
  end if;
  return null;
end $$;

-- Periode yang dihitung ulang. Per hari: yang kena dan sesudahnya yang sudah punya gaji (sama dengan chat).
-- Sejak X: semua periode yang berakhir pada/sesudah X, belum dirilis, dan sudah pernah dihitung.
create function fakta.web_periode_kena(p_mulai date, p_selesai date, p_sejak boolean) returns bigint[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(x.id order by x.tanggal_awal), '{}')
  from fakta.periode x
  where x.status not in ('dirilis', 'dikunci')
    and case when p_sejak then x.tanggal_akhir >= p_mulai
                          and exists (select 1 from hitung.versi_terakhir v where v.periode_id = x.id)
             else (x.tanggal_awal <= p_selesai and x.tanggal_akhir >= p_mulai)
                  or (x.tanggal_awal > p_selesai and exists (select 1 from hitung.versi_terakhir g where g.periode_id = x.id and g.jenis = 'hitung_gaji'))
        end
$$;

create function fakta.web_periode_json(p_id bigint[]) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'awal', x.tanggal_awal, 'akhir', x.tanggal_akhir, 'status', x.status)
                            order by x.tanggal_awal), '[]'::jsonb)
  from fakta.periode x where x.id = any (p_id)
$$;

-- Hasil harian dari baca tap terakhir periode yang memuat tanggal itu.
create function fakta.web_hasil_hari(p_tanggal date) returns setof hitung.hasil_harian
language sql stable set search_path = '' as $$
  select h.* from hitung.hasil_harian h
  where h.tanggal = p_tanggal
    and h.versi_id = (select v.id from hitung.versi_terakhir v
                      where v.jenis = 'baca_tap' and v.periode_id = (fakta.periode_tanggal(p_tanggal)).id)
$$;

-- ---------------------------------------------------------------------------
-- Pemeriksaan (dipakai pratinjau dan simpan). Tidak mengubah apa pun.
-- Keluaran: {"hasil": "siap", "isian", "ringkas", "catatan": [...], "orang", "periode": [...]} |
--           {"hasil": "ditolak", "alasan"}.
-- ---------------------------------------------------------------------------
create function fakta.web_perintah_periksa(p_jenis text, p jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_id text := nullif(upper(trim(p ->> 'id_karyawan')), '');
  v_div text := nullif(upper(trim(p ->> 'divisi')), '');
  v_alasan text := nullif(left(trim(p ->> 'alasan'), 200), '');
  v_jabatan text := nullif(left(trim(p ->> 'jabatan'), 80), '');
  v_id_mesin text := nullif(trim(p ->> 'id_mesin'), '');
  v_regu integer;
  v_mulai date;
  v_selesai date;
  v_t date;
  v_tolak text;
  v_catatan jsonb := '[]'::jsonb;
  v_ringkas text;
  v_orang integer;
  v_periode bigint[];
  v_nama text;
  v_d induk.divisi;
  v_r0 induk.karyawan_riwayat;
  v_g0 induk.penugasan_regu;
  v_s induk.status_kerja;
  v_mesin_lama text;
  v_n integer;
  v_x date;
  v_isian jsonb;
  v_div_ubah boolean;
  v_regu_ubah boolean;
  v_jab_ubah boolean;
  v_perlu_mesin boolean := false;
begin
  if p_jenis is null or p_jenis not in ('tambah_libur', 'absen_manual', 'berhenti', 'aktif_kembali', 'mutasi') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Jenis perintah tidak dikenal.');
  end if;
  begin
    v_mulai := nullif(p ->> 'mulai', '')::date;
    v_selesai := coalesce(nullif(p ->> 'selesai', '')::date, v_mulai);
    if nullif(p ->> 'regu', '') is not null then v_regu := (p ->> 'regu')::integer; end if;
  exception when others then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tanggal atau regu tidak terbaca.');
  end;
  if v_mulai is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tanggal wajib diisi.');
  end if;
  if v_alasan is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Keterangan/alasan wajib diisi.');
  end if;

  -- Tambah libur dan absen manual divisi: per hari, paling banyak 31 hari.
  if p_jenis in ('tambah_libur', 'absen_manual') then
    if v_selesai < v_mulai then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tanggal selesai sebelum tanggal mulai.');
    end if;
    if v_selesai - v_mulai + 1 > 31 then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Paling banyak 31 hari dalam satu perintah.');
    end if;
    if v_div is not null then
      select d.* into v_d from induk.divisi d where d.kode = v_div;
      if v_d.kode is null then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Divisi %s tidak ada.', v_div));
      end if;
    elsif p_jenis = 'absen_manual' then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Absen manual wajib memilih satu divisi.');
    end if;
    v_tolak := fakta.web_cek_hari(v_mulai, v_selesai);
    if v_tolak is not null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', v_tolak);
    end if;
    select min(x.id) into v_n from fakta.perintah_hrd x
    where x.jenis = p_jenis and x.id_karyawan is null and x.divisi is not distinct from v_div
      and x.tanggal_mulai <= v_selesai and coalesce(x.tanggal_selesai, x.tanggal_mulai) >= v_mulai
      and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = x.id);
    if v_n is not null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan',
        format('Sudah ada perintah no. %s yang sama untuk sebagian tanggal itu; batalkan dulu bila ingin mengganti.', v_n));
    end if;
    select count(*) into v_orang from induk.karyawan_riwayat r
    where daterange(r.berlaku_dari, r.berlaku_sampai, '[)') && daterange(v_mulai, v_selesai, '[]')
      and (v_div is null or r.divisi = v_div)
      and fakta.karyawan_aktif(r.id_karyawan, greatest(r.berlaku_dari, v_mulai));
    v_ringkas := format('%s %s, %s', case when p_jenis = 'tambah_libur' then 'Tambah libur' else 'Absen manual (hadir semua)' end,
                        coalesce('divisi ' || v_d.nama, 'semua divisi'),
                        case when v_mulai = v_selesai then fakta.tgl(v_mulai) else fakta.tgl(v_mulai) || ' s.d. ' || fakta.tgl(v_selesai) end);
    if p_jenis = 'tambah_libur' then
      select count(distinct h.id_karyawan) into v_n
      from generate_series(v_mulai::timestamp, v_selesai::timestamp, interval '1 day') d
      cross join lateral fakta.web_hasil_hari(d::date) h
      where h.masuk is not null and (v_div is null or h.divisi = v_div);
      if v_n > 0 then
        v_catatan := v_catatan || to_jsonb(format('%s orang sudah tap di tanggal itu. Bila hari itu libur, jam kerjanya dihitung sebagai masuk '
                                                  'di hari libur (lembur hari libur) sesuai aturan lembur yang berlaku.', v_n));
      end if;
    else
      select count(*) into v_n
      from generate_series(v_mulai::timestamp, v_selesai::timestamp, interval '1 day') d
      cross join lateral fakta.web_hasil_hari(d::date) h
      where h.divisi = v_div and h.status in ('sakit', 'izin', 'cuti', 'dinas_luar');
      if v_n > 0 then
        v_catatan := v_catatan || to_jsonb(format('%s hari-orang sudah tercatat sakit/izin/cuti/dinas luar; catatan itu tetap berlaku.', v_n));
      end if;
      v_catatan := v_catatan || to_jsonb('Orang yang tap tetap memakai jam tap-nya; yang tidak tap dianggap hadir sesuai jadwal (asal "manual").'::text);
    end if;
    v_periode := fakta.web_periode_kena(v_mulai, v_selesai, false);
    v_isian := jsonb_build_object('mulai', v_mulai, 'selesai', v_selesai, 'divisi', v_div, 'alasan', v_alasan);
    return jsonb_build_object('hasil', 'siap', 'jenis', p_jenis, 'isian', v_isian, 'ringkas', v_ringkas, 'catatan', v_catatan,
                              'orang', v_orang, 'periode', fakta.web_periode_json(v_periode));
  end if;

  -- Berhenti, aktif kembali, mutasi: satu orang, berlaku sejak satu tanggal.
  v_t := v_mulai;
  select k.nama into v_nama from induk.karyawan k where k.id = v_id;
  if v_nama is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Karyawan %s tidak ada.', coalesce(v_id, '(kosong)')));
  end if;
  v_tolak := fakta.web_cek_sejak(v_t, true);
  if v_tolak is not null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', v_tolak);
  end if;

  if p_jenis = 'berhenti' then
    if not fakta.karyawan_aktif(v_id, v_t) then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('%s %s tidak aktif pada %s.', v_id, v_nama, fakta.tgl(v_t)));
    end if;
    select s.* into v_s from induk.status_kerja s where s.id_karyawan = v_id and s.tanggal >= v_t order by s.tanggal limit 1;
    if v_s.id is not null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan',
        format('Sudah ada catatan "%s" %s pada %s; tanggal berhenti harus sesudahnya.', replace(v_s.jenis, '_', ' '), v_id, fakta.tgl(v_s.tanggal)));
    end if;
    select count(*), max(t.jam_lokal)::date into v_n, v_x
    from fakta.tap_mentah t
    join induk.pemetaan_id_mesin pm on pm.mesin = t.mesin and pm.id_mesin = t.id_mesin and pm.id_karyawan = v_id
     and daterange(pm.berlaku_dari, pm.berlaku_sampai, '[)') @> t.jam_lokal::date
    where t.jam_lokal >= (v_t + 1)::timestamp;
    if v_n > 0 then
      v_catatan := v_catatan || to_jsonb(format('PERHATIAN: ada %s tap sesudah %s (terakhir %s). Tap itu tidak dihitung dan tidak dibayar. '
                                                'Periksa lagi tanggalnya bila orang ini masih bekerja sesudah %s.', v_n, fakta.tgl(v_t), fakta.tgl(v_x), fakta.tgl(v_t)));
    end if;
    if (fakta.periode_tanggal(v_t)).id is not null then
      v_catatan := v_catatan || to_jsonb(format('Periode no. %s menjadi masa pajak terakhir orang ini: PPh 21-nya dihitung ulang setahun.',
                                                (fakta.periode_tanggal(v_t)).id));
    end if;
    v_ringkas := format('Berhenti %s %s, hari kerja terakhir %s', v_id, v_nama, fakta.tgl(v_t));
  elsif p_jenis = 'aktif_kembali' then
    select s.* into v_s from induk.status_kerja s where s.id_karyawan = v_id order by s.tanggal desc, s.id desc limit 1;
    if v_s.id is null or v_s.jenis <> 'berhenti' then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('%s %s tidak sedang berhenti.', v_id, v_nama));
    end if;
    if v_t <= v_s.tanggal then
      return jsonb_build_object('hasil', 'ditolak', 'alasan',
        format('Tanggal mulai lagi harus sesudah hari kerja terakhir (%s).', fakta.tgl(v_s.tanggal)));
    end if;
    if not exists (select 1 from induk.karyawan_riwayat r where r.id_karyawan = v_id
                     and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v_t and r.berlaku_sampai is null) then
      return jsonb_build_object('hasil', 'ditolak', 'alasan',
        'Data divisi/gaji orang ini tidak berlaku terbuka sejak tanggal itu; perlu ubah data karyawan (paket 9b-2).');
    end if;
    if not exists (select 1 from induk.pemetaan_id_mesin pm where pm.id_karyawan = v_id
                     and daterange(pm.berlaku_dari, pm.berlaku_sampai, '[)') @> v_t) then
      v_catatan := v_catatan || to_jsonb('PERHATIAN: orang ini tidak punya ID mesin yang berlaku; tap-nya tidak akan dikenali.'::text);
    end if;
    v_catatan := v_catatan || to_jsonb(format('Divisi, regu, gaji, dan ID mesin lama dipakai lagi; tap sejak %s dihitung.', fakta.tgl(v_t)));
    v_ringkas := format('Aktif kembali %s %s, mulai %s', v_id, v_nama, fakta.tgl(v_t));
  else
    -- Mutasi.
    if not fakta.karyawan_aktif(v_id, v_t) then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('%s %s tidak aktif pada %s.', v_id, v_nama, fakta.tgl(v_t)));
    end if;
    select r.* into v_r0 from induk.karyawan_riwayat r
    where r.id_karyawan = v_id and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v_t;
    if v_r0.id is null or v_r0.berlaku_sampai is not null or v_r0.berlaku_dari >= v_t then
      return jsonb_build_object('hasil', 'ditolak', 'alasan',
        format('Sudah ada perubahan data %s pada atau sesudah %s; mutasi harus sesudah perubahan terakhir.', v_id, fakta.tgl(v_t)));
    end if;
    select d.* into v_d from induk.divisi d where d.kode = coalesce(v_div, v_r0.divisi);
    if v_d.kode is null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Divisi %s tidak ada.', v_div));
    end if;
    select g.* into v_g0 from induk.penugasan_regu g
    where g.id_karyawan = v_id and daterange(g.berlaku_dari, g.berlaku_sampai, '[)') @> v_t;
    v_div_ubah := v_d.kode <> v_r0.divisi;
    if v_d.pola = 'mingguan' then
      if v_regu is not null and v_regu <> 0 then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Divisi %s tidak memakai regu (jadwal mingguan).', v_d.nama));
      end if;
      v_regu := 0;
    else
      if v_regu is null and v_div_ubah then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Pilih regu di divisi %s (1–%s).', v_d.nama, v_d.jumlah_regu));
      end if;
      v_regu := coalesce(v_regu, v_g0.regu, 0);
      if v_regu < 1 or v_regu > v_d.jumlah_regu then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Regu di divisi %s harus 1–%s.', v_d.nama, v_d.jumlah_regu));
      end if;
    end if;
    v_regu_ubah := v_regu <> coalesce(v_g0.regu, 0);
    v_jab_ubah := v_jabatan is not null and v_jabatan is distinct from v_r0.jabatan;
    if not (v_div_ubah or v_regu_ubah or v_jab_ubah) then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tidak ada yang berubah (divisi, regu, dan jabatan sama dengan sekarang).');
    end if;
    if v_regu_ubah then
      if v_g0.id is not null and (v_g0.berlaku_sampai is not null or v_g0.berlaku_dari >= v_t) then
        return jsonb_build_object('hasil', 'ditolak', 'alasan',
          format('Sudah ada perubahan regu %s pada atau sesudah %s; mutasi harus sesudah perubahan terakhir.', v_id, fakta.tgl(v_t)));
      end if;
      if v_g0.id is null and exists (select 1 from induk.penugasan_regu g where g.id_karyawan = v_id and g.berlaku_dari >= v_t) then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Sudah ada perubahan regu %s sesudah %s.', v_id, fakta.tgl(v_t)));
      end if;
    end if;
    -- C7: divisi baru memakai mesin lain -> ID di mesin itu wajib (kecuali sudah punya).
    v_mesin_lama := (select d.mesin_utama from induk.divisi d where d.kode = v_r0.divisi);
    if v_div_ubah and v_d.mesin_utama is not null and v_d.mesin_utama is distinct from v_mesin_lama
       and not exists (select 1 from induk.pemetaan_id_mesin pm where pm.id_karyawan = v_id and pm.mesin = v_d.mesin_utama
                         and daterange(pm.berlaku_dari, pm.berlaku_sampai, '[)') @> v_t and pm.berlaku_sampai is null) then
      if v_id_mesin is null then
        return jsonb_build_object('hasil', 'ditolak', 'alasan',
          format('Divisi %s memakai mesin %s, sedangkan ID %s terdaftar di mesin lain. Isi ID orang ini di mesin %s.',
                 v_d.nama, v_d.mesin_utama, v_id, v_d.mesin_utama));
      end if;
      if v_id_mesin !~ '^[0-9A-Za-z]+$' or length(v_id_mesin) > 20 then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', 'ID mesin hanya huruf dan angka, paling panjang 20.');
      end if;
      if exists (select 1 from induk.pemetaan_id_mesin pm where pm.mesin = v_d.mesin_utama and pm.id_mesin = v_id_mesin
                   and daterange(pm.berlaku_dari, pm.berlaku_sampai, '[)') && daterange(v_t, null, '[)')) then
        return jsonb_build_object('hasil', 'ditolak', 'alasan',
          format('ID %s di mesin %s sudah dipakai orang lain pada atau sesudah %s.', v_id_mesin, v_d.mesin_utama, fakta.tgl(v_t)));
      end if;
      v_perlu_mesin := true;
    end if;
    if not v_perlu_mesin then
      v_id_mesin := null;
    end if;
    v_catatan := v_catatan || to_jsonb('Gaji pokok, tunjangan, PTKP, cara bayar, rekening, BPJS, dan tanda rahasia tidak berubah (disalin apa adanya).'::text);
    v_catatan := v_catatan || to_jsonb(format('Jadwal mengikuti divisi %s%s mulai %s.', v_d.nama,
                                              case when v_d.pola = 'rotasi' then ' regu ' || v_regu else '' end, fakta.tgl(v_t)));
    if v_perlu_mesin then
      v_catatan := v_catatan || to_jsonb(format('ID mesin baru: %s di mesin %s, berlaku sejak %s.', v_id_mesin, v_d.mesin_utama, fakta.tgl(v_t)));
    end if;
    v_ringkas := format('Mutasi %s %s mulai %s: %s', v_id, v_nama, fakta.tgl(v_t), concat_ws(', ',
      case when v_div_ubah then 'divisi ' || v_r0.divisi || ' → ' || v_d.kode end,
      case when v_regu_ubah then 'regu ' || coalesce(v_g0.regu, 0) || ' → ' || v_regu end,
      case when v_jab_ubah then 'jabatan ' || coalesce(v_r0.jabatan, '-') || ' → ' || v_jabatan end));
  end if;
  v_periode := fakta.web_periode_kena(v_t, null, true);
  v_isian := jsonb_build_object('id_karyawan', v_id, 'mulai', v_t, 'alasan', v_alasan)
          || case when p_jenis = 'mutasi' then jsonb_build_object('divisi', v_d.kode, 'regu', v_regu,
                                                                  'jabatan', coalesce(v_jabatan, v_r0.jabatan), 'id_mesin', v_id_mesin,
                                                                  'div_ubah', v_div_ubah, 'regu_ubah', v_regu_ubah, 'jab_ubah', v_jab_ubah)
                  else '{}'::jsonb end;
  return jsonb_build_object('hasil', 'siap', 'jenis', p_jenis, 'isian', v_isian, 'ringkas', v_ringkas, 'catatan', v_catatan,
                            'orang', 1, 'periode', fakta.web_periode_json(v_periode)) || fakta.identitas_karyawan(v_id);
end $$;

-- ---------------------------------------------------------------------------
-- Simpan: pemeriksaan diulang, perintah dicatat, data induk diubah (dicatat per baris), periode masuk antrean.
-- ---------------------------------------------------------------------------
create function fakta.web_catat_ubah(p_perintah bigint, p_tabel text, p_baris bigint, p_aksi text, p_sampai date default null) returns void
language sql set search_path = '' as $$
  insert into fakta.perintah_web_ubah (perintah_id, tabel, baris, aksi, ditutup_ke) values (p_perintah, p_tabel, p_baris, p_aksi, p_sampai)
$$;

create function fakta.web_antrean(p_perintah bigint, p_periode bigint[]) returns void
language sql set search_path = '' as $$
  insert into fakta.antrean_kerja (periode_id, perintah_id)
  select x, p_perintah from unnest(p_periode) x
  on conflict (periode_id) where status = 'menunggu' do nothing
$$;

create function fakta.web_perintah_simpan(p_pengguna bigint, p_draf bigint) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_d fakta.draf_perintah_web;
  v_cek jsonb;
  v_i jsonb;
  v_p bigint;
  v_t date;
  v_id text;
  v_baris bigint;
  v_r0 induk.karyawan_riwayat;
  v_g0 induk.penugasan_regu;
  v_periode bigint[];
begin
  perform pg_advisory_xact_lock(hashtext('fakta.perintah_web'));
  select d.* into v_d from fakta.draf_perintah_web d where d.id = p_draf for update;
  if v_d.id is null or v_d.pengguna <> p_pengguna or v_d.selesai_pada is not null or v_d.kedaluwarsa < now() then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Pratinjau ini sudah tidak berlaku (lewat 15 menit atau sudah dipakai). Buat pratinjau lagi.');
  end if;
  v_cek := fakta.web_perintah_periksa(v_d.jenis, v_d.isian);
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  -- Isian hasil pemeriksaan ulang harus sama dengan yang dilihat HRD di pratinjau.
  if v_cek -> 'isian' <> v_d.isian then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Data berubah sejak pratinjau. Buat pratinjau lagi.');
  end if;
  v_i := v_cek -> 'isian';
  v_t := (v_i ->> 'mulai')::date;
  v_id := v_i ->> 'id_karyawan';
  perform set_config('app.pengguna', 'web:' || p_pengguna, true);
  insert into fakta.perintah_hrd (oleh, asal, jenis, id_karyawan, divisi, tanggal_mulai, tanggal_selesai, nilai, alasan)
  values (p_pengguna, 'web', v_d.jenis, v_id,
          case when v_d.jenis in ('tambah_libur', 'absen_manual', 'mutasi') then v_i ->> 'divisi' end,
          v_t, case when v_d.jenis in ('tambah_libur', 'absen_manual') then (v_i ->> 'selesai')::date end,
          case when v_d.jenis = 'mutasi' then jsonb_build_object('regu', v_i -> 'regu', 'jabatan', v_i -> 'jabatan', 'id_mesin', v_i -> 'id_mesin')::text end,
          v_i ->> 'alasan')
  returning id into v_p;

  if v_d.jenis in ('berhenti', 'aktif_kembali') then
    insert into induk.status_kerja (id_karyawan, jenis, tanggal, alasan) values (v_id, v_d.jenis, v_t, v_i ->> 'alasan')
    returning id into v_baris;
    perform fakta.web_catat_ubah(v_p, 'induk.status_kerja', v_baris, 'tambah');
  elsif v_d.jenis = 'mutasi' then
    if (v_i ->> 'div_ubah')::boolean or (v_i ->> 'jab_ubah')::boolean then
      select r.* into v_r0 from induk.karyawan_riwayat r
      where r.id_karyawan = v_id and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v_t for update;
      update induk.karyawan_riwayat set berlaku_sampai = v_t where id = v_r0.id;
      perform fakta.web_catat_ubah(v_p, 'induk.karyawan_riwayat', v_r0.id, 'tutup', v_t);
      insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, berlaku_sampai, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap,
                                          ptkp, cara_bayar, rekening_terenkripsi, wajib_tap, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan)
      values (v_id, v_t, null, v_i ->> 'divisi', v_i ->> 'jabatan', v_r0.tipe_upah, v_r0.gaji_pokok, v_r0.tunjangan_tetap,
              v_r0.ptkp, v_r0.cara_bayar, v_r0.rekening_terenkripsi, v_r0.wajib_tap, v_r0.gaji_rahasia, v_r0.bpjs_kesehatan, v_r0.bpjs_ketenagakerjaan)
      returning id into v_baris;
      perform fakta.web_catat_ubah(v_p, 'induk.karyawan_riwayat', v_baris, 'tambah');
    end if;
    if (v_i ->> 'regu_ubah')::boolean then
      select g.* into v_g0 from induk.penugasan_regu g
      where g.id_karyawan = v_id and daterange(g.berlaku_dari, g.berlaku_sampai, '[)') @> v_t for update;
      if v_g0.id is not null then
        update induk.penugasan_regu set berlaku_sampai = v_t where id = v_g0.id;
        perform fakta.web_catat_ubah(v_p, 'induk.penugasan_regu', v_g0.id, 'tutup', v_t);
      end if;
      insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari) values (v_id, (v_i ->> 'regu')::integer, v_t)
      returning id into v_baris;
      perform fakta.web_catat_ubah(v_p, 'induk.penugasan_regu', v_baris, 'tambah');
    end if;
    if v_i ->> 'id_mesin' is not null then
      insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari)
      values ((select d.mesin_utama from induk.divisi d where d.kode = v_i ->> 'divisi'), v_i ->> 'id_mesin', v_id, v_t)
      returning id into v_baris;
      perform fakta.web_catat_ubah(v_p, 'induk.pemetaan_id_mesin', v_baris, 'tambah');
    end if;
  end if;

  v_periode := array(select (x ->> 'id')::bigint from jsonb_array_elements(v_cek -> 'periode') x);
  insert into fakta.perintah_web (perintah_id, pengguna, periode, jejak_akhir, ringkas)
  values (v_p, p_pengguna, v_periode, coalesce((select max(j.id) from jejak.perubahan j), 0), v_cek ->> 'ringkas');
  perform fakta.web_antrean(v_p, v_periode);
  update fakta.draf_perintah_web set selesai_pada = now(), perintah_id = v_p where id = v_d.id;
  return jsonb_build_object('hasil', 'disimpan', 'perintah_id', v_p, 'jenis', v_d.jenis, 'ringkas', v_cek ->> 'ringkas',
                            'periode', v_cek -> 'periode');
end $$;

-- ---------------------------------------------------------------------------
-- Batalkan perintah web (C10). Ditolak bila periodenya sudah dirilis, atau bila sesudah perintah itu ada perubahan
-- apa pun (dari web, file, atau tangan) pada status kerja, riwayat, regu, atau ID mesin orang yang sama.
-- ---------------------------------------------------------------------------
create function fakta.web_perintah_batal(p_pengguna bigint, p_perintah bigint) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_x fakta.perintah_hrd;
  v_w fakta.perintah_web;
  v_tolak text;
  v_b bigint;
  v_u fakta.perintah_web_ubah;
  v_periode bigint[];
  v_ringkas text;
  v_j bigint;
begin
  perform pg_advisory_xact_lock(hashtext('fakta.perintah_web'));
  select x.* into v_x from fakta.perintah_hrd x where x.id = p_perintah;
  select w.* into v_w from fakta.perintah_web w where w.perintah_id = p_perintah;
  if v_x.id is null or v_x.asal <> 'web' or v_w.perintah_id is null or v_x.jenis = 'batalkan_perintah' then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Perintah web itu tidak ada.');
  end if;
  select b.id into v_b from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = v_x.id;
  if v_b is not null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Perintah no. %s sudah dibatalkan (perintah no. %s).', v_x.id, v_b));
  end if;
  if v_x.jenis in ('tambah_libur', 'absen_manual') then
    v_tolak := fakta.web_cek_hari(v_x.tanggal_mulai, coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai));
  else
    v_tolak := fakta.web_cek_sejak(v_x.tanggal_mulai, false);
    select min(j.id) into v_j from jejak.perubahan j
    where j.id > v_w.jejak_akhir
      and j.tabel in ('induk.status_kerja', 'induk.karyawan_riwayat', 'induk.penugasan_regu', 'induk.pemetaan_id_mesin')
      and coalesce(j.data_baru, j.data_lama) ->> 'id_karyawan' = v_x.id_karyawan
      -- Perubahan oleh perintah web lain yang sudah dibatalkan (perintah itu dan pembatalannya) saling meniadakan.
      and not exists (select 1 from fakta.perintah_web_ubah u
                      join fakta.perintah_hrd q on q.id = u.perintah_id
                      join fakta.perintah_hrd qb on qb.jenis = 'batalkan_perintah' and qb.membatalkan = q.id
                      where u.perintah_id <> v_x.id and u.tabel = j.tabel
                        and u.baris = (coalesce(j.data_baru, j.data_lama) ->> 'id')::bigint
                        and j.waktu in (q.dibuat, qb.dibuat));
    if v_tolak is null and v_j is not null then
      v_tolak := format('Sesudah perintah no. %s ada perubahan lain pada data %s (status, divisi, regu, atau ID mesin). '
                        'Batalkan perubahan yang lebih baru dulu.', v_x.id, v_x.id_karyawan);
    end if;
  end if;
  if v_tolak is not null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', v_tolak);
  end if;
  perform set_config('app.pengguna', 'web:' || p_pengguna, true);
  insert into fakta.perintah_hrd (oleh, asal, jenis, id_karyawan, divisi, tanggal_mulai, tanggal_selesai, alasan, membatalkan)
  values (p_pengguna, 'web', 'batalkan_perintah', v_x.id_karyawan, v_x.divisi, v_x.tanggal_mulai, v_x.tanggal_selesai,
          'Pembatalan lewat web', v_x.id)
  returning id into v_b;
  -- Pengecualian sempit: hanya selama baris-baris perintah ini dikembalikan.
  perform set_config('app.batal_perintah_web', v_x.id::text, true);
  for v_u in select u.* from fakta.perintah_web_ubah u where u.perintah_id = v_x.id order by u.id desc loop
    if v_u.aksi = 'tambah' then
      execute format('delete from %s where id = $1', v_u.tabel) using v_u.baris;
    else
      execute format('update %s set berlaku_sampai = null where id = $1', v_u.tabel) using v_u.baris;
    end if;
  end loop;
  perform set_config('app.batal_perintah_web', '', true);
  v_periode := case when v_x.jenis in ('tambah_libur', 'absen_manual')
                    then fakta.web_periode_kena(v_x.tanggal_mulai, coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai), false)
                    else fakta.web_periode_kena(v_x.tanggal_mulai, null, true) end;
  v_ringkas := format('Pembatalan perintah no. %s (%s)', v_x.id, v_w.ringkas);
  insert into fakta.perintah_web (perintah_id, pengguna, periode, jejak_akhir, ringkas)
  values (v_b, p_pengguna, v_periode, coalesce((select max(j.id) from jejak.perubahan j), 0), v_ringkas);
  perform fakta.web_antrean(v_b, v_periode);
  return jsonb_build_object('hasil', 'dibatalkan', 'perintah_id', v_b, 'membatalkan', v_x.id, 'ringkas', v_ringkas,
                            'periode', fakta.web_periode_json(v_periode));
end $$;

-- ---------------------------------------------------------------------------
-- Daftar untuk halaman: pilihan divisi dan 30 perintah web terakhir dengan keadaan hitung ulang.
-- ---------------------------------------------------------------------------
create function fakta.web_perintah_daftar() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'hari_ini', fakta.web_hari_ini(),
    'divisi', (select coalesce(jsonb_agg(jsonb_build_object('kode', d.kode, 'nama', d.nama, 'pola', d.pola, 'jumlah_regu', d.jumlah_regu,
                                                            'mesin', d.mesin_utama) order by d.kode), '[]'::jsonb) from induk.divisi d),
    'perintah', (select coalesce(jsonb_agg(x order by (x ->> 'id')::bigint desc), '[]'::jsonb) from (
      select jsonb_build_object(
        'id', p.id, 'jenis', p.jenis, 'dibuat', p.dibuat, 'ringkas', w.ringkas, 'membatalkan', p.membatalkan,
        'oleh', coalesce(u.email, 'akun ' || u.id),
        'dibatalkan', (select b.id from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = p.id limit 1),
        'hitung', case when exists (select 1 from fakta.antrean_kerja a where a.periode_id = any (w.periode) and a.status = 'menunggu') then 'menunggu'
                       when exists (select 1 from fakta.antrean_kerja a where a.perintah_id = p.id and a.status = 'gagal') then 'gagal'
                       else 'selesai' end,
        'periode', fakta.web_periode_json(w.periode)) as x
      from fakta.perintah_web w
      join fakta.perintah_hrd p on p.id = w.perintah_id
      join induk.pengguna u on u.id = w.pengguna
      order by p.id desc limit 30) y))
$$;

-- ---------------------------------------------------------------------------
-- Pintu web: api.web_hrd dari 0040 ditambah aksi perintah.
-- ---------------------------------------------------------------------------
create or replace function api.web_hrd(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_s fakta.sesi_web;
  v_aksi text := coalesce(p ->> 'aksi', '');
  v_periode bigint;
  v_r jsonb;
  v_draf bigint;
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
  -- Paket 9b-1: perintah lewat web.
  if v_aksi = 'perintah_daftar' then
    return jsonb_build_object('hasil', 'ok', 'data', fakta.web_perintah_daftar());
  end if;
  if v_aksi = 'perintah_pratinjau' then
    v_r := fakta.web_perintah_periksa(p #>> '{perintah,jenis}', coalesce(p -> 'perintah', '{}'::jsonb));
    if v_r ->> 'hasil' <> 'siap' then
      return v_r;
    end if;
    insert into fakta.draf_perintah_web (pengguna, jenis, isian, kedaluwarsa)
    values (v_s.pengguna, v_r ->> 'jenis', v_r -> 'isian', now() + interval '15 minutes') returning id into v_draf;
    return jsonb_build_object('hasil', 'ok', 'data', (v_r - 'hasil') || jsonb_build_object('draf_id', v_draf));
  end if;
  if v_aksi in ('perintah_simpan', 'perintah_batal') then
    begin
      v_draf := (p #>> '{perintah,nomor}')::bigint;
    exception when others then
      v_draf := null;
    end;
    if v_draf is null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Nomor tidak terbaca.');
    end if;
    v_r := case when v_aksi = 'perintah_simpan' then fakta.web_perintah_simpan(v_s.pengguna, v_draf)
                else fakta.web_perintah_batal(v_s.pengguna, v_draf) end;
    if v_r ->> 'hasil' not in ('disimpan', 'dibatalkan') then
      return v_r;
    end if;
    return jsonb_build_object('hasil', v_r ->> 'hasil', 'data', v_r - 'hasil',
                              'telegram_id', (select u.telegram_id from induk.pengguna u where u.id = v_s.pengguna));
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

revoke all on function jejak.boleh_batal_web(text, bigint, text, date), fakta.tgl(date), fakta.web_hari_ini(),
  fakta.web_cek_hari(date, date), fakta.web_cek_sejak(date, boolean), fakta.web_periode_kena(date, date, boolean),
  fakta.web_periode_json(bigint[]), fakta.web_hasil_hari(date), fakta.web_perintah_periksa(text, jsonb),
  fakta.web_catat_ubah(bigint, text, bigint, text, date), fakta.web_antrean(bigint, bigint[]),
  fakta.web_perintah_simpan(bigint, bigint), fakta.web_perintah_batal(bigint, bigint), fakta.web_perintah_daftar() from public;
