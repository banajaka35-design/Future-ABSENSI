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

## Uji nyata (22 Nov 2026, akun pembangun)

| Langkah | Hasil (dicek di Supabase dan Sheets) | Label |
| --- | --- | --- |
| `/batalperintah 1604` (11.47 WIB) | Konfirmasi: izin no. 1604 Vina Pohan 30 Mar 2026, dicatat lewat chat, status `izin`; **menyebut periode no. 3 dan no. 4** (perbaikan temuan 7a terbukti) | [Pasti] (tangkapan layar pemilik) |
| Ya, batalkan (11.48.53 WIB) | Perintah no. 1605 `batalkan_perintah`, `membatalkan = 1604`, asal chat, oleh pembangun; antrean periode 3 dan 4 | [Pasti] |
| Hitung ulang | Periode 3 selesai 11.49.22 (versi gaji 32), periode 4 selesai 11.49.44 (versi gaji 34): **sekitar 51 detik**. Isi Sheets dipicu 11.49.46, berhasil | [Pasti] |
| Hasil | 10067 30 Mar 2026 kembali `alpha`; premi hadir hilang; PPh 21 Rp29.422; dibayar **Rp5.513.378** (sama dengan sebelum uji 7a). Versi gaji 32 dibanding versi 25 (sebelum uji 7a): 0 orang berbeda dari 1.010 | [Pasti] |
| Sheets baris 10067 | Alpha 1, Izin 0, Premi hadir 0, PPh 21 −29422, Dibayar 5513378; cocok dengan gudang | [Pasti] |

| Uji tolak `/batalperintah 1604` kedua kali (16.07 WIB) | Bot: "Perintah no. 1604 sudah dibatalkan oleh perintah no. 1605. Tidak ada yang dicatat." Gudang: pembatalan untuk 1604 tetap 1, perintah chat tetap 2, draf tetap 2, tidak ada antrean baru | [Pasti] |
| Pesan bot sesudah Ya | "Hasil PEMBATALAN 10067 ... • Senin, 30 Mar 2026: izin → alpha" dan "Sheets SELESAI diperbarui ... diperiksa sama dengan gudang" sampai ke chat | [Pasti] (tangkapan layar pemilik) |

**Uji nyata 7d selesai.**

## Temuan

1. Kabar Sheets sesudah perintah chat menulis "Lama sejak **file** masuk: 145 detik", padahal pemicunya perintah HRD (teks dari workflow Isi Sheets). Hanya kata; angkanya diukur dari tombol Ya. Perbaikan butuh paket kecil.
