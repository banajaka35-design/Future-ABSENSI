# Rencana Tahap 8: pendaftaran karyawan dan pesan rincian gaji

19 November 2026 · acuan PRD v2 (bagian 9 celah K1, K5, K8; bagian 10 "Pesan gaji"; bagian 13 baris Tahap 8)

**Gerbang (PRD v2 bagian 13):** pesan sampai ke akun uji, dan pendaftaran dengan kode salah ditolak.

**Hasil gerbang:** "pesan sampai ke akun uji" lulus uji nyata 20 Nov 2026 15.31 WIB (akun Telegram kedua sebagai karyawan 10735, `docs/serah-terima.md`). "Pendaftaran dengan kode salah ditolak" lulus uji otomatis 8a; uji nyata menunggu akun yang belum terdaftar.

| Paket | Isi | Status |
| --- | --- | --- |
| 8a | Pendaftaran karyawan lewat bot: kode sekali pakai dari HRD, konfirmasi nama dan divisi, ganti HP lewat HRD (K1, K8) | di-"buat" 19 Nov 2026, `docs/rencana-8a.md` |
| 8b | Rilis gaji: HRD mengajukan → bos menyetujui (bila pengaturan `hrd_lalu_bos`) → HRD merilis dengan PIN, ringkasan total dan konfirmasi kedua (K5) | belum; masalah: semua periode demo "belum bisa diajukan" karena data pajak Januari tidak ada (sejak 4b-3) |
| 8c | Pesan rincian gaji ke tiap karyawan sesudah rilis (bagian 10): antrean, pesan panjang dipecah, minta ulang | terpasang 20 Nov 2026, `docs/laporan-8c.md` |
| 8d | Jalur bos: total lengkap dan gaji orang rahasia (F15, F15b); aturan "orang rahasia wajib transfer" | terpasang 20 Nov 2026 (keputusan (a) bot dengan PIN, (i) wajib transfer), `docs/laporan-8d.md` |
| 8e | Keberatan karyawan (`docs/kontrak-data.md` tabel `keberatan`) | terpasang dan lulus uji nyata 23 Nov 2026, `docs/laporan-8e.md` |
| 8f | Pembangun mencabut akun HRD/bos/karyawan (`/cabutakun`) | terpasang dan lulus uji nyata 23 Nov 2026, `docs/laporan-8f.md` |

Setiap paket punya daftar dan "buat" sendiri.
