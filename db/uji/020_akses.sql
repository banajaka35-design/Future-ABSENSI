-- Uji akses (kontrak data aturan 7; PRD celah K6): peran publik Supabase tidak bisa membaca tabel apa pun.
begin;

insert into induk.karyawan (id, nama) values ('10001', 'Andi Lubis');

select uji.harus_ditolak('akses: tanpa login (anon) tidak bisa membaca data karyawan',
  'select * from induk.karyawan', 'anon');
select uji.harus_ditolak('akses: pengguna login biasa tidak bisa membaca data karyawan langsung',
  'select * from induk.karyawan', 'authenticated');
select uji.harus_ditolak('akses: tanpa login tidak bisa membaca tap',
  'select * from fakta.tap_mentah', 'anon');
select uji.harus_ditolak('akses: tanpa login tidak bisa membaca aturan',
  'select * from aturan.pengaturan', 'anon');
select uji.harus_ditolak('akses: tanpa login tidak bisa menambah tap',
  $$insert into fakta.kiriman_file (nama_file, sidik, jenis, hasil) values ('x', repeat('d', 64), 'tap_mesin', 'diterima')$$, 'anon');
select uji.harus_ditolak('akses: tanpa login tidak bisa membaca catatan perubahan',
  'select * from jejak.perubahan', 'anon');

rollback;
