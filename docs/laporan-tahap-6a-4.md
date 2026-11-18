# Laporan paket 6a-4: tanda anomali divisi tidak membuka gaji orang rahasia

18 November 2026 · "buat" pemilik 18 Nov 2026 · dokumen sebelum kode: commit 98f165f (halaman demo versi 3, ralat laporan 6a-3) · kode: commit dc1e73e

## Masalah

Halaman demo menampilkan "Lembur divisi KTR naik dari Rp14780776 menjadi Rp20159394" (periode Nov–Des). Angka divisi memuat 3 orang rahasia; lembur orang KTR lainnya tampil per orang (19.921.677), sehingga selisihnya = lembur gabungan orang rahasia 237.717 (dicek di Supabase).

## Yang diubah

- `web/buat_data.py`: tanda tingkat divisi untuk divisi yang memuat orang rahasia di periode itu diberi keterangan "Divisi KTR: angka tidak ditampilkan karena divisi ini memuat gaji rahasia". Divisi lain tetap berangka.
- `web/periksa_data.py`: keterangan berisi "Rp" tidak boleh menyangkut orang rahasia atau divisi yang memuat orang rahasia (divisi dihitung dari hasil harian dengan SQL sendiri).
- `sistem/uji/uji_kebocoran.py`: uji kebalikan (keterangan dikembalikan berangka → pemeriksa GAGAL); kini dijalankan untuk Pabrik A dan B.

Sheets, Supabase, mesin hitung tidak diubah (Sheets tidak memuat tanda anomali).

## Hasil (diukur)

- Lokal: tanda periode 3 KAM/PRD/QC tetap berangka; periode 4 KTR tanpa angka; pemeriksa 0 beda.
- Uji GitHub commit dc1e73e: uji database 453 lulus; uji simulasi 88 lulus; 0 gagal. Pabrik A dan B: 1 tanda divisi berahasia tanpa angka; uji kebalikan GAGAL sesuai harapan.
- Terbitkan demo (run 44242701673, tombol): lulus; pemeriksa terhadap Supabase 0 beda (termasuk aturan tanda berangka) sebelum diunggah.

## Dicek langsung (18 Nov 2026, 12.2x WIB)

Halaman terbit dibuka di browser aplikasi Claude (komputer pemilik terhubung lagi), `data.json` dibuat 12.13 WIB: tanda periode 3 KAM/PRD/QC berangka; periode 4 KTR "Divisi KTR: angka tidak ditampilkan karena divisi ini memuat gaji rahasia". Sesuai.

## Keputusan pemilik sesudahnya (18 Nov 2026)

- Paket isi Sheets otomatis sesudah file Telegram **dimajukan** sebelum G1.
- Nama orang rahasia di daftar tanda "gaji berubah" (tanpa angka) **tetap ditampilkan** ("harus tetap transparan").
