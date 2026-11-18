# Rekap ke Google Sheets (paket 6a; versi 2: 6a-2; versi 3: 6a-3)

18 November 2026 · versi 1 dan versi 2 masing-masing ditulis dan di-commit **sebelum kode** · versi 3: total Ringkasan tanpa orang rahasia (`docs/permintaan-perubahan-04.md`, F15b) · versi 2: daftar transfer dan tunai dipisah, isi amplop per orang (keputusan pemilik 18 Nov 2026, `docs/permintaan-perubahan-03.md`) · acuan: PRD v2 bagian 7 (D3, D4), 9 (K3, K4, K7), 10, 11, 12 (U3), 13 (Tahap 6); keputusan pemilik 18 Nov 2026 (`docs/rencana-tahap-6.md`): (a) Sheets hanya rekap, (1) akun layanan Google + workflow GitHub, aturan gaji rahasia tetap (F15).

## 1. Prinsip

1. **Gudang adalah sumber kebenaran; Sheets hanya salinan** yang ditimpa setiap kali diisi (D3). Sistem tidak pernah membaca angka dari Sheets untuk dihitung.
2. **Hanya rekap** (D4, keputusan (a)): satu baris per karyawan per periode. Log tap mentah dan rincian harian tidak ditulis.
3. **Nomor rekening tidak pernah ditulis** (kontrak data).
4. **Karyawan `gaji_rahasia`** (menurut riwayat terakhirnya, sama dengan halaman demo): barisnya ada dengan ID, nama, divisi, cara bayar, dan hitungan hadir/telat/alpha; **semua kolom rupiah dan keterangan rupiah kosong** (F15: HRD tidak boleh melihat angkanya; Sheets dibagikan ke HRD menurut K7).
5. Gudang hanya **dibaca** (lewat secret `SUPABASE_DB_URL` yang sudah ada). Tidak ada migrasi, tidak ada jalan baru ke gudang dari internet.
6. Versi yang dipakai: **versi terakhir** setiap periode (`hitung.versi_terakhir`, jenis `hitung_gaji`); hitungan hari diambil dari versi baca tap yang menjadi sumber versi gaji itu (`versi_hitung.versi_sumber`), sama seperti halaman demo.

## 2. Tab

Sistem hanya mengurus tab miliknya: `Ringkasan`, `Riwayat isi`, dan tab yang namanya diawali `Gaji `. Tab lain (misalnya buatan HRD, atau tab bawaan "Sheet1") tidak disentuh. Tab `Gaji ...` untuk periode yang sudah tidak ada di gudang (misalnya sesudah Reset) dihapus.

Baris 1 setiap tab milik sistem berisi catatan: *"Diisi otomatis dari gudang data. Jangan diubah dengan tangan: isinya ditimpa setiap kali diisi ulang."* Setiap tab milik sistem dikunci (protected range): hanya akun layanan yang boleh mengubah (pemilik file tetap bisa, aturan Google). Baris 1–2 dibekukan.

### 2.1 `Ringkasan`

| Baris | Isi |
| --- | --- |
| 1 | catatan |
| 2 | `Status` · `SEDANG DIISI <waktu WIB>` / `SELESAI <waktu WIB>, diperiksa sama dengan gudang` / `GAGAL <waktu WIB>, jangan dipakai` |
| 3 | kosong |
| 4 | judul kolom |
| 5 dst. | satu baris per periode, urut tanggal awal |

Kolom: Periode (id), Tanggal awal, Tanggal akhir, Tanggal bayar, Versi baca tap (versi kode dari versi baca tap yang menjadi sumber versi gaji), Versi hitung gaji (versi kode), Orang, Total pendapatan, Total potongan, Total gaji bersih, Total dibayar, Total sisa pembulatan, Transfer, Tunai, PPh tertahan (orang), Bisa diajukan (YA/TIDAK), Orang rahasia (tidak termasuk).

**Versi 3 (F15b):** Orang, semua total rupiah, Transfer, Tunai, dan PPh tertahan dihitung **tanpa orang rahasia**, sehingga total = jumlah baris yang terlihat di tab Gaji periode itu (selisih 0). "Orang rahasia (tidak termasuk)" = jumlah orang rahasia yang punya ringkasan gaji di periode itu. "Bisa diajukan" tetap dari `hitung.periode_bisa_diajukan` (semua orang). Baris 3 Ringkasan berisi keterangan: "Total tidak termasuk orang yang gajinya rahasia (lihat kolom terakhir); total lengkap hanya untuk bos."

Angka sama dengan halaman demo (keduanya dari gudang dengan cara hitung yang sama; uji simulasi memeriksa demo = gudang dan Sheets = gudang). ~~Totals mencakup karyawan rahasia~~ (versi 1–2; bocor, diganti versi 3).

### 2.2 `Gaji <tanggal awal> sd <tanggal akhir> transfer` dan `... tunai` (dua tab per periode, versi 2)

Setiap periode punya **dua tab**: `transfer` berisi karyawan yang cara bayarnya transfer, `tunai` berisi yang tunai, menurut riwayat yang berlaku di tanggal akhir periode. Setiap karyawan yang punya ringkasan gaji di versi itu ada di **tepat satu** tab. Karyawan tanpa cara bayar → pemeriksa GAGAL (tidak boleh terjadi). Tab dibuat walaupun daftarnya kosong (hanya catatan dan judul). Tab versi 1 `Gaji <awal> sd <akhir>` (tanpa akhiran) terhapus otomatis karena bukan tab yang dipakai.

Baris 1 catatan, baris 2 judul kolom, baris 3 dst. satu baris per karyawan, urut ID.

**Kolom pengenal dan hadir** (dari hasil harian versi sumber; berlaku juga untuk orang rahasia):

| Kolom | Arti |
| --- | --- |
| ID | ID karyawan, **ditulis sebagai teks** |
| Nama | |
| Divisi | divisi di hari terakhir periode yang punya hasil harian |
| Cara bayar | transfer / tunai, menurut riwayat yang berlaku di tanggal akhir periode |
| Hadir (hari) | status `hadir` |
| Masuk hari libur (hari) | status `lembur_hari_libur` |
| Telat (kali) | hari `hadir` dengan menit telat > 0 |
| Telat (menit) | jumlah menit telat |
| Lupa tap (kali) | hari dengan `lupa_tap` terisi |
| Alpha (hari) | status `alpha` |
| Izin (hari) | status `izin` |
| Sakit (hari) | status `sakit` |
| Cuti (hari) | status `cuti` |

**Kolom rupiah** (dari rincian gaji; kosong untuk orang rahasia; komponen yang tidak ada untuk orang itu = 0). Urutan tetap:

| Kolom | Komponen gudang | Kelompok |
| --- | --- | --- |
| Gaji pokok | `gaji_pokok` | pendapatan |
| Tunjangan tetap | `tunjangan_tetap` | pendapatan |
| Potongan hari tidak dibayar | `potongan_tidak_dibayar` (alpha + izin tidak dibayar; bernilai minus) | pendapatan |
| Uang makan | `uang_makan` | pendapatan |
| Tunjangan shift malam | `tunjangan_shift_malam` | pendapatan |
| Premi hadir | `premi_hadir` | pendapatan |
| Lembur | `lembur` | pendapatan |
| THR | `thr` | pendapatan |
| Pengembalian PPh 21 | `pengembalian_pph21` | pendapatan |
| Denda | `denda` (minus) | potongan |
| Kasbon | `kasbon` (minus) | potongan |
| BPJS Kesehatan (karyawan) | `bpjs_kesehatan_karyawan` (minus) | potongan |
| BPJS JHT (karyawan) | `bpjs_jht_karyawan` (minus) | potongan |
| BPJS JP (karyawan) | `bpjs_jp_karyawan` (minus) | potongan |
| PPh 21 | `pph21` (minus) | potongan |
| *komponen lain* | komponen yang tidak ada di daftar ini ditambahkan di sini dengan nama gudangnya, supaya baris tetap bisa dijumlah | sesuai gudang |
| Total pendapatan | `ringkasan_gaji.total_pendapatan` | |
| Total potongan | `ringkasan_gaji.total_potongan` (minus) | |
| Gaji bersih | `ringkasan_gaji.gaji_bersih` | |
| Sisa pembulatan lalu | `sisa_lalu` | |
| Dibayar | `dibayar` | |
| Sisa pembulatan | `sisa_pembulatan` | |
| Keterangan lembur | bukti komponen `lembur` (berisi dasar upah, jadi kosong untuk orang rahasia) | |
| Keterangan hari tidak dibayar | bukti komponen `potongan_tidak_dibayar` | |
| Peringatan | `peringatan`, dipisah koma (misalnya `pph_masa_terakhir_tertahan`) | |
| Ditanggung perusahaan: BPJS Kesehatan, JHT, JP, JKK, JKM | komponen `bpjs_*_perusahaan`; tidak masuk gaji bersih | perusahaan |

**Kolom tambahan khusus tab `tunai`: isi amplop per orang** (sesudah kolom "Ditanggung perusahaan"). Satu kolom per pecahan, judul `Amplop Rp100.000 (lembar)`, `Amplop Rp50.000 (lembar)`, dan seterusnya, dari pecahan terbesar. Pecahan = {100.000, 50.000, 20.000, 10.000, 5.000, 2.000, 1.000} yang **tidak lebih kecil dari pengaturan `pembulatan_tunai`** di tanggal akhir periode (sama dengan `hitung.pecahan_tunai`). Isi: "Dibayar" dipecah dari pecahan terbesar; dibayar ≤ 0 → semua 0. Orang rahasia: kolom amplop kosong.

Arti "telat" dan "lupa tap" di Pabrik A: **tidak ada potongan rupiah** untuk telat; telat menghilangkan premi hadir dan (di atas batas) uang makan. Jadi PRD v2 "rincian dan nominal telat atau lupa tap" ditulis sebagai jumlah kali/menit di kolom hadir, sedangkan akibat rupiahnya terlihat di Premi hadir dan Uang makan. Alpha: jumlah hari di kolom hadir, rupiahnya di "Potongan hari tidak dibayar" beserta keterangannya.

### 2.3 `Riwayat isi`

Baris 1 catatan, baris 2 judul, satu baris baru setiap kali diisi (tidak pernah dihapus oleh sistem). Kolom: Waktu (WIB), Commit, Pemicu (workflow), Periode dan versi gaji yang dipakai, Orang, Lama isi (ms), Uji teks panjang, Uji tanda sama dengan.

Dua kolom uji terakhir selalu berisi `123456789012345678` dan `=1+1` sebagai **teks**. Pemeriksa membacanya kembali dari Google; bila berubah (menjadi angka yang digit akhirnya rusak, atau dihitung menjadi 2), pemeriksa GAGAL. Ini bukti nyata bahwa ID mesin 18 digit (celah M1) dan isi yang diawali `=` aman.

## 3. Cara menulis

- Semua isi ditulis dengan `valueInputOption=RAW` (isi disimpan apa adanya; Google tidak mengubah teks menjadi angka atau rumus). ID dan semua teks dikirim sebagai teks; rupiah dan hitungan dikirim sebagai angka bulat.
- Satu permintaan tulis per tab, bukan per baris. Batas Google: 60 permintaan tulis per menit per pengguna per proyek; saran kiriman maksimal 2 MB (dokumen resmi "Usage limits"). Satu kali isi butuh sekitar 10 permintaan. Bila Google menjawab 429 atau 5xx: coba ulang dengan jeda 1, 2, 4, 8 detik, lalu berhenti GAGAL.
- Urutan satu kali isi:
  1. `Ringkasan` baris 2 = `SEDANG DIISI`.
  2. Buat tab yang belum ada, hapus tab `Gaji ...` yang periodenya sudah tidak ada, pasang kunci yang belum ada.
  3. Kosongkan lalu tulis setiap tab `Gaji ...` dan isi `Ringkasan`.
  4. Tambah satu baris `Riwayat isi`.
  5. Pemeriksa berjalan (langkah terpisah).
  6. Pemeriksa lulus → `Ringkasan` baris 2 = `SELESAI ...`. Pemeriksa gagal atau langkah mana pun gagal → `GAGAL ...` (dicoba ditulis; bila Google tidak bisa dihubungi, status tetap `SEDANG DIISI`, yang juga berarti jangan dipakai).
- Masuk ke Google memakai kunci akun layanan (secret `GOOGLE_SA_KEY`, isi file JSON dari Google Cloud): token dibuat dengan tanda tangan RS256 memakai `openssl` (ada di server GitHub), hanya pustaka bawaan Python. Lingkup izin: `https://www.googleapis.com/auth/spreadsheets`. Akun layanan hanya bisa membuka spreadsheet yang dibagikan kepadanya. Isi kunci tidak pernah dicetak ke log. ID spreadsheet di secret `SHEETS_ID`.

## 4. Kapan diisi

Workflow "Isi Sheets": sesudah "Pasang ke Supabase" atau "Reset Supabase" lulus, dan lewat tombol. Satu antrean (`isi-sheets`), tidak jalan bersamaan. Secret belum diisi → workflow GAGAL dengan pesan yang menyebut secret yang kurang.

**Tidak di 6a:** isi otomatis sesudah file masuk lewat Telegram (butuh Edge Function memicu GitHub dengan token GitHub di Supabase), pemberitahuan Telegram bila isi gagal (6a: workflow merah), tab anomali.

## 5. Pemeriksa (gerbang Tahap 6 menurut PRD v2: "Isi Sheets sama dengan gudang")

`web/periksa_sheets.py` membaca ulang seluruh tab milik sistem dari Google (nilai mentah, bukan tampilan) dan menghitung ulang dari gudang dengan **perintah SQL sendiri**, terpisah dari penulis. GAGAL bila salah satu:

1. Daftar tab `Gaji ...` tidak sama dengan dua tab (transfer, tunai) untuk setiap periode yang punya versi gaji.
2. Judul kolom berbeda dari dokumen ini.
3. Satu sel saja berbeda dari gudang (termasuk sel yang seharusnya kosong untuk orang rahasia, dan ID yang bukan teks).
4. Jumlah orang di tab berbeda dari jumlah ringkasan gaji di gudang.
5. Per baris (bukan rahasia): jumlah kolom komponen pendapatan + potongan ≠ Gaji bersih, atau Dibayar + Sisa pembulatan ≠ Gaji bersih + Sisa pembulatan lalu.
6. `Ringkasan`: satu angka berbeda dari gudang, atau total tab periode (termasuk orang rahasia, dihitung dari gudang) berbeda dari `Ringkasan` (U3).
7. Baris terakhir `Riwayat isi`: commit tidak sama dengan yang sedang diperiksa, atau dua kolom uji tidak kembali persis sebagai teks.
8. Tab milik sistem tanpa kunci, atau kunci yang mengizinkan akun lain selain akun layanan.
9. (versi 2) Karyawan berada di tab yang tidak sesuai cara bayarnya di gudang, ada di dua tab, atau tidak punya cara bayar.
11. (versi 3, F15b) Untuk setiap periode dan setiap angka Ringkasan (orang, pendapatan, potongan, gaji bersih, dibayar, sisa, transfer, tunai): angka Ringkasan dikurangi jumlah baris yang terlihat di dua tab Gaji periode itu ≠ 0; atau "Orang rahasia (tidak termasuk)" ≠ jumlah dari gudang.
10. (versi 2) Tab `tunai`: untuk setiap orang bukan rahasia, jumlah (lembar × pecahan) ≠ Dibayar; atau jumlah lembar per pecahan seluruh tab (termasuk orang rahasia, dihitung dari gudang) ≠ `hitung.pecahan_tunai(versi)`.

## 6. Uji

- **Uji otomatis (GitHub, setiap dorongan)**: Sheets tiruan (`sistem/uji/sheets_tiruan.py`, server kecil di komputer uji, tanpa internet) yang meniru bagian Sheets API yang dipakai, termasuk masuk dengan token. Tiruan menolak `valueInputOption` selain `RAW`. Dengan data simulasi Pabrik A: isi → periksa lulus; isi ulang → tab dan kunci tidak dobel; satu sel diubah → pemeriksa GAGAL; satu sel orang rahasia diisi angka → GAGAL; ID ditulis sebagai angka → GAGAL; tab `Gaji` periode yang tidak ada → dihapus; tab buatan HRD → tidak disentuh. Versi 2: 8 tab Gaji; satu lembar amplop diubah → GAGAL; orang dipindah ke tab cara bayar yang salah → GAGAL; tab versi 1 terhapus.
- **Uji nyata** (sesudah pemilik mengisi secret): workflow dijalankan ke spreadsheet "PROJECT ABSENSI", lalu isi Sheets dicek langsung (bukan dari log workflow).
- **Diukur**: lama isi (langkah penulis saja) dan lama dari awal workflow pemicu sampai `SELESAI`. Target PRD v2 bagian 11 ("rekap selesai di Sheets untuk 55.000–65.000 baris paling lama 60 detik") mengacu jumlah tap, bukan baris Sheets; keduanya dilaporkan terpisah. Lama dari file Telegram masuk sampai Sheets terisi tidak bisa diukur di 6a.
- **Bukti akhir paket** (PRD v2 bagian 12): jumlah baris per tab, 3 contoh orang lengkap (satu di antaranya rahasia), dan tautan Sheets.

## 7. Yang disiapkan pemilik

1. Proyek Google Cloud, Google Sheets API dinyalakan.
2. Akun layanan, kunci JSON → secret GitHub `GOOGLE_SA_KEY`.
3. Spreadsheet "PROJECT ABSENSI" dibagikan ke email akun layanan sebagai Editor; ID spreadsheet → secret `SHEETS_ID`.
4. Pengaturan berbagi spreadsheet: matikan "Editor dapat mengubah izin dan berbagi" (K7; sekarang menyala, dicek 18 Nov 2026).
5. Untuk demo, akun HRD = akun pemilik saja (K7).

## 8. Belum pasti

- ~~Kunci akun layanan boleh dibuat dari Gmail pribadi~~: terbukti 18 Nov 2026 (proyek tanpa organisasi).
- ~~`RAW` menyimpan teks angka sebagai teks~~: terbukti di uji nyata 18 Nov 2026 (kolom uji `Riwayat isi` kembali persis).
- [Kemungkinan Besar] Kunci tab tidak menghalangi akun layanan yang memasangnya; isi kedua di Google sungguhan belum dijalankan (terbukti pada Pasang berikutnya).
- [Pasti, 18 Nov 2026] Google menambahkan pemilik file ke daftar pengubah kunci tab; pemeriksa mengizinkan email di `PEMBANGUN_EMAIL`.
