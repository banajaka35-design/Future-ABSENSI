# Rencana paket 9d: paket pasang

Ditulis 25 November 2026. **Belum di-"buat".** Isi 9d menurut `docs/rencana-tahap-9.md`: kuesioner, templat unggah data
karyawan asli, dan panduan memasang dari nol. Gerbang Tahap 9 no. 3: "Perusahaan contoh baru (Pabrik B) bisa dipasang dari nol
hanya dengan kuesioner dan templat."

## Keadaan sekarang [Pasti, diperiksa 25 Nov]

| Hal | Sekarang | Masalahnya untuk perusahaan sungguhan |
| --- | --- | --- |
| Aturan dan susunan perusahaan | Ditulis tangan sebagai SQL: `db/data_awal/pabrik_a_struktur.sql` (131 baris) dan `pabrik_b_struktur.sql` (128 baris). Isinya mesin, divisi, jam kerja, rotasi regu, jadwal kantor, kalender, pengaturan, toleransi, lembur, UMK, THR, cuti, batas potongan, komponen tidak tetap | Perusahaan baru butuh orang yang bisa menulis SQL. Tidak ada daftar pertanyaan untuk HRD |
| Aturan pemerintah | Ikut di file per pabrik (pengali lembur, BPJS) dan sebagian di `aturan_resmi.sql` | Angka pemerintah tersalin di setiap perusahaan, rawan beda |
| Data karyawan | CSV karangan di `data/simulasi/<pabrik>/induk/` (karyawan, pemetaan ID mesin, mutasi regu), dimuat `muat_karyawan.py` | Data asli tidak boleh masuk repo. Belum ada templat kosong dan pemeriksa isian |
| Pemasangan | `db/pasang_supabase.sh` dan workflow "Pasang ke Supabase" selalu memuat Pabrik A | Tidak bisa memilih perusahaan. Repo ini publik, jadi log workflow terlihat umum |
| Panduan | Tabel "Sebelum dipasang untuk perusahaan sungguhan" di `docs/serah-terima.md` (12 butir) | Belum berupa langkah urut yang bisa diikuti |

## Usulan: dipecah tiga, "buat" satu per satu

### 9d-1: kuesioner dan pembuat susunan perusahaan (tanpa menyentuh Supabase)

1. **Folder baru `pasang/`** (dicatat di tabel struktur folder CLAUDE.md). **Kuesioner** `pasang/kuesioner-contoh.toml`: satu file teks berisi pertanyaan berkelompok dengan penjelasan di setiap baris.
   Isinya mesin, divisi (pola, jumlah regu, mesin), jam kerja, rotasi, jadwal kantor, libur perusahaan, pengaturan PRD bagian 11
   (pola hari kerja, lembur otomatis/perlu perintah, cuti bersama, pembulatan tunai, premi, uang makan, shift malam, alur rilis,
   tutup buku, gajian), toleransi, lembur, UMK wilayah, THR, cuti, batas potongan, nominal komponen tidak tetap.
2. **Kuesioner Pabrik A dan Pabrik B** diisi Claude dari file SQL yang ada sekarang (`pasang/pabrik_a.toml`, `pasang/pabrik_b.toml`).
3. **Pembuat susunan** `pasang/buat_susunan.py` (Python, pustaka bawaan saja): kuesioner → SQL. Kuesioner yang salah ditolak
   dengan pesan bahasa Indonesia per isian (misalnya divisi memakai mesin yang tidak ada, regu rotasi tidak cocok dengan siklus,
   tanggal gajian di luar 1–28, UMK kosong).
4. **Aturan pemerintah dipisah** dari file per pabrik ke satu file bersama (pengali lembur, BPJS, kalender nasional). Isinya tidak
   berubah. Yang diisi perusahaan hanya hal yang memang pilihan perusahaan.
5. **Uji gerbang 3 (otomatis, masuk CI):** pasang Pabrik A dan Pabrik B dari kuesioner ke database baru, lalu bandingkan semua
   tabel `induk` dan `aturan` dengan hasil file SQL tulisan tangan: harus sama persis. Sesudah itu uji U5 Pabrik B (kunci jawaban)
   dijalankan di atas hasil kuesioner dan harus tetap lulus. Uji tolak: 6 contoh kuesioner salah harus ditolak.
6. Pemasangan demo di Supabase **tidak diubah** di 9d-1: tetap memakai file SQL lama. Bukti kesamaan cukup dari uji.

### 9d-2: templat data karyawan dan jalur muat

1. **Templat kosong** `pasang/templat-karyawan.csv` dengan kolom yang sama seperti data simulasi (ID, nama, divisi, regu, mulai,
   gaji pokok, tunjangan tetap, PTKP, cara bayar, wajib tap, gaji rahasia), ditambah pemetaan ID mesin dan saldo cuti awal.
   Bisa dibuka dan disimpan dari Excel atau Google Sheets (CSV UTF-8).
2. **Pemeriksa templat** `pasang/periksa_karyawan.py`: menolak ID ganda, divisi/regu yang tidak ada di kuesioner, tanggal salah,
   PTKP tidak dikenal, gaji di bawah UMK pada 12 bulan pertama (sama dengan K3 9b-2), orang rahasia yang dibayar tunai (aturan 8d).
   Laporan per baris dalam bahasa Indonesia. Tidak ada yang dimuat sebelum semua baris lulus.
3. **Jalur muat** sesuai keputusan K3 di bawah.
4. Uji: Pabrik B dimuat dari templat (isi = CSV simulasi B) sama persis dengan cara lama; 8 contoh templat salah ditolak.

### 9d-3: panduan pasang dan pemisahan demo/perusahaan

1. **Panduan** `docs/panduan-pasang.md`: langkah urut dari nol. Isinya membuat repo privat dari repo ini, membuat proyek
   Supabase (wilayah, paket berbayar untuk cadangan), mengisi secret, bot Telegram baru, Sheets dan akun layanan, Brevo dengan
   domain sendiri, mengisi kuesioner bersama HRD, memuat templat, uji pertama, dan hal yang harus dimatikan (Terbitkan demo,
   penyambung Claude). Setiap butir tabel "Sebelum dipasang" punya langkahnya.
2. **Pemasangan memilih perusahaan:** `pasang_supabase.sh` membaca kuesioner perusahaan, tidak lagi selalu Pabrik A.
   Demo memakai `pasang/pabrik_a.toml`. Ini **mengubah workflow Pasang demo**, sehingga perlu satu kali Pasang ke Supabase dengan
   bukti: sidik gaji periode 4 tetap `c427e5a53c5f` dan isi tabel `induk`/`aturan` sama sebelum dan sesudah.
3. **Penjaga di repo perusahaan:** workflow Terbitkan demo dan Cadangan sebagai artifact menolak berjalan bila repo publik atau
   bila ada karyawan bukan simulasi (memperluas pengaman D1).
4. **Uji coba panduan:** Claude mengikuti panduan sendiri untuk memasang Pabrik B ke database lokal kosong, hanya dari kuesioner
   dan templat. Langkah yang macet diperbaiki di panduan. Ini bukti gerbang 3 yang kedua (cara manusia, bukan hanya uji otomatis).

## Keputusan untuk pemilik

| No | Pertanyaan | Pilihan | Saran Claude dan alasannya |
| --- | --- | --- | --- |
| K1 | Bentuk kuesioner | (a) file teks TOML yang diisi pembangun saat wawancara HRD; (b) Google Sheets yang diisi HRD sendiri | **(a)**. Bisa dibaca Python tanpa pustaka tambahan, bisa diberi penjelasan per baris, dan perubahannya tercatat di Git. HRD tetap diwawancarai; yang mengetik pembangun. (b) butuh penyambung Sheets dan pemeriksaan yang lebih rumit [Kemungkinan Besar] |
| K2 | Bentuk templat karyawan | (a) CSV UTF-8; (b) file Excel (.xlsx) | **(a)**. Excel dan Sheets bisa menyimpan CSV; Python membacanya tanpa pustaka luar. Risikonya, Excel bisa mengubah ID "00123" jadi angka; pemeriksa menolak ID yang kehilangan nol di depan, dan panduan menjelaskan cara menyimpan sebagai teks [Kemungkinan Besar] |
| K3 | Jalur memuat data karyawan asli (data tidak boleh masuk repo) | (a) file ditaruh di folder Drive tertutup milik perusahaan, lalu workflow "Muat karyawan" di repo privat perusahaan mengambilnya dengan akun layanan; (b) pembangun mengirim file ke bot Telegram, bot memeriksa, menampilkan pratinjau, lalu memuat setelah dikonfirmasi PIN; (c) disalin manual dari komputer pemilik | **(a)**. Mengikuti aturan 8 (Supabase hanya lewat workflow), memakai pola akun layanan yang sudah ada (Sheets), dan tidak butuh migrasi atau Edge Function baru. (b) lebih nyaman tapi menambah kode bot dan migrasi. (c) melanggar aturan 8 |
| K4 | Repo untuk perusahaan sungguhan | (a) repo privat baru per perusahaan, dibuat dari repo ini; (b) satu repo dengan GitHub Environments per perusahaan | **(a)**. Repo ini publik; log dan cadangan perusahaan tidak boleh di sini (syarat 25 Nov). Kekurangannya, perbaikan kode harus ditarik ke tiap repo; untuk satu–dua perusahaan masih ringan [Kemungkinan Besar] |
| K5 | Urutan | (a) 9d-1 → 9d-2 → 9d-3, "buat" satu per satu; (b) ketiganya sekaligus | **(a)**. 9d-1 tidak menyentuh Supabase dan sudah membuktikan gerbang 3 secara otomatis; 9d-3 satu-satunya yang memicu Pasang |

Tidak ada pilihan di sini yang membatasi akun pembangun. Hak penuh akun pembangun untuk perusahaan sungguhan tetap tercatat
"diputuskan ulang saat pemasangan pertama" dan **tidak** diputuskan di 9d.

## Analisa celah

| No | Celah | Penutup | Label |
| --- | --- | --- | --- |
| V1 | Pembuat susunan menghasilkan aturan sedikit berbeda dari SQL tulisan tangan, sehingga gaji Pabrik A/B berubah diam-diam | Uji membandingkan isi semua tabel `induk` dan `aturan`, lalu U5 Pabrik B dengan kunci jawaban; demo tidak diganti sebelum 9d-3 | [Pasti] |
| V2 | Kuesioner tidak bisa menampung pola jadwal perusahaan lain (misalnya rotasi 3 regu 12 jam) | Rotasi ditulis sebagai siklus kode bebas, sama dengan tabel `induk.pola_rotasi` sekarang; pola yang tidak bisa ditulis dicatat sebagai temuan, tidak ditebak | [Kemungkinan Besar] |
| V3 | Data asli bocor lewat log workflow | Pemeriksa hanya mencetak nomor baris dan nama isian, tidak mencetak nama, gaji, atau rekening; repo perusahaan privat (K4) | [Kemungkinan Besar] |
| V4 | Excel merusak isi CSV (nol di depan ID, tanggal jadi format lokal, pemisah titik koma) | Pemeriksa menolak dengan pesan jelas; panduan menjelaskan cara menyimpan | [Kemungkinan Besar] |
| V5 | Aturan pemerintah yang dipisah menjadi satu file membuat demo berbeda. Contoh nyata: batas atas JP di file Pabrik A ditulis 10.547.000, lalu dibetulkan oleh `aturan_resmi.sql` dengan menutup baris lama dan menambah baris baru (paket 16 Nov). Bila pemisahan langsung menulis angka yang benar, riwayat baris di demo berbeda dari perusahaan baru | Perusahaan baru langsung memakai angka resmi bertanggal; demo tetap memakai urutan lama (file Pabrik A + `aturan_resmi.sql`). Uji V1 membandingkan hasil akhir yang berlaku per tanggal, bukan nomor baris; perbedaan riwayat dicatat di laporan | [Kemungkinan Besar] |
| V6 | Panduan cepat usang setelah perubahan kode | Uji coba panduan (9d-3 butir 4) diulang setiap ada perubahan cara pasang; dicatat di serah-terima | [Menebak] |
| V7 | Angka aturan pemerintah untuk 2027 (UMK, batas JP, kalender libur) belum ada | Bukan isi 9d; panduan mencantumkan pemeriksaan tahunan sebelum Januari | [Pasti] |

## Yang dipasang

- 9d-1 dan 9d-2: tidak ada pemasangan Supabase, tidak ada migrasi, tidak ada perubahan Edge Function.
- 9d-3: satu kali Pasang ke Supabase demo (karena cara pasang berubah), dengan bukti sidik gaji periode 4 tetap `c427e5a53c5f`.

## Yang belum pasti

- [Menebak] Jumlah pertanyaan kuesioner sekitar 40–60 isian; dihitung pasti saat 9d-1 dibuat.
- [Kemungkinan Besar] Gerbang 1 ("HRD menjalankan satu bulan penuh tanpa bantuan") tidak bisa dibuktikan di 9d karena belum ada
  HRD sungguhan. Menurut aturan 10, gerbang ini berjalan di belakang dan dimulai saat perusahaan pertama dipasang.
