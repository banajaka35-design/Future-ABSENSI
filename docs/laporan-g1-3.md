# Laporan paket G1-3: total gaji di bot dan halaman unggah tanpa orang rahasia

19 November 2026 · rencana `docs/rencana-g1-3.md` (di-"buat" pemilik 19 Nov 2026 13.48 WIB) · kasus F15b, F15c · commit 2d9b002

## Yang dibuat

1. **Migrasi 0024** (`db/migrasi/0024_total_tanpa_rahasia.sql`)
   - `hitung.ringkasan_terlihat(versi)`: jumlah orang terlihat, gaji bersih terlihat, dan jumlah orang rahasia untuk satu versi gaji, dengan aturan F15c (rahasia pada hari mana pun di periode itu, atau rahasia sekarang). Hanya mengembalikan jumlah, bukan nomor orang.
   - `api.pintu_kerjakan`: kolom `fakta.antrean_kerja.hasil` kini hanya menyimpan nomor versi gaji (tanpa rupiah dan jumlah orang). Angka untuk balasan bot dihitung saat itu juga (T1).
   - `api.pintu_status_kiriman` (halaman unggah): total dihitung saat dibaca, lewat `fakta.hasil_antrean_tampil`. Orang yang dijadikan rahasia sesudah file diproses ikut disembunyikan (C1).
   - 3 baris antrean lama (kiriman 18) dibersihkan: `orang` dan `bersih` dihapus, diberi tanda `angka_dihapus` (C1b).
   - Kedua fungsi baru tidak bisa dipanggil peran `pintu`, `anon`, atau `authenticated` (C3).
2. **Bot** (`sistem/pintu/inti.ts`)
   - Pesan "X orang, gaji bersih RpY (tidak termasuk N orang rahasia)". Kalimat yang sama dipakai halaman unggah (`teksHasil`).
   - Hanya melayani chat pribadi (C2): pesan, file, `/unggah`, atau tombol dari grup, atau dari chat yang bukan milik pengirim, dijawab satu kalimat tanpa tautan, angka, atau pemrosesan file.
3. **Halaman unggah** (`web/demo/unggah/index.html`): menampilkan kalimat dari server; baris tanpa angka tertulis "angka gaji tidak ditampilkan".
4. **Uji**: `db/uji/160_total_tanpa_rahasia.sql` (14 uji) dan 8 uji baru di `sistem/pintu/uji_pintu.ts`.

Tombol pilihan mesin ternyata sudah aman sebelum paket ini [Pasti]: `api.pintu_ambil_tunda` hanya mengembalikan file bila penekan tombol sama dengan pengirimnya. Tidak diubah; kini dibuktikan oleh uji.

## Uji [Pasti]

- Lokal (Postgres 16): database 467 lulus 0 gagal (sebelumnya 453); pintu 48 lulus 0 gagal (sebelumnya 40).
- **Uji gagal dengan aturan lama**: fungsi diganti sementara di database uji lokal. Aturan "semua orang dihitung": 6 uji GAGAL. Aturan "status rahasia terakhir saja": 3 uji GAGAL.
- Uji pintu dengan data simulasi Pabrik A (daftar rahasia dibaca dari file induk, bukan dari database): total bot 5.063.821.620 = jumlah gaji yang terlihat; semua orang 5.078.665.620.
- GitHub run 44476203799 lulus: database 467, simulasi 119, pintu 48, penyambung 23 (postgres.js sungguhan).

## Pemasangan [Pasti]

- Pasang ke Supabase lewat cabang `pasang` (run 44477603013) lulus; Edge Function `pintu-telegram` dipasang ulang. Isi Sheets, Terbitkan demo, dan Cadangan malam jalan otomatis sesudahnya dan lulus.
- Dicek langsung di Supabase:
  - 0024 terpasang 14.13 WIB, sidik `d2df7d1f4a99` sama dengan repo;
  - 3 baris antrean lama tanpa rupiah dan tanpa jumlah orang;
  - `pintu` dan `anon` tidak punya izin jalankan kedua fungsi baru;
  - total tanpa orang rahasia keempat periode sama dengan hitungan sebelum pasang.

## Uji nyata lewat bot (19 Nov 2026) [Pasti]

Pemilik mengirim `A_p2_MA1_ujig13.csv` (salinan file simulasi MA1 periode 2, satu baris dibuang) lewat chat pribadi bot. Kiriman no. 19, diterima 14.19 WIB, 36.178 tap; 4 periode dihitung ulang (14.19.34–14.20.58 WIB, tanpa galat).

| Periode | Balasan bot | Sheets "Ringkasan" | Supabase (tanpa rahasia) |
| --- | --- | --- | --- |
| 21 Jan–20 Feb | 1.008 orang · Rp5.167.334.029 | 1.008 · 5.167.334.029 | 1.008 · 5.167.334.029 |
| 21 Feb–20 Mar | 1.007 · Rp8.191.235.519 | 1.007 · 8.191.235.519 | 1.007 · 8.191.235.519 |
| 21 Mar–20 Apr | 1.007 · Rp5.690.720.227 | 1.007 · 5.690.720.227 | 1.007 · 5.690.720.227 |
| 21 Nov–20 Des | 1.003 · Rp4.983.863.768 | 1.003 · 4.983.863.768 | 1.003 · 4.983.863.768 |

- Semua pesan periode memuat "(tidak termasuk 3 orang rahasia)". Total bot − total Sheets = 0 di keempat periode.
- Gaji tidak berubah: total semua orang sama dengan sebelum file dikirim (mis. periode 2 tetap 8.216.773.882).
- Kolom antrean baru (antrean 4–7) hanya berisi `versi_gaji`, `bisa_diajukan`, `segera`.
- Sheets SELESAI 14.22 WIB, pemeriksa 0 beda; 216 detik sejak file masuk (diukur sekali; 6e: 172 detik).
- Pemberitahuan segera "memori mesin penuh atau mesin mati" (tap terakhir 244 hari sebelum dikirim) **benar**: data simulasi lama sengaja dikirim. Sama seperti kiriman 18 di uji 6e.
- File dikirim tanpa keterangan mesin; tombol pilihan mesin muncul dan bekerja.

## Penelusuran: di mana angka gaji ditulis untuk HRD [Pasti, dari kode]

| Tempat | Angka gaji | Status sesudah G1-3 |
| --- | --- | --- |
| Balasan bot sesudah file diproses (`inti.ts`) | total gaji bersih, jumlah orang | tanpa orang rahasia (F15c) |
| Halaman unggah web (status kiriman) | total gaji bersih, jumlah orang | tanpa orang rahasia, dihitung saat dibaca |
| Sheets dan halaman demo | per orang, total, grafik, tanda anomali | sudah sejak 6a-3, 6a-4, G1-2 |
| Pemberitahuan segera (Telegram) | tidak ada rupiah; hanya tanda dari pembaca tap | aman |
| Pengingat kirim file | tidak ada angka gaji | aman |
| Kabar "Sheets SELESAI/GAGAL" | tidak ada angka gaji | aman |

## Hal yang dicatat, tidak dikerjakan di paket ini

- **3 pesan bot lama (18 Nov 2026)** yang memuat total termasuk orang rahasia **dibiarkan** (keputusan pemilik, 19 Nov 2026). Penerimanya hanya akun pembangun; datanya simulasi. Bot tidak menyimpan nomor pesan Telegram, jadi tidak bisa menariknya sendiri [Kemungkinan Besar].
- **Temuan T2 [Kemungkinan Besar]: riwayat versi Google Sheets.** Bila seseorang baru dijadikan rahasia, versi lama Sheets masih memuat gajinya bagi siapa pun yang punya hak edit. Sekarang editornya hanya akun pemilik dan akun layanan. Perlu paket sendiri sebelum ada HRD sungguhan.
- **Total lengkap untuk bos belum ada [Pasti].** Kasus F15/F15b menulis "akun bos bisa melihat" dan Sheets Ringkasan menulis "total lengkap hanya untuk bos", tetapi belum ada akun atau jalur bos untuk melihatnya. Saat ini gaji orang rahasia hanya bisa dibaca langsung di Supabase. Perlu keputusan pemilik dan paket sendiri (kemungkinan Tahap 8 atau 9).
- Selama beberapa menit antara Pasang dan Terbitkan demo, halaman unggah lama bisa menampilkan "NaN" untuk 3 baris lama [Kemungkinan Besar]; tidak membuka angka apa pun. Sudah terbit ulang (run 44478353648).

## Tidak diubah

Mesin hitung, isi Sheets, halaman demo utama, pemeriksa Python.
