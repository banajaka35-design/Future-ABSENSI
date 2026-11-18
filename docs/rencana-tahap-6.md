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

## Daftar paket 6a (siap di-"buat", 18 Nov 2026)

**Diubah / ditambah di repo**
1. `docs/rekap-sheets.md` ditulis dan di-commit sebelum kode: tab, kolom, kapan diisi, pemeriksaan.
2. Tab di spreadsheet "PROJECT ABSENSI": **Ringkasan** (satu baris per periode: orang, pendapatan, potongan, bersih, dibayar, transfer, tunai; angka sama dengan halaman demo), **satu tab per periode** "Gaji <tanggal awal>" (satu baris per karyawan, kolom PRD v2 bagian 10: ID, nama, divisi, hari hadir, gaji pokok, uang makan, lembur, telat/lupa tap, alpha (jumlah dan nominal), kasbon, BPJS, PPh 21, gaji bersih), **Riwayat isi** (kapan diisi, commit, versi hitung per periode).
3. Karyawan `gaji_rahasia`: baris ada, kolom angka kosong. Nomor rekening tidak pernah ditulis. Log tap dan rincian harian tidak ditulis (keputusan (a)).
4. Penulis isi `web/isi_sheets.py`: membaca gudang (hanya membaca, lewat `SUPABASE_DB_URL` yang sudah ada), menimpa seluruh isi tab (PRD D3).
5. Pemeriksa `web/periksa_sheets.py`: isi Sheets dibaca ulang lewat API, dibandingkan dengan gudang memakai perintah SQL sendiri (bukan hasil penulis); beda satu sel = GAGAL (gerbang Tahap 6 v2, U3).
6. Workflow baru "Isi Sheets": jalan sesudah "Pasang ke Supabase" lulus dan lewat tombol; satu antrean, tidak jalan bersamaan.
7. Uji otomatis: penulis dan pemeriksa dijalankan dengan Sheets tiruan (tanpa internet) di uji simulasi; uji pemeriksa harus menangkap satu sel yang sengaja diubah.
8. Serah-terima dan laporan `docs/laporan-tahap-6a.md` (termasuk lama isi yang diukur, dibanding target 60 detik PRD v2).

**Dipasang ke Supabase:** tidak ada (tanpa migrasi; hanya membaca).

**Disiapkan pemilik (dipandu satu per satu, boleh sambil jalan):** proyek Google Cloud, Sheets API dinyalakan, akun layanan, kunci JSON ke secret GitHub `GOOGLE_SA_KEY`, spreadsheet dibagikan ke email akun layanan sebagai Editor, ID spreadsheet ke secret `SHEETS_ID`.

**Belum pasti**
- [Kemungkinan Besar] Pembuatan kunci akun layanan diizinkan untuk Gmail pribadi (lihat keputusan 2).
- [Menebak] Pustaka Google (`google-auth`) dipasang di server GitHub saat workflow jalan; di uji tiruan tidak dibutuhkan.
- Isi otomatis sesudah file masuk lewat Telegram **tidak** ikut 6a: butuh Edge Function memicu GitHub (token GitHub di Supabase). Diusulkan paket kecil sesudahnya.
- Tab anomali tidak ada di PRD v2 bagian 10, jadi tidak ikut 6a.
- Kolom "rincian lembur/telat/alpha" ditulis sebagai jumlah (jam/kali/hari) + nominal; bentuk rincian lain belum ditetapkan.

## Daftar paket 6a-2 (menunggu "buat", 18 Nov 2026)

Cara bayar berpola (permintaan perubahan 03) dan daftar transfer/tunai dipisah di Sheets. Keputusan pemilik 18 Nov 2026: tidak acak; tampilan dipisah; Pabrik A hanya Gudang tunai. File bank (6c) dan lembar cetak (6b) **ditunda** (tidak untuk portofolio sekarang); isi amplop per orang masuk paket ini.

**Urutan dan isi**

1. `docs/permintaan-perubahan-03.md` (sudah ditulis) dan `docs/rekap-sheets.md` versi 2 di-commit **sebelum kode**.
2. Generator: isian `divisi_tunai` (A: GDG; B: PRD, GDG) menggantikan `cara_bayar_tunai`; `self.r.random()` tetap dipanggil. Data simulasi dibuat ulang. **Syarat lanjut:** di `sidik_isi.txt` hanya baris `A/induk/karyawan.csv` dan `B/induk/karyawan.csv` yang berubah, dan di kedua file itu hanya kolom `cara_bayar`. Bila ada file lain berubah → berhenti dan lapor. `docs/data-simulasi.md` dan `docs/laporan-kewajaran-data.md` diperbarui.
3. Sheets: tab per periode dipecah menjadi `Gaji <awal> sd <akhir> transfer` dan `Gaji <awal> sd <akhir> tunai` (4 periode × 2 = 8 tab). Kolom sama dengan 6a; tab tunai ditambah **isi amplop per orang** (lembar per pecahan, pecahan mengikuti pengaturan `pembulatan_tunai`). Tab Ringkasan dan Riwayat isi tetap. Tab lama `Gaji <awal> sd <akhir>` (tanpa akhiran) dihapus otomatis oleh aturan "tab Gaji yang tidak dipakai dihapus".
4. Pemeriksa: setiap orang tepat di satu tab sesuai cara bayar di gudang; isi amplop per orang = dibayar; jumlah lembar semua amplop per pecahan = `hitung.pecahan_tunai` (perintah SQL gudang); orang tanpa cara bayar → GAGAL.
5. Uji Sheets tiruan diperbarui (8 tab; amplop diubah 1 lembar → GAGAL; orang dipindah ke tab yang salah → GAGAL).
6. Uji GitHub harus lulus semua (uji database, U1, U2, U5, U10, halaman demo = gudang, Sheets).
7. **Supabase** (sesudah uji lulus): Claude memicu **Reset Supabase** (cabang `reset`), lalu **Pasang ke Supabase** (cabang `pasang`) supaya pintu Telegram, akun pembangun, dan jadwal pengingat terpasang ulang (Reset tidak menjalankan `pasang_pintu.sh`; dicek 18 Nov 2026). Terbitkan demo dan Isi Sheets berjalan otomatis sesudah Pasang.
8. Dicek langsung di Supabase: karyawan 1.044; cara bayar per divisi (GDG semua tunai, lainnya transfer); **total gaji bersih tiap periode sama dengan sebelum paket** (5.183.058.029 · 8.216.773.882 · 5.706.405.590 · 4.999.870.485); jumlah hasil harian sama; akses tanpa login tetap ditolak (Cadangan malam).
9. Dicek langsung di Sheets: 8 tab Gaji + Ringkasan + Riwayat isi; contoh 3 orang (1 transfer, 1 tunai dengan isi amplop, 1 rahasia).
10. Uji nyata bot oleh pemilik: kirim satu pesan ke bot "Abaensi" sesudah Pasang → bot membalas (akun pembangun terdaftar ulang).
11. Laporan `docs/laporan-tahap-6a-2.md` dan serah-terima.

**Tidak diubah:** kasus jebakan, migrasi database (tidak ada migrasi baru), mesin hitung, halaman demo (angkanya ikut berubah sendiri dari gudang; tampilan dipisah di halaman demo menyusul bersama paket grafik).

**Akibat Reset yang perlu diketahui pemilik:** riwayat kiriman Telegram (no. 19–22), catatan pemberitahuan, kode email, dan catatan pengingat 22-12-2026 untuk MA2 terhapus (data demo). Jejak perubahan ikut terhapus (sifat Reset, hanya demo).

**Belum pasti**
- [Kemungkinan Besar] Hanya kolom `cara_bayar` yang berubah di data simulasi (dibuktikan di langkah 2 sebelum lanjut).
- [Kemungkinan Besar] Reset lalu Pasang memulihkan bot sepenuhnya; dibuktikan di langkah 10.
- [Kemungkinan Besar] Uji U10 (anomali gaji Pabrik B) tetap lulus walau angka dibayar Pabrik B berubah; dibuktikan di langkah 6.

## Daftar paket 6a-3 (menunggu "buat", 18 Nov 2026): total HRD tanpa orang rahasia

Permintaan perubahan 04 (kasus F15b). Dikerjakan sebelum paket G1 (grafik); G1 ditulis ulang sesudahnya dengan temuan 2–5 analisa ulang.

1. **Dokumen dulu**: `docs/kasus-jebakan.md` + F15b, `docs/rekap-sheets.md` versi 3, `docs/halaman-demo.md` versi 2 (bagian rahasia), di-commit sebelum kode.
2. **Sheets Ringkasan**: Orang, semua total rupiah, Transfer, Tunai, PPh tertahan dihitung **tanpa orang rahasia**; kolom baru "Orang rahasia (tidak termasuk)"; catatan di baris atas Ringkasan. Tab Gaji tidak berubah (baris rahasia tetap tanpa angka).
3. **Halaman demo**: Ringkasan per periode, transfer/tunai, dan pecahan uang tunai tanpa orang rahasia, dengan keterangan "tidak termasuk N orang rahasia; amplop orang rahasia disiapkan terpisah". Tanda anomali atas nama orang rahasia ditampilkan tanpa keterangan berangka (sekarang tidak ada, dijaga untuk perusahaan lain).
4. **Pemeriksa Sheets dan demo**: total = jumlah orang bukan rahasia dari gudang (SQL sendiri), **dan uji kebocoran: total dikurangi jumlah semua baris yang terlihat = 0** untuk setiap angka. Pecahan tunai demo = amplop orang tunai bukan rahasia; dan amplop bukan rahasia + amplop rahasia = `hitung.pecahan_tunai` (gudang tetap utuh).
5. **Uji**: Sheets tiruan dan uji demo Pabrik A diperbarui; **uji kebocoran juga di Pabrik B** (1 orang rahasia) untuk halaman demo dan Sheets tiruan; satu uji: total dikembalikan ke cara lama → pemeriksa GAGAL. Semua uji GitHub harus lulus.
6. **Terbit**: "Isi Sheets" dan "Terbitkan demo" dijalankan lewat tombol (tanpa Reset atau Pasang; Supabase tidak diubah).
7. **Dicek langsung**: Ringkasan Sheets dan halaman demo: total = jumlah yang terlihat (selisih 0), keterangan "tidak termasuk 3 orang rahasia".
8. Laporan `docs/laporan-tahap-6a-3.md` dan serah-terima.

**Tidak diubah:** gudang, mesin hitung (`hitung.pecahan_tunai` tetap menghitung semua orang), bot, data simulasi.

**Belum pasti**
- [Kemungkinan Besar] Tanda anomali tingkat divisi (bila ada di perusahaan lain) masih memasukkan orang rahasia dalam angka divisinya; risikonya kecil karena tidak bisa dipisah per orang tanpa total lengkap. Dicatat, tidak diubah di paket ini.
- Total lengkap untuk bos baru ada saat akun bos dibangun (Tahap 9).

## Yang belum pasti (diputuskan pemilik, satu per satu)

1. ~~**(a) atau (b)**~~ **Diputuskan pemilik 18 Nov 2026: (a)**, Sheets hanya rekap satu baris per orang (sesuai PRD v2 celah D4 dan bagian 10). Rincian tap: (a) Sheets hanya rekap sesuai PRD celah D4; (b) tambah tab "rincian tap per orang" seperti file 2 rekap HRD. Saran: (a), karena D4 melarang log tap mentah di Sheets dan rincian sudah ada di halaman demo/rincian gaji.
2. ~~**Cara sistem menulis ke Sheets.**~~ **Diputuskan pemilik 18 Nov 2026: (1) akun layanan Google + workflow GitHub** (bukan Apps Script seperti tulisan PRD v2 bagian 4), supaya gudang tetap tertutup dan semua kode tetap di GitHub. Cek dokumen 18 Nov 2026: batasan Google yang melarang kunci akun layanan berlaku otomatis untuk *organisasi* Google Cloud yang dibuat sejak 3 Mei 2024; akun Gmail pribadi tanpa organisasi umumnya tidak kena [Kemungkinan Besar], tetapi ada satu laporan forum Gmail pribadi tetap ditolak. Bila ditolak: cadangan tanpa kunci (Workload Identity Federation dari GitHub), lebih rumit. Catatan usulan awal: Usulan: akun layanan Google (service account) yang diberi akses edit ke satu spreadsheet saja; kuncinya di secret GitHub. Pemilik perlu membuat akun layanan di Google Cloud (langkah dipandu satu per satu). [Kemungkinan Besar] ini cara paling sederhana tanpa membuka database; belum dicek ke dokumen resmi Google.
3. **Bank yang dipakai perusahaan sasaran** dan bentuk file unggah massalnya (setiap bank berbeda). Untuk demo bisa satu bentuk CSV umum dulu.
4. **Cara file bank sampai ke HRD** tanpa melanggar aturan rekening: misalnya dikirim sebagai dokumen ke Telegram HRD, atau diunduh dari halaman unggah dengan tautan 15 menit (5d/5e). Belum diputuskan.
5. **Bentuk lembar cetak** yang biasa dipakai HRD sasaran (contoh lembar dari perusahaan nyata akan sangat membantu; isi pribadinya tidak dicatat di repo).

## Acuan PRD (18 Nov 2026)

Teks PRD v3.1 tidak tersedia; pemilik memutuskan memakai **PRD v2** (dokumen Claude "PRD v2 — Sistem Absensi & Payroll Otomatis"). Isi v2 yang dipakai:

| Hal | Isi PRD v2 | Bagian |
| --- | --- | --- |
| Tahap 6 | "Rekap ke Google Sheets"; selesai kalau "Isi Sheets sama dengan gudang" | 13 |
| Isi Sheets | Rekap gaji bulanan, satu baris per karyawan; kolom ID, nama, divisi, hari hadir, gaji pokok, uang makan, lembur, telat/lupa tap, alpha (rincian dan nominal), kasbon, BPJS, PPh 21, gaji bersih | 10 |
| D3 / D4 | Sheets hanya salinan yang ditimpa tiap hitung; hanya rekap, log tap mentah dan rincian harian tetap di gudang | 7, 10 |
| K3 / K7 | Pintu Sheets memakai kunci rahasia; Sheets dibagikan hanya ke akun HRD yang disebut satu per satu | 9 |
| U3 | Sheets dibandingkan dengan gudang, selisih nol | 12 |
| Target | Rekap selesai di Sheets paling lama 60 detik | 11 |
| Alat | "Google Sheets dan Apps Script" | 4 |
| File bank, slip PDF | Tahap lanjutan sesudah Tahap 9 | 10, 13 |

**Mungkin berbeda dari v3.1:** (1) [Kemungkinan Besar] lembar cetak, bahan tunai, dan file bank tidak ada di Tahap 6 v2 (kata "cetak" dan "tunai" tidak ada sama sekali; file bank = tahap lanjutan), jadi 6b dan 6c kemungkinan berasal dari v3.1 atau dari chat; (2) [Menebak] bunyi gerbang Tahap 6 bisa berubah di v3.1; dipakai bunyi v2; (3) [Kemungkinan Besar] v2 menyebut Apps Script, sedangkan sistem sekarang berjalan di Supabase dan GitHub (dibahas di keputusan 2).

## Yang dulu dibutuhkan dari PRD v3.1 (tidak tersedia, diganti v2)

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
