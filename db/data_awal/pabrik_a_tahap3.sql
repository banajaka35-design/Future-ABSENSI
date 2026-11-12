-- Data awal Tahap 3 untuk pemasangan demo Pabrik A (simulasi): empat periode uji.
-- Bukan migrasi: isi untuk satu pemasangan. Dijalankan sekali; dijalankan ulang ditolak aturan tumpang tindih.

begin;
set local app.pengguna = 'data-awal';

-- PRD bagian 5: tutup buku tanggal 20, gajian tanggal 25.
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-01-21', '2026-02-20', '2026-02-25'),
  ('2026-02-21', '2026-03-20', '2026-03-25'),
  ('2026-03-21', '2026-04-20', '2026-04-25'),
  ('2026-11-21', '2026-12-20', '2026-12-25');

commit;
