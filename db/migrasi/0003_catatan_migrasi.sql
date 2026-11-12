-- 0003_catatan_migrasi.sql
-- Catatan migrasi yang sudah terpasang, supaya alur pemasangan tahu file mana yang belum dijalankan
-- dan menolak file yang isinya berubah setelah dipasang (aturan F13).

create table jejak.migrasi (
  nama text primary key,
  sidik text not null check (sidik ~ '^[0-9a-f]{64}$'),
  dipasang timestamptz not null default now()
);

create trigger tolak_ubah before update or delete on jejak.migrasi
  for each row execute function jejak.tolak_ubah();
