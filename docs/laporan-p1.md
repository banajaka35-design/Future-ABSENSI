# Laporan paket P1: periode gaji bulanan otomatis

Di-"buat" 25 November 2026 14.30 WIB menurut `docs/rencana-p1-periode.md` dengan K1 (a) dan K2 (a) sesuai saran.
Commit kode 04cae46. Terpasang di Supabase 25 Nov 2026 (Pasang run 45572909077).

## Yang dibuat

- **Migrasi 0043** (`db/migrasi/0043_periode_bulanan.sql`):
  - `fakta.tutup_buku_berikut(tanggal)`: tanggal tutup buku pertama yang tidak sebelum tanggal itu (0 atau tanggal melewati
    panjang bulan = akhir bulan), menurut pengaturan yang berlaku pada tanggal itu;
  - `fakta.gajian_sesudah(tanggal_akhir)`: tanggal gajian pertama sesudah akhir periode;
  - `fakta.buat_periode_sampai(tanggal, hari_ini, alasan)`: membuat periode berurutan sesudah periode terakhir sampai periode yang
    memuat tanggal itu. Batas: tidak membuat periode yang mulai sesudah hari ini (WIB), paling banyak 2 per panggilan, tidak pernah
    membuat periode pertama, tidak mengubah periode yang ada; kunci advisory untuk file yang masuk bersamaan; setiap periode baru
    dicatat di `fakta.riwayat_status_periode` (oleh: akun pengirim, alasan: nomor kiriman);
  - `fakta.terima_file_atas_nama` (jalur bersama bot dan halaman unggah) memanggilnya sesudah file diterima, sebelum antrean
    hitung diisi; keluaran ditambah `periode_baru`. **Tidak** dipanggil dari `fakta.terima_kiriman`, sehingga pemuat data simulasi
    dan uji tidak bergantung pada tanggal hari ini (C1).
- **Bot dan halaman unggah** (`sistem/pintu/inti.ts`): balasan sesudah file tersimpan ditambah, misalnya
  "Periode baru no. 5 dibuat: 21 Des 2026 – 20 Jan 2027, gajian 25 Jan 2027."

## Hasil uji [Pasti, diukur 25 Nov]

| Uji | Hasil |
| --- | --- |
| Database lokal | 936 lulus, 0 gagal (917 + 19 baru di `db/uji/350_periode_bulanan.sql`) |
| Pintu lokal | 124 lulus, 0 gagal (123 + 1 baru) |
| GitHub "Uji database" commit 04cae46 (run 45570212601) | success: database 936, simulasi 153, pintu 124, penyambung 24, pemicu 12, pemulihan cadangan 10 |
| Pasang ke Supabase (run 45572909077) | success: 0043 terpasang, pemeriksaan data awal 33 lulus, Edge Function terpasang ulang |

Uji 350 mencakup: tanpa periode tidak membuat periode pertama; contoh Pabrik A (21 Des 2026 – 20 Jan 2027, bayar 25 Jan 2027);
tutup buku pada hari itu sendiri; batas hari ini; tap tahun 2030 hanya membuat 2 periode berurutan; pengaturan bertanggal
(tutup buku berganti menjadi akhir bulan dan gajian tanggal 5 mulai 1 Mar 2027 → 21–31 Mar, lalu 1–30 Apr); jalur file bot
membuat periode Mei 2027, mengisi antrean hitung, dan mencatat akun pengirim; file kedua di periode yang sudah ada tidak membuat apa
pun.

## Dicek langsung di Supabase sesudah Pasang [Pasti, hanya baca]

- Sidik gaji periode 1–4 tetap `d7a6e443b8c5`, `c642bd4a9b7c`, `45a6ca644ca5`, `c427e5a53c5f`.
- Masih 4 periode; periode terakhir berakhir 20 Des 2026 (tidak ada periode yang dibuat saat Pasang).
- `fakta.tutup_buku_berikut('2026-12-21')` = 20 Jan 2027, `fakta.gajian_sesudah('2027-01-20')` = 25 Jan 2027 (pengaturan Pabrik A
  di Supabase).
- `fakta.terima_file_atas_nama` di Supabase memanggil `fakta.buat_periode_sampai`.
- Pasang ini juga bukti penjaga 9d bekerja di GitHub Actions sungguhan: repo demo dikenali dan memasang jalur demo seperti biasa.

## Yang belum

- **Uji nyata** baru bisa mulai **21 Des 2026** (batas hari ini; periode 5 demo mulai 21 Des). Berjalan di belakang (aturan 10):
  pada atau sesudah 21 Des 2026 kirim file mesin berisi tap 21 Des lewat bot, lalu cek balasan bot, periode 5 di Supabase
  (21 Des 2026 – 20 Jan 2027, bayar 25 Jan 2027, riwayat status), Sheets, dan web HRD.
- Perintah HRD untuk tanggal di periode yang belum ada tetap ditolak "tanpa periode" sampai file pertama periode itu masuk
  (sesuai K1 (a), sama dengan perilaku sebelum P1).
