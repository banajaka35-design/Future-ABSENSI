-- 0033_batal_perintah.sql
-- Paket 7d (docs/rencana-tahap-7.md bagian 7): membatalkan perintah sakit/izin/cuti lewat chat, daftar perintah chat
-- terakhir, dan perbaikan temuan uji nyata 7a: konfirmasi menyebut semua periode yang dihitung ulang (termasuk periode
-- sesudahnya yang sudah punya gaji). Pembatalan dicatat sebagai perintah 'batalkan_perintah' (kolom membatalkan) yang
-- sudah dihormati baca tap dan hitung gaji sejak Tahap 3; fakta tetap hanya bertambah. Migrasi hanya maju.

-- ---------------------------------------------------------------------------
-- Draf boleh berisi pembatalan
-- ---------------------------------------------------------------------------
alter table fakta.draf_perintah add column membatalkan bigint references fakta.perintah_hrd (id);
alter table fakta.draf_perintah drop constraint draf_perintah_jenis_check;
alter table fakta.draf_perintah add constraint draf_perintah_jenis_check
  check (jenis in ('sakit', 'izin', 'cuti', 'batalkan_perintah'));
alter table fakta.draf_perintah add constraint draf_perintah_membatalkan_check
  check ((jenis = 'batalkan_perintah') = (membatalkan is not null));

-- ---------------------------------------------------------------------------
-- Periode yang dihitung ulang bila perintah di rentang ini dicatat: yang memuat rentang, ditambah periode sesudahnya
-- yang sudah punya gaji dan belum dirilis/dikunci (sisa pembulatan dan kasbon berantai, aturan J4). Satu sumber untuk
-- teks konfirmasi dan isi antrean.
-- ---------------------------------------------------------------------------
create function fakta.periode_hitung_ulang(p_mulai date, p_selesai date) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'awal', x.tanggal_awal, 'akhir', x.tanggal_akhir, 'status', x.status)
                            order by x.tanggal_awal), '[]'::jsonb)
  from fakta.periode x
  where (x.tanggal_awal <= p_selesai and x.tanggal_akhir >= p_mulai)
     or (x.tanggal_awal > p_selesai and x.status not in ('dirilis', 'dikunci')
         and exists (select 1 from hitung.versi_terakhir g where g.periode_id = x.id and g.jenis = 'hitung_gaji'))
$$;

-- periksa_perintah: sama dengan 0032, ditambah 'periode_ulang' (semua periode yang akan dihitung ulang).
-- Jenis 'batalkan_perintah' diperiksa dengan aturan tanggal yang sama.
create or replace function fakta.periksa_perintah(p_jenis text, p_id text, p_mulai date, p_selesai date) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_hari date;
  v_p fakta.periode;
  v_periode jsonb := '[]'::jsonb;
  v_ulang jsonb;
begin
  if p_jenis is null or p_jenis not in ('sakit', 'izin', 'cuti', 'batalkan_perintah') then
    return jsonb_build_object('hasil', 'jenis_salah');
  end if;
  if p_id is null or not exists (select 1 from induk.karyawan k where k.id = p_id) then
    return jsonb_build_object('hasil', 'tidak_ada', 'id', p_id);
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
    -- Pembatalan boleh untuk hari yang orangnya sudah tidak aktif: mengembalikan hari itu ke hasil tap.
    if p_jenis <> 'batalkan_perintah' and not fakta.karyawan_aktif(p_id, v_hari) then
      return jsonb_build_object('hasil', 'tidak_aktif', 'tanggal', v_hari) || fakta.identitas_karyawan(p_id);
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

-- ---------------------------------------------------------------------------
-- Siapkan pembatalan. Masukan: {"telegram_id", "perintah_id"}.
-- Keluaran: {"hasil": "siap" | "bukan_hrd" | "tidak_ada_perintah" | "jenis_tidak_bisa" | "sudah_dibatalkan" |
--            penolakan periksa_perintah, ...}. Tanpa angka gaji (F15).
-- ---------------------------------------------------------------------------
create function api.pintu_batal_siapkan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_x fakta.perintah_hrd;
  v_selesai date;
  v_batal bigint;
  v_cek jsonb;
  v_draf bigint;
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
  if v_x.jenis not in ('sakit', 'izin', 'cuti') or v_x.id_karyawan is null or v_x.tanggal_mulai is null then
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
  return v_cek || jsonb_build_object('draf_id', v_draf, 'jenis', 'batalkan_perintah', 'mulai', v_x.tanggal_mulai, 'selesai', v_selesai,
    'dibatalkan', jsonb_build_object('id', v_x.id, 'jenis', v_x.jenis, 'asal', v_x.asal, 'alasan', v_x.alasan),
    'hari', fakta.hari_perintah(v_x.id_karyawan, v_x.tanggal_mulai, v_selesai)) || fakta.identitas_karyawan(v_x.id_karyawan);
end $$;

-- ---------------------------------------------------------------------------
-- Simpan (tombol Ya/Batal), menggantikan versi 0032: sekarang juga untuk draf pembatalan, dan antrean memakai
-- fakta.periode_hitung_ulang (isi sama dengan 0032).
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
    -- kunci perintah yang dibatalkan supaya dua pembatalan bersamaan tidak sama-sama tercatat
    perform 1 from fakta.perintah_hrd x where x.id = v_d.membatalkan for update;
    select b.id into v_batal from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = v_d.membatalkan limit 1;
    if v_batal is not null then
      return jsonb_build_object('hasil', 'sudah_dibatalkan', 'perintah_id', v_d.membatalkan, 'oleh_perintah', v_batal);
    end if;
  end if;
  v_cek := fakta.periksa_perintah(v_d.jenis, v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai);
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  v_sebelum := fakta.hari_perintah(v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai);
  insert into fakta.perintah_hrd (oleh, asal, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, alasan, membatalkan)
  values (v_hrd, 'chat', v_d.jenis, v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai, v_d.catatan, v_d.membatalkan)
  returning id into v_perintah;
  update fakta.draf_perintah set selesai_pada = now(), hasil = 'disimpan', perintah_id = v_perintah where id = v_d.id;
  insert into fakta.antrean_kerja (periode_id, perintah_id)
  select (x ->> 'id')::bigint, v_perintah from jsonb_array_elements(v_cek -> 'periode_ulang') x
  on conflict (periode_id) where status = 'menunggu' do nothing;
  return v_cek || jsonb_build_object('hasil', 'disimpan', 'perintah_id', v_perintah, 'jenis', v_d.jenis,
    'mulai', v_d.tanggal_mulai, 'selesai', v_d.tanggal_selesai, 'membatalkan', v_d.membatalkan, 'hari_sebelum', v_sebelum)
    || fakta.identitas_karyawan(v_d.id_karyawan);
end $$;

-- ---------------------------------------------------------------------------
-- 10 perintah chat terakhir (semua akun HRD/pembangun). Masukan: {"telegram_id"}. Tanpa angka gaji.
-- ---------------------------------------------------------------------------
create function api.pintu_perintah_terakhir(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  return jsonb_build_object('hasil', 'ada', 'daftar', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id, 'jenis', x.jenis, 'id_karyawan', x.id_karyawan, 'nama', k.nama,
      'mulai', x.tanggal_mulai, 'selesai', coalesce(x.tanggal_selesai, x.tanggal_mulai),
      'membatalkan', x.membatalkan, 'oleh', u.peran, 'saya', u.id = v_hrd,
      'dibuat', to_char(x.dibuat at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI'),
      'dibatalkan_oleh', (select min(b.id) from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = x.id))
      order by x.id desc)
    from (select * from fakta.perintah_hrd where asal = 'chat' order by id desc limit 10) x
    left join induk.karyawan k on k.id = x.id_karyawan
    left join induk.pengguna u on u.id = x.oleh), '[]'::jsonb));
end $$;

revoke all on function fakta.periode_hitung_ulang(date, date) from public;
grant execute on function api.pintu_batal_siapkan(jsonb), api.pintu_perintah_terakhir(jsonb) to pintu;
