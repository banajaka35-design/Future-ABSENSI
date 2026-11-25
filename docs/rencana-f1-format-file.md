# Rencana paket F1: pembaca berbagai format file mesin

Ditulis 25 November 2026. **Belum di-"buat".**

## Masalah [Pasti, ditemukan 25 Nov 15.24–15.30]

- Pemilik mengirim file mesin asli "ABSEN_OKTOBER_MOF.xls" (6 orang, 258 tap, Oktober 2026). Bot dan halaman unggah
  **menolaknya**: "Format file tidak dikenal". Pembaca (`sistem/urai/urai.ts`) hanya membaca teks CSV dan `attlog.dat`; file
  dibuka di `sistem/pintu/inti.ts` sebagai teks UTF-8 (`alat.urai(teks)`), padahal `.xls` adalah file biner.
- Isi file itu sudah berbentuk log tap mentah dengan kolom yang dikenali sistem. Setelah disimpan sebagai CSV di folder sementara
  (tidak masuk repo): 258 tap, 0 baris ditolak; dipasang ke database lokal sementara lewat jalur PT (9d) dan dikirim lewat jalur
  bot: absen harian dan gaji terhitung; Orang 1 tanggal 1–9 Okt cocok dengan file asli (termasuk tap sore berstatus "C/Masuk" dibaca
  pulang, sesuai kasus A01).
- Kekurangan ini **sudah diketahui sejak Tahap 3** (`docs/laporan-tahap-3.md` temuan 2: "File mesin asli berbentuk .xls…
  Pembuka .xls dipasang di Edge Function Tahap 5"; `docs/serah-terima.md` syarat Tahap 5), tetapi tidak masuk daftar isi paket
  Tahap 5 sehingga tidak pernah dibuat. Semua uji lulus karena data simulasi berbentuk CSV.
- Pemilik minta format mesin lain diakomodasi sekalian (15.30). Contoh file sungguhan dari merek lain **tidak ada**; pengetahuan
  tentang merek lain berstatus [Menebak] sampai ada contoh.

## Isi paket

1. **Pembuka file tanpa pustaka luar** (aturan yang sama dengan pembaca sekarang: bisa dipakai di Node dan Deno), di
   `sistem/urai/`:
   - `.xls` (Excel 97–2003, BIFF8 di dalam berkas OLE): string bersama, sel teks, angka, dan rumus bernilai teks; lembar pertama
     yang judulnya dikenali;
   - `.xlsx` (Excel baru, ZIP + XML; pembuka ZIP memakai `DecompressionStream` bawaan Node/Deno);
   - `.csv` / `.txt`: pemisah koma, titik koma, atau tab dikenali otomatis; huruf UTF-8, UTF-8 dengan BOM, UTF-16 (simpanan Excel
     "Unicode text"), atau Windows-1252 (CSV dari Excel lama);
   - `attlog.dat` tetap seperti sekarang.
   Jenis file dikenali dari isinya (tanda awal berkas), bukan dari nama file.
2. **Pengenal kolom yang luwes** untuk log tap mentah:
   - ID: `No.ID`, `ID`, `AC-No.`, `PIN`, `NIK`, `No. Pegawai`, `Employee ID` (daftar sinonim, [Menebak] di luar `No.ID`);
   - waktu: satu kolom (`Tgl/Waktu`, `Waktu`, `Date Time`, `Time`) **atau** dua kolom (`Tanggal` + `Jam`);
   - nama dan status **tidak wajib**; masuk/pulang tetap ditentukan dari jam (kasus A01, perilaku sekarang);
   - tanggal teks (`dd/mm/yyyy`, `dd-mm-yyyy`, `yyyy-mm-dd`, jam dengan titik atau titik dua, dengan atau tanpa detik) dan tanggal
     angka Excel (termasuk pengaturan tanggal 1904 di Excel Mac).
3. **Penjaga** (file ditolak dengan alasan yang bisa dipahami HRD, tidak ditebak):
   - tanggal bercampur hari/bulan dan bulan/hari (kasus A10, perilaku sekarang);
   - ID yang disimpan Excel sebagai angka dan sudah kehilangan digit (lebih dari 15 angka) atau tertulis `1,98E+17` (kasus F01);
   - judul kolom ganda atau tidak lengkap (misalnya dua kolom yang sama-sama dikenali sebagai ID);
   - file bentuk **rekap** (kolom Masuk/Pulang per hari): ditolak dengan pesan "kirim log/data absensi mentah dari aplikasi mesin";
   - berkas rusak atau sengaja dibuat aneh: batas ukuran sesudah dibuka, batas jumlah baris (65.536 untuk `.xls`, 200.000 untuk
     lainnya), pembuka berhenti bila struktur berkas berputar.
4. **Pintu masuk diubah**: bot dan halaman unggah meneruskan **isi biner** file ke pembaca (sekarang diubah ke teks dulu). Sidik
   file tetap dari isi biner (perilaku sekarang).
5. **Alat cek contoh file** `sistem/urai/cek_file.ts`: membaca satu file tanpa menyimpan apa pun dan menulis jenis file, kolom yang
   dikenali, jumlah orang, jumlah tap, rentang tanggal, dan baris yang ditolak, **tanpa menulis nama**. Dipakai di langkah 1
   panduan pasang (`docs/pasang/README.md` dan pertanyaan A5 diperbarui).
6. **Uji** (`sistem/urai/uji_urai.ts` dan uji simulasi):
   - berkas uji dibuat dari data simulasi Pabrik A/B dalam bentuk `.xls`, `.xlsx`, CSV titik koma, TXT UTF-16, Windows-1252,
     tanggal + jam terpisah, tanpa kolom status, tanggal angka Excel; disimpan di repo (isinya karangan);
   - satu berkas `.xls` meniru **persis** susunan file asli pemilik (5 kolom, ID 18 angka, "C/Masuk" sore) dengan nama dan ID
     karangan; data asli tidak masuk repo;
   - **uji kesamaan:** satu periode Pabrik A dalam bentuk CSV, `.xls`, dan `.xlsx` menghasilkan daftar tap yang sama persis, lalu
     sidik hasil absen yang sama (seperti uji U6);
   - uji tolak untuk setiap penjaga di butir 3;
   - waktu baca berkas sebesar satu periode Pabrik A (±40.000 baris) diukur, karena Edge Function gratis dibatasi 2 detik CPU
     (`docs/laporan-kelayakan-teknis.md`).
7. **Pasang** ke Supabase (Edge Function; tanpa migrasi bila tidak diperlukan) sesudah uji GitHub lulus. Sidik gaji periode 1–4
   tidak boleh berubah.
8. **Uji nyata:** Claude mengirim satu berkas `.xls` berisi data demo karangan (tap yang sudah ada di demo, sehingga gaji tidak
   berubah); pemilik mengirimnya ke bot dari HP; dicek di Supabase (kiriman tercatat, jumlah tap sama, sidik gaji tetap).
   File asli pemilik **tidak** dikirim ke bot demo.

## Keputusan untuk pemilik

| No | Pertanyaan | Pilihan | Saran Claude dan alasannya |
| --- | --- | --- | --- |
| K1 | Cara membuka `.xls`/`.xlsx` | (a) pembuka ditulis sendiri tanpa pustaka luar; (b) pustaka SheetJS dari situs resminya (rencana Tahap 3) | **(a)**. Situs SheetJS tidak bisa diakses dari komputer kerja Claude, jadi (b) tidak bisa diuji di sini [Pasti, laporan Tahap 3]; versi npm-nya punya celah keamanan yang diketahui. (a) lebih banyak kode, tetapi cukup untuk membaca sel dan bisa diuji penuh |
| K2 | File rekap | (a) ditolak dengan pesan yang menunjukkan cara ekspor log mentah; (b) diterima sebagai jalur cadangan | **(a)**, sesuai diskusi 15.33–15.34. Ditambahkan nanti bila ada PT yang hanya punya rekap |

Tidak ada keputusan yang mengubah angka gaji atau membatasi akun pembangun.

## Analisa celah

| No | Celah | Penutup | Label |
| --- | --- | --- | --- |
| C1 | Tanggal salah baca (hari/bulan tertukar, tanggal angka Excel bergeser karena sistem 1904 atau tahun kabisat 1900 Excel) | Penjaga A10; pengaturan tanggal berkas dibaca; uji tanggal angka di kedua sistem; uji kesamaan CSV = xls = xlsx | [Pasti] |
| C2 | ID 18 angka rusak karena disimpan sebagai angka | Ditolak (lebih dari 15 angka bermakna atau notasi ilmiah) | [Pasti] |
| C3 | Pembacaan terlalu lambat untuk Edge Function (2 detik CPU) | Diukur dengan berkas sebesar Pabrik A; bila lewat, batas baris diturunkan dan dicatat | [Kemungkinan Besar] |
| C4 | Berkas berbahaya (ZIP bom, struktur OLE berputar) membuat Edge Function macet | Batas ukuran sesudah dibuka, batas sektor/baris, deteksi putaran; uji dengan berkas rusak | [Kemungkinan Besar] |
| C5 | Sinonim kolom salah kenali (misalnya kolom "ID" yang berisi kode departemen) | Wajib ada kolom waktu yang terbaca untuk hampir semua baris; dua kolom ID → ditolak; alat cek dipakai saat pasang PT | [Kemungkinan Besar] |
| C6 | Data yang sama dikirim dalam dua bentuk (CSV lalu XLS) tercatat dua kali | Tap identik dihitung satu (kasus A06, sudah ada); diuji ulang | [Kemungkinan Besar] |
| C7 | Format merek lain tidak cocok dengan tebakan sinonim | Ditolak dengan pesan jelas, bukan salah hitung; format baru ditambahkan dari contoh sungguhan | [Menebak] untuk merek lain |
| C8 | Perubahan pembaca merusak hasil file CSV yang sudah ada | Uji U1/U4/U6/sidik lama harus tetap lulus dengan angka sama | [Pasti] |

## Yang dipasang

Edge Function (bot dan halaman unggah) lewat workflow Pasang. Migrasi hanya bila pesan tolak baru perlu dikenali database
(dipastikan saat dibuat). Halaman web tidak berubah.

## Yang belum pasti

- [Menebak] Besarnya kode pembuka `.xls` (berkas OLE + BIFF8) sekitar 300–500 baris; diukur saat dibuat.
- [Kemungkinan Besar] Tanggal pada file asli pemilik tersimpan sebagai teks (terlihat dari isinya), tetapi file dari mesin lain
  bisa menyimpan tanggal sebagai angka Excel; keduanya diuji.
