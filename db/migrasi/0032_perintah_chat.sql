-- 0032_perintah_chat.sql
-- Paket 7a (docs/rencana-tahap-7.md bagian 5; PRD v2 bagian 13 Tahap 7): izin, sakit, cuti lewat chat, termasuk susulan.
-- Alur: bot menyiapkan draf -> HRD menekan Ya -> perintah dicatat (asal 'chat', oleh = akun) -> periode masuk antrean
-- kerja yang sama dengan file -> baca tap + hitung gaji -> bot membaca status hari itu sesudahnya.
-- Efek perintah pada hitungan sudah ada sejak Tahap 3 (perintah terbaru menang di hari yang sama); migrasi ini tidak
-- mengubah aturan hitung. Migrasi hanya maju; jangan diedit setelah dipasang.

-- ---------------------------------------------------------------------------
-- Draf: satu baris per perintah yang menunggu tombol Ya/Batal; tombol berlaku sekali dan 15 menit.
-- ---------------------------------------------------------------------------
create table fakta.draf_perintah (
  id bigint generated always as identity primary key,
  dibuat timestamptz not null default now(),
  pengguna bigint not null references induk.pengguna (id),
  jenis text not null check (jenis in ('sakit', 'izin', 'cuti')),
  id_karyawan text not null references induk.karyawan (id),
  tanggal_mulai date not null,
  tanggal_selesai date not null,
  catatan text check (catatan is null or length(catatan) <= 200),
  kedaluwarsa timestamptz not null,
  selesai_pada timestamptz,
  hasil text check (hasil in ('disimpan', 'dibatalkan')),
  perintah_id bigint references fakta.perintah_hrd (id),
  check (tanggal_selesai >= tanggal_mulai),
  check ((selesai_pada is null) = (hasil is null)),
  check ((hasil = 'disimpan') = (perintah_id is not null))
);

-- Antrean tahu asal hitung ulang (file atau perintah chat).
alter table fakta.antrean_kerja add column perintah_id bigint references fakta.perintah_hrd (id);

-- ---------------------------------------------------------------------------
-- Pembantu
-- ---------------------------------------------------------------------------

-- Periode yang memuat satu tanggal, atau null.
create function fakta.periode_tanggal(p_hari date) returns fakta.periode
language sql stable set search_path = '' as $$
  select p.* from fakta.periode p where p_hari between p.tanggal_awal and p.tanggal_akhir
$$;

-- Status satu orang per hari dari baca tap terakhir, dan perintah pribadi yang berlaku sekarang di hari itu
-- (aturan baca tap: sakit/izin/cuti/dinas luar terbaru yang tidak dibatalkan).
create function fakta.hari_perintah(p_id text, p_mulai date, p_selesai date) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'tanggal', d::date,
    'status', (select h.status from hitung.hasil_harian h
               join hitung.versi_terakhir v on v.id = h.versi_id and v.jenis = 'baca_tap'
               join fakta.periode p on p.id = v.periode_id and d::date between p.tanggal_awal and p.tanggal_akhir
               where h.id_karyawan = p_id and h.tanggal = d::date),
    'perintah_lama', (select jsonb_build_object('id', x.id, 'jenis', x.jenis) from fakta.perintah_hrd x
                      where x.id_karyawan = p_id and x.jenis in ('sakit', 'izin', 'cuti', 'dinas_luar')
                        and d::date between x.tanggal_mulai and coalesce(x.tanggal_selesai, x.tanggal_mulai)
                        and not exists (select 1 from fakta.perintah_hrd b where b.jenis = 'batalkan_perintah' and b.membatalkan = x.id)
                      order by x.id desc limit 1))
    order by d), '[]'::jsonb)
  from generate_series(p_mulai::timestamp, p_selesai::timestamp, interval '1 day') d
$$;

-- Pemeriksaan bersama siapkan dan simpan. Mengembalikan {"hasil": "siap", ...} atau penolakan dengan alasannya.
create function fakta.periksa_perintah(p_jenis text, p_id text, p_mulai date, p_selesai date) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_hari date;
  v_p fakta.periode;
  v_periode jsonb := '[]'::jsonb;
begin
  if p_jenis is null or p_jenis not in ('sakit', 'izin', 'cuti') then
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
    if not fakta.karyawan_aktif(p_id, v_hari) then
      return jsonb_build_object('hasil', 'tidak_aktif', 'tanggal', v_hari) || fakta.identitas_karyawan(p_id);
    end if;
    if not v_periode @> jsonb_build_array(jsonb_build_object('id', v_p.id)) then
      v_periode := v_periode || jsonb_build_array(jsonb_build_object('id', v_p.id, 'awal', v_p.tanggal_awal,
                                                                      'akhir', v_p.tanggal_akhir, 'status', v_p.status));
    end if;
  end loop;
  return jsonb_build_object('hasil', 'siap', 'periode', v_periode,
    'pengajuan_batal', exists (select 1 from jsonb_array_elements(v_periode) x where x ->> 'status' in ('diajukan', 'disetujui')));
end $$;

-- ---------------------------------------------------------------------------
-- Fungsi untuk bot (peran pintu)
-- ---------------------------------------------------------------------------

-- Siapkan draf. Masukan: {"telegram_id", "jenis", "id_karyawan", "mulai", "selesai", "catatan"} (tanggal yyyy-mm-dd).
-- Keluaran: {"hasil": "siap" | "bukan_hrd" | "jenis_salah" | "tidak_ada" | "tanggal_salah" | "terlalu_panjang" |
--            "tanpa_periode" | "periode_dirilis" | "tidak_aktif", ...}. Tanpa angka gaji (F15).
create function api.pintu_perintah_siapkan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_id text := upper(trim(p ->> 'id_karyawan'));
  v_mulai date;
  v_selesai date;
  v_cek jsonb;
  v_draf bigint;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  begin
    v_mulai := (p ->> 'mulai')::date;
    v_selesai := coalesce((p ->> 'selesai')::date, v_mulai);
  exception when others then
    return jsonb_build_object('hasil', 'tanggal_salah');
  end;
  v_cek := fakta.periksa_perintah(p ->> 'jenis', v_id, v_mulai, v_selesai);
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  perform set_config('app.pengguna', 'telegram:' || (p ->> 'telegram_id'), true);
  insert into fakta.draf_perintah (pengguna, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, catatan, kedaluwarsa)
  values (v_hrd, p ->> 'jenis', v_id, v_mulai, v_selesai, nullif(left(trim(p ->> 'catatan'), 200), ''), now() + interval '15 minutes')
  returning id into v_draf;
  return v_cek || jsonb_build_object('draf_id', v_draf, 'jenis', p ->> 'jenis', 'mulai', v_mulai, 'selesai', v_selesai,
    'catatan', nullif(left(trim(p ->> 'catatan'), 200), ''), 'hari', fakta.hari_perintah(v_id, v_mulai, v_selesai))
    || fakta.identitas_karyawan(v_id);
end $$;

-- Tombol Ya/Batal. Masukan: {"telegram_id", "draf_id", "ya"}. Ya: pemeriksaan diulang, status hari sebelumnya dicatat
-- untuk kabar "sebelum -> sesudah", perintah dicatat, periode yang kena
-- (dan periode sesudahnya yang sudah punya gaji dan belum dirilis) masuk antrean.
-- Keluaran: {"hasil": "disimpan" | "dibatalkan" | "tidak_berlaku" | "bukan_hrd" | penolakan periksa_perintah, ...}.
create function api.pintu_perintah_simpan(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_d fakta.draf_perintah;
  v_cek jsonb;
  v_perintah bigint;
  v_sebelum jsonb;
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
  v_cek := fakta.periksa_perintah(v_d.jenis, v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai);
  if v_cek ->> 'hasil' <> 'siap' then
    return v_cek;
  end if;
  v_sebelum := fakta.hari_perintah(v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai);
  insert into fakta.perintah_hrd (oleh, asal, jenis, id_karyawan, tanggal_mulai, tanggal_selesai, alasan)
  values (v_hrd, 'chat', v_d.jenis, v_d.id_karyawan, v_d.tanggal_mulai, v_d.tanggal_selesai, v_d.catatan)
  returning id into v_perintah;
  update fakta.draf_perintah set selesai_pada = now(), hasil = 'disimpan', perintah_id = v_perintah where id = v_d.id;
  insert into fakta.antrean_kerja (periode_id, perintah_id)
  select x.id, v_perintah
  from fakta.periode x
  where (x.tanggal_awal <= v_d.tanggal_selesai and x.tanggal_akhir >= v_d.tanggal_mulai)
     or (x.tanggal_awal > v_d.tanggal_selesai and x.status not in ('dirilis', 'dikunci')
         and exists (select 1 from hitung.versi_terakhir g where g.periode_id = x.id and g.jenis = 'hitung_gaji'))
  on conflict (periode_id) where status = 'menunggu' do nothing;
  return v_cek || jsonb_build_object('hasil', 'disimpan', 'perintah_id', v_perintah, 'jenis', v_d.jenis,
    'mulai', v_d.tanggal_mulai, 'selesai', v_d.tanggal_selesai, 'hari_sebelum', v_sebelum) || fakta.identitas_karyawan(v_d.id_karyawan);
end $$;

-- Status hari-hari perintah sesudah hitung ulang. Masukan: {"telegram_id", "perintah_id"}.
-- Keluaran: {"hasil": "ada", "hari": [...], "selesai": antrean perintah ini sudah habis, ...} atau {"hasil": "tidak_ada"}.
create function api.pintu_perintah_hasil(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hrd bigint := api.pintu_hrd((p ->> 'telegram_id')::bigint);
  v_x fakta.perintah_hrd;
begin
  if v_hrd is null then
    return jsonb_build_object('hasil', 'bukan_hrd');
  end if;
  select x.* into v_x from fakta.perintah_hrd x where x.id = (p ->> 'perintah_id')::bigint and x.asal = 'chat';
  if v_x.id is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  return jsonb_build_object('hasil', 'ada', 'perintah_id', v_x.id, 'jenis', v_x.jenis,
    'mulai', v_x.tanggal_mulai, 'selesai', coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai),
    'hari', fakta.hari_perintah(v_x.id_karyawan, v_x.tanggal_mulai, coalesce(v_x.tanggal_selesai, v_x.tanggal_mulai)),
    'selesai_dihitung', not exists (select 1 from fakta.antrean_kerja a where a.perintah_id = v_x.id and a.status = 'menunggu'),
    'gagal', exists (select 1 from fakta.antrean_kerja a where a.perintah_id = v_x.id and a.status = 'gagal'))
    || fakta.identitas_karyawan(v_x.id_karyawan);
end $$;

revoke all on function fakta.periode_tanggal(date), fakta.hari_perintah(text, date, date),
  fakta.periksa_perintah(text, text, date, date) from public;
grant execute on function api.pintu_perintah_siapkan(jsonb), api.pintu_perintah_simpan(jsonb), api.pintu_perintah_hasil(jsonb) to pintu;
