# Laporan paket 7a: izin, sakit, cuti lewat chat

21 November 2026 · rencana `docs/rencana-tahap-7.md` bagian 5 (di-"buat" pemilik 10.39 WIB) · migrasi 0032 · commit e2530ec

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Migrasi 0032 | Tabel `fakta.draf_perintah` (tombol Ya sekali pakai, 15 menit); kolom `fakta.antrean_kerja.perintah_id`; fungsi `api.pintu_perintah_siapkan`, `api.pintu_perintah_simpan`, `api.pintu_perintah_hasil`; pembantu `fakta.periksa_perintah`, `fakta.hari_perintah`, `fakta.periode_tanggal` (tertutup untuk peran `pintu`) |
| Bot (`sistem/pintu/inti.ts`) | `/izin`, `/sakit`, `/cuti <ID> <tanggal> [tanggal selesai] [catatan]` (juga tanpa garis miring); tombol tetap **Perintah HRD** (HRD dan pembangun) yang bertanya lewat kolom balas; konfirmasi dengan tombol **Ya, catat / Batal**; sesudah Ya: "Tercatat", hitung ulang lewat antrean, Isi Sheets dipicu (pemicu "perintah HRD"), lalu "Hasil ... sebelum → sesudah"; menu dan `/bantuan` diperbarui |
| Aturan | Hanya `hrd` dan `pembangun`; tanggal harus di periode yang tercatat dan belum `dirilis`/`dikunci` (diperiksa lagi saat Ya); rentang paling panjang 31 hari; karyawan aktif setiap tanggalnya (tanggal berhenti = hari kerja terakhir, boleh); perintah baru menang atas perintah lama di hari yang sama (aturan baca tap yang sudah ada, ditulis di konfirmasi); periode sesudahnya yang sudah punya gaji ikut dihitung ulang, kecuali yang sudah dirilis |
| Tidak diubah | Aturan hitung gaji, baca tap, Sheets, halaman demo |

## Uji (diukur)

| Uji | Hasil |
| --- | --- |
| Lokal Postgres 16: `db/uji/jalankan.sh` | 678 lulus, 0 gagal (35 uji baru di `db/uji/240_perintah_chat.sql`, termasuk **gerbang: izin susulan alpha → izin sesudah antrean dikerjakan**) |
| Lokal: `sistem/uji/uji_pintu.sh` | 105 lulus, 0 gagal (7 uji baru: baca tanggal, baca perintah, penolakan, konfirmasi, Ya → izin di gudang, tombol Perintah HRD, menu) |
| Bukti uji gagal dengan kode lama | Tanpa migrasi 0032: uji 240 berhenti, `function api.pintu_perintah_siapkan(unknown) does not exist`, skrip keluar dengan kode 3 |
| Pemeriksaan tipe (`tsc`) | Galat sama dengan sebelum paket (9 baris lama), tidak ada yang baru |
| GitHub "Uji database" run 44863350409 | Lulus (database 678, pintu 105, penyambung 23), sekitar 12 menit |
| GitHub "Pasang ke Supabase" run 44864570653 | Lulus: hanya 0032 dipasang, pemeriksaan 33 lulus 0 gagal, Edge Function `pintu-telegram` terpasang ulang |
| Dicek langsung di Supabase (21 Nov 2026 11.1x WIB) | 0032 sidik `a0d560b9e134` = repo; draf 0, perintah chat 0; periode 1–2 dikunci, 3–4 dihitung; 10067 tanggal 30 Mar 2026 masih `alpha`; peran `pintu` boleh menjalankan fungsi api baru, tidak boleh pembantu fakta |

## Uji nyata gerbang (22 Nov 2026, akun pembangun)

| Langkah | Hasil (dicek di Supabase dan Sheets, bukan dari balasan bot) | Label |
| --- | --- | --- |
| `/izin 10067 30-03-2026` | Konfirmasi: Vina Pohan (Produksi), 30 Mar 2026 `alpha`, periode no. 3 | [Pasti] (tangkapan layar pemilik) |
| Ya, catat (10.40.41 WIB) | Perintah no. 1604 `asal = chat`, jenis izin, `oleh` = akun pembangun; antrean periode 3 dan 4 dengan `perintah_id = 1604` | [Pasti] |
| Hitung ulang | Periode 3 selesai 10.41.06 (versi gaji 28), periode 4 selesai 10.41.26 (versi gaji 30): **sekitar 45 detik dari Ya sampai kedua periode selesai** (diukur dari jam di gudang). Isi Sheets dipicu 10.41.28, selesai 10.43.06 (berhasil) | [Pasti] |
| **GERBANG: izin susulan mengubah hasil** | 10067 tanggal 30 Mar 2026: `alpha` → `izin` di `hitung.hasil_harian` | [Pasti] |
| Akibat ke gaji (aturan C3 lama) | 10067 periode 3: premi hadir 0 → Rp100.000; PPh 21 Rp29.422 → Rp44.883; potongan hari tidak dibayar tetap Rp153.846 ("alpha 0, izin 1"); dibayar Rp5.513.378 → **Rp5.597.917 (+Rp84.539)**. Dari 1.010 orang di periode 3, hanya 10067 yang angka dibayarnya berubah (versi 25 dibanding 28) | [Pasti] |
| Sheets tab "Gaji 2026-03-21 sd 2026-04-20 transfer" | Baris 10067: Alpha 0, Izin 1, Premi hadir 100000, PPh 21 −44883, Dibayar 5597917; cocok dengan gudang | [Pasti] |

**Gerbang Tahap 7 lulus untuk izin.** Sisa uji nyata: uji tolak `/izin 10067 25-02-2026` (periode 2 dikunci).

## Temuan

1. **Teks konfirmasi dan "Tercatat" hanya menyebut periode yang memuat tanggal perintah** (periode 3), padahal periode sesudahnya yang sudah punya gaji (periode 4) juga dihitung ulang. Hitungan benar; hanya teksnya kurang. Perbaikan butuh paket kecil.
