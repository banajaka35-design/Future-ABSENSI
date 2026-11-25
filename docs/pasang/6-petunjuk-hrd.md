# Petunjuk pemakaian untuk HRD

Diserahkan ke HRD PT di langkah 8 panduan pasang. Ditulis dari perintah yang ada di sistem per 25 November 2026 (bot: teks
`/bantuan` di `sistem/pintu/inti.ts`; web HRD: `web/demo/hrd/index.html`). Bila fitur berubah, petunjuk ini ikut diperbarui.

## Yang dikerjakan sistem untuk HRD

- Membaca file mesin absen dan menentukan setiap hari setiap karyawan: hadir, telat, alpha, lembur, libur.
- Menghitung gaji: gaji pokok, potongan hari tidak dibayar, lembur, uang makan, premi, tunjangan shift malam, BPJS, PPh 21,
  kasbon, pembulatan tunai.
- Mengisi rekap Google Sheets setiap kali ada perubahan.
- Mengirim rincian gaji ke setiap karyawan lewat Telegram sesudah gaji dirilis.

## Memulai

1. Pembangun memberi **kode undangan**. Di Telegram, buka bot PT lalu ketik `/gabung KODE`.
2. Buat PIN 6 angka: tombol **PIN** atau `/pin`. PIN dipakai untuk merilis gaji.
3. `/bantuan` menampilkan semua perintah. Perintah boleh diketik tanpa garis miring (misalnya `izin 10001 30-03-2026`).

Tanggal ditulis `tanggal-bulan-tahun` (`30-03-2026`), atau `tanggal-bulan` untuk tahun ini (`30-03`).

## Setiap periode gaji

1. **Kirim file mesin** ke bot sebagai dokumen (bukan foto), sesudah tutup buku, persis seperti keluar dari aplikasi mesin
   (`.xls`, `.xlsx`, `.csv`, `.txt`, atau `attlog.dat`; pilih menu "log/data absensi", bukan rekap). Atau ketik `/unggah` untuk tautan halaman unggah
   di komputer. Bot membalas bila file diterima dan setelah gaji selesai dihitung; Sheets ikut diperbarui.
   **File dengan judul kolom yang belum dikenal** (misalnya mesin baru): bot menahan file dan bertanya sekali, dengan tombol,
   kolom mana yang berisi ID karyawan dan tanggal-jam (bila tidak ada di tombol, pilih "Lainnya, ketik sendiri" lalu ketik
   judul kolomnya). Periksa contoh hasil bacaan (ID, nama hari, tanggal, jam), lalu tekan **Ya, simpan**. File berikutnya dari
   mesin yang sama dengan judul kolom yang sama dibaca otomatis. Bila judul kolom berubah, bot bertanya lagi. Konfirmasi ini
   hanya lewat bot; halaman unggah menolak file seperti itu sampai disimpan lewat bot.
2. **Periksa "Perlu dicek"** di web HRD: alpha beruntun, ID mesin yang tidak dikenal, hari tanpa tap massal, dan sejenisnya.
3. **Catat yang belum tercatat** (izin, sakit, lembur, dan seterusnya; lihat bagian berikut). Periode dihitung ulang otomatis.
4. **Ajukan rilis:** `/ajukan`. Bila PT memakai persetujuan bos, bos menerima pesan dengan tombol Setujui/Tolak.
5. **Rilis:** `/rilis`, tombol Rilis, lalu ketik PIN. Sesudah dirilis, periode terkunci (tidak bisa diubah lagi) dan rincian gaji
   dikirim ke karyawan yang sudah terdaftar.
   Urutan rilis wajib berurutan: periode sebelumnya harus dirilis dulu.

## Perintah lewat chat bot

| Keperluan | Ketik | Contoh |
| --- | --- | --- |
| Izin, sakit, cuti (boleh susulan) | `/izin`, `/sakit`, `/cuti` ID tanggal [tanggal selesai] [catatan] | `/sakit 10001 30-03 31-03` |
| Kasbon | `/kasbon` ID jumlah cicilan-per-periode [catatan] | `/kasbon 10001 1.000.000 250rb` |
| Lihat saldo kasbon | `/kasbon` ID | `/kasbon 10001` |
| Ganti cicilan | `/cicilan` ID jumlah | `/cicilan 10001 200rb` |
| Pelunasan tunai di luar gaji | `/lunas` ID jumlah [catatan] | `/lunas 10001 500rb` |
| Setujui lembur (bila PT mewajibkan perintah) | `/setujuilembur` ID-atau-divisi tanggal [tanggal selesai] | `/setujuilembur PRD 05-12-2026` |
| Batalkan lembur | `/batalkanlembur` ID-atau-divisi tanggal | `/batalkanlembur 10001 26-11-2026` |
| Datang lebih awal dihitung lembur | `/setujuiawal` ID-atau-divisi tanggal | `/setujuiawal 10001 21-11-2026` |
| Batalkan perintah yang salah | `/batalperintah` nomor | `/batalperintah 1604` |
| 10 perintah terakhir | `/perintahku` | |
| Kode daftar untuk karyawan | `/kode` ID | `/kode 10001` |
| Contoh pesan gaji karyawan | `/contohgaji` ID nomor-periode | `/contohgaji 10001 3` |
| Keberatan karyawan yang belum dijawab | `/keberatan` (jawab dengan tombol Terima/Tolak) | |

Perintah yang mengubah data (izin, sakit, cuti, kasbon, lembur, pembatalan) menampilkan ringkasan dulu dengan tombol **Ya/Batal**;
tidak ada yang tersimpan sebelum Ya ditekan. Jumlah uang boleh ditulis `1500000`, `1.500.000`, `1,5jt`, atau `500rb`.

## Web HRD

Masuk dengan email akun HRD; kode 6 angka dikirim ke email itu. Sesi berlaku 2 jam, berakhir bila 30 menit tidak dipakai.

| Tab | Gunanya |
| --- | --- |
| Periode | Daftar periode: status rilis, jumlah orang, total gaji bersih dan dibayar. Klik baris untuk rincian (pendapatan, potongan, transfer, tunai) |
| Gaji | Gaji per orang untuk satu periode. Bawaan: periode tertua yang belum dirilis. Klik orang untuk rincian komponen, status harian, dan perintah |
| Perlu dicek | Hal yang perlu diperiksa sebelum mengajukan rilis |
| Keberatan | Keberatan karyawan dan keadaannya (dijawab lewat bot) |
| Coba aturan | Mencoba mengubah toleransi telat, lembur, uang makan, premi, atau shift malam, lalu melihat selisih gaji per orang. Tidak disimpan |
| Perintah | Tambah libur, absen manual divisi, berhenti, aktif kembali, mutasi; karyawan baru dan ubah gaji (perlu persetujuan bos/pembangun dengan PIN) |

Total di web HRD dan Sheets **tidak termasuk** orang bergaji rahasia. Total lengkap hanya untuk bos, lewat bot dengan PIN.

## Untuk karyawan

1. HRD membuat kode: `/kode ID`, lalu memberikannya ke karyawan.
2. Karyawan membuka bot PT dan mengetik `/daftar KODE`, lalu mengonfirmasi nama dan divisinya.
3. Sesudah gaji dirilis, karyawan menerima rincian gajinya. Tombol **Gaji saya** mengirim ulang rincian terakhir.
4. Bila ada yang tidak sesuai: `/keberatan tanggal alasan`, paling lambat 14 hari sesudah tanggal bayar. HRD menjawab lewat bot.

## Bila ada masalah

- File ditolak: bot menyebut alasannya (bentuk file, mesin salah, file ganda). Kirim ulang file yang benar.
- Salah mencatat perintah: `/batalperintah nomor`, atau tombol Batalkan di tab Perintah web HRD, selama periodenya belum dirilis.
- Lupa PIN: minta pembangun menghapus PIN (`/hapuspin`), lalu buat PIN baru.
- Karyawan ganti HP: HRD membuat kode `/kode ID ganti`; akun lama nonaktif setelah akun baru menekan "Ya".
- HRD atau bos ganti akun Telegram: minta pembangun mencabut akun lama (`/cabutakun`), lalu gabung lagi dengan kode undangan baru.
