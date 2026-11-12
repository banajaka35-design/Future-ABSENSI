# Laporan uji kelayakan teknis — Tahap 1,5

12 November 2026 · acuan: PRD v3.1 aturan F1, uji U13

Tujuan: membuktikan asumsi paling berisiko sebelum membangun, yaitu apakah paket gratis sanggup menangani file mesin pabrik 1.000 karyawan.

## Hasil ukur

| No | Yang diukur | Hasil | Batas layanan | Kesimpulan |
| --- | --- | --- | --- | --- |
| 1 | Urai file .xls Pabrik A (40.567 baris, 4,4 MB) | 983 ms CPU (mode biasa), 655 ms (mode ringan) | Cloudflare Workers gratis: 10 ms CPU | **Tidak muat**, sekitar 65–100 kali di atas batas |
| 2 | Urai file .xls Pabrik B (8.082 baris, 0,9 MB) | 191 ms CPU | Cloudflare Workers gratis: 10 ms CPU | **Tidak muat** |
| 3 | Urai file .csv Pabrik A / B | 17 ms / 3 ms CPU | Cloudflare Workers gratis: 10 ms CPU | A tidak muat, B muat tanpa sisa ruang |
| 4 | Urai .xls Pabrik A di Supabase Edge Functions | Dari angka no. 1: 0,66–1,0 detik | Edge Functions gratis: 2 detik CPU, 256 MB memori | **Muat**, sisa ruang sekitar 2 kali; file 60 ribu baris akan sekitar 1–1,5 detik (tipis) |
| 5 | Baca tap satu periode Pabrik A di database Supabase gratis (46.877 tap, 23.250 hari-orang: jendela tap, buang tap dobel kurang dari 60 menit, masuk dan pulang per hari) | **0,19 detik** | Panggilan lewat API: batas 8 detik | **Muat** dengan ruang sangat lega |
| 6 | Simpan 46.877 tap ke database dengan kunci unik (tap dobel ditolak) | 0,30 detik | — | Muat |
| 7 | Ruang database per periode Pabrik A (tap + jadwal + indeks) | ±6 MB | Supabase gratis: 500 MB | Cukup untuk puluhan periode data simulasi |
| 8 | Ukuran file .xls vs batas unduh Telegram | 4,4 MB (Pabrik A). File mesin asli sekitar 2 kali lebih besar per baris, jadi file asli diperkirakan 8–13 MB | Telegram: 20 MB | Muat (Dugaan kuat untuk file asli) |
| 9 | Jumlah baris file .xls | 40.567 (Pabrik A) | Format .xls: 65.536 baris per lembar | Muat. Pabrik yang mencatat lebih dari 2 tap per hari (misalnya istirahat) bisa melewati batas ini; aplikasi mesin biasanya memecah file atau memakai .xlsx |

Angka no. 1–3 diukur di komputer kerja Claude (Intel Xeon 2,1 GHz), median dari 5 kali jalan, memakai pustaka SheetJS yang juga dipakai di Workers dan Edge Functions. Angka no. 5–7 diukur langsung di proyek Supabase banajaka35 (paket gratis, Mumbai) dengan data sintetis bervolume sama, di schema percobaan yang sudah dihapus. Waktu di server sungguhan bisa berbeda, jadi angka no. 4 harus diukur ulang di Edge Functions sungguhan saat Tahap 5.

## Yang belum diuji langsung

- **Tulis 1.000 baris ke Google Sheets.** Tidak diuji karena jalurnya (API dari server) baru ada di Tahap 6. Dipindah menjadi syarat gerbang Tahap 6.
- **Unduh file dari Telegram.** Batas 20 MB sudah Terbukti dari dokumentasi resmi (PRD bagian 15); pengunduhan sungguhan diuji di Tahap 5.

## Temuan penting

1. **Cloudflare Workers gratis tidak bisa mengurai file mesin**, bahkan untuk perusahaan 150 orang. Rancangan v3.1 (Worker mengurai file) harus diubah atau Cloudflare harus berbayar.
2. **Database Supabase gratis jauh lebih kuat dari yang dibutuhkan** untuk menghitung. Keputusan menaruh hitungan di database (PRD bagian 6) terbukti tepat.
3. **Panggilan lewat API dibatasi 8 detik per perintah.** Semua hitungan harus dirancang selesai jauh di bawah itu, atau dipecah. Hitungan satu periode saat ini 0,19 detik.

## Pilihan jalur (perlu keputusan pemilik proyek)

| Pilihan | Cara kerja | Biaya | Risiko |
| --- | --- | --- | --- |
| **1. Supabase Edge Functions mengurai** (usulan) | Webhook Telegram langsung ke Edge Function: unduh file, urai, simpan ke database; hitungan di database. Cloudflare tetap dipakai untuk halaman web | Gratis | Sisa ruang CPU sekitar 2 kali untuk Pabrik A; lega untuk pasar sasaran 50–300 orang. Kalau ukuran nyata di Tahap 5 melewati 1,5 detik, pindah ke pilihan 2 tanpa mengubah database |
| 2. Cloudflare Workers berbayar mengurai | Sesuai rancangan v3.1 | $5 per bulan | Paling lega (30 detik CPU); butuh biaya sejak awal |
| 3. HRD mengirim .csv | Worker gratis hanya meneruskan, database mengurai teks | Gratis | Menambah langkah bagi HRD dan membuka risiko file dibuka di Excel (celah M1). Tidak disarankan |

**Keputusan (12 November 2026): pilihan 1, Supabase Edge Functions.** Gerbang Tahap 1,5 terpenuhi. Ukuran CPU urai di Edge Functions sungguhan menjadi syarat gerbang Tahap 5.
