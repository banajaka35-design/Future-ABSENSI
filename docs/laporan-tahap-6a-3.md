# Laporan paket 6a-3: total untuk HRD tanpa orang rahasia (F15b)

18 November 2026 · "buat" pemilik 18 Nov 2026 · permintaan perubahan 04 · dokumen sebelum kode: commit 7e4d99b (F15b, Sheets versi 3, halaman demo versi 2) · kode: commit a3de2c2

## Masalah yang ditutup

Total Ringkasan (Sheets 6a dan halaman demo 4c) memasukkan orang rahasia, sedangkan gaji orang lain tampil per orang, sehingga total − jumlah yang terlihat = gaji orang rahasia (periode 1: 15.724.000 untuk 3 orang; Pabrik B: gaji persis 1 orang).

## Yang diubah

| Bagian | Isi |
| --- | --- |
| Sheets Ringkasan | Orang, semua total rupiah, transfer, tunai, PPh tertahan tanpa orang rahasia; kolom "Orang rahasia (tidak termasuk)"; keterangan di baris 3 |
| Halaman demo | Ringkasan dan pecahan uang tunai tanpa orang rahasia, keterangan "tidak termasuk N orang rahasia"; tanda anomali atas nama orang rahasia tanpa keterangan |
| Pemeriksa Sheets dan demo | Total dari gudang tanpa rahasia (SQL sendiri) + uji kebocoran: total − jumlah baris yang terlihat = 0; demo: pecahan tampil + amplop rahasia = `hitung.pecahan_tunai` |
| Uji | Sheets tiruan 43 uji (+ total cara lama → GAGAL); `sistem/uji/uji_kebocoran.py` dijalankan untuk Pabrik B (1 orang rahasia) di uji simulasi |

Gudang, mesin hitung, bot, data simulasi tidak diubah. Supabase tidak diubah.

## Hasil (diukur)

- Uji GitHub commit a3de2c2 (run 44240234351): uji database 453 lulus; uji simulasi 76 lulus; 0 gagal. Pabrik B: total − terlihat = 0 di 4 periode (1 orang rahasia); pemeriksa Sheets dan demo lulus.
- Isi Sheets (run 44240902374, tombol): lulus, pemeriksa 0 beda (4.025 orang-periode bukan rahasia, 3 rahasia).
- Terbitkan demo (run 44240905726, tombol): lulus, pemeriksa 0 beda.

## Dicek langsung

- Sheets Ringkasan periode 1: Orang 1.008, total gaji bersih 5.167.334.029, orang rahasia 3, keterangan baris 3 ada. Sama dengan hitungan di Supabase untuk orang bukan rahasia (5.167.334.029).
- Halaman demo terbit (dibuka di browser aplikasi Claude, data.json dibaca langsung): total gaji bersih − jumlah gaji bersih semua orang yang tampil = **0** di keempat periode (5.167.334.029 · 8.191.235.519 · 5.690.720.227 · 4.983.863.768); keterangan "tidak termasuk 3 orang yang gajinya rahasia" tampil.

## Belum dikerjakan

- Total lengkap untuk bos: menunggu akun bos (Tahap 9); sampai itu hanya di gudang.
- [Kemungkinan Besar] Tanda anomali tingkat divisi masih memasukkan orang rahasia dalam angka divisinya (risiko kecil; dicatat).
