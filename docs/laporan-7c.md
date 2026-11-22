# Laporan paket 7c-1: setujui/batalkan lembur lewat chat

22 November 2026 · rencana `docs/rencana-tahap-7.md` bagian 9 (di-"buat" pemilik 17.12 WIB) · migrasi 0035 · commit b1b70c0 + a7a97b7

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Migrasi 0035 | Draf boleh bersasaran divisi (khusus perintah lembur); `fakta.identitas_sasaran`, `fakta.periksa_lembur`, `fakta.hari_lembur`, `fakta.lembur_target`; `api.pintu_lembur_siapkan`; `api.pintu_perintah_simpan`, `api.pintu_batal_siapkan`, `api.pintu_perintah_hasil`, `api.pintu_perintah_terakhir` diganti (perintah lembur, sasaran divisi). **Mesin hitung gaji tidak diubah** (versi kode tetap 6) |
| Bot | `/setujuilembur`, `/batalkanlembur <ID atau kode divisi> <tanggal> [tanggal selesai] [catatan]`; konfirmasi menyebut pengaturan lembur per hari, menit lewat jadwal (orang) atau jumlah orang lembur 60 menit+ (divisi), perintah lembur yang sudah ada, dan memberi tahu bila perintah tidak mengubah hari itu; "Hasil": lembur rupiah sebelum → sesudah (orang), atau jumlah orang berubah dan total (divisi, tanpa orang rahasia); `/batalperintah` dan `/perintahku` untuk perintah lembur |

## Uji (diukur)

| Uji | Hasil |
| --- | --- |
| Lokal Postgres 16 | Database 733 lulus (13 uji baru di `db/uji/270_lembur_chat.sql`: D04, F12, D05, pembatalan, penolakan); pintu 115 lulus (3 uji baru) |
| Bukti uji gagal dengan kode lama | Tanpa 0035: `function api.pintu_lembur_siapkan(unknown) does not exist`, keluar kode 3 |
| GitHub run 45012580348 | **Gagal**: uji penyambung P7 (pengingat) gagal karena tap uji 7c dikirim lewat mesin MA1 yang seharusnya "belum mengirim". Diperbaiki di commit a7a97b7 (pilih mesin yang sudah mengirim; dicek lokal MA1 tetap belum mengirim). Tidak dipasang |
| GitHub run 45014375040 | Lulus: database 733, simulasi 129, pintu 115, penyambung 23 |
| GitHub "Pasang ke Supabase" run 45015680331 | Lulus: hanya 0035, pemeriksaan 33 lulus, Edge Function terpasang ulang |
| Dicek di Supabase | 0035 sidik `572cb01ee415` = repo; versi kode gaji tetap `hitung_gaji 6 (paket 7b)`; perintah lembur 0; 10067 periode 4: lembur Rp80.925, dibayar Rp4.460.925, 26 Nov 2026 pulang 127 menit lewat jadwal |

## Uji nyata (22 Nov 2026, akun pembangun)

| Langkah | Hasil (dicek di Supabase dan Sheets) | Label |
| --- | --- | --- |
| `/batalkanlembur 10067 26-11-2026` | Konfirmasi: pengaturan otomatis; pulang 127 menit lewat jadwal; periode no. 4 dihitung ulang | [Pasti] (tangkapan layar pemilik) |
| Ya, catat (18.55.38 WIB) | Perintah no. 1608 `batalkan_lembur`, 10067, 26 Nov 2026, oleh pembangun; periode 4 selesai 18.55.59 (versi gaji 42): **sekitar 21 detik**; Isi Sheets dipicu 18.56.01, berhasil | [Pasti] |
| **D05 nyata** | 10067 periode 4: lembur Rp80.925 → **Rp0**; dibayar Rp4.460.925 → **Rp4.380.000**; tanda `lembur_tidak_dibayar_tanpa_izin` (kelebihan jam tetap tercatat). Versi 42 dibanding 40: hanya 1 orang berbeda | [Pasti] |
| Sheets tab periode 4 | Baris 10067: Lembur 0, Dibayar 4380000, Peringatan "lembur_tidak_dibayar_tanpa_izin, pph_masa_terakhir_tertahan"; cocok dengan gudang | [Pasti] |

Sisa: `/batalperintah 1608` → lembur kembali Rp80.925; uji tolak `/setujuilembur XYZ 26-11-2026`.
