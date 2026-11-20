# Laporan paket 8c: pesan rincian gaji ke tiap karyawan (terpasang; uji nyata berjalan)

20 November 2026 · rencana `docs/rencana-8c.md` · commit a791fc4

## Yang dibuat

- Migrasi `0029_pesan_gaji.sql` (lihat rencana), termasuk `fakta.rahasia_di_periode` (aturan F15c, sama dengan `hitung.ringkasan_terlihat`).
- `db/pasang_pintu.sh`: penjadwal `kirim-pesan-gaji` tiap menit.
- `sistem/pintu/inti.ts`: `susunPesanGaji`, `kirimAntreanGaji`, `gajiSaya`, `contohGaji`, tombol karyawan, `menu` → `/bantuan`.

## Celah yang tertangkap saat membuat [Pasti]

- Versi pertama contoh pesan memakai status rahasia di akhir periode saja; uji bot menemukan HRD bisa melihat contoh gaji orang yang dijadikan rahasia sesudah periode itu. Diperbaiki dengan aturan F15c (rahasia di hari mana pun dalam periode, atau rahasia sekarang); uji database untuk kasus ini ditambah.

## Uji yang diubah karena aturan berubah

- `db/uji/200_rilis_mudah.sql`: teks status sesudah rilis kini "Dirilis, pesan gaji sedang dikirim".
- `sistem/pintu/uji_pintu.ts` (8b-4): karyawan kini mendapat tombol tetap; akun tak dikenal tetap tanpa tombol.

## Uji [Pasti]

- Lokal: database 627 (sebelumnya 603), pintu 92 (sebelumnya 85), simulasi 128.
- Uji bisa gagal: pemeriksaan rahasia di contoh pesan dan penguncian dimatikan → 6 uji 210 GAGAL.
- GitHub run 44695671102 lulus: database 627, simulasi 128, pintu 92, penyambung 23.

## Pemasangan [Pasti]

- Pasang run 44697264021 lulus: 0029 dipasang (sidik `0e3a190326c8` = repo); pemeriksaan 33 lulus; penjadwal `kirim-pesan-gaji` (`* * * * *`) aktif dan berjalan (5 kali "succeeded" sampai 14.55 WIB; Edge Function tidak dipanggil karena tidak ada pekerjaan).
- Supabase: antrean periode 1 = 1.011 baris, periode 2 = 1.010 baris, semuanya `tanpa_akun` (belum ada akun karyawan); periode 1 dan 2 `dikunci` oleh sistem ("antrean pesan gaji selesai").
- Sheets (14.51 WIB, sama dengan gudang): periode 1 dan 2 "Dirilis, pesan gaji selesai dikirim", 3 "Bisa diajukan", 4 "rilis dulu periode no. 3". Terbitkan demo lulus.

## Belum selesai

- Uji nyata `/contohgaji` oleh pemilik.
- Gerbang Tahap 8 "pesan sampai ke akun uji": butuh akun Telegram kedua sebagai karyawan.
- Kecepatan kirim belum diukur (belum ada antrean nyata).
