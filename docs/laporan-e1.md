# Laporan paket E1: enkripsi cadangan

19 November 2026 · rencana `docs/rencana-e1.md` (di-"buat" pemilik 19 Nov 2026 15.01 WIB) · commit ae87de8 · panduan `docs/cadangan.md`

## Celah yang ditutup [Pasti]

Cadangan malam, cadangan sebelum Pasang, dan cadangan sebelum Reset menyimpan seluruh skema proyek (termasuk gaji orang rahasia) sebagai artifact GitHub tanpa enkripsi. Sebelum paket ini: 30 artifact aktif, sekitar 324 MB.

## Yang dibuat

1. `db/kunci_cadangan.sh` (`periksa`, `kunci`, `buka`): gpg simetris AES-256, kunci dari secret `CADANGAN_KUNCI` lewat pipa (tidak tampil di daftar proses atau log). Kunci kosong → GAGAL tanpa membuat file. `kunci` menghapus file asli.
2. Cadangan malam, Pasang, Reset: memeriksa kunci **sebelum** membuat cadangan, lalu hanya mengunggah `.dump.gpg`. Pasang dan Reset berhenti sebelum menyentuh Supabase bila kunci kosong.
3. Cadangan malam: uji pemulihan memakai file terenkripsi yang diunggah (buka → pulihkan → bandingkan jumlah baris). Sentuhan jalur API dan uji akses tanpa login tetap jalan walau langkah cadangan gagal.
4. `sistem/uji/uji_cadangan.sh` di workflow Uji database (9 uji).
5. Secret `CADANGAN_KUNCI` diisi pemilik 19 Nov 2026 (sekitar 15.12 WIB); kalimatnya disimpan pemilik sendiri, tidak pernah ada di chat atau repo.

## Uji [Pasti]

- Lokal: 9 lulus, 0 gagal. Cadangan Postgres sungguhan (database uji, 440.976 byte) dikunci, dibuka, lalu dipulihkan ke database kosong: 1.044 karyawan, sama dengan sumber.
- GitHub run 44484460590 lulus: uji cadangan 9, database 467, simulasi 123, pintu 48, penyambung 23. gpg tersedia di mesin GitHub.

## Bukti nyata [Pasti]

Cadangan malam dipicu lewat tombol (run 44485626472, 19 Nov 2026 15.13 WIB), lulus:
- "Kunci cadangan tersedia"; cadangan dikunci: `malam-20261119-081311.dump.gpg`, 12.872.204 byte.
- Unggahan: 1 file; artifact `cadangan-malam-42` 12.876.308 byte (selisih hanya pembungkus zip), habis 3 Des 2026.
- Uji pemulihan dari file terenkripsi: dibuka, dipulihkan ke Postgres 17 kosong, 55 tabel / 1.373.892 baris sama dengan Supabase.
- Sentuhan jalur API HTTP 200; uji akses tanpa login lulus.

Artifact tidak bisa diunduh dari lingkungan kerja Claude (jaringan menolak alamat penyimpanan GitHub), jadi isi zip dibuktikan dari log unggah (1 file) dan ukurannya, bukan dengan membukanya.

## Belum terbukti / dicatat

- Jalur "kunci kosong → Pasang dan Reset berhenti" hanya dibuktikan lewat uji skrip (kunci kosong → GAGAL), tidak dengan menjalankan Pasang tanpa secret.
- [Pasti] Secret melindungi dari unduhan artifact dan token pemicu yang bocor (isi secret tidak bisa dibaca lewat API), tidak dari orang yang bisa mengubah workflow. Untuk perusahaan sungguhan cadangan tidak disimpan di GitHub.
- [Pasti] Kalimat rahasia hilang = cadangan terenkripsi tidak bisa dibuka.
- 30 artifact lama tanpa enkripsi **dibiarkan sampai habis masa simpan** (pemilik tidak memilih penghapusan); yang terakhir habis paling lambat sekitar 19 Des 2026 [Kemungkinan Besar].

## Tidak diubah

Supabase, bot, Sheets, halaman demo.
