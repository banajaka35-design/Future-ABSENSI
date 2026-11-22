# Laporan paket 7d: batalkan perintah lewat chat

22 November 2026 · rencana `docs/rencana-tahap-7.md` bagian 7 (di-"buat" pemilik 10.47 WIB) · migrasi 0033 · commit b900eb8

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Migrasi 0033 | `fakta.draf_perintah` boleh berisi draf `batalkan_perintah` (kolom `membatalkan`); `fakta.periode_hitung_ulang` (satu sumber untuk teks dan antrean); `fakta.periksa_perintah` diganti (ikut mengembalikan `periode_ulang`); `api.pintu_batal_siapkan`, `api.pintu_perintah_terakhir`; `api.pintu_perintah_simpan` diganti (bisa menyimpan pembatalan, mengunci perintah yang dibatalkan supaya tidak dobel) |
| Bot | `/batalperintah <nomor>` → konfirmasi (perintah, asal chat/file, status sekarang, periode yang dihitung ulang) → **Ya, batalkan / Tidak** → hitung ulang → "Hasil PEMBATALAN ... sebelum → sesudah"; `/perintahku` (10 perintah chat terakhir semua akun HRD/pembangun, tanda DIBATALKAN); pesan "Tercatat" 7a menulis "Salah catat? Ketik /batalperintah <nomor>"; konfirmasi dan "Tercatat" menyebut semua periode yang dihitung ulang (perbaikan temuan uji nyata 7a) |
| Perubahan dari daftar | Nama perintah `/batalperintah`, bukan `/batal`: `/batal` sudah dipakai untuk pengajuan rilis (8b). Dicatat di rencana |

## Uji (diukur)

| Uji | Hasil |
| --- | --- |
| Lokal Postgres 16 | Database 695 lulus (17 uji baru, `db/uji/250_batal_perintah.sql`); pintu 108 lulus (3 uji baru) |
| Bukti uji gagal dengan kode lama | Tanpa 0033: `function api.pintu_batal_siapkan(jsonb) does not exist`, skrip keluar kode 3 |
| Pemeriksaan tipe (`tsc`) | Galat lama saja (9 baris), tidak ada yang baru |
| GitHub "Uji database" run 44982777108 | Lulus (database 695, pintu 108, penyambung 23) |
| GitHub "Pasang ke Supabase" run 44983488913 | Lulus: hanya 0033 dipasang, pemeriksaan 33 lulus, Edge Function terpasang ulang; Isi Sheets, Cadangan, Terbitkan demo sesudahnya berhasil |
| Dicek di Supabase | 0033 sidik `f4747ab411ca` = repo; perintah chat 1 (no. 1604); 10067 30 Mar 2026 `izin` |

## Uji nyata

Belum. Langkah: `/batalperintah 1604` → Ya, batalkan; lalu `/batalperintah 1604` sekali lagi (harus ditolak).
