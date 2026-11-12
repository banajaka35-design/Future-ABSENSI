-- 0005_cabut_izin_fungsi.sql
-- Pengaman kedua (PRD celah K6): Postgres memberi izin menjalankan fungsi baru ke semua peran (PUBLIC).
-- Saat ini peran tanpa login tetap tidak bisa memakainya karena tidak boleh masuk ke skema proyek,
-- tetapi kalau suatu saat ada skema yang dibuka, semua fungsi di dalamnya langsung bisa dipanggil.
-- Izin itu dicabut untuk fungsi yang sudah ada dan untuk fungsi yang dibuat nanti.
-- Pemicu (trigger) tidak terpengaruh: izin hanya diperiksa saat pemicu dibuat, bukan saat berjalan
-- (dibuktikan di db/uji/030_akses_katalog.sql).
-- Peran yang kelak perlu memanggil fungsi tertentu diberi izin satu per satu di migrasi berikutnya.

revoke execute on all functions in schema induk, aturan, fakta, hitung, jejak, api from public;

-- Aturan bawaan untuk fungsi baru. Harus tanpa "in schema": aturan per skema hanya bisa menambah izin,
-- tidak bisa mencabut izin bawaan Postgres untuk PUBLIC. Berlaku untuk fungsi yang dibuat oleh peran
-- yang menjalankan migrasi ini (pemilik skema proyek). Di skema lain (misalnya public), Supabase
-- memberi izin kepada perannya sendiri secara terpisah, jadi tidak terpengaruh.
alter default privileges revoke execute on functions from public;
