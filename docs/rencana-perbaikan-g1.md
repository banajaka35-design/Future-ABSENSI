# Rencana paket G1-2: celah sesudah G1 (menunggu "buat")

18 November 2026 · hasil analisa ulang sesudah G1 terbit

## Temuan

| No | Temuan | Besar | Bukti |
| --- | --- | --- | --- |
| C1 | Status rahasia diambil dari **status terakhir** saja (halaman demo, Sheets, kedua pemeriksa). Orang yang dulu rahasia lalu tidak lagi akan **terbuka gaji lamanya** di semua periode lama. | Besar bila terjadi, belum terjadi | Supabase 18 Nov: 3 orang rahasia, statusnya tidak pernah berubah. Kode: CTE `rahasia` = `distinct on ... order by berlaku_dari desc` di `web/buat_data.py`, `web/isi_sheets.py`, `web/periksa_data.py`. Data simulasi tidak punya kasus ini, jadi uji sekarang tidak menangkapnya. |
| C2 | Sesudah file Telegram masuk, Sheets terisi otomatis (6e) tetapi **halaman demo tidak diterbitkan ulang**. Akibatnya demo dan Sheets bisa berbeda angka sampai ada Pasang atau tombol ditekan. | Sedang | `terbitkan-demo.yml` hanya jalan sesudah "Pasang ke Supabase" atau lewat tombol. |
| C3 | Teks "Arahkan kursor ke batang" tidak berlaku di HP, karena layar sentuh tidak punya kursor. | Kecil | Teks keterangan grafik. |
| C4 | Persen porsi dibulatkan satu desimal, sehingga jumlahnya bisa 100,1% (periode 1: 13,5 + 4,5 + 16,2 + 57,7 + 8,2). | Kecil, biasa | Tidak diubah; cukup ditulis di keterangan. |

Yang dicek dan aman:
- tidak ada `innerHTML`, jadi nama dari data tidak bisa menjadi kode;
- semua total grafik sudah tanpa orang rahasia, dan diuji kebocorannya per divisi;
- THR dan hitungan PPh tertahan tanpa orang rahasia;
- header keamanan aktif dan konsol bersih;
- Supabase tidak diubah oleh G1.

## Isi paket

1. **C1, aturan baru**: gaji satu periode disembunyikan bila orang itu rahasia **pada hari mana pun di periode itu, atau rahasia sekarang**.
   - "Rahasia sekarang" tetap ikut supaya tidak ada yang lebih terbuka daripada hari ini.
   - Aturan ini diterapkan di `web/buat_data.py`, `web/isi_sheets.py`, `web/periksa_data.py` dan `web/periksa_sheets.py`.
   - Ditulis sebagai permintaan perubahan 05 dan satu baris kasus jebakan baru (F15c), bukan dengan mengubah F15/F15b.
2. **Uji C1**: di database uji, status satu orang rahasia diubah menjadi "tidak rahasia mulai periode 4". Hasil yang diharapkan:
   - periode 1–3 orang itu tetap tanpa angka di demo dan Sheets;
   - periode 4 tampil;
   - kedua pemeriksa lulus;
   - pemeriksa GAGAL bila aturannya dikembalikan ke "status terakhir".
3. **C2**: `terbitkan-demo.yml` juga berjalan sesudah "Isi Sheets" lulus.
   - Satu antrean, jadi tidak ada dua penerbitan bersamaan.
   - Pemeriksa demo tetap jadi syarat unggah.
4. **C3**: teks diganti menjadi "arahkan kursor atau ketuk 'Lihat angka'". **C4**: keterangan "persen dibulatkan, jumlahnya bisa 100,1%".
5. Uji GitHub lulus. Lalu tombol "Terbitkan demo" ditekan, Sheets diisi ulang lewat tombol "Isi Sheets", dan hasilnya dicek langsung di halaman, Sheets dan Supabase.
6. Laporan dan serah-terima diperbarui.

## Tidak diubah

Supabase tidak dipasang ulang: tidak ada migrasi dan tidak ada Pasang/Reset. Status rahasia orang sungguhan di Supabase tidak diubah; uji C1 hanya di database uji. Mesin hitung dan bot juga tidak diubah.

## Belum pasti

- [Kemungkinan Besar] Isi Sheets otomatis plus terbit demo menambah sekitar 2–3 menit kerja GitHub per file masuk. Ini tebakan dari lama run "Terbitkan demo" hari ini (sekitar 2–3 menit), belum diukur dalam alur penuh.
- [Menebak] Bila PRD v3.1 mengatur riwayat status rahasia secara berbeda, aturan C1 perlu dicocokkan lagi.
