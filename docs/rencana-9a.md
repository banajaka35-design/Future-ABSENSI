# Rencana paket 9a: web HRD (lihat saja)

Ditulis 23 November 2026. Acuan: `docs/rencana-tahap-9.md`. **Belum di-"buat".**

## Gunanya

Saat ini HRD hanya punya bot dan Sheets. Bot tidak cocok untuk menelusuri 1.000 orang, dan Sheets tidak menampilkan status harian per orang atau keberatan. Web HRD menampilkan semua itu dari gudang data dalam satu halaman, **tanpa mengubah apa pun**.

## Keadaan sekarang [Pasti, dicek di kode 23 Nov]

- Halaman unggah (`web/demo/unggah/`) sudah memakai masuk dengan kode email: Brevo, kode 6 angka berlaku 10 menit, dan hanya sidiknya yang disimpan. Hasil masuk adalah tautan unggah 15 menit.
- Halaman diterbitkan ke `future-absensi-demo.pages.dev` oleh workflow "Terbitkan demo". Data diambil langsung dari Edge Function `pintu-telegram`, yang hanya menerima permintaan dari alamat halaman demo (5d).
- Akun yang punya email hanya akun pembangun (`PEMBANGUN_EMAIL`).

## Isi paket

1. **Migrasi `0039_web_hrd.sql`**
   - Tabel `fakta.sesi_web`: hanya sidik kode sesi yang disimpan, beserta akun dan batas waktu. Sesi berlaku **2 jam** sejak masuk dan bisa diakhiri dengan tombol Keluar. Kode email lama tetap dipakai untuk masuk.
   - Fungsi `api.web_sesi_buat` (dari kode email), `api.web_sesi_akhiri`, dan fungsi baca yang semuanya memeriksa sesi:
     - `api.web_ringkasan`: daftar periode dengan status, jumlah orang, total pendapatan, potongan, bersih, transfer, tunai, dan jumlah orang rahasia. Angkanya sama dengan tab Ringkasan di Sheets (tanpa orang rahasia, F15b).
     - `api.web_gaji_periode`: baris per orang berisi ID, nama, divisi, cara bayar, bersih, dan dibayar. Orang rahasia ditulis "rahasia" tanpa angka (F15c).
     - `api.web_orang`: satu orang dalam satu periode. Isinya komponen gaji (`hitung.rincian_gaji`, kecuali orang rahasia), dan status harian dari baca tap terakhir (status, jadwal, jam masuk dan pulang, telat, lembur, lupa tap) beserta perintah HRD yang berlaku.
     - `api.web_perlu_dicek`: anomali baca tap periode itu (`hitung.anomali`, misalnya alpha beruntun, mesin tidak mengirim, ID tidak dikenal).
     - `api.web_keberatan`: keberatan terbuka dan yang sudah dijawab, berikut keputusannya.
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
