# Rencana paket G1: grafik di halaman demo (menunggu "buat")

18 November 2026 · dimajukan dari Tahap 9 untuk portofolio (diskusi pemilik 18 Nov 2026; syarat PRD v2 "web dibangun setelah hitungan terbukti benar" sudah terpenuhi: U2, U3, U5 lulus, angka demo = gudang) · acuan: PRD v2 bagian 10 (tiga grafik web), `docs/halaman-demo.md`, keputusan 6a-2 (tampilan transfer/tunai dipisah menyusul di halaman demo)

## Isi paket

1. **Dokumen dulu**: `docs/halaman-demo.md` versi 2 (bagian grafik, tampilan transfer/tunai, pemeriksaan baru) di-commit sebelum kode.
2. **Tiga grafik** (PRD v2 bagian 10), untuk periode yang sedang dipilih di halaman:
   - **Biaya per divisi**: batang berkelompok per divisi, tiga nilai: gaji pokok (komponen `gaji_pokok`), lembur (komponen `lembur`), dan potongan (total potongan, sama dengan arti "Total potongan" di Ringkasan).
   - **Telat per tanggal**: jumlah orang yang telat per tanggal dalam periode (hari berstatus hadir dengan menit telat > 0; arti sama dengan kolom "Telat (kali)" di Sheets).
   - **Porsi gaji per divisi**: bagian total gaji bersih tiap divisi, ditampilkan sebagai batang mendatar dengan persen (lebih mudah dibaca dan dibandingkan daripada diagram pai).
   - Divisi = divisi di hari terakhir periode (sama dengan halaman demo dan Sheets). Total per divisi **termasuk** orang rahasia, sama seperti total di Ringkasan; angka per orang rahasia tetap tidak tampil.
3. **Tampilan transfer/tunai dipisah**: daftar karyawan diberi pilihan Semua / Transfer / Tunai; rincian orang tunai menampilkan isi amplop (lembar per pecahan, aturan sama dengan Sheets 6a-2).
4. **Cara membuat**: grafik digambar sebagai SVG oleh kode halaman sendiri, **tanpa pustaka dari luar** (halaman tetap satu file statis, tidak memuat apa pun dari CDN). Panduan desain grafik (dataviz) dibaca sebelum kode grafik ditulis. Tampilan terang dan gelap mengikuti pengaturan perangkat, dan halaman tetap terbaca di layar HP.
5. **Data**: `web/buat_data.py` menambah ke `data.json` per periode: jumlah per divisi (orang, gaji pokok, lembur, potongan, gaji bersih), jumlah telat per tanggal; per orang: cara bayar dan isi amplop (bukan rahasia). Tetap salinan tetap; halaman tidak menyentuh Supabase.
6. **Pemeriksa** `web/periksa_data.py` ditambah, dengan perintah SQL sendiri: jumlah per divisi, telat per tanggal, cara bayar per orang, isi amplop = dibayar, jumlah lembar semua amplop = `hitung.pecahan_tunai`. Beda satu angka → tidak diunggah (sama seperti sekarang).
7. **Uji**: uji simulasi GitHub (yang sudah menjalankan pembuat data + pemeriksa) ditambah satu uji: satu angka grafik di `data.json` diubah → pemeriksa GAGAL. Semua uji GitHub harus lulus.
8. **Terbit**: workflow "Terbitkan demo" dijalankan lewat tombol (Claude memicunya) sesudah uji lulus.
9. **Dicek langsung**: halaman terbit dibuka di browser aplikasi Claude; tangkapan layar tiga grafik di ukuran layar komputer dan HP; angka satu divisi dan satu tanggal dicocokkan dengan Supabase.
10. **Laporan** `docs/laporan-grafik-demo.md` dan serah-terima.

## Tidak diubah

Supabase (tidak ada migrasi, tidak ada pemasangan), mesin hitung, Sheets, bot Telegram, kasus jebakan. Login, akun HRD/bos, dan "daftar perlu dicek" (PRD v2 bagian 10) tetap di Tahap 9.

## Belum pasti

- [Kemungkinan Besar] Ukuran `data.json` hanya bertambah sedikit (5 divisi dan sekitar 30 tanggal per periode); diukur saat dibuat.
- [Menebak] Di layar HP, grafik telat 30 batang mungkin terlalu rapat; bila begitu, label tanggal dijarangkan (tidak mengubah angka).
