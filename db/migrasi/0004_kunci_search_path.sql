-- 0004_kunci_search_path.sql
-- Temuan penasihat keamanan Supabase (12 Nov 2026): fungsi tanpa search_path tetap bisa dibelokkan
-- ke objek palsu dengan nama sama. Semua fungsi kita sudah memakai nama lengkap schema,
-- jadi search_path dikosongkan tanpa mengubah perilaku.

alter function jejak.catat_perubahan() set search_path = '';
alter function jejak.tolak_ubah() set search_path = '';
alter function jejak.jaga_bertanggal() set search_path = '';
alter function fakta.jaga_periode() set search_path = '';
alter function fakta.ubah_status_periode(bigint, text, text, text, text) set search_path = '';
alter function induk.waktu_baku(text, timestamp) set search_path = '';
alter function induk.karyawan_pada(text, date) set search_path = '';
alter function hitung.bagi_bulat(numeric, numeric) set search_path = '';
alter function hitung.persen_dari(bigint, integer) set search_path = '';
alter function aturan.cek_nilai_pengaturan() set search_path = '';
