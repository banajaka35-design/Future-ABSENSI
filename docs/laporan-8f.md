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

(diisi setelah dilakukan: akun ketiga `/gabung` sebagai bos, uji bos, lalu `/cabutakun`)
