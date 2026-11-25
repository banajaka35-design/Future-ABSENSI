# Permintaan perubahan 07: format file baru dikonfirmasi HRD sekali (kasus jebakan F09)

Diajukan 25 November 2026 (paket F2, `docs/rencana-f2-konfirmasi-format.md`) · status: **disetujui pemilik 25 Nov 2026 16.46
("setuju dan hapus", jawaban atas permintaan persetujuan PP07 dan "buat" F2 sesuai saran)**

## Latar belakang

Kasus F09 (PRD M8) menjaga agar format file mesin yang belum dikenal tidak ditebak. Paket F1 mematuhinya apa adanya (keputusan
pemilik 15.51, pilihan A). Akibatnya, menambah format baru selalu butuh pembangun. Pemilik minta bot bertanya ke HRD dengan pilihan
dan boleh diketik sendiri (15.49–15.51), supaya HRD tidak menunggu, tanpa menebak.

## Usulan

| | Bunyi F09 |
| --- | --- |
| Sebelum | File dengan kolom waktu bernama "Waktu" (format baru yang belum dikenal) → Ditolak dengan pesan format tidak dikenal; pemberitahuan segera |
| Sesudah | File dengan kolom waktu bernama "Waktu" (format baru yang belum dikenal) → **Tidak dihitung otomatis**: file ditahan, pembangun diberi tahu, dan HRD yang mengirim diminta memilih kolom sekali dengan contoh hasil bacaan. Dihitung hanya sesudah HRD menekan "Ya, simpan"; file berikutnya dari mesin yang sama dengan judul kolom yang sama dibaca dengan profil itu; judul yang berbeda ditanyakan lagi. Bila HRD menekan "Tidak", file ditolak dengan pesan format tidak dikenal dan pemberitahuan segera seperti sebelumnya |

## Dampak

- Pembaca (`sistem/urai/urai.ts`) tanpa profil tetap menolak F09 (uji pembaca F09 tidak berubah).
- Bot: percakapan konfirmasi, profil format per mesin (migrasi 0044), `/profilmesin` untuk pembangun.
- Halaman unggah web: format baru tetap ditolak dengan arahan konfirmasi lewat bot.
- Angka gaji tidak berubah untuk file yang sudah dikenali.
