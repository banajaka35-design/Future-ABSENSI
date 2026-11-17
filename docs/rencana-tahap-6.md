# Rencana Tahap 6 (draf daftar paket, belum di-"buat")

17 November 2026 · ditulis untuk dilanjutkan 18 Nov 2026 · acuan: `docs/serah-terima.md` (tabel rencana Tahap 3–9, pertanyaan terbuka (a)/(b)), `docs/kontrak-data.md`, PRD v3.1 (dikelola pemilik; **bagian yang dibutuhkan belum disalin ke repo**, lihat "Yang dibutuhkan dari PRD")

## Isi Tahap 6 menurut rencana

"Rekap Sheets, lembar siap cetak, file bank, bahan tunai." Hasil yang bisa dilihat pemilik: **Sheets terisi otomatis**. Syarat yang menunggu: keputusan (a)/(b).

## Yang sudah ada dan dipakai ulang

| Bahan | Sudah ada sejak |
| --- | --- |
| Gaji per orang, ringkasan per periode, versi terakhir | 4b (`hitung.ringkasan_gaji`, `hitung.versi_terakhir`) |
| Pecahan uang tunai per versi | 4b-3 (`hitung.pecahan_tunai`) |
| Status pengajuan, anomali gaji | 4b (`hitung.periode_bisa_diajukan`, `hitung.anomali_gaji`) |
| Pemeriksa "angka sama dengan gudang" | 4c (`web/periksa_data.py`, pola yang sama dipakai untuk Sheets) |
| Hitung otomatis sesudah file masuk | 5b (antrean kerja) |
| Spreadsheet "PROJECT ABSENSI" di Drive tertutup pemilik | 13 Nov 2026 (sel A1 sudah dikosongkan) |

## Usulan pembagian paket

### 6a: rekap ke Google Sheets
1. Dokumen dulu: `docs/rekap-sheets.md` (tab, kolom, kapan diisi, pemeriksaan).
2. Tab yang diusulkan: **Ringkasan periode** (angka sama dengan halaman demo), **Gaji per orang** (komponen utama, tanpa nomor rekening; karyawan `gaji_rahasia` tanpa angka), **Anomali** (tanda gaji dan pemberitahuan segera yang masih terbuka), **Riwayat isi** (kapan diisi, versi hitung yang dipakai).
3. Diisi oleh workflow GitHub yang membaca gudang (seperti "Terbitkan demo"), sesudah pemasangan dan sesudah antrean selesai; Sheets tidak pernah ditulis tangan oleh sistem lain.
4. Pemeriksa: isi Sheets dibaca ulang dan dibandingkan dengan gudang memakai perintah SQL sendiri; beda satu angka = gagal.
5. Uji otomatis dengan Sheets tiruan; uji nyata di spreadsheet "PROJECT ABSENSI".

### 6b: lembar siap cetak dan bahan tunai
1. Lembar per periode: rekap per divisi dan daftar tanda terima gaji tunai.
2. Bahan tunai: jumlah lembar per pecahan untuk seluruh pembayaran tunai, dan isi amplop per orang (dari `hitung.pecahan_tunai`).
3. Bentuk: halaman HTML siap cetak (dicetak dari browser ke kertas atau PDF), terbit bersama halaman demo; tidak memuat nomor rekening.

### 6c: file bank (transfer gaji)
1. Satu file per periode berisi daftar transfer.
2. Nomor rekening disimpan terenkripsi dan **tidak boleh keluar ke Sheets atau chat** (kontrak data). Cara file sampai ke HRD harus diputuskan (lihat pertanyaan 4).
3. Data simulasi belum berisi nomor rekening; perlu nomor karangan untuk demo.

## Yang belum pasti (diputuskan pemilik, satu per satu)

1. **(a) atau (b)** untuk rincian tap: (a) Sheets hanya rekap sesuai PRD celah D4; (b) tambah tab "rincian tap per orang" seperti file 2 rekap HRD. Saran: (a), karena D4 melarang log tap mentah di Sheets dan rincian sudah ada di halaman demo/rincian gaji.
2. **Cara sistem menulis ke Sheets.** Usulan: akun layanan Google (service account) yang diberi akses edit ke satu spreadsheet saja; kuncinya di secret GitHub. Pemilik perlu membuat akun layanan di Google Cloud (langkah dipandu satu per satu). [Kemungkinan Besar] ini cara paling sederhana tanpa membuka database; belum dicek ke dokumen resmi Google.
3. **Bank yang dipakai perusahaan sasaran** dan bentuk file unggah massalnya (setiap bank berbeda). Untuk demo bisa satu bentuk CSV umum dulu.
4. **Cara file bank sampai ke HRD** tanpa melanggar aturan rekening: misalnya dikirim sebagai dokumen ke Telegram HRD, atau diunduh dari halaman unggah dengan tautan 15 menit (5d/5e). Belum diputuskan.
5. **Bentuk lembar cetak** yang biasa dipakai HRD sasaran (contoh lembar dari perusahaan nyata akan sangat membantu; isi pribadinya tidak dicatat di repo).

## Yang dibutuhkan dari PRD v3.1 (salinan teks oleh pemilik)

- Bagian 17, baris Tahap 6: bunyi gerbangnya persis.
- Celah D4 (log tap mentah di Sheets) dan bagian lain yang menyebut Sheets.
- Bagian yang menyebut file bank, lembar cetak, atau bahan tunai.

## Urutan yang diusulkan untuk 18 Nov 2026

1. Pemilik menempelkan bagian PRD di atas.
2. Keputusan 1 (a)/(b), lalu keputusan 2 (cara menulis Sheets).
3. Daftar paket 6a dirapikan sesuai PRD → pemilik mengetik "buat".
4. Sambil 6a dikerjakan, pemilik menyiapkan akun layanan Google (syarat yang menunggu orang lain tidak menghentikan pekerjaan, aturan 10).
5. 6b dan 6c sesudah 6a, masing-masing dengan daftar dan "buat" sendiri.

## Catatan lain yang menunggu (dari serah-terima)

- Uji "demo masih hidup setelah 8 hari tanpa dipakai": dicek sekitar 21 Nov 2026 lewat Cadangan malam. Catatan: Supabase dipakai terus sampai 17 Nov, jadi hitungan 8 hari dimulai dari pemakaian terakhir.
- Pengingat sungguhan pertama: 21 Des 2026 (hari ke-1 sesudah tutup buku 20 Des). Hari ke-2 (22 Des) untuk MA2 sudah tercatat oleh uji 5c dan tidak dikirim lagi.
- Kunci Brevo mati bila 90 hari tidak dipakai.
- Pemilik: sesuaikan syarat gerbang Tahap 4 di PRD (unggah lewat web pindah ke Tahap 5).
