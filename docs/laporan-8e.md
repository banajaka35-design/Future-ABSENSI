# Laporan paket 8e: keberatan karyawan lewat bot

Rencana: `docs/rencana-8e.md`. "Buat" dari pemilik: 23 Nov 2026 14.56 WIB, dengan semua saran: batas 14 hari sesudah tanggal bayar; pilihan (i), yaitu keberatan dicatat dan diputuskan tanpa mengubah gaji; bos tidak diberi tahu.

## Yang dibuat

- Migrasi `0038_keberatan.sql`:
  - `fakta.keberatan` dan `fakta.keputusan_keberatan`, keduanya hanya bisa ditambah. Satu keberatan hanya punya satu keputusan.
  - `fakta.draf_keberatan`, berlaku 10 menit.
  - Bukti diambil dari baca tap terakhir: status hari, jadwal, jam masuk dan pulang, menit telat, pulang cepat, dan lebih, ditambah tap hari itu beserta perannya. Bukti tidak memuat angka rupiah.
  - Fungsi `api.pintu_keberatan_siapkan`, `_kirim`, `_putuskan`, dan `_daftar`.
- Bot:
  - Karyawan memakai `/keberatan <tanggal> <alasan>`, atau kata `keberatan` tanpa garis miring, lalu menekan Kirim atau Batal.
  - Tombol tetap karyawan menjadi "Gaji saya", "Keberatan", dan "Bantuan".
  - HRD dan pembangun menerima pesan dengan tombol Terima dan Tolak. Menolak harus disertai alasan, yang diketik dengan membalas pesan bot.
  - Karyawan menerima jawabannya. HRD atau pembangun lain ikut diberi tahu.
  - `/keberatan` tanpa isi menampilkan keberatan milik karyawan sendiri, atau daftar keberatan yang belum dijawab bila dipakai HRD.
  - Kalimat penutup rincian gaji diganti menjadi cara memakai `/keberatan`.

## Uji [Pasti]

| Uji | Hasil |
| --- | --- |
| Database lokal + CI (run 45136704026, commit 7785ac2) | 790 lulus, 0 gagal (24 uji baru 8e) |
| Bot lokal + CI | 119 lulus, 0 gagal (2 uji baru 8e) |
| Pasang ke Supabase (run 45138806938) | hijau; 0038 terpasang; pemeriksaan 33 lulus |
| Supabase sesudah Pasang | 0038 ada di `jejak.migrasi`; kedua tabel ada; peran `pintu` boleh memanggil fungsi baru |

Catatan saat membuat: periode 2 dan 3 sudah lewat batas 14 hari, jadi uji nyata memakai periode 4. Untuk 10735, data 21 Nov tercatat `hadir` dari mesin dan data 22 Nov tercatat `libur`.

## Uji nyata

(diisi setelah dilakukan)
