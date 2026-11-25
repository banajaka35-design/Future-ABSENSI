# Laporan paket F1: pembaca berbagai format file mesin

Di-"buat" 25 November 2026 15.38 WIB menurut `docs/rencana-f1-format-file.md` dengan K1 (pembuka ditulis sendiri) dan K2 (rekap
ditolak). Ditahan 15.4x karena rencana bertentangan dengan kasus jebakan F09 ("Waktu" ada di daftar sinonim); **pemilik memilih
pilihan A 15.51**: F09 dipatuhi apa adanya, "Waktu" dan "Time" tidak dikenali. Commit kode 6a51242. Terpasang 25 Nov 2026
(Pasang run 45586315282). Tanpa migrasi.

## Yang dibuat

- `sistem/urai/berkas.ts` (baru, tanpa pustaka luar, jalan di Node dan Deno):
  - `.xls`: pembaca berkas OLE (FAT, DIFAT, aliran mini) dan BIFF8 (SST dengan CONTINUE, LABELSST, LABEL, NUMBER, RK, MULRK,
    FORMULA + STRING, DATEMODE); berkas terkunci dan Excel sebelum 97 ditolak dengan alasan;
  - `.xlsx`: pembaca ZIP (direktori pusat, `DecompressionStream("deflate-raw")`), workbook, relasi, sharedStrings, worksheet;
    pengaturan tanggal 1904;
  - teks: BOM UTF-8, UTF-16 LE/BE, UTF-8 ketat, bila gagal Windows-1252;
  - jenis berkas dari tanda awal isi; batas 200.000 baris, 256 kolom, 64 MB terurai; penjaga putaran rantai sektor.
- `sistem/urai/urai.ts`:
  - `uraiTabel`: kolom dikenali dari judul (sinonim ID: No.ID, ID, AC-No., PIN, NIK, NIP, No. Pegawai, dan lain-lain; tanggal-jam
    satu kolom: Tgl/Waktu, Date Time, Tanggal Jam, dan lain-lain; atau Tanggal + Jam); judul laporan di atas tabel boleh; nama dan
    status tidak wajib; tanggal teks d/m/yyyy (pemisah `/ - .`), yyyy-mm-dd, atau angka Excel;
  - pemisah teks koma, titik koma, atau tab dipilih otomatis;
  - penjaga: A10 (hari/bulan tercampur), F01 (notasi ilmiah), ID angka lebih dari 15 digit, dua kolom ID, rekap, Excel rusak;
    semua pesan tolak berawalan "Format file tidak dikenal" atau "No.ID rusak" (pemberitahuan segera, migrasi 0018);
  - `uraiBerkas(isi biner)` untuk bot dan web; `urai(teks)` lama tetap (pemuat data simulasi).
- Bot dan halaman unggah meneruskan isi biner (`sistem/pintu/inti.ts`, `sambung.ts`, Edge Function `index.ts`;
  `db/pasang_pintu.sh` ikut menyalin `berkas.ts`).
- Alat cek contoh file `sistem/urai/cek_file.ts` (tanpa menyimpan, tanpa nama); `docs/pasang/` langkah 1, pertanyaan A5, dan
  petunjuk HRD diperbarui.
- Berkas contoh `sistem/urai/contoh/` (dibuat `buat_contoh.py` dari data simulasi; tiruan susunan file asli dengan nama dan ID
  karangan).

## Hasil uji [Pasti, diukur 25 Nov]

| Uji | Hasil |
| --- | --- |
| Pembaca (`uji_urai.ts`) | 25 lulus, 0 gagal (17 lama + 8 baru) |
| Pintu (bot/web) | 125 lulus, 0 gagal (124 + 1: kirim `.xls` lewat bot) |
| Simulasi | 153 lulus, 0 gagal (hasil data CSV lama tetap sama: U1, U4, U6, sidik) |
| GitHub "Uji database" commit 6a51242 (run 45584341205) | success: pembaca 25, database 936, simulasi 153, pintu 125, penyambung 24, pemicu 12, pemulihan 10 |
| Waktu baca `.xls` 40.566 baris | 199 ms (komputer kerja), 106 ms (GitHub); batas Edge Function 2 detik CPU |

Uji baru: CSV = `.xls` = `.xlsx` = tanggal angka Excel = CSV titik koma Windows-1252 = TXT UTF-16 (tap sama persis, termasuk nomor
baris); ID "No. Pegawai" + Tanggal + Jam terpisah + judul laporan; Excel 1904; satu periode MA1 dalam `.xls`; tiruan file asli
(ID 18 angka utuh, "C/Masuk" sore); penolakan rekap, F09 dalam `.xlsx`, ID angka 18 digit, dua kolom ID, Excel terpotong;
"Waktu"/"Time" tidak dikenali juga sebagai kolom jam; jenis berkas dari isi, Windows-1252, BOM.

Kesamaan hasil absen dibuktikan di tingkat tap (masukan ke database identik), tidak dengan pemasangan database tambahan.

## File asli pemilik (dicek hanya di komputer kerja Claude)

"File Oktober" (`.xls` dari mesin pemilik, 6 orang): sebelum F1 ditolak "Format file tidak dikenal"; sesudah F1 **diterima langsung:
258 tap, 0 ditolak, 1–30 Okt 2026**, sama persis dengan hasil lewat CSV. Tidak dikirim ke bot atau Supabase; tidak masuk repo.

## Uji nyata: LULUS 25 Nov 2026 16.41–16.42 WIB [Pasti]

Pemilik mengirim `A_p3_MA2_ujinyata.xls` (data demo periode 3 mesin MA2 dalam `.xls`, dibuat Claude) ke bot dari Telegram.
- Bot bertanya mesin, lalu "diterima (mesin MA2)" dan "tersimpan: 5.199 tap, 2026-03-25 s.d. 2026-04-20".
- Supabase: kiriman no. 20 diterima, 5.199 baris, 5.199 tap; periode 3 dan 4 dihitung ulang (16.41, 16.42), antrean selesai.
- **Sidik gaji periode 1–4 tetap** `d7a6e443b8c5`, `c642bd4a9b7c`, `45a6ca644ca5`, `c427e5a53c5f` (tap sudah ada di demo).
- Isi Sheets dipicu bot 16.42.
Sebelumnya dicoba di salinan demo lokal: hasil sama.

## Yang belum

- Format dengan judul "Waktu"/"Time" saja, dan merek mesin lain tanpa contoh: ditolak dengan pesan jelas. Rencana F2 (HRD
  konfirmasi sekali lewat bot): `docs/rencana-f2-konfirmasi-format.md`.
- Bentuk rekap: ditolak (K2).
- Sinonim di luar No.ID dan Tgl/Waktu berstatus [Menebak] sampai ada contoh file sungguhan.
- Data asli pemilik di komputer kerja Claude belum dihapus (menunggu kata "hapus" dari pemilik).
