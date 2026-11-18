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

## Belum terbukti (menunggu pemilik menyiapkan akun layanan)

- Uji nyata ke spreadsheet "PROJECT ABSENSI": isi, pemeriksa, status SELESAI, dan dua kolom uji `Riwayat isi` di Google sungguhan.
- Lama isi di Google sungguhan dan lama dari awal workflow pemicu sampai SELESAI.
- [Kemungkinan Besar] Google menambahkan pemilik file ke daftar pengubah kunci tab; karena itu `SHEETS_BOLEH_EDIT` diisi dari secret `PEMBANGUN_EMAIL`. Bila email pemilik spreadsheet berbeda, pemeriksa akan GAGAL di bagian kunci dan menyebut emailnya.
- Bukti akhir PRD v2 bagian 12 (jumlah baris per tab, 3 contoh orang lengkap, tautan Sheets) dicatat sesudah uji nyata.

## Tidak di 6a

Isi otomatis sesudah file masuk lewat Telegram; pemberitahuan Telegram bila isi gagal; tab anomali; lembar cetak, bahan tunai, file bank (6b/6c).
