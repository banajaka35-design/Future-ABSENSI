-- 0042_ajukan_uang.sql
-- Paket 9b-2 (docs/rencana-9b-2.md): karyawan baru dan ubah gaji lewat web HRD. Karena mengubah uang, simpan di web
-- hanya membuat PENGAJUAN; data induk baru diubah sesudah bos atau pembangun menyetujui lewat bot dengan PIN.
-- Keputusan pemilik 25 Nov 2026 10.46 (K1-K4 sesuai saran): persetujuan PIN perlu; pembangun boleh menyetujui
-- pengajuannya sendiri (dicatat "sendiri"); di bawah UMK ditolak pada 12 bulan pertama; orang rahasia hanya pembangun.
-- Nomor rekening dan pajak awal tahun tidak termasuk. Migrasi hanya maju; jangan diedit setelah dipasang.

alter table fakta.draf_perintah_web drop constraint draf_perintah_web_jenis_check,
  add constraint draf_perintah_web_jenis_check
  check (jenis in ('tambah_libur', 'absen_manual', 'berhenti', 'aktif_kembali', 'mutasi', 'karyawan_baru', 'ubah_gaji'));

-- ---------------------------------------------------------------------------
-- Pengajuan dan keputusannya (keduanya hanya bertambah; satu keputusan per pengajuan).
-- ---------------------------------------------------------------------------
create table fakta.pengajuan_uang (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  pengaju bigint not null references induk.pengguna (id),
  jenis text not null check (jenis in ('karyawan_baru', 'ubah_gaji')),
  id_karyawan text not null,
  isian jsonb not null,
  ringkas text not null,         -- dengan angka (untuk bos/pembangun)
  ringkas_hrd text not null,     -- tanpa angka bila orang itu rahasia (F15)
  rahasia boolean not null,
  hangus_pada timestamptz not null
);
create table fakta.keputusan_uang (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  pengajuan_id bigint not null unique references fakta.pengajuan_uang (id),
  oleh bigint not null references induk.pengguna (id),
  keputusan text not null check (keputusan in ('setuju', 'tolak', 'tarik')),
  sendiri boolean not null,
  perintah_id bigint references fakta.perintah_hrd (id),
  check ((keputusan = 'setuju') = (perintah_id is not null))
);
create trigger tolak_ubah before update or delete on fakta.pengajuan_uang for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.pengajuan_uang for each statement execute function jejak.tolak_ubah();
create trigger tolak_ubah before update or delete on fakta.keputusan_uang for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.keputusan_uang for each statement execute function jejak.tolak_ubah();

-- Menunggu PIN untuk keputusan pengajuan (tombol Setujui/Tolak -> PIN), selain periode.
alter table fakta.tunggu_pin alter column periode_id drop not null,
  add column pengajuan_uang bigint references fakta.pengajuan_uang (id),
  drop constraint tunggu_pin_aksi_check,
  add constraint tunggu_pin_aksi_check check (aksi in ('rilis', 'setujui', 'tolak', 'lengkap', 'uang_setuju', 'uang_tolak')),
  add constraint tunggu_pin_sasaran_check check ((aksi like 'uang_%') = (pengajuan_uang is not null and periode_id is null));

-- Sama dengan 0031; tunggu sebelumnya untuk pengajuan uang dikosongkan supaya sasaran tidak tercampur.
create or replace function api.pintu_minta_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_aksi text := p ->> 'aksi';
begin
  if v_aksi = 'rilis' and api.pintu_hrd(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  if v_aksi in ('setujui', 'tolak') and fakta.pembangun(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  if v_aksi = 'lengkap' and fakta.bos_atau_pembangun(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  if v_aksi is null or v_aksi not in ('rilis', 'setujui', 'tolak', 'lengkap')
     or not exists (select 1 from fakta.periode x where x.id = (p ->> 'periode_id')::bigint) then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  insert into fakta.tunggu_pin (telegram_id, aksi, periode_id, batas)
  values (v_tg, v_aksi, (p ->> 'periode_id')::bigint, now() + interval '5 minutes')
  on conflict (telegram_id) do update set aksi = excluded.aksi, periode_id = excluded.periode_id, pengajuan_uang = null, batas = excluded.batas;
  return jsonb_build_object('hasil', 'menunggu', 'aksi', v_aksi, 'periode_id', (p ->> 'periode_id')::bigint);
end $$;

-- Rupiah dengan titik ribuan (tidak bergantung pengaturan bahasa server).
create function fakta.rp(p bigint) returns text
language sql immutable set search_path = '' as $$ select replace(to_char(p, 'FM999,999,999,999,999'), ',', '.') $$;

create function fakta.status_pengajuan(p_id bigint) returns text
language sql stable set search_path = '' as $$
  select coalesce((select case k.keputusan when 'setuju' then 'disetujui' when 'tolak' then 'ditolak' else 'ditarik' end
                   from fakta.keputusan_uang k where k.pengajuan_id = p_id),
                  (select case when a.hangus_pada <= now() then 'hangus' else 'menunggu' end from fakta.pengajuan_uang a where a.id = p_id))
$$;

-- ---------------------------------------------------------------------------
-- Pemeriksaan isian uang (pratinjau, ajukan, dan sekali lagi saat disetujui). Tidak mengubah apa pun.
-- p_pembangun: pengaju akun pembangun (K4: hanya pembangun untuk orang rahasia dan tanda rahasia).
-- ---------------------------------------------------------------------------
create function fakta.web_uang_periksa(p_jenis text, p jsonb, p_pembangun boolean) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_id text := nullif(upper(trim(p ->> 'id_karyawan')), '');
  v_nama text := nullif(left(trim(p ->> 'nama'), 100), '');
  v_div text := nullif(upper(trim(p ->> 'divisi')), '');
  v_alasan text := nullif(left(trim(p ->> 'alasan'), 200), '');
  v_jabatan text := nullif(left(trim(p ->> 'jabatan'), 80), '');
  v_id_mesin text := nullif(trim(p ->> 'id_mesin'), '');
  v_t date;
  v_regu integer;
  v_pokok bigint;
  v_tetap bigint;
  v_ptkp text := nullif(upper(trim(p ->> 'ptkp')), '');
  v_cara text := nullif(lower(trim(p ->> 'cara_bayar')), '');
  v_kes boolean;
  v_tk boolean;
  v_wajib boolean;
  v_rahasia boolean;
  v_umk bigint;
  v_mulai date;
  v_tolak text;
  v_catatan jsonb := '[]'::jsonb;
  v_d induk.divisi;
  v_r0 induk.karyawan_riwayat;
  v_nama_lama text;
  v_isian jsonb;
  v_ringkas text;
  v_ringkas_hrd text;
  v_periode bigint[];
  v_ubah text[] := '{}';
  v_persen numeric;
  v_rahasia_lama boolean := false;
  f_bool constant text := '^(ya|tidak|true|false)$';
begin
  if p_jenis not in ('karyawan_baru', 'ubah_gaji') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Jenis perintah tidak dikenal.');
  end if;
  begin
    v_t := nullif(p ->> 'mulai', '')::date;
    if nullif(p ->> 'regu', '') is not null then v_regu := (p ->> 'regu')::integer; end if;
    if nullif(replace(replace(p ->> 'gaji_pokok', '.', ''), ',', ''), '') is not null then
      v_pokok := replace(replace(p ->> 'gaji_pokok', '.', ''), ',', '')::bigint;
    end if;
    if nullif(replace(replace(p ->> 'tunjangan', '.', ''), ',', ''), '') is not null then
      v_tetap := replace(replace(p ->> 'tunjangan', '.', ''), ',', '')::bigint;
    end if;
  exception when others then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tanggal, regu, atau angka gaji tidak terbaca (angka tanpa huruf).');
  end;
  if coalesce(lower(p ->> 'bpjs_kesehatan'), 'ya') !~ f_bool or coalesce(lower(p ->> 'bpjs_ketenagakerjaan'), 'ya') !~ f_bool
     or coalesce(lower(p ->> 'wajib_tap'), 'ya') !~ f_bool or coalesce(lower(p ->> 'rahasia'), 'tidak') !~ f_bool then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Pilihan ya/tidak tidak terbaca.');
  end if;
  if v_t is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tanggal wajib diisi.');
  end if;
  if v_alasan is null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Keterangan/alasan wajib diisi.');
  end if;
  if v_id is null or v_id !~ '^[0-9A-Z]{1,20}$' then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'ID karyawan hanya huruf dan angka, paling panjang 20.');
  end if;
  if v_pokok is not null and (v_pokok <= 0 or v_pokok > 1000000000) or v_tetap is not null and (v_tetap < 0 or v_tetap > 1000000000) then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Gaji pokok harus lebih dari 0 dan paling banyak Rp1.000.000.000; tunjangan 0 sampai Rp1.000.000.000.');
  end if;
  if v_ptkp is not null and v_ptkp not in ('TK/0', 'TK/1', 'TK/2', 'TK/3', 'K/0', 'K/1', 'K/2', 'K/3') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'PTKP harus salah satu dari TK/0–TK/3 atau K/0–K/3.');
  end if;
  if v_cara is not null and v_cara not in ('tunai', 'transfer') then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Cara bayar harus tunai atau transfer.');
  end if;
  v_tolak := fakta.web_cek_sejak(v_t, true);
  if v_tolak is not null then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', v_tolak);
  end if;
  v_umk := (select u.nilai from aturan.upah_minimum u where daterange(u.berlaku_dari, u.berlaku_sampai, '[)') @> v_t limit 1);

  if p_jenis = 'karyawan_baru' then
    if exists (select 1 from induk.karyawan k where k.id = v_id) then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('ID %s sudah dipakai (juga bila orangnya sudah berhenti atau dibatalkan).', v_id));
    end if;
    if v_nama is null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Nama wajib diisi.');
    end if;
    if v_pokok is null or v_ptkp is null or v_cara is null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Gaji pokok, PTKP, dan cara bayar wajib diisi.');
    end if;
    v_tetap := coalesce(v_tetap, 0);
    select d.* into v_d from induk.divisi d where d.kode = v_div;
    if v_d.kode is null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Pilih divisi.');
    end if;
    if v_d.pola = 'mingguan' then
      if v_regu is not null and v_regu <> 0 then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Divisi %s tidak memakai regu (jadwal mingguan).', v_d.nama));
      end if;
      v_regu := 0;
    elsif v_regu is null or v_regu < 1 or v_regu > v_d.jumlah_regu then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Regu di divisi %s harus 1–%s.', v_d.nama, v_d.jumlah_regu));
    end if;
    v_wajib := coalesce(lower(p ->> 'wajib_tap'), 'ya') in ('ya', 'true');
    if v_id_mesin is not null or v_wajib then
      if v_id_mesin is null then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Isi ID orang ini di mesin %s (wajib tap).', v_d.mesin_utama));
      end if;
      if v_id_mesin !~ '^[0-9A-Za-z]+$' or length(v_id_mesin) > 20 then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', 'ID mesin hanya huruf dan angka, paling panjang 20.');
      end if;
      if exists (select 1 from induk.pemetaan_id_mesin pm where pm.mesin = v_d.mesin_utama and pm.id_mesin = v_id_mesin
                   and daterange(pm.berlaku_dari, pm.berlaku_sampai, '[)') && daterange(v_t, null, '[)')) then
        return jsonb_build_object('hasil', 'ditolak', 'alasan',
          format('ID %s di mesin %s sudah dipakai orang lain pada atau sesudah %s.', v_id_mesin, v_d.mesin_utama, fakta.tgl(v_t)));
      end if;
    end if;
    v_rahasia := coalesce(lower(p ->> 'rahasia'), 'tidak') in ('ya', 'true');
    if v_rahasia and not p_pembangun then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tanda gaji rahasia hanya bisa dipasang akun pembangun.');
    end if;
    -- K3: karyawan baru selalu di 12 bulan pertama.
    if v_umk is not null and v_pokok + v_tetap < v_umk then
      return jsonb_build_object('hasil', 'ditolak', 'alasan',
        format('Gaji pokok + tunjangan Rp%s di bawah UMK Rp%s; tidak boleh untuk masa kerja di bawah 1 tahun.',
               fakta.rp(v_pokok + v_tetap), fakta.rp(v_umk)));
    end if;
    v_kes := coalesce(lower(p ->> 'bpjs_kesehatan'), 'ya') in ('ya', 'true');
    v_tk := coalesce(lower(p ->> 'bpjs_ketenagakerjaan'), 'ya') in ('ya', 'true');
    v_isian := jsonb_build_object('id_karyawan', v_id, 'nama', v_nama, 'mulai', v_t, 'divisi', v_d.kode, 'regu', v_regu,
      'jabatan', v_jabatan, 'wajib_tap', v_wajib, 'id_mesin', v_id_mesin, 'mesin', case when v_id_mesin is not null then v_d.mesin_utama end,
      'gaji_pokok', v_pokok, 'tunjangan', v_tetap, 'ptkp', v_ptkp, 'cara_bayar', v_cara, 'bpjs_kesehatan', v_kes,
      'bpjs_ketenagakerjaan', v_tk, 'rahasia', v_rahasia, 'alasan', v_alasan);
    v_ringkas := format('Karyawan baru %s %s mulai %s, divisi %s%s, gaji pokok Rp%s + tunjangan Rp%s, %s, %s',
      v_id, v_nama, fakta.tgl(v_t), v_d.kode, case when v_d.pola = 'rotasi' then ' regu ' || v_regu else '' end,
      fakta.rp(v_pokok), fakta.rp(v_tetap), v_ptkp, v_cara)
      || case when v_rahasia then ', RAHASIA' else '' end;
    v_ringkas_hrd := case when v_rahasia then format('Karyawan baru %s %s mulai %s (gaji rahasia)', v_id, v_nama, fakta.tgl(v_t)) else v_ringkas end;
    if v_pokok * 4 < 3 * (v_pokok + v_tetap) then
      v_catatan := v_catatan || to_jsonb('Gaji pokok kurang dari 75% gaji pokok + tunjangan tetap; mesin hitung akan memberi tanda.'::text);
    end if;
    if (fakta.periode_tanggal(v_t)).id is not null and (fakta.periode_tanggal(v_t)).tanggal_awal < v_t then
      v_catatan := v_catatan || to_jsonb('Masuk di tengah periode: gaji periode pertama dihitung sebanding hari aktif (aturan B3).'::text);
    end if;
    v_catatan := v_catatan || to_jsonb('Nomor rekening dan penghasilan dari tempat kerja lain tahun ini belum bisa diisi lewat web.'::text);
  else
    -- Ubah gaji.
    select k.nama into v_nama_lama from induk.karyawan k where k.id = v_id;
    if v_nama_lama is null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Karyawan %s tidak ada.', v_id));
    end if;
    if not fakta.karyawan_aktif(v_id, v_t) then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', format('%s %s tidak aktif pada %s.', v_id, v_nama_lama, fakta.tgl(v_t)));
    end if;
    select r.* into v_r0 from induk.karyawan_riwayat r where r.id_karyawan = v_id and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v_t;
    if v_r0.id is null or v_r0.berlaku_sampai is not null or v_r0.berlaku_dari >= v_t then
      return jsonb_build_object('hasil', 'ditolak', 'alasan',
        format('Sudah ada perubahan data %s pada atau sesudah %s; perubahan gaji harus sesudah perubahan terakhir.', v_id, fakta.tgl(v_t)));
    end if;
    v_rahasia_lama := exists (select 1 from induk.karyawan_riwayat r where r.id_karyawan = v_id and r.gaji_rahasia);
    if v_rahasia_lama and not p_pembangun then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Gaji orang ini rahasia; hanya akun pembangun yang bisa mengubahnya.');
    end if;
    v_rahasia := case when p ->> 'rahasia' is null or p ->> 'rahasia' = '' then v_r0.gaji_rahasia else lower(p ->> 'rahasia') in ('ya', 'true') end;
    if v_rahasia is distinct from v_r0.gaji_rahasia and not p_pembangun then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tanda gaji rahasia hanya bisa diubah akun pembangun.');
    end if;
    v_pokok := coalesce(v_pokok, v_r0.gaji_pokok);
    v_tetap := coalesce(v_tetap, v_r0.tunjangan_tetap);
    v_ptkp := coalesce(v_ptkp, v_r0.ptkp);
    v_cara := coalesce(v_cara, v_r0.cara_bayar);
    v_kes := case when coalesce(p ->> 'bpjs_kesehatan', '') = '' then v_r0.bpjs_kesehatan else lower(p ->> 'bpjs_kesehatan') in ('ya', 'true') end;
    v_tk := case when coalesce(p ->> 'bpjs_ketenagakerjaan', '') = '' then v_r0.bpjs_ketenagakerjaan else lower(p ->> 'bpjs_ketenagakerjaan') in ('ya', 'true') end;
    if v_pokok <> v_r0.gaji_pokok then v_ubah := v_ubah || format('gaji pokok Rp%s → Rp%s', fakta.rp(v_r0.gaji_pokok), fakta.rp(v_pokok)); end if;
    if v_tetap <> v_r0.tunjangan_tetap then v_ubah := v_ubah || format('tunjangan Rp%s → Rp%s', fakta.rp(v_r0.tunjangan_tetap), fakta.rp(v_tetap)); end if;
    if v_ptkp <> v_r0.ptkp then v_ubah := v_ubah || format('PTKP %s → %s', v_r0.ptkp, v_ptkp); end if;
    if v_cara <> v_r0.cara_bayar then v_ubah := v_ubah || format('cara bayar %s → %s', v_r0.cara_bayar, v_cara); end if;
    if v_kes <> v_r0.bpjs_kesehatan then v_ubah := v_ubah || format('BPJS kesehatan %s', case when v_kes then 'ikut' else 'tidak ikut' end); end if;
    if v_tk <> v_r0.bpjs_ketenagakerjaan then v_ubah := v_ubah || format('BPJS ketenagakerjaan %s', case when v_tk then 'ikut' else 'tidak ikut' end); end if;
    if v_rahasia <> v_r0.gaji_rahasia then v_ubah := v_ubah || case when v_rahasia then 'gaji jadi RAHASIA' else 'tanda rahasia DICABUT' end; end if;
    if cardinality(v_ubah) = 0 then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Tidak ada yang berubah.');
    end if;
    -- K3: di bawah UMK ditolak pada 12 bulan pertama; sesudahnya peringatan.
    v_mulai := (select min(s.tanggal) from induk.status_kerja s where s.id_karyawan = v_id and s.jenis = 'mulai');
    if v_umk is not null and v_pokok + v_tetap < v_umk then
      if v_mulai is null or v_mulai > v_t - interval '12 months' then
        return jsonb_build_object('hasil', 'ditolak', 'alasan',
          format('Gaji pokok + tunjangan Rp%s di bawah UMK Rp%s; tidak boleh untuk masa kerja di bawah 1 tahun.',
                 fakta.rp(v_pokok + v_tetap), fakta.rp(v_umk)));
      end if;
      v_catatan := v_catatan || to_jsonb(format('PERHATIAN: gaji pokok + tunjangan di bawah UMK Rp%s (masa kerja sudah lebih dari 1 tahun).',
                                                fakta.rp(v_umk)));
    end if;
    v_persen := round(100.0 * ((v_pokok + v_tetap) - (v_r0.gaji_pokok + v_r0.tunjangan_tetap)) / nullif(v_r0.gaji_pokok + v_r0.tunjangan_tetap, 0), 1);
    if v_persen < 0 then
      v_catatan := v_catatan || to_jsonb(format('PERHATIAN: gaji TURUN %s%%.', abs(v_persen)));
    elsif v_persen > 50 then
      v_catatan := v_catatan || to_jsonb(format('PERHATIAN: gaji naik %s%% (lebih dari 50%%). Periksa jumlah nolnya.', v_persen));
    elsif v_persen > 0 then
      v_catatan := v_catatan || to_jsonb(format('Gaji pokok + tunjangan naik %s%%.', v_persen));
    end if;
    if v_pokok * 4 < 3 * (v_pokok + v_tetap) then
      v_catatan := v_catatan || to_jsonb('Gaji pokok kurang dari 75% gaji pokok + tunjangan tetap; mesin hitung akan memberi tanda.'::text);
    end if;
    if (fakta.periode_tanggal(v_t)).id is not null and (fakta.periode_tanggal(v_t)).tanggal_awal < v_t then
      v_catatan := v_catatan || to_jsonb('Berlaku di tengah periode: gaji periode itu dihitung per hari dengan gaji lama dan baru (aturan B3).'::text);
    end if;
    v_isian := jsonb_build_object('id_karyawan', v_id, 'mulai', v_t, 'gaji_pokok', v_pokok, 'tunjangan', v_tetap, 'ptkp', v_ptkp,
      'cara_bayar', v_cara, 'bpjs_kesehatan', v_kes, 'bpjs_ketenagakerjaan', v_tk, 'rahasia', v_rahasia, 'alasan', v_alasan);
    v_ringkas := format('Ubah gaji %s %s mulai %s: %s', v_id, v_nama_lama, fakta.tgl(v_t), array_to_string(v_ubah, ', '));
    v_ringkas_hrd := case when v_rahasia or v_rahasia_lama then format('Ubah gaji %s %s mulai %s (gaji rahasia)', v_id, v_nama_lama, fakta.tgl(v_t))
                          else v_ringkas end;
  end if;
  v_periode := fakta.web_periode_kena(v_t, null, true);
  return jsonb_build_object('hasil', 'siap', 'jenis', p_jenis, 'isian', v_isian, 'ringkas', v_ringkas, 'ringkas_hrd', v_ringkas_hrd,
                            'rahasia', coalesce(v_rahasia, false) or v_rahasia_lama, 'catatan', v_catatan, 'orang', 1,
                            'periode', fakta.web_periode_json(v_periode),
                            'penyetuju', 'bos atau pembangun, lewat bot dengan PIN');
end $$;

-- ---------------------------------------------------------------------------
-- Ajukan (dari draf web): pemeriksaan diulang, pengajuan dicatat; data induk BELUM diubah.
-- ---------------------------------------------------------------------------
create function fakta.web_uang_ajukan(p_pengguna bigint, p_d fakta.draf_perintah_web) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pembangun boolean := exists (select 1 from induk.pengguna u where u.id = p_pengguna and u.peran = 'pembangun');
  v_cek jsonb := fakta.web_uang_periksa(p_d.jenis, p_d.isian, v_pembangun);
  v_a bigint;
begin
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  if v_cek -> 'isian' <> p_d.isian then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Data berubah sejak pratinjau. Buat pratinjau lagi.');
  end if;
  perform set_config('app.pengguna', 'web:' || p_pengguna, true);
  insert into fakta.pengajuan_uang (pengaju, jenis, id_karyawan, isian, ringkas, ringkas_hrd, rahasia, hangus_pada)
  values (p_pengguna, p_d.jenis, v_cek #>> '{isian,id_karyawan}', v_cek -> 'isian', v_cek ->> 'ringkas', v_cek ->> 'ringkas_hrd',
          (v_cek ->> 'rahasia')::boolean, now() + interval '7 days')
  returning id into v_a;
  update fakta.draf_perintah_web set selesai_pada = now() where id = p_d.id;
  return jsonb_build_object('hasil', 'diajukan', 'pengajuan_id', v_a, 'ringkas', v_cek ->> 'ringkas', 'ringkas_hrd', v_cek ->> 'ringkas_hrd',
    'penerima', to_jsonb(fakta.penerima(array['bos', 'pembangun'])),
    'pengaju', (select coalesce(u.email, 'akun ' || u.id) from induk.pengguna u where u.id = p_pengguna));
end $$;

-- ---------------------------------------------------------------------------
-- Terapkan pengajuan yang disetujui: pemeriksaan diulang dengan hak pengaju, data induk diubah (dicatat per baris
-- untuk pembatalan 9b-1), periode masuk antrean.
-- ---------------------------------------------------------------------------
create function fakta.web_uang_terapkan(p_a fakta.pengajuan_uang) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_pembangun boolean := exists (select 1 from induk.pengguna u where u.id = p_a.pengaju and u.peran = 'pembangun');
  v_cek jsonb := fakta.web_uang_periksa(p_a.jenis, p_a.isian, v_pembangun);
  v_i jsonb;
  v_p bigint;
  v_t date;
  v_id text := p_a.id_karyawan;
  v_baris bigint;
  v_r0 induk.karyawan_riwayat;
  v_periode bigint[];
begin
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  if v_cek -> 'isian' <> p_a.isian then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Data karyawan berubah sejak pengajuan; pengajuan tidak berlaku lagi. HRD perlu mengajukan ulang.');
  end if;
  v_i := p_a.isian;
  v_t := (v_i ->> 'mulai')::date;
  if p_a.jenis = 'karyawan_baru' then
    -- Baris nama tidak dicatat untuk pembatalan: ID tidak dipakai ulang (rencana 9b-2).
    insert into induk.karyawan (id, nama) values (v_id, v_i ->> 'nama');
  end if;
  insert into fakta.perintah_hrd (oleh, asal, jenis, id_karyawan, divisi, tanggal_mulai, nilai, alasan)
  values (p_a.pengaju, 'web', p_a.jenis, v_id, v_i ->> 'divisi', v_t, 'pengajuan ' || p_a.id, v_i ->> 'alasan')
  returning id into v_p;
  if p_a.jenis = 'karyawan_baru' then
    insert into induk.status_kerja (id_karyawan, jenis, tanggal, alasan) values (v_id, 'mulai', v_t, v_i ->> 'alasan') returning id into v_baris;
    perform fakta.web_catat_ubah(v_p, 'induk.status_kerja', v_baris, 'tambah');
    insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                        wajib_tap, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan)
    values (v_id, v_t, v_i ->> 'divisi', v_i ->> 'jabatan', 'bulanan', (v_i ->> 'gaji_pokok')::bigint, (v_i ->> 'tunjangan')::bigint,
            v_i ->> 'ptkp', v_i ->> 'cara_bayar', (v_i ->> 'wajib_tap')::boolean, (v_i ->> 'rahasia')::boolean,
            (v_i ->> 'bpjs_kesehatan')::boolean, (v_i ->> 'bpjs_ketenagakerjaan')::boolean)
    returning id into v_baris;
    perform fakta.web_catat_ubah(v_p, 'induk.karyawan_riwayat', v_baris, 'tambah');
    insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari) values (v_id, (v_i ->> 'regu')::integer, v_t) returning id into v_baris;
    perform fakta.web_catat_ubah(v_p, 'induk.penugasan_regu', v_baris, 'tambah');
    if v_i ->> 'id_mesin' is not null then
      insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values (v_i ->> 'mesin', v_i ->> 'id_mesin', v_id, v_t)
      returning id into v_baris;
      perform fakta.web_catat_ubah(v_p, 'induk.pemetaan_id_mesin', v_baris, 'tambah');
    end if;
  else
    select r.* into v_r0 from induk.karyawan_riwayat r
    where r.id_karyawan = v_id and daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> v_t for update;
    update induk.karyawan_riwayat set berlaku_sampai = v_t where id = v_r0.id;
    perform fakta.web_catat_ubah(v_p, 'induk.karyawan_riwayat', v_r0.id, 'tutup', v_t);
    insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                        rekening_terenkripsi, wajib_tap, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan)
    values (v_id, v_t, v_r0.divisi, v_r0.jabatan, v_r0.tipe_upah, (v_i ->> 'gaji_pokok')::bigint, (v_i ->> 'tunjangan')::bigint,
            v_i ->> 'ptkp', v_i ->> 'cara_bayar', v_r0.rekening_terenkripsi, v_r0.wajib_tap, (v_i ->> 'rahasia')::boolean,
            (v_i ->> 'bpjs_kesehatan')::boolean, (v_i ->> 'bpjs_ketenagakerjaan')::boolean)
    returning id into v_baris;
    perform fakta.web_catat_ubah(v_p, 'induk.karyawan_riwayat', v_baris, 'tambah');
  end if;
  v_periode := array(select (x ->> 'id')::bigint from jsonb_array_elements(v_cek -> 'periode') x);
  insert into fakta.perintah_web (perintah_id, pengguna, periode, jejak_akhir, ringkas)
  values (v_p, p_a.pengaju, v_periode, coalesce((select max(j.id) from jejak.perubahan j), 0), p_a.ringkas_hrd);
  perform fakta.web_antrean(v_p, v_periode);
  return jsonb_build_object('hasil', 'diterapkan', 'perintah_id', v_p, 'periode', v_cek -> 'periode');
end $$;

-- ---------------------------------------------------------------------------
-- Bot: tombol Setujui/Tolak -> PIN -> keputusan.
-- ---------------------------------------------------------------------------
-- Masukan: {"telegram_id", "pengajuan_id", "setuju"}. Keluaran: {"hasil": "menunggu" | "bukan_bos" | "tidak_berlaku", ...}.
create function api.pintu_uang_minta_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_a fakta.pengajuan_uang;
begin
  if fakta.bos_atau_pembangun(v_tg) is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  select a.* into v_a from fakta.pengajuan_uang a where a.id = (p ->> 'pengajuan_id')::bigint;
  if v_a.id is null or fakta.status_pengajuan(v_a.id) <> 'menunggu' then
    return jsonb_build_object('hasil', 'tidak_berlaku', 'status', fakta.status_pengajuan(v_a.id));
  end if;
  insert into fakta.tunggu_pin (telegram_id, aksi, periode_id, pengajuan_uang, batas)
  values (v_tg, case when coalesce((p ->> 'setuju')::boolean, false) then 'uang_setuju' else 'uang_tolak' end, null, v_a.id,
          now() + interval '5 minutes')
  on conflict (telegram_id) do update set aksi = excluded.aksi, periode_id = null, pengajuan_uang = excluded.pengajuan_uang, batas = excluded.batas;
  return jsonb_build_object('hasil', 'menunggu', 'pengajuan_id', v_a.id, 'ringkas', v_a.ringkas);
end $$;

-- Sama dengan 0028, ditambah pengajuan_uang.
create or replace function api.pintu_ambil_pin(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t fakta.tunggu_pin;
begin
  delete from fakta.tunggu_pin t where t.telegram_id = (p ->> 'telegram_id')::bigint returning t.* into v_t;
  delete from fakta.tunggu_pin t where t.batas < now() - interval '1 day';
  if v_t.telegram_id is null or v_t.batas < now() then
    return case when v_t.telegram_id is null then '{}'::jsonb else jsonb_build_object('lewat', true) end;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('aksi', v_t.aksi, 'periode_id', v_t.periode_id, 'pengajuan_uang', v_t.pengajuan_uang));
end $$;

-- Masukan: {"telegram_id", "pengajuan_id", "setuju", "pin"}. Keluaran: {"hasil": "disetujui" | "ditolak" | "tidak_berlaku" |
-- "belum_ada_pin" | "pin_salah" | "terkunci" | "bukan_bos", ...}.
create function api.pintu_uang_putuskan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tg bigint := (p ->> 'telegram_id')::bigint;
  v_u bigint := fakta.bos_atau_pembangun((p ->> 'telegram_id')::bigint);
  v_a fakta.pengajuan_uang;
  v_pin text;
  v_r jsonb;
  v_setuju boolean := coalesce((p ->> 'setuju')::boolean, false);
  v_dasar jsonb;
begin
  if v_u is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  perform pg_advisory_xact_lock(hashtext('fakta.perintah_web'));
  select a.* into v_a from fakta.pengajuan_uang a where a.id = (p ->> 'pengajuan_id')::bigint for update;
  if v_a.id is null or fakta.status_pengajuan(v_a.id) <> 'menunggu' then
    return jsonb_build_object('hasil', 'tidak_berlaku', 'status', fakta.status_pengajuan(v_a.id), 'pengajuan_id', v_a.id);
  end if;
  v_pin := fakta.periksa_pin(v_u, p ->> 'pin');
  if v_pin <> 'benar' then
    return jsonb_build_object('hasil', case v_pin when 'belum_ada' then 'belum_ada_pin' when 'terkunci' then 'terkunci' else 'pin_salah' end);
  end if;
  perform set_config('app.pengguna', 'telegram:' || v_tg, true);
  v_dasar := jsonb_build_object('pengajuan_id', v_a.id, 'ringkas', v_a.ringkas, 'sendiri', v_a.pengaju = v_u,
    'pengaju_telegram', (select u.telegram_id from induk.pengguna u where u.id = v_a.pengaju and u.aktif),
    'oleh', (select u.peran from induk.pengguna u where u.id = v_u));
  if not v_setuju then
    insert into fakta.keputusan_uang (pengajuan_id, oleh, keputusan, sendiri) values (v_a.id, v_u, 'tolak', v_a.pengaju = v_u);
    return v_dasar || jsonb_build_object('hasil', 'ditolak');
  end if;
  v_r := fakta.web_uang_terapkan(v_a);
  if v_r ->> 'hasil' <> 'diterapkan' then
    return v_dasar || jsonb_build_object('hasil', 'tidak_berlaku', 'alasan', v_r ->> 'alasan');
  end if;
  insert into fakta.keputusan_uang (pengajuan_id, oleh, keputusan, sendiri, perintah_id)
  values (v_a.id, v_u, 'setuju', v_a.pengaju = v_u, (v_r ->> 'perintah_id')::bigint);
  return v_dasar || jsonb_build_object('hasil', 'disetujui', 'perintah_id', (v_r ->> 'perintah_id')::bigint, 'periode', v_r -> 'periode');
end $$;

-- /pengajuan: daftar yang menunggu (bos/pembangun). Keluaran: {"hasil": "ada" | "bukan_bos", "pengajuan": [...]}.
create function api.pintu_uang_daftar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if fakta.bos_atau_pembangun((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'bukan_bos');
  end if;
  return jsonb_build_object('hasil', 'ada', 'pengajuan', (
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'ringkas', a.ringkas, 'dibuat', a.dibuat,
                                                 'pengaju', coalesce(u.email, 'akun ' || u.id)) order by a.id), '[]'::jsonb)
    from fakta.pengajuan_uang a join induk.pengguna u on u.id = a.pengaju
    where fakta.status_pengajuan(a.id) = 'menunggu'));
end $$;

-- ---------------------------------------------------------------------------
-- Web: daftar pengajuan dan penarikan oleh pengaju.
-- ---------------------------------------------------------------------------
create function fakta.web_pengajuan_daftar(p_pembangun boolean) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(x order by (x ->> 'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('id', a.id, 'jenis', a.jenis, 'dibuat', a.dibuat,
      'ringkas', case when p_pembangun then a.ringkas else a.ringkas_hrd end,
      'pengaju', coalesce(u.email, 'akun ' || u.id), 'pengaju_id', a.pengaju, 'status', fakta.status_pengajuan(a.id),
      'diputuskan_oleh', (select coalesce(v.email, v.peran || ' ' || v.id) || case when k.sendiri then ' (sendiri)' else '' end
                          from fakta.keputusan_uang k join induk.pengguna v on v.id = k.oleh where k.pengajuan_id = a.id),
      'perintah_id', (select k.perintah_id from fakta.keputusan_uang k where k.pengajuan_id = a.id)) as x
    from fakta.pengajuan_uang a join induk.pengguna u on u.id = a.pengaju
    order by a.id desc limit 30) y
$$;

create function fakta.web_uang_tarik(p_pengguna bigint, p_id bigint) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_a fakta.pengajuan_uang;
begin
  perform pg_advisory_xact_lock(hashtext('fakta.perintah_web'));
  select a.* into v_a from fakta.pengajuan_uang a where a.id = p_id;
  if v_a.id is null or v_a.pengaju <> p_pengguna then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Pengajuan itu tidak ada atau bukan milik akun ini.');
  end if;
  if fakta.status_pengajuan(v_a.id) <> 'menunggu' then
    return jsonb_build_object('hasil', 'ditolak', 'alasan', format('Pengajuan no. %s sudah %s.', v_a.id, fakta.status_pengajuan(v_a.id)));
  end if;
  perform set_config('app.pengguna', 'web:' || p_pengguna, true);
  insert into fakta.keputusan_uang (pengajuan_id, oleh, keputusan, sendiri) values (v_a.id, p_pengguna, 'tarik', true);
  return jsonb_build_object('hasil', 'ditarik', 'pengajuan_id', v_a.id);
end $$;

-- ---------------------------------------------------------------------------
-- Pintu web: api.web_hrd dari 0041 ditambah karyawan baru, ubah gaji, dan pengajuan.
-- ---------------------------------------------------------------------------
create or replace function api.web_hrd(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_s fakta.sesi_web;
  v_aksi text := coalesce(p ->> 'aksi', '');
  v_periode bigint;
  v_r jsonb;
  v_draf bigint;
  v_pembangun boolean;
  v_d fakta.draf_perintah_web;
  v_x fakta.perintah_hrd;
begin
  select s.* into v_s from fakta.sesi_web s where s.sidik = p ->> 'sidik_sesi' for update;
  if v_s.id is null or v_s.berakhir is not null or v_s.berlaku_sampai <= now() or v_s.terakhir_dipakai <= now() - interval '30 minutes'
     or not exists (select 1 from induk.pengguna u where u.id = v_s.pengguna and u.aktif and u.peran in ('hrd', 'pembangun')) then
    return jsonb_build_object('hasil', 'sesi_tidak_berlaku');
  end if;
  v_pembangun := exists (select 1 from induk.pengguna u where u.id = v_s.pengguna and u.peran = 'pembangun');
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
  -- Paket 9b-1/9b-2: perintah lewat web.
  if v_aksi = 'perintah_daftar' then
    return jsonb_build_object('hasil', 'ok', 'data', fakta.web_perintah_daftar()
      || jsonb_build_object('pengajuan', fakta.web_pengajuan_daftar(v_pembangun), 'pembangun', v_pembangun, 'pengguna', v_s.pengguna));
  end if;
  if v_aksi = 'perintah_pratinjau' then
    if p #>> '{perintah,jenis}' in ('karyawan_baru', 'ubah_gaji') then
      v_r := fakta.web_uang_periksa(p #>> '{perintah,jenis}', coalesce(p -> 'perintah', '{}'::jsonb), v_pembangun);
    else
      v_r := fakta.web_perintah_periksa(p #>> '{perintah,jenis}', coalesce(p -> 'perintah', '{}'::jsonb));
    end if;
    if v_r ->> 'hasil' <> 'siap' then
      return v_r;
    end if;
    insert into fakta.draf_perintah_web (pengguna, jenis, isian, kedaluwarsa)
    values (v_s.pengguna, v_r ->> 'jenis', v_r -> 'isian', now() + interval '15 minutes') returning id into v_draf;
    return jsonb_build_object('hasil', 'ok', 'data', (v_r - 'hasil') || jsonb_build_object('draf_id', v_draf));
  end if;
  if v_aksi in ('perintah_simpan', 'perintah_batal', 'pengajuan_tarik') then
    begin
      v_draf := (p #>> '{perintah,nomor}')::bigint;
    exception when others then
      v_draf := null;
    end;
    if v_draf is null then
      return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Nomor tidak terbaca.');
    end if;
    if v_aksi = 'pengajuan_tarik' then
      v_r := fakta.web_uang_tarik(v_s.pengguna, v_draf);
      return case when v_r ->> 'hasil' = 'ditarik' then jsonb_build_object('hasil', 'ditarik', 'data', v_r - 'hasil') else v_r end;
    end if;
    if v_aksi = 'perintah_simpan' then
      select d.* into v_d from fakta.draf_perintah_web d where d.id = v_draf for update;
      if v_d.jenis in ('karyawan_baru', 'ubah_gaji') then
        if v_d.pengguna <> v_s.pengguna or v_d.selesai_pada is not null or v_d.kedaluwarsa < now() then
          return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Pratinjau ini sudah tidak berlaku (lewat 15 menit atau sudah dipakai). Buat pratinjau lagi.');
        end if;
        perform pg_advisory_xact_lock(hashtext('fakta.perintah_web'));
        v_r := fakta.web_uang_ajukan(v_s.pengguna, v_d);
        if v_r ->> 'hasil' <> 'diajukan' then
          return v_r;
        end if;
        return jsonb_build_object('hasil', 'diajukan', 'data', v_r - 'hasil');
      end if;
      v_r := fakta.web_perintah_simpan(v_s.pengguna, v_draf);
    else
      -- K4: perintah uang untuk orang rahasia hanya dibatalkan pembangun.
      select x.* into v_x from fakta.perintah_hrd x where x.id = v_draf;
      if v_x.jenis in ('karyawan_baru', 'ubah_gaji') and not v_pembangun
         and exists (select 1 from fakta.pengajuan_uang a join fakta.keputusan_uang k on k.pengajuan_id = a.id
                     where k.perintah_id = v_x.id and a.rahasia) then
        return jsonb_build_object('hasil', 'ditolak', 'alasan', 'Perintah ini menyangkut gaji rahasia; hanya akun pembangun yang bisa membatalkannya.');
      end if;
      v_r := fakta.web_perintah_batal(v_s.pengguna, v_draf);
    end if;
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

revoke all on function fakta.rp(bigint), fakta.status_pengajuan(bigint), fakta.web_uang_periksa(text, jsonb, boolean),
  fakta.web_uang_ajukan(bigint, fakta.draf_perintah_web), fakta.web_uang_terapkan(fakta.pengajuan_uang),
  fakta.web_pengajuan_daftar(boolean), fakta.web_uang_tarik(bigint, bigint) from public;
grant execute on function api.pintu_uang_minta_pin(jsonb), api.pintu_uang_putuskan(jsonb), api.pintu_uang_daftar(jsonb) to pintu;
