# Perawatan tahunan dan pembaruan kode

Dipakai setelah PT memakai sistem. Semua perubahan aturan tetap mengikuti aturan kerja repo (CLAUDE.md): ditulis di GitHub
dulu, dipasang lewat workflow Pasang, dan diperiksa sampai ke database dan Sheets.

## Setiap tahun (sebelum gaji Januari)

| Hal | Sumber resmi | Disimpan di | Catatan |
| --- | --- | --- | --- |
| UMK kabupaten/kota PT | Keputusan gubernur (biasanya terbit akhir November) | `aturan.upah_minimum` | Aturan bertanggal: baris lama ditutup, baris baru mulai 1 Januari |
| Kalender libur nasional dan cuti bersama | SKB 3 Menteri | `induk.kalender` (lewat `db/data_awal/aturan_resmi.sql`) | Kalender 2027 sudah dimuat (dicek di pemeriksaan data awal); 2028 belum |
| Batas upah BPJS Jaminan Pensiun | Surat BPJS Ketenagakerjaan (biasanya berubah 1 Maret) | `aturan.bpjs` (lewat `aturan_resmi.sql`) | Sejak 1 Mar 2026: Rp11.086.300 |
| Batas upah BPJS Kesehatan dan tarif BPJS | Peraturan pemerintah | `aturan.bpjs` | Sekarang batas Rp12.000.000 |
| Tarif TER dan PTKP PPh 21 | Peraturan pemerintah/DJP | migrasi (paket 4a, 0008) | Bila berubah, perlu migrasi baru dan uji |
| Isian pajak awal tahun | Data PT | `induk.pajak_awal_tahun` | Hanya untuk tahun pertama sistem dipakai di tengah tahun |
| THR tahun itu | Tanggal hari raya | `aturan.thr` | Satu baris per tahun |

Angka pemerintah yang sama untuk semua PT diperbarui di repo demo (`db/data_awal/aturan_resmi.sql`), lalu ditarik ke repo PT
(bagian berikut). Angka milik PT (UMK, THR, nominal uang makan) diperbarui di repo PT saja.

**Temuan 9d:** jalur memperbarui aturan milik PT di database yang sudah terpasang belum ada (Pasang melewati susunan yang sudah
terisi). Sebelum PT pertama perlu paket kecil, misalnya file perubahan aturan PT yang dijalankan setiap Pasang dan aman dijalankan
berulang, seperti `aturan_resmi.sql`.

## Setiap hari dan bulan

- Periksa hasil workflow Cadangan (atau cadangan Supabase berbayar) minimal sekali seminggu.
- **Periode gaji baru:** sekarang periode hanya dibuat dari file susunan saat pemasangan (temuan 9d). Sistem belum membuat periode
  berikutnya sendiri. Sebelum PT pertama perlu paket kecil "periode bulanan" yang membuat periode baru dari pengaturan
  `tanggal_tutup_buku` dan `tanggal_gajian`.

## Menarik perbaikan kode dari repo ini ke repo PT

Repo PT adalah salinan repo ini. Perbaikan mesin hitung, bot, atau web dikerjakan di repo ini dulu (diuji dengan data simulasi),
lalu ditarik ke repo PT. Kalimat untuk Claude:

> Tarik perubahan dari banajaka35-design/Future-ABSENSI cabang main ke repo <akun-PT>/absensi-pt-abc. Jangan menimpa file
> susunan PT dan pengaturan khusus PT. Jalankan uji, lalu laporkan apa saja yang berubah sebelum Pasang.

Aturannya:
- Migrasi baru (`db/migrasi/`) ikut ditarik. File migrasi yang sudah dipasang tidak pernah diedit.
- Uji di repo PT harus lulus sebelum Pasang.
- Bila perbaikan mengubah angka gaji, periode yang belum dirilis di PT dihitung ulang; periode yang sudah dirilis tidak berubah.
  Selisihnya dilaporkan ke HRD PT sebelum Pasang.
- Petunjuk HRD (`6-petunjuk-hrd.md`) diperbarui bila ada perintah atau tab baru.
