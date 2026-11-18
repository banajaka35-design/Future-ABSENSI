# Permintaan perubahan 05: gaji rahasia dinilai per periode, bukan dari status terakhir

Diajukan 18 November 2026 (paket G1-2, celah C1) · status: **disetujui pemilik 18 Nov 2026 ("buat" untuk paket G1-2 yang memuat aturan ini)**

## Latar belakang

Sampai paket G1, halaman demo, Sheets, dan kedua pemeriksa memakai status `gaji_rahasia` **terakhir** saja [Pasti, kode `distinct on ... order by berlaku_dari desc`]. Akibatnya, kalau seseorang dulu rahasia lalu statusnya dicabut, gaji semua periode lamanya ikut terbuka. Supabase 18 Nov 2026: 3 orang rahasia dan status mereka tidak pernah berubah, jadi kebocoran ini belum terjadi.

Celah turunan yang ditemukan saat mengerjakan aturan ini [Pasti, dari isi `hitung.anomali_gaji`]: tanda anomali selalu membandingkan periode ini dengan **periode lalu**. Dua hal bisa membuka angka gaji periode lalu:
- tanda "gaji berubah dari Rp… menjadi Rp…" untuk orang yang rahasia di periode lalu tetapi tidak di periode ini;
- tanda "lembur divisi naik dari Rp…" untuk divisi yang memuat orang rahasia di periode lalu tetapi tidak di periode ini (misalnya orang rahasia pindah divisi).

## Usulan

Tambah kasus **F15c** (F15 dan F15b tidak diubah):

| No | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| F15c | Status rahasia seseorang berubah di tengah riwayat (dicabut atau dipasang) | Gaji satu periode disembunyikan bila orang itu rahasia **pada hari mana pun di periode itu, atau rahasia sekarang**. Tanda anomali yang membandingkan dengan periode lalu tidak berangka bila orang itu, atau divisi itu, memuat orang rahasia di periode ini **atau** periode lalu | Permintaan perubahan 05 |

"Rahasia sekarang" ikut dihitung supaya tidak ada yang lebih terbuka daripada hari ini.

## Dampak

Halaman demo (daftar, rincian, grafik, total, tanda anomali) dan Sheets mengikuti aturan per periode. Gudang dan mesin hitung tidak berubah. Di data sekarang hasilnya sama persis dengan sebelumnya, karena tidak ada status yang berubah.
