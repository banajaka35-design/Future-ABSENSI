# Laporan paket G1: grafik di halaman demo

18 November 2026 · rencana `docs/rencana-grafik-demo.md` versi 2 · rancangan `docs/halaman-demo.md` versi 5 · commit e28ed4d dan perbaikan sesudahnya

## Yang dibuat

- Bagian "Grafik periode" di https://future-absensi-demo.pages.dev untuk periode yang dipilih:
  - **Biaya per divisi**: empat grafik kecil (gaji pokok, lembur, potongan hari tidak dibayar, potongan lain), masing-masing dengan skalanya sendiri.
  - **Porsi gaji bersih per divisi**: persen dan rupiah.
  - **Orang telat per tanggal**.
  - Setiap grafik punya "Lihat angka" (tabel).
- Semua rupiah grafik **tanpa orang rahasia**, dengan keterangan "tidak termasuk 3 di Kantor". Hitungan telat termasuk orang rahasia, karena itu bukan angka gaji (sama dengan Sheets).
- Tanda "Angka sementara" muncul untuk periode yang punya orang dengan PPh tertahan. Keterangan THR muncul di periode Feb–Mar.
- Daftar karyawan:
  - pilihan Semua / Transfer / Tunai;
  - kolom Cara bayar;
  - rincian orang tunai menampilkan isi amplop.
- Pemeriksa (`web/periksa_data.py`) mencocokkan:
  - setiap angka grafik dengan gudang;
  - kebocoran per divisi (total divisi dikurangi jumlah orang yang tampil harus 0);
  - telat per tanggal, THR, cara bayar;
  - amplop = dibayar.
- Penghitung ukuran batang ada di `web/demo/grafik_inti.js` dan diuji `node --test` (6 uji). Pembuat header mengizinkan skrip dari halaman sendiri (`'self'`); skrip dari situs lain tetap ditolak.

## Hasil uji [Pasti]

- GitHub "Uji database" lulus (run 44287623380, lalu run 44289826858 sesudah perbaikan). Uji baru:
  - grafik 6/6;
  - "skrip dari situs lain ditolak";
  - "total grafik divisi berahasia ditambah → pemeriksa GAGAL" untuk Pabrik A dan B.
- Satu angka grafik diubah tangan (lembur KTR +237.717) → pemeriksa menulis 2 BEDA (uji lokal).
- Terbitkan demo (run 44291605144): pemeriksa "4 periode, 1044 karyawan, 3 rahasia; 0 beda".

## Dicek langsung di halaman terbit [Pasti]

| Yang dicek | Halaman | Supabase |
| --- | --- | --- |
| Jumlah gaji bersih semua divisi, periode 21 Jan–20 Feb, tanpa rahasia | 5.167.334.029 | 5.167.334.029 |
| Orang telat 4 Feb 2026 | 46 | 46 |
| Orang tunai periode 1 | 152 | 152 |
| THR periode Feb–Mar tanpa rahasia | Rp3.236.662.509 | 3.236.662.509 (semua termasuk rahasia: 3.247.308.342) |
| Amplop karyawan 10731 periode 1 | Rp4.267.000 | dibayar 4.267.000 |

- Lebar komputer: tangkapan layar dilihat, batang dan label tidak bertabrakan.
- Lebar 375 px: grafik muat (tepi kanan 339 px).
- Konsol tanpa galat. Header CSP aktif.
- `data.json` 201 KB.

## Ditemukan dan diperbaiki saat cek langsung

1. **Daftar karyawan melebar ke 402 px di layar 375 px.** Penyebabnya kolom Cara bayar yang baru. Tabel kini bisa digeser ke samping (`.gulir`); lebar halaman kembali 375 px.
2. **Teks tanda salah.** Rencana menulis "PPh akhir tahun belum dihitung, periode Nov–Des". Kenyataannya PPh masa terakhir tertahan di **semua** periode: 12, 11 dan 15 orang (karyawan berhenti) di periode 1–3, dan 1.003 orang di Nov–Des. Teks kini berbunyi "PPh 21 masa terakhir N orang belum bisa dihitung (dihitung 0)". Ralat juga ditulis di `docs/halaman-demo.md`.

## Menyimpang dari daftar

- Daftar menyebut "batang berkelompok per divisi". Yang dibuat adalah **empat grafik kecil**, karena gaji pokok (miliaran) dan potongan (jutaan) dalam satu skala membuat batang potongan hampir tak terlihat. Alasannya ditulis di `docs/halaman-demo.md` v5.
- Daftar menyebut "angka tertulis di tiap batang". Grafik telat hanya menulis angka tertinggi, karena 30–31 batang terlalu rapat. Angka lengkap ada di "Lihat angka" dan saat kursor diarahkan.
- Pilihan terang/gelap dikeluarkan dari G1 (K6, sudah di daftar).

## Belum pasti

- [Kemungkinan Besar] Tangkapan layar 375 px dari panel browser terpotong di kanan karena panel lebih sempit dari layar tiruan. Ukuran yang diukur lewat halaman sendiri: 375 px, tidak melebar.

## Tidak diubah

Supabase (tanpa migrasi, tanpa Pasang), mesin hitung, Sheets, bot.
