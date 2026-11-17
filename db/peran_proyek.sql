-- Peran database milik proyek yang dibuat migrasi (peran tidak ikut cadangan pg_dump, karena peran milik
-- seluruh server, bukan satu skema). Dijalankan sebelum memulihkan cadangan ke database baru.
--   pintu  : Edge Function pintu Telegram (migrasi 0015); kata sandinya dipasang ulang oleh db/pasang_pintu.sh.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'pintu') then
    create role pintu login noinherit;
  end if;
end $$;
