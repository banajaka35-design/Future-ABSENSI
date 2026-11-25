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

25 Nov 2026, pemilik lewat web HRD (sesi web no. 2, masuk dengan email pembangun 08.42 WIB). Semua dicek langsung di Supabase [Pasti].

| Langkah | Hasil |
| --- | --- |
| Sebelum (08.42) | toleransi telat 5; 50 versi hitung; periode 4 `dihitung`, sidik hasil `c427e5a53c5f`; antrean aktif 0 |
| Coba toleransi telat 5 → 10, periode 4 (08.43) | Selesai 23 detik (`lama_ms` 23.225, diukur sekali). 1.003 orang: 87 naik, 0 turun, 916 sama; total Rp4.983.863.768 → Rp4.992.563.768 (selisih Rp8.700.000 = 87 × Rp100.000); 3 orang rahasia tidak ditampilkan |
| Cocok manual 3 orang | 10002 (telat 6 menit), 10032 (9 menit), 10050 (7 menit): masing-masing satu kali telat di atas 5 dan tidak di atas 10 menit, tanpa alpha, sekarang tanpa premi hadir → dengan toleransi 10 tidak telat → premi hadir Rp100.000; di layar +Rp100.000 (contoh 10002: 4.614.850 → 4.714.850) |
| Sesudah | toleransi tetap 5; versi hitung tetap 50; sidik periode 4 sama; status `dihitung`; `fakta.coba_aturan` no. 1 tercatat (pengguna 1, aturan `telat_menit` 10, ringkasan sama dengan layar) |

**Uji nyata 9c LULUS.**
