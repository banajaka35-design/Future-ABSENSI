# Laporan paket 8f: pembangun bisa mencabut akun

Rencana: `docs/rencana-8f.md`. "Buat" dari pemilik: 23 Nov 2026 14.06 WIB.

## Yang dibuat

- Migrasi `0037_cabut_akun.sql`: tabel `fakta.cabut_akun` (hanya bertambah), `api.pintu_cabut_daftar`, `api.pintu_cabut_akun`. Akun yang dicabut menjadi nonaktif, PIN-nya dihapus, dan Telegram serta email-nya dilepas, sehingga HP atau email yang sama bisa bergabung atau mendaftar lagi. Draf perintah yang masih terbuka, tunggu PIN, dan kode email yang belum dipakai ditutup. Akun pembangun tidak bisa dicabut.
- Bot: `/cabutakun` (atau kata "cabut akun") khusus pembangun. Alurnya: tombol pilih akun, lalu tombol "Ya, cabut" / "Tidak". Akun yang dicabut diberi tahu, tombol tetapnya dihapus, dan menunya kembali ke menu umum. Perintah ini ditambahkan ke menu dan teks bantuan pembangun.

## Uji [Pasti]

| Uji | Hasil |
| --- | --- |
| Database lokal + CI (run 45129798495, commit dece9f2) | 766 lulus, 0 gagal (18 uji baru 8f) |
| Bot lokal + CI | 117 lulus, 0 gagal (1 uji baru 8f) |
| Pasang ke Supabase (run 45131949331) | hijau; 0037 terpasang; pemeriksaan 33 lulus; menu bot dipasang ulang |
| Supabase sesudah Pasang | `jejak.migrasi` memuat 0037, `fakta.cabut_akun` ada (0 baris), peran `pintu` boleh memanggil `api.pintu_cabut_akun` |

## Uji nyata

Uji nyata 23 Nov 2026 dengan akun Telegram ketiga milik pemilik, semuanya dicek di Supabase [Pasti]:

| Jam WIB | Langkah | Bukti di Supabase / Sheets |
| --- | --- | --- |
| 14.00 | `/daftar salah12345` dari akun ketiga | ditolak; `fakta.percobaan_daftar` no. 2 berhasil = false; akun tetap 2 |
| 14.40–14.42 | `/undang bos` → `/gabung` akun ketiga | undangan no. 2 dipakai akun no. 3 (bos, Telegram ...9322); undangan no. 1 (14.01) dibiarkan hangus |
| 14.43 | `/pin` bos | `pin_tersamar` bcrypt 60 karakter |
| 14.44 | pembangun mengajukan periode 3 | pengajuan no. 4, versi gaji 45, status `diajukan` |
| 14.45 | bos menekan Setujui + PIN | status `disetujui`, "disetujui bos" oleh pengguna 3; angka bot (1.007 orang, bersih 5.691.968.045, transfer 4.994.759.580, tunai 697.207.000, 3 rahasia) sama dengan gudang |
| 14.47 | bos Total lengkap periode 3 + PIN | `fakta.lihat_rahasia` no. 2 (pengguna 3, periode 3, versi 45); angka yang diharapkan: 1.010 orang, bersih 5.707.653.408, transfer 5.010.444.943, tunai 697.207.000; pemilik melanjutkan tanpa melaporkan beda [Kemungkinan Besar cocok] |
| 14.48 | pembangun `/batal 3` | status kembali `dihitung` ("dibatalkan pembangun"); tidak ada yang dirilis |
| 14.50 | Sheets otomatis | Ringkasan: SELESAI 14.50.07, periode 3 total bersih 5.691.968.045 = gudang |
| 14.50 | pembangun `/cabutakun` → bos ...9322 → Ya | `fakta.cabut_akun` no. 1; akun no. 3 nonaktif, Telegram dan PIN kosong; tunggu PIN 0 |

**Uji nyata 8f lulus. Sisa Tahap 8 (gerbang kode salah ditolak, undang/gabung bos, bos menyetujui, bos melihat total lengkap) lulus.** Keadaan sesudahnya: akun aktif = pembangun dan karyawan 10735, sama dengan sebelum uji.
