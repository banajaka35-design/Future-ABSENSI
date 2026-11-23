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

Uji nyata dilakukan pada 23 Nov 2026 dengan akun kedua (karyawan 10735) dan akun pembangun. Semua langkah dicek di Supabase [Pasti]:

| Jam WIB | Langkah | Bukti di Supabase |
| --- | --- | --- |
| 15.42 | `/keberatan 21-11-2026 jam pulang saya salah` | Draf no. 1. Bukti sama dengan gudang (hadir; jadwal S 15.00–23.00; masuk 14.44, pulang 23.12; lebih 12 menit; 2 tap) |
| 15.43 | Karyawan menekan Kirim | Keberatan no. 1 tercatat (pengguna 2, periode 4). Draf berubah menjadi `dikirim`. Pembangun menerima pesan dengan tombol Terima/Tolak |
| 15.45–15.46 | Pembangun menekan Tolak dan membalas dengan alasan | Keputusan: ditolak, "tap pulang 23.12 sesuai mesin", oleh pengguna 1. Karyawan menerima "DITOLAK HRD" beserta alasannya |
| 15.47 | `/keberatan 23-11-2026 saya lembur tapi tidak tercatat`, lalu Kirim, lalu pembangun menekan Terima | Keberatan no. 2 diterima tanpa catatan. Pemilik melaporkan pesan di kedua akun sesuai harapan |
| Sesudahnya | Gaji tidak berubah | Sidik hasil gaji periode 4 tetap `c427e5a53c5f`. Tidak ada perintah HRD baru (nomor terakhir tetap 1611) |

**Uji nyata 8e lulus.** Keberatan no. 1 dan 2 tetap tercatat, karena data fakta hanya bertambah.
