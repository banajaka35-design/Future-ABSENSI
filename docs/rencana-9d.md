# Rencana paket 9d: kerangka pasang untuk PT baru

Ditulis 25 November 2026, versi 2 (versi 1 terlalu besar: program kuesioner, jalur Drive, keputusan repo; dibuang atas
masukan pemilik 13.20). **Belum di-"buat".**

## Tujuan

Bila suatu hari ada PT yang mau memakai sistem, pemasangan tidak dimulai dari nol: langkahnya urut dan bahannya siap.
Kode sistem (mesin hitung, pembaca file mesin, bot, web HRD, Sheets, uji) dipakai ulang tanpa diubah. Yang dibuat baru per PT
hanya isi perusahaan (aturan, data karyawan) dan akun atas nama PT.

Yang hanya bisa dikerjakan saat PT sudah ada **tidak** dikerjakan di 9d: jawaban aturan PT, akun PT, data karyawan asli, cara
memuat data asli, repo PT, dan keputusan ulang hak akun pembangun.

## Alur pasang PT baru yang didukung kerangka

1. Wawancara HRD dengan daftar pertanyaan.
2. Buat repo privat PT (salinan repo ini).
3. Buat akun atas nama PT (daftar periksa).
4. Claude menyusun file susunan PT dari jawaban wawancara (bentuk sama dengan Pabrik A).
5. HRD mengisi templat karyawan.
6. Pasang ke Supabase PT dengan workflow yang sama.
7. Uji banding 1–2 periode dengan hitungan manual HRD.
8. Serahkan petunjuk pemakaian ke HRD.

## Isi paket

1. **Daftar pertanyaan untuk HRD** `docs/pasang/1-pertanyaan-hrd.md`. Bahasa biasa, bisa dicetak atau dikirim lewat WhatsApp.
   Setiap pertanyaan diberi catatan isian sistem yang diisinya (untuk pembangun/Claude), dan contoh jawaban dari Pabrik A.
   Disusun dari semua isian di `db/data_awal/pabrik_a_struktur.sql` dan kolom data karyawan, sehingga tidak ada isian sistem
   tanpa pertanyaan. Kelompok: perusahaan dan mesin absen, divisi dan shift, jadwal dan libur, gajian dan tutup buku, telat dan
   lembur, tunjangan dan potongan, cara bayar, persetujuan gaji, gaji rahasia.
2. **Daftar periksa akun** `docs/pasang/2-daftar-periksa-akun.md`: repo privat, Supabase (atas nama PT, wilayah, paket untuk
   cadangan), bot Telegram baru, Google Sheets + akun layanan, email pengirim dengan domain PT, secret yang harus diisi, dan yang
   wajib dimatikan di repo PT (Terbitkan demo, cadangan sebagai artifact GitHub). Disusun dari tabel "Sebelum dipasang" di
   `docs/serah-terima.md` (12 butir), semuanya punya langkah.
3. **Cara pasang memilih perusahaan** (satu-satunya perubahan kode): `db/pasang_supabase.sh` dan `db/data_awal/muat_karyawan.py`
   bisa diarahkan ke file susunan dan folder data karyawan perusahaan lain. Bila tidak diarahkan, tetap Pabrik A seperti sekarang,
   sehingga pemasangan demo tidak berubah dan **tidak perlu Pasang ulang ke Supabase**.
4. **Templat karyawan** `docs/pasang/templat-karyawan.csv` (kosong, kolom sama dengan data simulasi) dan
   `docs/pasang/4-isi-templat.md`: arti setiap kolom, isian yang boleh, kesalahan Excel yang sering terjadi (nol di depan ID hilang,
   tanggal berubah format).
5. **Cara uji banding** `docs/pasang/5-uji-banding.md`: sistem berjalan bersama hitungan manual HRD 1–2 periode; selisih per orang
   dicatat dan dijelaskan (sistem salah, manual salah, atau aturan belum dicatat); gaji baru dibayar memakai angka sistem setelah
   tidak ada selisih yang belum dijelaskan.
6. **Petunjuk pemakaian HRD** `docs/pasang/6-petunjuk-hrd.md`: kirim file mesin, perintah lewat chat dan web, perlu dicek,
   ajukan dan rilis gaji, keberatan karyawan, coba aturan. Bahasa HRD, bukan bahasa pembangun.
7. **Perawatan tahunan dan pembaruan** `docs/pasang/7-perawatan.md`: UMK, kalender libur dan cuti bersama, batas BPJS, cadangan,
   dan cara menarik perbaikan kode dari repo ini ke repo PT.
8. **Panduan utama** `docs/pasang/README.md`: alur 1–8 di atas, setiap langkah menunjuk ke dokumennya.
9. **Bukti (gerbang 3 Tahap 9):**
   - Uji otomatis baru di uji simulasi: Pabrik B dipasang lewat jalur "pilih perusahaan" (file `pabrik_b_struktur.sql` + data B)
     dan uji U5 Pabrik B tetap lulus; pemasangan tanpa pilihan tetap Pabrik A dan semua uji lama tetap lulus.
   - Uji daftar pertanyaan: setiap tabel yang diisi file susunan Pabrik A disebut di daftar pertanyaan (pemeriksaan otomatis
     sederhana, gagal bila ada tabel tanpa pertanyaan).
   - Uji coba manual oleh Claude: menjawab daftar pertanyaan untuk Pabrik B dari `docs/data-simulasi.md`, mengikuti panduan
     sampai database lokal terpasang, dan mencatat langkah yang macet. Hasilnya di laporan.

## Analisa celah

| No | Celah | Penutup | Label |
| --- | --- | --- | --- |
| V1 | Perubahan cara pasang merusak pemasangan demo | Bawaan tetap Pabrik A; uji database dan simulasi lama harus lulus dengan angka sama; demo tidak dipasang ulang | [Pasti] |
| V2 | Daftar pertanyaan melewatkan aturan yang dipakai sistem | Uji otomatis tabel ↔ pertanyaan (isi 9) | [Kemungkinan Besar] |
| V3 | Petunjuk HRD cepat usang bila fitur berubah | Petunjuk ditulis dari perintah yang ada sekarang; laporan paket berikutnya wajib menyebut bila petunjuk perlu diperbarui | [Menebak] |
| V4 | Data asli PT ikut masuk repo saat pemasangan nanti | Daftar periksa dan templat menegaskan data asli tidak masuk repo; cara memuat data asli diputuskan saat PT ada | [Kemungkinan Besar] |
| V5 | Angka aturan pemerintah 2027 belum ada | Bukan isi 9d; masuk daftar perawatan tahunan | [Pasti] |

## Yang dipasang

Tidak ada pemasangan Supabase, tidak ada migrasi, tidak ada perubahan Edge Function. Yang berubah: dokumen di `docs/pasang/`,
dua file pemasang (dengan bawaan tetap Pabrik A), dan uji simulasi.

## Yang belum pasti

- [Menebak] Jumlah pertanyaan sekitar 30–50; dihitung pasti saat dibuat.
- [Kemungkinan Besar] Gerbang 1 Tahap 9 ("HRD menjalankan satu bulan penuh tanpa bantuan") baru bisa dibuktikan saat PT pertama;
  berjalan di belakang menurut aturan 10.
