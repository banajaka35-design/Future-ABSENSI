# Laporan paket D1: pengaman halaman demo publik

19 November 2026 · rencana `docs/rencana-d1.md` (di-"buat" pemilik 19 Nov 2026 14.32 WIB) · commit 9b79458

## Celah yang ditutup [Pasti]

Workflow "Terbitkan demo" berjalan otomatis sesudah setiap "Isi Sheets" dan menerbitkan gaji per orang dari Supabase ke https://future-absensi-demo.pages.dev/ (publik). Sebelum paket ini tidak ada pemeriksaan apakah data di Supabase masih data simulasi.

## Yang dibuat

1. `db/cek_hanya_simulasi.sh`: semua karyawan di database harus ada di `data/simulasi/*/induk/karyawan.csv` dengan ID dan nama yang sama. Satu saja tidak cocok → GAGAL (keluar 1). Hanya jumlah yang dicetak; ID dan nama tidak masuk log. Hanya membaca database: daftar karyawan diambil lalu dicocokkan di Python.
2. Workflow "Terbitkan demo": langkah "Pengaman - hanya data simulasi yang boleh terbit" paling awal sesudah klien Postgres terpasang. GAGAL → tidak ada data dibuat atau diunggah; halaman lama tetap.
3. Uji D1 di `sistem/uji/jalankan_simulasi.sh` (database simulasi Pabrik B): data simulasi → boleh terbit; satu karyawan asing → ditolak; nama karyawan simulasi beda satu huruf → ditolak; keadaan dikembalikan → boleh terbit lagi.

Dua kesalahan rancangan pertama yang tertangkap uji lokal sebelum dikirim [Pasti]:
- Galat sambungan database memberi pesan menyesatkan ("tabel karyawan tidak ada"); hasilnya tetap GAGAL. Diperbaiki: galat sambungan kini menghentikan skrip dengan pesan dari psql.
- Transaksi baca-saja Postgres tidak mengizinkan tabel sementara (cara pengaman Reset). Diganti: pencocokan di Python.

## Uji [Pasti]

- Lokal: skrip LULUS untuk database simulasi (1.044 karyawan), GAGAL untuk karyawan asing, GAGAL untuk nama beda satu huruf, GAGAL bila database tidak bisa dihubungi. Uji simulasi lengkap 123 lulus, 0 gagal (sebelumnya 119), 6 menit 41 detik.
- GitHub run 44481526827 lulus: database 467, simulasi 123 (4 uji D1), pintu 48, penyambung 23.

## Bukti nyata [Pasti]

- "Terbitkan demo" dipicu lewat tombol (`gh workflow run`, run 44482940850): lulus. Langkah pengaman: "LULUS: 1044 karyawan di database, semuanya data simulasi (1240 karyawan karangan di repo)"; pemeriksa demo 0 beda; terbit.
- Halaman terbit dicek langsung (`data.json` lewat browser): dibuat 2026-11-19 14:52 WIB; 1.044 karyawan; total keempat periode sama dengan Sheets dan Supabase (1.008 · 5.167.334.029; 1.007 · 8.191.235.519; 1.007 · 5.690.720.227; 1.003 · 4.983.863.768), 3 rahasia.

## Belum terbukti

- Jalur GAGAL hanya dibuktikan di uji otomatis dan lokal, tidak di Supabase sungguhan (butuh karyawan palsu di Supabase; dilarang aturan 8).
- [Kemungkinan Besar] Bila Terbitkan demo gagal karena pengaman, kabarnya hanya email bawaan GitHub, bukan Telegram.
- [Kemungkinan Besar] Memeriksa daftar karyawan cukup: data halaman demo (`web/buat_data.py`) hanya terikat ke karyawan; tanda "ID tidak dikenal" dari file asli tidak ikut diterbitkan.
- Logika pengaman ada dua salinan (Reset dan D1). Menyatukannya paket terpisah.

## Dokumen

Tabel "Sebelum dipasang untuk perusahaan sungguhan" di `docs/serah-terima.md` ditambah: halaman demo publik (D1), akses Sheets HRD lihat saja (T2), akses pembangun dan Claude ke gaji.

## Tidak diubah

Supabase (tanpa migrasi dan tanpa Pasang), bot, Isi Sheets, Reset.
