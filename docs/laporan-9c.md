# Laporan paket 9c: coba aturan

Rencana: `docs/rencana-9c.md`, termasuk analisa celah K1–K8. "Buat" dari pemilik: 23 Nov 2026 17.15 WIB.

## Yang dibuat

- **Migrasi `0040_coba_aturan.sql`**
  - `fakta.coba_aturan` hanya bisa ditambah.
  - `fakta.aturan_sekarang` memberi nilai aturan yang berlaku, untuk mengisi isian awal.
  - `fakta.coba_aturan_jalankan` menjalankan percobaan di sub-transaksi yang **selalu dibatalkan**.
  - Aturan bertanggal diganti dengan cara resmi: baris terbuka ditutup di tanggal awal periode, lalu baris percobaan ditambahkan. Ini perlu karena `jejak.jaga_bertanggal` melarang isi aturan diubah langsung. Bila aturan sudah berganti di tengah periode, percobaan ditolak dengan alasan yang jelas.
  - `api.web_hrd` mendapat aksi baru `aturan_sekarang` dan `coba_aturan`.
- **Edge Function:** isian aturan diteruskan, tetapi hanya 7 kunci yang dikenal. Penolakan dari database diteruskan bersama alasannya (409/400/429).
- **Halaman:** tab "Coba aturan" berisi isian yang terisi nilai sekarang, tombol "Hitung percobaan" (batas tunggu 110 detik), ringkasan naik/turun/total, dan daftar orang yang berubah beserta komponennya.

## Uji [Pasti]

| Uji | Hasil |
| --- | --- |
| **Gerbang 2** (uji database 320) | Toleransi telat 10, uang makan 20.000, dan kelipatan lembur 15 dicoba. Aturan yang sama lalu dipasang sungguhan dan dihitung ulang. Selisih per orang, total selisih, serta jumlah naik dan turun **sama persis** |
| K1 | Sesudah percobaan, jumlah versi hitung, isi aturan, dan status periode sama persis dengan sebelumnya |
| CI run 45158116016, commit f11a910 | Database 830 (20 uji baru 9c), pintu 121, simulasi 132, penyambung 24: semua lulus |
| Pasang ke Supabase, run 45160906600 | 0040 terpasang; pemeriksaan 33 lulus |
| Terbitkan demo, run 45161923082 | Terbit dengan 3 sidik skrip |
| Supabase sebelum uji nyata (17.4x) | 0040 ada; antrean 0; 50 versi hitung; periode 3 dan 4 `dihitung`; toleransi telat 5 |

## Uji nyata

(diisi setelah dilakukan)
