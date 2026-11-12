-- 0007_sidik_zona_tetap.sql
-- Temuan 13 Nov 2026: sidik hasil hitung.baca_tap ikut berubah menurut zona waktu sesi, karena waktu
-- diubah menjadi teks memakai zona sesi (Supabase UTC, komputer kerja Asia/Jakarta). Isi hasilnya sama
-- persis; hanya sidiknya yang berbeda. Zona sesi di dalam fungsi dikunci ke UTC supaya sidik sama di
-- semua pemasangan. Semua perhitungan jam di dalam fungsi sudah memakai zona yang ditulis jelas
-- (Asia/Jakarta atau zona mesin), jadi hasilnya tidak berubah.

alter function hitung.baca_tap(bigint) set timezone = 'UTC';
