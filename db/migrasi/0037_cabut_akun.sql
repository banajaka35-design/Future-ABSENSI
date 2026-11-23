-- 0037_cabut_akun.sql
-- Paket 8f (docs/rencana-8f.md): pembangun mencabut akun HRD, bos, atau karyawan lewat bot (/cabutakun).
-- Akun dinonaktifkan, PIN dihapus, Telegram dan email dilepas (agar HP/email yang sama bisa /gabung atau /daftar lagi),
-- tunggu PIN, draf perintah terbuka, dan kode email yang belum dipakai milik akun itu ditutup. Riwayat lama tetap
-- menunjuk ke nomor akun lama. Migrasi hanya maju; jangan diedit setelah dipasang.

create table fakta.cabut_akun (
  id bigint generated always as identity primary key,
  pengguna bigint not null references induk.pengguna (id),
  telegram_id_lama bigint,
  peran text not null,
  id_karyawan text,
  oleh bigint not null references induk.pengguna (id),
  waktu timestamptz not null default now()
);
create trigger tolak_ubah before update or delete on fakta.cabut_akun for each row execute function jejak.tolak_ubah();
create trigger tolak_kosongkan before truncate on fakta.cabut_akun for each statement execute function jejak.tolak_ubah();

-- Daftar akun yang bisa dicabut (aktif, bukan pembangun). Masukan: {"telegram_id"}.
-- Keluaran: {"hasil": "ada" | "bukan_pembangun", "akun": [{"id", "peran", "label"}]}.
create function api.pintu_cabut_daftar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if fakta.pembangun((p ->> 'telegram_id')::bigint) is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  return jsonb_build_object('hasil', 'ada', 'akun', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', u.id, 'peran', u.peran,
             'label', case when u.id_karyawan is not null then u.id_karyawan || ' ' || coalesce(k.nama, '')
                           else coalesce(u.email, 'Telegram ...' || right(u.telegram_id::text, 4)) end) order by u.id)
    from induk.pengguna u left join induk.karyawan k on k.id = u.id_karyawan
    where u.aktif and u.peran in ('hrd', 'bos', 'karyawan')), '[]'::jsonb));
end $$;

-- Cabut satu akun. Masukan: {"telegram_id", "pengguna_id"}.
-- Keluaran: {"hasil": "dicabut" | "bukan_pembangun" | "tidak_ada", "telegram_id" (lama), "peran", "label"}.
create function api.pintu_cabut_akun(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_oleh bigint := fakta.pembangun((p ->> 'telegram_id')::bigint);
  v_u induk.pengguna;
  v_label text;
begin
  if v_oleh is null then
    return jsonb_build_object('hasil', 'bukan_pembangun');
  end if;
  select u.* into v_u from induk.pengguna u
  where u.id = (p ->> 'pengguna_id')::bigint and u.aktif and u.peran in ('hrd', 'bos', 'karyawan') for update;
  if v_u.id is null then
    return jsonb_build_object('hasil', 'tidak_ada');
  end if;
  v_label := case when v_u.id_karyawan is not null
                  then v_u.id_karyawan || ' ' || coalesce((select k.nama from induk.karyawan k where k.id = v_u.id_karyawan), '')
                  else coalesce(v_u.email, 'Telegram ...' || right(v_u.telegram_id::text, 4)) end;
  perform set_config('app.pengguna', 'cabut-akun-telegram', true);
  update induk.pengguna set aktif = false, pin_tersamar = null, telegram_id = null, email = null where id = v_u.id;
  insert into fakta.cabut_akun (pengguna, telegram_id_lama, peran, id_karyawan, oleh)
  values (v_u.id, v_u.telegram_id, v_u.peran, v_u.id_karyawan, v_oleh);
  if v_u.telegram_id is not null then
    delete from fakta.tunggu_pin where telegram_id = v_u.telegram_id;
  end if;
  update fakta.draf_perintah set selesai_pada = now(), hasil = 'dibatalkan' where pengguna = v_u.id and selesai_pada is null;
  update fakta.kode_email set berlaku_sampai = least(berlaku_sampai, now()) where pengguna = v_u.id and dipakai is null;
  return jsonb_build_object('hasil', 'dicabut', 'telegram_id', v_u.telegram_id, 'peran', v_u.peran, 'label', v_label);
end $$;

-- ---------------------------------------------------------------------------
-- Hak akses
-- ---------------------------------------------------------------------------
grant execute on function api.pintu_cabut_daftar(jsonb), api.pintu_cabut_akun(jsonb) to pintu;
