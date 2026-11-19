# Rencana paket E1: enkripsi cadangan

19 November 2026 · di-"buat" pemilik 19 Nov 2026 15.01 WIB · celah nomor 2 dari evaluasi sesudah G1-3

Ditulis sebelum kode. Yang tidak tertulis di sini tidak ikut dikerjakan.

## Celah [Pasti]

Cadangan malam (14 hari), cadangan sebelum Pasang (30 hari), dan cadangan sebelum Reset (30 hari) menyimpan seluruh skema proyek, termasuk gaji orang rahasia, sebagai artifact GitHub **tanpa enkripsi**. 19 Nov 2026: 30 artifact aktif, sekitar 324 MB. Siapa pun yang bisa membaca Actions repo ini dapat mengunduhnya, termasuk token pemicu Sheets (izin Actions) bila bocor [Kemungkinan Besar].

## Isi paket

0. Pemilik membuat secret GitHub `CADANGAN_KUNCI` (kalimat rahasia panjang) dan menyimpannya sendiri. Kalimat ini tidak pernah ditulis di chat atau repo.
1. `db/kunci_cadangan.sh kunci <file>`: enkripsi gpg simetris AES-256 dengan `CADANGAN_KUNCI` → `<file>.gpg`, file asli dihapus. `buka <file.gpg> <keluaran>`: membuka. Kunci kosong → GAGAL, tidak ada file dibuat.
2. Cadangan malam, Pasang, Reset: hanya mengunggah `.dump.gpg`. Kunci kosong → GAGAL sebelum mengunggah; Pasang dan Reset berhenti sebelum menyentuh Supabase.
3. Cadangan malam: uji pemulihan memakai file terenkripsi (buka → pulihkan → jumlah baris sama). Sentuhan jalur API dan uji akses tanpa login tetap jalan walau langkah cadangan gagal (supaya proyek gratis tidak dijeda dan gerbang "demo hidup" tetap teramati).
4. Uji otomatis `sistem/uji/uji_cadangan.sh` di workflow Uji database: kunci → buka sama persis; kalimat salah → GAGAL; file terenkripsi tanpa penanda dump Postgres dan tanpa teks data; kunci kosong → GAGAL tanpa file.
5. Bukti nyata sesudah secret diisi: picu Cadangan malam lewat tombol; artifact berakhiran `.gpg`; uji pemulihan lulus.
6. Dokumen: `docs/cadangan.md` (cara membuka cadangan secara manual), `docs/laporan-e1.md`, serah-terima.
7. Artifact lama tanpa enkripsi: **dibiarkan sampai habis masa simpan** (pemilik tidak memilih penghapusan; pilihan (b)).

Tidak diubah: Supabase, bot, Sheets, halaman demo.

## Belum pasti

- [Kemungkinan Besar] gpg sudah ada di mesin GitHub (ubuntu-latest).
- [Pasti] Secret melindungi dari unduhan artifact dan token pemicu yang bocor; tidak dari orang yang bisa mengubah workflow. Untuk perusahaan sungguhan, cadangan tidak disimpan di GitHub sama sekali.
- [Pasti] Kalimat rahasia hilang = cadangan terenkripsi tidak bisa dibuka siapa pun.
