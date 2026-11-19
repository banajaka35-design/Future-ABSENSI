# Rencana Tahap 8: pendaftaran karyawan dan pesan rincian gaji

19 November 2026 · acuan PRD v2 (bagian 9 celah K1, K5, K8; bagian 10 "Pesan gaji"; bagian 13 baris Tahap 8)

**Gerbang (PRD v2 bagian 13):** pesan sampai ke akun uji, dan pendaftaran dengan kode salah ditolak.

| Paket | Isi | Status |
| --- | --- | --- |
| 8a | Pendaftaran karyawan lewat bot: kode sekali pakai dari HRD, konfirmasi nama dan divisi, ganti HP lewat HRD (K1, K8) | di-"buat" 19 Nov 2026, `docs/rencana-8a.md` |
| 8b | Rilis gaji: HRD mengajukan → bos menyetujui (bila pengaturan `hrd_lalu_bos`) → HRD merilis dengan PIN, ringkasan total dan konfirmasi kedua (K5) | belum; masalah: semua periode demo "belum bisa diajukan" karena data pajak Januari tidak ada (sejak 4b-3) |
| 8c | Pesan rincian gaji ke tiap karyawan sesudah rilis (bagian 10): antrean, pesan panjang dipecah, minta ulang | belum |
| 8d | Jalur bos: total lengkap dan gaji orang rahasia (F15, F15b); aturan "orang rahasia wajib transfer" | belum; keputusan pemilik (a) bot dengan PIN atau (b) Sheets khusus bos; saran Claude (a) |
| 8e | Keberatan karyawan (`docs/kontrak-data.md` tabel `keberatan`) | belum; [Kemungkinan Besar] bukan dari baris Tahap 8 PRD v2, ikut atau ditunda diputuskan pemilik |

Setiap paket punya daftar dan "buat" sendiri.
