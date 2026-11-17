-- 0017_pintu_pembangun.sql
-- Paket 5b (keputusan pemilik 17 Nov 2026): akun dengan hak akses `pembangun` (pemilik proyek yang menguji)
-- juga boleh mengirim file ke bot, seperti HRD. Nama fungsi tetap; hanya daftar hak akses yang diperluas.
-- Migrasi hanya maju; jangan diedit setelah dipasang.

create or replace function api.pintu_hrd(p_telegram_id bigint) returns bigint
language sql stable security definer set search_path = '' as $$
  select u.id from induk.pengguna u
  where u.telegram_id = p_telegram_id and u.peran in ('hrd', 'pembangun') and u.aktif
$$;
