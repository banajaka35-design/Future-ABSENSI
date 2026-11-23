# Laporan penutup Tahap 8: pendaftaran karyawan, rilis dengan PIN, pesan gaji, jalur bos, keberatan

Ditulis 23 November 2026. Acuan: PRD v2 bagian 13, baris Tahap 8. **Gerbang: pesan sampai ke akun uji, dan pendaftaran dengan kode salah ditolak.** Rencana: `docs/rencana-tahap-8.md`.

## Gerbang

| Syarat | Hasil | Label |
| --- | --- | --- |
| Pesan sampai ke akun uji | **LULUS 20 Nov 2026 15.31 WIB.** Akun Telegram kedua mendaftar sebagai karyawan 10735. Rincian gaji periode 2 terkirim otomatis dan `fakta.kirim_gaji` berubah menjadi `terkirim` (`docs/laporan-8c.md`) | [Pasti] |
| Pendaftaran dengan kode salah ditolak | **LULUS 23 Nov 2026 14.00 WIB.** `/daftar salah12345` dari akun ketiga ditolak (sisa percobaan 4). `fakta.percobaan_daftar` no. 2 tercatat `berhasil = false`, dan jumlah akun tetap 2 | [Pasti] |

## Yang dibangun

Semua paket terpasang di Supabase dan lulus uji nyata.

| Paket | Isi | Migrasi | Laporan |
| --- | --- | --- | --- |
| 8a | `/kode` dan `/daftar`: kode 60 menit sekali pakai (yang disimpan hanya sidiknya), konfirmasi nama dan divisi, 5 salah per jam lalu terkunci, ganti HP lewat HRD | 0025 | `docs/laporan-8a.md` |
| 8b, 8b-2 s.d. 8b-5 | Alur ajukan → setujui → rilis dengan PIN; pembangun boleh menyetujui; urutan rilis; `/batal`; `/hapuspin`; `/undang` dan `/gabung`; tombol tetap; Sheets ikut status | 0026–0028 | `docs/laporan-8b*.md` |
| 8c, 8c-2 | Pesan rincian gaji ke karyawan sesudah rilis, `/gaji`, sisa pembulatan | 0029–0030 | `docs/laporan-8c.md` |
| 8d, 8d-2 | Jalur bos: total lengkap termasuk orang rahasia dengan PIN (F15, F15b); orang rahasia wajib dibayar transfer | 0031 | `docs/laporan-8d.md` |
| 8f | `/cabutakun`: pembangun mencabut akun HRD, bos, atau karyawan; HP yang sama bisa bergabung lagi | 0037 | `docs/laporan-8f.md` |
| 8e | `/keberatan`: karyawan mengirim keberatan beserta bukti tap; HRD atau pembangun menerima atau menolak (tolak wajib beralasan); karyawan dikabari; gaji tidak berubah dengan sendirinya | 0038 | `docs/laporan-8e.md` |

## Bukti (diukur)

| Hal | Hasil | Label |
| --- | --- | --- |
| Uji otomatis terakhir (GitHub run 45136704026, commit 7785ac2) | Database 790, pintu 119, penyambung 23, uji pemulihan cadangan 10: semua lulus | [Pasti] |
| Bos sungguhan (akun ketiga, 23 Nov 14.40–14.50) | Bergabung lewat undangan, membuat PIN, menyetujui periode 3 dengan tombol (angka bot = gudang: 1.007 orang, bersih Rp5.691.968.045), membuka total lengkap (tercatat di `fakta.lihat_rahasia`), lalu dicabut | [Pasti] |
| Tidak ada periode yang dirilis karena uji 23 Nov | Periode 3 kembali `dihitung` sesudah `/batal 3`; Sheets cocok (SELESAI 14.50) | [Pasti] |
| Keberatan (23 Nov 15.42–15.48) | No. 1 ditolak dengan alasan, no. 2 diterima; sidik gaji periode 4 tetap `c427e5a53c5f` | [Pasti] |

## Keadaan demo sesudah Tahap 8

| Hal | Isi | Label |
| --- | --- | --- |
| Akun aktif | Pembangun (akun pemilik) dan karyawan 10735 (akun kedua). Bos uji (akun no. 3) sudah dicabut | [Pasti] |
| Periode | 1 dan 2 `dikunci` (dirilis 20 Nov); 3 dan 4 `dihitung` | [Pasti] |
| Catatan uji yang tetap ada (fakta hanya bertambah) | Undangan no. 1–2, pengajuan no. 4, `lihat_rahasia` no. 2, `cabut_akun` no. 1, keberatan no. 1–2 | [Pasti] |

## Yang tidak dikerjakan di Tahap 8

| Hal | Rencana | Label |
| --- | --- | --- |
| Koreksi otomatis untuk keberatan yang diterima di periode yang sudah dirilis (selisih dibawa ke gaji periode berikutnya) | Paket terpisah; menyangkut mesin hitung dan kasus jebakan baru (keputusan pemilik 8e (i)) | [Pasti] |
| Pengingat harian untuk keberatan yang belum dijawab | Belum ada; HRD melihat daftarnya dengan `/keberatan` | [Pasti] |
| Rincian gaji lama masih menulis "Hubungi HRD" | Pesan yang sudah terkirim tidak berubah; rincian berikutnya memakai kalimat baru | [Pasti] |
