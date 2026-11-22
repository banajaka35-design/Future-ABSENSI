# Laporan paket 7b: kasbon lewat chat

22 November 2026 · rencana `docs/rencana-tahap-7.md` bagian 8 (di-"buat" pemilik 16.13 WIB, pilihan (a)) · migrasi 0034 · commit cc9375f

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Migrasi 0034 | `hitung.hitung_gaji` versi kode 6: salinan versi 5 (0014) dengan **satu syarat**: baris `buku_kasbon` yang perintahnya dibatalkan tidak dihitung (saldo dan cicilan). Aturan I2–I4 tidak berubah. `fakta.keadaan_kasbon`; `api.pintu_kasbon_saldo`, `api.pintu_kasbon_siapkan`; `api.pintu_perintah_simpan`, `api.pintu_batal_siapkan`, `api.pintu_perintah_hasil` diganti (kasbon); draf menampung jenis kasbon, jumlah, cicilan |
| Bot | `/kasbon <ID>` (saldo, 5 catatan terakhir); `/kasbon <ID> <jumlah> <cicilan> [catatan]` (cicilan wajib); `/cicilan <ID> <jumlah>`; `/lunas <ID> <jumlah> [catatan]` (ditolak bila melebihi saldo); jumlah `1.000.000`, `1jt`, `1,5jt`, `250rb`; konfirmasi Ya/Batal; "Hasil KASBON": potongan periode berjalan sebelum → sesudah, sisa saldo, cicilan; `/batalperintah` untuk kasbon; angka orang rahasia tidak ditampilkan |
| Pencatat (PRD C10) | Setiap catatan = perintah `kasbon` (asal chat, `oleh` = akun, `nilai` = jenis:jumlah:cicilan) + baris `buku_kasbon` dengan `perintah_id` |
| Kabar Sheets | Sesudah perintah chat menulis "Lama sejak perintah dicatat" (temuan 7d), `web/kabar_telegram.py` |
| Uji lama yang diubah | `db/uji/100_pajak_awal_tahun.sql`: versi kode gaji yang diharapkan 5 → 6 (naik dengan sengaja; bukan kasus jebakan) |

## Uji (diukur)

| Uji | Hasil |
| --- | --- |
| Lokal Postgres 16 | Database 720 lulus (23 uji baru di `db/uji/260_kasbon_chat.sql`); simulasi 129 lulus (U1 kunci jawaban lulus, Sheets 1 uji baru); pintu 112 lulus (4 uji baru) |
| Bukti uji gagal dengan kode lama | Tanpa 0034: "versi kode gaji terbaru" GAGAL dan `function api.pintu_kasbon_siapkan(unknown) does not exist`, keluar kode 3 |
| Pemeriksaan tipe (`tsc`) | Galat lama saja (9 baris) |
| GitHub "Uji database" run 45008213195 | Lulus: database 720, simulasi 129 (U1 lulus 3 kali), pintu 112, penyambung 23 |
| GitHub "Pasang ke Supabase" run 45009451824 | Lulus: hanya 0034, pemeriksaan 33 lulus, Edge Function terpasang ulang |
| Dicek di Supabase | 0034 sidik `f7ea788433d5` = repo; versi kode gaji `hitung_gaji 6 (paket 7b)`; kasbon 0 baris; periode hari ini no. 4 (21 Nov–20 Des, `dihitung`); 10067 periode 4 dibayar Rp4.460.925, bukan rahasia |

## Uji nyata

Belum. Langkah: `/kasbon 10067 1.000.000 250.000` → Ya; lalu `/batalperintah <nomor>` → Ya; uji tolak `/lunas 10067 5.000.000`.
