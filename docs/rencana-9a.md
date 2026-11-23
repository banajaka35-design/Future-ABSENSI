# Rencana paket 9a: web HRD (lihat saja)

Ditulis 23 November 2026. Acuan: `docs/rencana-tahap-9.md`. **Di-"buat" pemilik 23 Nov 2026 15.54 WIB dengan permintaan "analisa lagi kelemahan dan celahnya, lalu perbaiki"** (hasilnya di bagian "Analisa celah" di bawah; daftar isi sudah disesuaikan).

## Gunanya

Saat ini HRD hanya punya bot dan Sheets. Bot tidak cocok untuk menelusuri 1.000 orang, dan Sheets tidak menampilkan status harian per orang atau keberatan. Web HRD menampilkan semua itu dari gudang data dalam satu halaman, **tanpa mengubah apa pun**.

## Keadaan sekarang [Pasti, dicek di kode 23 Nov]

- Halaman unggah (`web/demo/unggah/`) sudah memakai masuk dengan kode email: Brevo, kode 6 angka berlaku 10 menit, dan hanya sidiknya yang disimpan. Hasil masuk adalah tautan unggah 15 menit.
- Halaman diterbitkan ke `future-absensi-demo.pages.dev` oleh workflow "Terbitkan demo". Data diambil langsung dari Edge Function `pintu-telegram`, yang hanya menerima permintaan dari alamat halaman demo (5d).
- Akun yang punya email hanya akun pembangun (`PEMBANGUN_EMAIL`).

## Isi paket

1. **Migrasi `0039_web_hrd.sql`**
   - Tabel `fakta.sesi_web`: hanya sidik kode sesi yang disimpan, beserta akun dan batas waktu. Sesi berlaku **2 jam** sejak masuk dan berakhir bila **30 menit** tidak dipakai (C4) dan bisa diakhiri dengan tombol Keluar. Kode email lama tetap dipakai untuk masuk.
   - Fungsi `api.web_sesi_buat` (dari kode email) dan satu pintu baca `api.web_hrd` (aksi: ringkasan, gaji, orang, perlu_dicek, keberatan, keluar) yang selalu memeriksa sesi dulu:
     - `ringkasan`: daftar periode dengan status, jumlah orang, total pendapatan, potongan, bersih, transfer, tunai, dan jumlah orang rahasia. Angkanya sama dengan tab Ringkasan di Sheets (tanpa orang rahasia, F15b).
     - `gaji`: baris per orang berisi ID, nama, divisi, cara bayar, bersih, dan dibayar. Orang rahasia ditulis "rahasia" tanpa angka (F15c).
     - `orang`: satu orang dalam satu periode. Isinya komponen gaji (`hitung.rincian_gaji`, kecuali orang rahasia), dan status harian dari baca tap terakhir (status, jadwal, jam masuk dan pulang, telat, lembur, lupa tap) beserta perintah HRD yang berlaku.
     - `perlu_dicek`: anomali baca tap periode itu (`hitung.anomali`, misalnya alpha beruntun, mesin tidak mengirim, ID tidak dikenal).
     - `keberatan`: keberatan terbuka dan yang sudah dijawab, berikut keputusannya.
   - Hanya akun aktif `hrd` dan `pembangun`. Akun yang dicabut (8f) langsung kehilangan sesinya.
   - Batas: 300 permintaan per sesi per jam.
2. **Edge Function:** jalur baru `hrd/...` di penyambung yang sama (`sistem/pintu/sambung.ts`), dengan pemeriksaan alamat asal yang sama seperti halaman unggah.
3. **Halaman `web/demo/hrd/index.html`:** satu file, tanpa pustaka luar.
   - Isinya: masuk dengan email lalu kode, tab Periode, Gaji (bisa dicari dengan ID atau nama dan diurutkan), rincian orang (kalender status harian), Perlu dicek, dan Keberatan.
   - Ada tombol Keluar. Tampilan nyaman di HP.
   - Diterbitkan bersama halaman demo. Halamannya tidak berisi data apa pun; semua data diminta setelah masuk.
4. **Uji**
   - Database:
     - sesi kedaluwarsa atau sudah diakhiri ditolak;
     - akun karyawan, bos, dan akun yang dicabut ditolak;
     - total sama dengan perhitungan Ringkasan Sheets;
     - orang rahasia tanpa angka;
     - peran `pintu`, `anon`, dan `authenticated` tidak bisa membaca tabel langsung.
   - Bot/penyambung: jalur `hrd/...` menolak alamat asal lain dan sesi palsu.
   - Halaman: pemeriksaan isi HTML (tidak ada data tertanam, tidak ada pustaka luar).
5. **Pasang ke Supabase** lewat cabang `pasang` setelah uji GitHub lulus. Lalu **Terbitkan demo** supaya halaman `/hrd/` terbit.
6. **Uji nyata:** pemilik masuk ke `/hrd/` dengan email pembangun. Lalu dicocokkan:
   - total periode 3 dan 4 dengan Sheets;
   - 3 orang (termasuk 10735) dengan Supabase;
   - orang rahasia tampil tanpa angka;
   - keberatan no. 1 dan 2 tampil.
   Sesudah Keluar, sesi ditolak.
7. **Dokumen:** `docs/laporan-9a.md` dan `docs/serah-terima.md`.

## Keputusan Claude

- [Kemungkinan Besar] **Sesi 2 jam**, bukan memakai tautan unggah 15 menit. Melihat data butuh waktu lebih lama daripada mengunggah file, dan 2 jam tetap pendek bila HP tertinggal.
- [Kemungkinan Besar] **Orang rahasia tetap tanpa angka di web, termasuk untuk akun pembangun.** Total lengkap tetap hanya lewat bot dengan PIN (8d), supaya hanya ada satu jalur ke gaji rahasia.
- [Kemungkinan Besar] **Hanya melihat.** Menjawab keberatan dan memberi perintah tetap lewat bot sampai paket 9b.
- **Anomali gaji (lembur divisi naik, dan sebagainya)** sudah tampil di halaman demo dengan aturan rahasia 6a-4. Di 9a hanya anomali baca tap yang ditampilkan, supaya aturan rahasia tidak diulang di tempat kedua.

## Belum pasti

- [Menebak] Lama pengerjaan belum diukur. Paket ini lebih besar dari 8e karena ada halaman baru.
- [Kemungkinan Besar] Waktu muat daftar gaji 1.000 orang belum diukur. Bila lambat, daftar dibagi per halaman.
- HRD sungguhan belum punya email di sistem. Uji nyata memakai email pembangun.

## Analisa celah (23 Nov 2026 15.55 WIB) dan perbaikannya

| No | Celah atau kelemahan | Akibat bila dibiarkan | Perbaikan (masuk paket ini) | Label |
| --- | --- | --- | --- | --- |
| C1 | Aturan "siapa rahasia" ditulis ulang di tempat ketiga | Web bisa membuka gaji yang di Sheets disembunyikan bila aturannya berbeda sedikit saja | Memakai fungsi yang sudah ada, `fakta.rahasia_di_periode` (F15c, sama dengan bot). Uji: jumlah orang dan total web = cara hitung Ringkasan Sheets | [Pasti] |
| C2 | Alasan keberatan, nama, dan catatan ditulis karyawan/HRD lalu ditampilkan di halaman | Skrip jahat dalam teks (XSS) bisa mencuri sesi HRD | Halaman hanya memakai `textContent`/`createElement`, tidak pernah `innerHTML` untuk data. Uji memeriksa file halaman: `innerHTML` hanya boleh diisi teks kosong. CSP 6f tetap memblok skrip asing | [Pasti] |
| C3 | Kode sesi disimpan di `localStorage` | Bertahan berhari-hari di HP, mudah dicuri | Kode sesi hanya di memori dan `sessionStorage` (hilang saat tab ditutup); dikirim di isi POST, tidak pernah di alamat (URL) | [Pasti] |
| C4 | Sesi 2 jam tanpa batas diam | HP yang tertinggal terbuka tetap bisa dipakai 2 jam | Batas diam **30 menit** ditambah batas mutlak 2 jam | [Kemungkinan Besar] |
| C5 | Pemeriksaan kode email disalin dari fungsi lama | Aturan 5 kali salah / sekali pakai bisa berbeda antara unggah dan web HRD | Pemeriksaan kode email dipindah ke satu fungsi bersama (`fakta.pakai_kode_email`); `api.pintu_tukar_kode_email` lama ikut memakainya (uji 140/150 lama tetap harus lulus) | [Pasti] |
| C6 | Halaman baru tidak terdaftar di header keamanan | Skrip halaman diblok CSP (halaman mati) atau, bila CSP dilonggarkan, terbuka XSS | `web/buat_headers.py` ditambah `hrd/index.html` (sidik skrip), uji `--periksa` di CI | [Pasti] |
| C7 | Jawaban data bisa tersimpan di cache peramban/perantara | Gaji terbaca dari cache sesudah keluar | Semua jawaban jalur `hrd/` memakai `cache-control: no-store` | [Pasti] |
| C8 | Akun dicabut (8f) atau peran berubah | Sesi lama tetap jalan sampai 2 jam | Setiap permintaan memeriksa ulang akun aktif dan peran `hrd`/`pembangun`; `/cabutakun` juga mengakhiri semua sesi akun itu | [Pasti] |
| C9 | Daftar perintah HRD per orang memuat kolom `nilai` (jumlah kasbon) | Uang orang rahasia terbuka lewat jalur perintah | Daftar perintah hanya jenis, tanggal, asal, dan status batal; tanpa `nilai` | [Pasti] |
| C10 | Versi data yang ditampilkan berbeda dengan Sheets | HRD melihat angka berbeda di dua tempat | Sama dengan Sheets: versi gaji terakhir, dan hasil harian dari versi baca yang dipakai versi gaji itu (`versi_sumber`); periode tanpa gaji memakai baca tap terakhir | [Pasti] |
| C11 | Permintaan tanpa batas | Satu sesi bisa membebani database | Batas 300 permintaan per sesi per jam; batas kode email lama (3 per 15 menit, 50 per jam) tetap | [Pasti] |
| C12 | Email kode berjudul "unggah file" dipakai juga untuk web HRD | HRD bingung | Judul email mengikuti tujuan: "Kode masuk web HRD" | [Pasti] |
| C13 | Halaman ada di situs demo publik | Untuk perusahaan sungguhan, alamat demo tidak boleh dipakai (D1) | Tetap di demo untuk 9a; dicatat di tabel "Sebelum dipasang" bahwa web HRD perusahaan memakai alamat sendiri (paket 9d) | [Pasti] |
| C14 | Pemakaian tidak tercatat | Tidak bisa ditelusuri siapa membuka data | `fakta.sesi_web` menyimpan akun, waktu masuk, terakhir dipakai, jumlah permintaan, dan waktu keluar | [Pasti] |
