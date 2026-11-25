# Rencana paket F2: HRD mengonfirmasi format file baru sekali lewat bot

Ditulis 25 November 2026. **Belum di-"buat".** Asal: diskusi pemilik 15.48–15.51 (F1, pilihan A): format file mesin yang belum
dikenal tidak ditebak, tetapi juga tidak boleh membuat HRD menunggu pembangun. Pemilik minta bot bertanya ke HRD dengan pilihan,
dan HRD boleh mengetik sendiri bila pilihan tidak ada.

## Masalah [Pasti, sesudah F1]

- Bot mengenali log tap dengan judul kolom yang ada di daftar (No.ID, Tgl/Waktu, Tanggal + Jam, dan lain-lain). File dengan judul
  lain, misalnya kolom waktu bernama "Waktu" saja (kasus jebakan F09) atau "Scan Date", ditolak dan pembangun diberi tahu.
- Menambah format baru sekarang butuh pembangun dan Claude (kirim contoh → ubah kode → uji → Pasang). Untuk PT yang memakai sistem
  sendiri, ini terlalu lambat.

## Isi paket

1. **Percakapan konfirmasi di bot.** Bila file berbentuk tabel ditolak karena kolomnya tidak dikenali (bukan karena rekap, file
   rusak, ID rusak, atau tanggal tercampur), file ditahan (cara yang sama dengan pertanyaan "dari mesin mana?" sekarang) dan bot
   bertanya ke HRD yang mengirim:
   1. "Kolom mana yang berisi ID karyawan?" — tombol berisi judul kolom yang ada di file, ditambah **[Lainnya, ketik sendiri]**;
   2. "Kolom mana yang berisi tanggal dan jam tap?" — tombol judul kolom, **[Tanggal dan jam di dua kolom]** (lalu ditanya kolom
      tanggal dan kolom jam), ditambah **[Lainnya, ketik sendiri]**;
   3. hanya bila tanggal di file bisa dibaca dua cara (semua angka ≤ 12): "Tanggal '03/04/2026' maksudnya?" — **[3 April 2026]**
      **[4 Maret 2026]**. Pilihan yang mustahil tidak ditampilkan (misalnya ada 25/04 → hanya hari/bulan);
   4. **contoh hasil bacaan**: 3 tap (awal, tengah, akhir file) dengan ID, hari, tanggal, dan jam, ditambah ringkasan (jumlah tap,
      jumlah ID, rentang tanggal, baris yang tidak terbaca) → **[Ya, simpan]** **[Tidak]**.
   Ketikan HRD dicocokkan dengan judul kolom yang benar-benar ada di file (tidak cocok → bot menyebut judul yang ada dan bertanya
   lagi). Ketikan tidak pernah langsung dipakai tanpa contoh hasil bacaan dan tombol "Ya, simpan".
2. **Profil format per mesin** (migrasi 0044): judul kolom yang dipilih, susunan tanggal (hari/bulan, bulan/hari, tahun-bulan-hari),
   sidik daftar judul kolom file, siapa yang menyetujui, dan kapan. Sesudah "Ya, simpan":
   - file yang ditahan langsung dihitung;
   - file berikutnya dari mesin yang sama **dengan judul kolom yang sama persis** dibaca otomatis memakai profil itu;
   - file dari mesin itu dengan judul kolom yang **berbeda** ditanyakan lagi (pengaman F09 tetap: perubahan format tidak lolos
     diam-diam).
3. **Pembangun diberi tahu** setiap ada profil baru (pesan berisi mesin, judul kolom, pilihan, dan contoh hasil bacaan, tanpa nama),
   dan bisa membatalkan profil dengan `/profilmesin` (daftar dan tombol Hapus). File yang sudah dihitung tidak berubah; file
   berikutnya ditanyakan lagi.
4. **Halaman unggah web**: file dengan format baru tetap ditolak dengan pesan "format baru: kirim file ini sekali lewat bot untuk
   konfirmasi" (konfirmasi hanya lewat bot, K1).
5. **Pembaca** (`sistem/urai/urai.ts`): `uraiTabel` menerima profil (kolom dan susunan tanggal) selain daftar sinonim; daftar sinonim
   F1 tidak berubah; tanpa profil, F09 tetap ditolak (uji F09 lama tetap lulus apa adanya).
6. **Permintaan perubahan 07** untuk kasus jebakan F09 (lihat bawah), disetujui pemilik sebelum "buat".
7. **Uji**: pembaca dengan profil (hari/bulan, bulan/hari, tahun-bulan-hari, dua kolom, ketikan), uji database (profil per mesin,
   judul berbeda ditanya lagi, hanya HRD/pembangun), uji pintu (seluruh percakapan: tombol, ketik sendiri cocok dan tidak cocok,
   pilihan tanggal mustahil tidak ditampilkan, Tidak → file tetap ditahan dan pembangun diberi tahu, Ya → dihitung, file kedua
   otomatis, `/profilmesin` hapus).
8. **Pasang** (migrasi 0044 + Edge Function) sesudah uji GitHub lulus; sidik gaji periode 1–4 tidak boleh berubah. **Uji nyata**:
   Claude menyiapkan file data demo dengan judul "Waktu" (F09); pemilik mengirim ke bot, menjawab pertanyaan, menekan "Ya, simpan";
   dicek Supabase; file kedua dengan judul yang sama terbaca otomatis.

## Usulan permintaan perubahan 07 (F09)

| | Bunyi |
| --- | --- |
| Sekarang | F09: File dengan kolom waktu bernama "Waktu" (format baru yang belum dikenal) → Ditolak dengan pesan format tidak dikenal; pemberitahuan segera |
| Usulan | F09: File dengan kolom waktu bernama "Waktu" (format baru yang belum dikenal) → **Tidak dihitung otomatis**: file ditahan, pembangun diberi tahu, dan HRD yang mengirim diminta memilih kolom sekali dengan contoh hasil bacaan. Dihitung hanya sesudah HRD menekan "Ya, simpan"; file berikutnya dari mesin yang sama dengan judul yang sama dibaca dengan profil itu; judul yang berbeda ditanyakan lagi |

Alasan: prinsip M8 (format baru tidak ditebak) tetap; yang berubah hanya siapa yang memastikan (HRD yang melihat data aslinya,
dengan contoh hasil bacaan) dan seberapa cepat. Keputusan pemilik 15.51.

## Keputusan untuk pemilik

| No | Pertanyaan | Pilihan | Saran Claude dan alasannya |
| --- | --- | --- | --- |
| K1 | Di mana konfirmasi dilakukan? | (a) bot saja; (b) bot dan halaman unggah web | **(a)**. Tombol dan ketik sendiri sudah ada polanya di bot (pertanyaan mesin, PIN); web butuh layar baru. Web bisa menyusul |
| K2 | Siapa yang boleh menyimpan profil? | (a) HRD dan pembangun; (b) pembangun saja | **(a)**. Tujuannya HRD tidak menunggu; pembangun tetap diberi tahu dan bisa membatalkan |
| K3 | Judul kolom berubah untuk mesin yang sudah punya profil | (a) ditanyakan lagi; (b) dipakai profil lama bila kolom yang dipilih masih ada | **(a)**. Sesuai F09: perubahan format tidak lolos diam-diam |

Tidak ada keputusan yang mengubah angka gaji atau membatasi akun pembangun.

## Analisa celah

| No | Celah | Penutup | Label |
| --- | --- | --- | --- |
| C1 | HRD salah pilih kolom (misalnya kolom nomor urut dianggap ID) | Contoh hasil bacaan + ringkasan (jumlah ID tak wajar terlihat); setelah dihitung, ID yang tidak dikenal muncul di "Perlu dicek"; pembangun bisa membatalkan profil | [Kemungkinan Besar] |
| C2 | HRD salah pilih susunan tanggal | Pilihan mustahil disembunyikan; contoh menampilkan nama hari (Senin/Minggu) yang mudah dicek; file yang sebagian tanggalnya mustahil tidak bisa disimpan | [Kemungkinan Besar] |
| C3 | Profil satu mesin dipakai untuk file mesin lain | Profil terikat kode mesin dan sidik judul kolom | [Pasti] |
| C4 | Percakapan menggantung (HRD tidak menjawab) | File tetap ditahan, tidak dihitung; penahanan hangus seperti pertanyaan mesin sekarang; pembangun sudah diberi tahu | [Kemungkinan Besar] |
| C5 | Ketikan berisi teks aneh atau panjang | Hanya dicocokkan dengan judul kolom yang ada; tidak disimpan selain judul yang cocok | [Pasti] |
| C6 | Format rekap atau file rusak masuk percakapan konfirmasi | Hanya penolakan "kolom tidak dikenali" yang masuk percakapan; rekap, rusak, ID rusak, tanggal tercampur tetap ditolak | [Pasti] |
| C7 | Uji lama F09 dan F1 berubah | Tanpa profil pembaca tetap menolak; uji pembaca lama tidak diubah | [Pasti] |

## Yang dipasang

Migrasi 0044 (tabel profil format mesin, fungsi api untuk percakapan, simpan, hapus) dan Edge Function, lewat workflow Pasang.

## Yang belum pasti

- [Menebak] Jumlah kode: percakapan bot sekitar 300–400 baris, migrasi sekitar 150 baris; diukur saat dibuat.
- [Kemungkinan Besar] Penahanan file memakai tabel yang sama dengan pertanyaan mesin (`pintu_tunda`); dipastikan saat dibuat.
