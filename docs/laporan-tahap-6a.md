# Laporan paket 6a: rekap Google Sheets

18 November 2026 · rancangan: `docs/rekap-sheets.md` (commit 551cff5, sebelum kode) · kode: commit 795b10f · acuan PRD v2 (PRD v3.1 tidak tersedia; keputusan pemilik 18 Nov 2026)

## Yang dibuat

| File | Isi |
| --- | --- |
| `web/sheets_api.py` | Penghubung Google Sheets API: masuk dengan kunci akun layanan (tanda tangan RS256 lewat `openssl`), coba ulang 1/2/4/8 detik untuk 429/5xx, semua isi ditulis `RAW` |
| `web/isi_sheets.py` | Penulis: membaca gudang (hanya membaca), status `SEDANG DIISI`, buat/hapus tab milik sistem, kunci tab, tulis satu permintaan per tab, tambah baris `Riwayat isi`; perintah `status SELESAI/GAGAL` |
| `web/periksa_sheets.py` | Pemeriksa gerbang "isi Sheets sama dengan gudang": SQL sendiri, setiap sel, judul kolom, jumlah orang, jumlah per baris, Ringkasan, kunci tab, uji teks 18 digit dan `=1+1` |
| `sistem/uji/sheets_tiruan.py` | Sheets tiruan tanpa internet (ketat: hanya `RAW`, tulis di luar grid ditolak, token diperiksa tanda tangannya) |
| `sistem/uji/uji_sheets.py` | 30 uji (lihat bawah); dipanggil dari `sistem/uji/jalankan_simulasi.sh` |
| `.github/workflows/isi-sheets.yml` | Workflow "Isi Sheets": sesudah Pasang/Reset lulus dan lewat tombol |

**Supabase tidak diubah** (tanpa migrasi, tanpa pemasangan).

## Hasil uji (diukur)

Uji lokal 18 Nov 2026 (Postgres 16, data simulasi Pabrik A, Sheets tiruan): **30 lulus, 0 gagal**.

- Isi pertama: 4 periode, 4.037 baris orang-periode; tab Gaji 1.008–1.013 baris × 42 kolom, 0,38–0,39 MB per tab (di bawah saran Google 2 MB); 21 permintaan ke Google; lama isi 728 ms di Sheets tiruan (bukan Google; angka Google sungguhan diukur di uji nyata).
- Pemeriksa: 0 beda, 3 orang rahasia, 3 permintaan ke Google.
- Pemeriksa terbukti menangkap: satu sel gaji bersih diubah 1 rupiah; angka orang rahasia muncul; ID tersimpan sebagai angka; teks 18 digit menjadi angka; tab Gaji lama tertinggal; total Ringkasan diubah; kunci tab mengizinkan akun lain; kunci hanya peringatan.
- Isi ulang tidak membuat tab atau kunci dobel; tab buatan HRD tidak disentuh; dua jawaban 503 dilewati dengan coba ulang; secret kosong → GAGAL dengan pesan.

Uji otomatis GitHub commit 795b10f (run 44226762084): **lulus**. Uji database 453 lulus 0 gagal; uji simulasi 55 lulus 0 gagal (25 lama + 30 Sheets); lama isi di Sheets tiruan 661 ms.

## Uji nyata ke Google Sheets (18 Nov 2026)

**Penyiapan** (dikerjakan Claude lewat browser aplikasi Claude dan konektor Drive, kecuali kunci dan secret oleh pemilik):

| Hal | Isi |
| --- | --- |
| Proyek Google Cloud | ID `future-absensi` (tanpa organisasi). Ditemukan juga proyek kedua bernama sama, ID `future-absensi-515103`; Sheets API sempat dinyalakan di proyek kedua itu. Proyek yang dipakai: `future-absensi` |
| Akun layanan | `isi-sheets@future-absensi.iam.gserviceaccount.com`, tanpa peran di proyek; kunci JSON ID `c96760a7…` dibuat 18 Nov 2026 oleh pemilik (kunci boleh dibuat: terbukti) |
| Spreadsheet | "PROJECT ABSENSI" dibagikan ke akun layanan sebagai Editor (tanpa pemberitahuan email); "editor boleh membagikan" dimatikan (K7) |
| Secret GitHub | `GOOGLE_SA_KEY`, `SHEETS_ID` diisi pemilik (jalur Claude ke secret GitHub ditolak HTTP 403) |

**Run 1** (44231730284): GAGAL sebelum menulis, Google HTTP 403 "Sheets API has not been used in project 327864651298" (proyek akun layanan berbeda dengan proyek tempat API dinyalakan). Status GAGAL tidak bisa ditulis karena alasan yang sama. Diperbaiki: Sheets API dinyalakan di proyek `future-absensi`.

**Run 2** (44232081983, commit 69e8a79, tombol): **lulus**. 4 tab Gaji 1.008–1.013 baris × 42 kolom; 21 permintaan ke Google; lama isi 8.812 ms (langkah isi termasuk baca gudang 9.348 ms); pemeriksa 0 beda, 3 rahasia, 3 permintaan; status `SELESAI 2026-11-18 10:41:45 WIB`.

**Dicek langsung di Sheets (konektor Google Sheets) dan Supabase:**

- Tab: Sheet1 (tidak disentuh), Ringkasan, 4 tab Gaji, Riwayat isi; setiap tab milik sistem punya satu kunci.
- [Pasti] Google menambahkan pemilik file ke daftar pengubah kunci: `isi-sheets@…` dan `banajaka35@gmail.com`. Pemeriksa lulus karena `PEMBANGUN_EMAIL` termasuk yang diizinkan. Editor lain (`jakabuana444@gmail.com`) tidak bisa mengubah tab milik sistem.
- `Riwayat isi`: `123456789012345678` dan `=1+1` kembali persis sebagai teks → ID 18 digit (M1) dan isi berawalan `=` aman di Google sungguhan.
- Ringkasan periode 4: 1.006 orang, total gaji bersih 4.999.870.485 = Supabase.
- Contoh 1: 10001 Eka Susanto, PRD, transfer, hadir 22, telat 1 kali/21 menit, lupa tap 1; gaji bersih 4.926.486, lembur 292.486, total pendapatan 5.102.486 = Supabase.
- Contoh 2: 11041 Yanti Manurung, KAM, tunai, hadir 2, alpha 2; potongan hari tidak dibayar −352.000 dengan keterangan "2 hari tidak dibayar (alpha 2, izin 0) …"; gaji bersih 206.000.
- Contoh 3 (rahasia): 10998 Hadi Rahayu, KTR, transfer, hadir 25, telat 2 kali/43 menit; **semua kolom rupiah kosong** (Supabase: gaji bersih 5.333.960, tidak tampil).
- PPh tertahan periode 4 = 1.006 orang (periode Desember, data Januari tidak ada; sesuai temuan 4b-3).

Tautan: https://docs.google.com/spreadsheets/d/1_YsSVF4bMtfxvylO7L_KDIQKxXqQdywCoZjqY_i3-mA/edit (dibagikan hanya ke pemilik, `jakabuana444@gmail.com`, dan akun layanan).

**Gerbang Tahap 6 menurut PRD v2 ("Isi Sheets sama dengan gudang"): terpenuhi untuk 6a.**

## Belum terbukti

- Lama dari awal workflow pemicu (Pasang/Reset) sampai SELESAI: run 2 dipicu tombol, jadi belum terukur; terukur otomatis pada Pasang berikutnya.
- Lama dari file Telegram masuk sampai Sheets terisi (tidak di 6a).

## Tidak di 6a

Isi otomatis sesudah file masuk lewat Telegram; pemberitahuan Telegram bila isi gagal; tab anomali; lembar cetak, bahan tunai, file bank (6b/6c).
