# Laporan paket E2: Cadangan malam tidak lagi gagal palsu

Rencana: `docs/rencana-e2.md`. "Buat" dari pemilik: 23 Nov 2026 13.28 WIB.

## Masalah [Pasti]

Run Cadangan malam 44707585585 gagal dengan selisih `fakta.minta_gaji 2 → 1`. Cadangan diambil lebih dulu, lalu beberapa menit kemudian Supabase dihitung untuk pembanding. Di antara keduanya bot menulis satu baris baru. Cadangannya sendiri utuh; pembandingnya yang terlambat.

## Yang diubah

1. `.github/workflows/cadangan-malam.yml`: Supabase dihitung (`db/hitung_baris.sql`) tepat sebelum dan tepat sesudah `pg_dump`. Dua file hitungan disimpan di folder sementara runner (tidak ikut diunggah) dan diberikan ke uji pemulihan.
2. `db/uji_pemulihan.sh`: bila `BARIS_SEBELUM` dan `BARIS_SESUDAH` diisi, jumlah baris hasil pemulihan tiap tabel harus berada di antara dua hitungan itu. Tabel yang berubah selama cadangan dicatat ("Catatan: ... berubah selama cadangan diambil"). Tabel hilang atau baris kurang = GAGAL. Hanya satu file diisi = GAGAL. Tanpa dua file, cara lama (sama persis dengan sumber sekarang) tetap dipakai.
3. Uji baru `db/uji/uji_pemulihan_rentang.sh` (10 pemeriksaan) di workflow Uji database, memakai database tiruan kecil.

Tidak ada migrasi. Supabase tidak diubah.

## Temuan saat menguji [Pasti]

Versi pertama pemeriksa rentang salah bila file "sebelum" dan "sesudah" adalah file yang sama (awk mengenali file dari namanya). Kasus E2b menangkapnya; diperbaiki dengan nomor urut file.

## Batas yang disadari [Pasti dari cara kerja pg_dump]

Rentang memeriksa jumlah, bukan isi. Bila dalam satu tabel ada baris dihapus dan ditambah selama cadangan diambil, jumlahnya bisa tetap di dalam rentang. Di proyek ini tabel fakta hanya bertambah, jadi risiko ini kecil [Kemungkinan Besar]. Isi cadangan dari pg_dump adalah potret satu saat (satu transaksi), jadi tidak bisa setengah-setengah.

## Hasil uji

| Uji | Hasil |
| --- | --- |
| Lokal `uji_pemulihan_rentang.sh` | 10 lulus, 0 gagal |
| CI Uji database | (diisi setelah run) |
| Cadangan malam manual | (diisi setelah run) |
| Cadangan malam sesudah Pasang/Isi Sheets berikutnya | berjalan di belakang (aturan 10) |
