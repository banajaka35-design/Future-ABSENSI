# Permintaan perubahan 04: total untuk HRD tidak boleh membuka gaji orang rahasia

Diajukan 18 November 2026 (paket 6a-3) · status: **disetujui pemilik 18 Nov 2026 ("setuju" untuk usulan: total HRD tanpa orang rahasia, total lengkap hanya untuk bos)**; daftar paket menunggu "buat".

## Latar belakang

Analisa ulang paket G1 (18 Nov 2026) menemukan [Pasti]: total di Ringkasan Sheets dan halaman demo memasukkan orang `gaji_rahasia`, sedangkan gaji semua orang lain tampil per orang. Total dikurangi jumlah yang terlihat = gaji orang rahasia. Diukur di Supabase, periode 1: 5.183.058.029 − 5.167.334.029 = 15.724.000 (gabungan 3 orang). Di Pabrik B (1 orang rahasia) cara ini membuka gaji persis satu orang. F15 hanya menguji permintaan rincian langsung, tidak menguji selisih total.

## Usulan

Tambah kasus **F15b** (F15 tidak diubah):

| No | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| F15b | Akun HRD (atau Sheets/halaman demo yang dibagikan ke HRD) menjumlah semua gaji yang terlihat lalu membandingkannya dengan total | Total yang terlihat HRD **tidak memasukkan** orang rahasia dan diberi keterangan "tidak termasuk N orang rahasia"; total dikurangi jumlah yang terlihat = 0. Total lengkap hanya untuk bos | Permintaan perubahan 04 |

## Dampak

Ringkasan Sheets (6a) dan halaman demo (4c) berubah: total uang, jumlah orang, transfer, tunai, PPh tertahan, dan pecahan tunai dihitung tanpa orang rahasia. Gudang dan mesin hitung tidak berubah. Total lengkap untuk bos menunggu akun bos (Tahap 9); sampai itu hanya ada di gudang.
