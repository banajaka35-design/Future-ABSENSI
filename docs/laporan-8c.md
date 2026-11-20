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

## Paket 8c-2 (20 Nov 2026, `docs/rencana-8c-2.md`, commit de493fd)

- Uji nyata `/contohgaji 10001 2` (14.56 WIB): angka pesan sama dengan Supabase dan Sheets. Temuan: "Sisa pembulatan lalu" tidak ada di pesan (132 baris rilis bukan nol).
- Migrasi 0030 + baris pesan "Sisa pembulatan periode lalu (ditambahkan)". Uji: database 629, pintu 93; bukti gagal: kolom dihapus → 2 uji 220 GAGAL. GitHub run 44699699796 lulus; Pasang run 44701633167 lulus (sidik 0030 `a4ae29a6326d` = repo).
- Supabase: `sisa_lalu` di isi pesan sama dengan gudang untuk 2.021/2.021 baris rilis. Contoh 10735 periode 2: bersih 6.798.540 + sisa lalu 942 = dibayar 6.799.000 + sisa 482.
