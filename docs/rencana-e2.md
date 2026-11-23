# Rencana paket E2: cadangan malam tidak gagal palsu

23 November 2026 · keputusan pemilik "sesuai saran kamu, buat" (13.28 WIB, pilihan (a) sesudah Tahap 7 ditutup)

## Masalah (diperiksa 23 Nov 2026)

- [Pasti] 6 run "Cadangan malam" sesudah Pasang/Isi Sheets (17–20 Nov) GAGAL dengan "jumlah baris hasil pemulihan berbeda dengan sumber"; contoh run 44707585585: sumber `fakta.minta_gaji` 2 / pemulihan 1, `fakta.pesan_telegram` sumber lebih banyak.
- [Pasti, dari kode] Penyebab: `db/uji_pemulihan.sh` menghitung baris **sumber saat perbandingan**, beberapa menit **sesudah** cadangan diambil (sesudah enkripsi, unggah, dan pemulihan). Baris yang ditulis bot di antara keduanya membuat selisih, padahal cadangannya utuh.
- Akibat: tanda GAGAL palsu bisa menutupi kegagalan cadangan yang sungguhan.

## Isi paket (tidak mengubah Supabase, tidak ada migrasi)

1. `.github/workflows/cadangan-malam.yml`: jumlah baris sumber dihitung **tepat sebelum dan tepat sesudah** cadangan diambil (dua file kecil, tidak berisi data pribadi), lalu diteruskan ke uji pemulihan.
2. `db/uji_pemulihan.sh`: bila dua hitungan itu ada, jumlah baris hasil pemulihan tiap tabel **harus berada di antara** hitungan sebelum dan sesudah (sama persis bila tabel tidak berubah selama cadangan). Tabel yang berubah selama cadangan disebut di log sebagai catatan, bukan kegagalan. Di luar rentang = GAGAL seperti sekarang. Tanpa dua file itu (pemakaian manual, `docs/cadangan.md`) cara lama tetap: harus sama persis.
3. Uji otomatis baru `db/uji/uji_pemulihan_rentang.sh` dijalankan di GitHub "Uji database": (a) cadangan utuh + baris baru sesudah cadangan → LULUS dengan catatan; (b) cadangan yang kehilangan baris (hasil pemulihan lebih sedikit dari hitungan sebelum) → GAGAL; (c) pemakaian lama tanpa rentang dengan sumber berubah → GAGAL seperti dulu.
4. Uji nyata: jalankan "Cadangan malam" lewat tombol (workflow_dispatch) dan sesudah satu "Pasang"/Isi Sheets berikutnya; harus hijau.
5. Dokumen: `docs/laporan-e2.md`, `docs/serah-terima.md`, `docs/cadangan.md`.

## Belum pasti

- [Kemungkinan Besar] tabel bisa berkurang barisnya selama cadangan hanya lewat Reset (tidak berjalan bersamaan karena antrean `concurrency`); karena itu batas bawah dan atas diambil dari nilai terkecil dan terbesar dua hitungan, bukan diasumsikan selalu bertambah.
