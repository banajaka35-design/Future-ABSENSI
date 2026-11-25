# Rencana paket 9b-2: karyawan baru dan ubah gaji lewat web

Ditulis 25 November 2026, sesudah 9b-1 selesai (`docs/laporan-9b-1.md`). Acuan: `docs/rencana-tahap-9.md` (9b), `docs/aturan-hitung-gaji.md` (B3, K14), `docs/kasus-jebakan.md` (F15, F15b, F15c). **Di-"buat" pemilik 25 Nov 2026 10.46 WIB dengan K1–K4 sesuai saran Claude** (persetujuan PIN perlu; pembangun boleh menyetujui pengajuannya sendiri, dicatat; di bawah UMK ditolak pada 12 bulan pertama; orang rahasia hanya pembangun). Angka tebakan (7 hari, Rp1 miliar, 50%) tidak dikoreksi.

## Gunanya

HRD bisa mendaftarkan karyawan baru dan mengubah gaji tanpa pembangun. Ini syarat Tahap 9: satu bulan penuh berjalan tanpa bantuan. Karena dua perintah ini **mengubah uang**, perintah tidak langsung berlaku. HRD mengajukan lewat web, lalu bos atau pembangun menyetujui lewat bot dengan PIN. Prinsipnya sama dengan rilis gaji: satu orang tidak bisa mengubah uang sendirian.

## Keadaan sekarang [Pasti, dicek 25 Nov di kode dan Supabase]

- Data karyawan baru tersebar di enam tabel:
  - `induk.karyawan` (ID, nama);
  - `induk.karyawan_riwayat` (divisi, jabatan, gaji pokok, tunjangan tetap, PTKP, cara bayar, BPJS, wajib tap, tanda rahasia);
  - `induk.status_kerja` (mulai);
  - `induk.penugasan_regu`;
  - `induk.pemetaan_id_mesin`;
  - `induk.pajak_awal_tahun` (penghasilan dari pemberi kerja sebelumnya).
- Mesin hitung sudah menangani karyawan yang masuk di tengah periode (B3 prorata, kasus K14). Pada 12 bulan pertama, gaji di bawah UMK diberi tanda `di_bawah_umk`. UMK demo Rp3.402.892; gaji pokok demo Rp3.450.000–8.950.000.
- **Nomor rekening belum pernah disimpan.** Kolomnya ada, tetapi 0 dari 1.044 baris terisi, dan cara enkripsinya belum dibangun. Karena itu rekening tidak masuk 9b-2 (lihat "Tidak termasuk").
- Orang rahasia (F15): HRD tidak boleh melihat gajinya; bos dan pembangun boleh. Web hanya untuk akun HRD dan pembangun.
- Persetujuan dengan PIN sudah ada untuk rilis gaji dan total lengkap (`fakta.persetujuan`, `fakta.tunggu_pin`, tombol bot). Akun aktif di demo sekarang: 1 pembangun, 1 karyawan. Bos dicabut saat uji 8f.
- 9b-1 sudah menyediakan:
  - alur pratinjau → simpan;
  - antrean hitung ulang dan pemicu Sheets;
  - pembatalan dengan pengecualian sempit.

## Isi paket

### 1. Migrasi `0042_ajukan_uang.sql`

**Pengajuan**
- Jenis perintah web bertambah dua:
  - `karyawan_baru`: ID, nama, tanggal mulai, divisi, regu, jabatan, wajib tap, ID mesin, gaji pokok, tunjangan tetap, PTKP, cara bayar, BPJS kesehatan, BPJS ketenagakerjaan;
  - `ubah_gaji`: ID, berlaku mulai, gaji pokok baru, tunjangan tetap baru, dan bila perlu PTKP, cara bayar, serta BPJS.
- Simpan tidak langsung mengubah data induk. Hasilnya **pengajuan** di tabel baru `fakta.pengajuan_uang` (hanya bertambah; keadaannya dicatat sebagai baris keputusan). Pengajuan hangus bila tidak diputuskan dalam 7 hari [Menebak: 7 hari].

**Persetujuan**
- Lewat bot: setujui atau tolak dengan PIN. Pemeriksaan diulang saat disetujui. Bila sudah tidak berlaku (periode dirilis, data berubah), persetujuan ditolak dengan alasannya.
- Bila disetujui, data induk diubah, setiap baris dicatat di `fakta.perintah_web_ubah`, periode masuk antrean, lalu Sheets diperbarui.

**Pemeriksaan isian**
- ID belum dipakai dan hanya huruf/angka.
- Nama tidak kosong.
- Divisi, regu, dan ID mesin diperiksa sama seperti mutasi 9b-1.
- Tanggal: tidak di periode yang sudah dirilis; paling jauh 62 hari ke depan.
- Batas uang:
  - nominal tidak negatif;
  - paling banyak Rp1 miliar per bulan [Menebak: batas salah ketik];
  - gaji pokok + tunjangan di bawah UMK: lihat keputusan K3;
  - gaji pokok di bawah 75% dari gaji pokok + tunjangan: peringatan, karena mesin hitung sudah menandainya.

**Pratinjau**
- Gaji lama → baru (untuk ubah gaji), dan kenaikan dalam persen.
- Peringatan merah bila gaji turun.
- Periode yang akan dihitung ulang.
- Siapa yang bisa menyetujui.

**Pembatalan sesudah disetujui**
- Memakai pengecualian sempit 9b-1, dengan syarat yang sama: periode belum dirilis dan belum ada perubahan lebih baru untuk orang itu.
- Untuk karyawan baru, semua baris yang dibuat dikembalikan. Baris nama (`induk.karyawan`) tetap ada, tetapi orangnya tidak aktif. ID-nya tidak bisa dipakai ulang untuk orang lain, supaya riwayat tidak tercampur.

### 2. Bot (Edge Function)

- Bila ada pengajuan baru, setiap akun bos dan pembangun yang aktif menerima pesan:
  - "Pengajuan no. N oleh HRD: [ringkas], gaji Rp… → Rp…";
  - tombol **Setujui** dan **Tolak**, lalu PIN (alur sama dengan rilis).
- Tolak meminta alasan singkat.
- Hasil keputusan dikabarkan ke pengaju.
- Perintah teks `/pengajuan` menampilkan daftar pengajuan yang menunggu.

### 3. Halaman web HRD

- Tab Perintah mendapat dua jenis baru, dengan isian uang.
- Kolom "Persetujuan" di tabel: menunggu / disetujui oleh … / ditolak (alasan) / hangus.
- HRD bisa menarik pengajuannya sendiri selama belum diputuskan.

### 4. Uji

- Database:
  - pengajuan tidak mengubah apa pun sebelum disetujui;
  - persetujuan tanpa PIN atau dengan PIN salah ditolak;
  - karyawan baru masuk di tengah periode dihitung prorata sesuai K14;
  - ubah gaji di tengah periode dihitung per hari sesuai B3;
  - batal sesudah disetujui mengembalikan data persis;
  - orang rahasia sesuai keputusan K4;
  - pengajuan hangus;
  - ID ganda ditolak;
  - jalan langsung ke fungsi dalam ditolak.
- Pintu bot: alur pesan pengajuan → Setujui → PIN → hitung ulang → kabar.
- Halaman: isian gaji hanya di dua jenis ini; tidak ada `innerHTML`; tidak ada rekening.

## Analisa celah

| No | Celah | Akibat | Penutup | Label |
| --- | --- | --- | --- | --- |
| U1 | Satu orang mengubah gaji sendirian | Gaji dinaikkan diam-diam | Pengajuan + persetujuan bos/pembangun dengan PIN (K1) | [Pasti] |
| U2 | Pengaju menyetujui sendiri | Persetujuan tidak berarti | HRD tidak bisa menyetujui. Untuk akun pembangun lihat K2 | [Pasti] |
| U3 | Data berubah antara pengajuan dan persetujuan | Yang disetujui berbeda dengan yang berlaku | Pemeriksaan diulang saat disetujui; isian harus sama dengan pengajuan; bila berbeda ditolak | [Pasti] |
| U4 | Gaji orang rahasia terlihat HRD lewat pratinjau atau tabel | Melanggar F15 | Lihat K4; tabel dan pratinjau untuk HRD tidak menampilkan angka orang rahasia | [Pasti] |
| U5 | HRD memasang atau mencabut tanda rahasia | Membuka gaji lama (F15c) atau menyembunyikan gaji dari HRD | Tanda rahasia tidak bisa diubah HRD (K4) | [Pasti] |
| U6 | Gaji di bawah UMK | Melanggar aturan upah minimum | K3 | [Kemungkinan Besar] |
| U7 | Salah ketik nol (Rp45.000.000 maksudnya Rp4.500.000) | Gaji 10 kali lipat | Pratinjau menulis angka dengan pemisah ribuan dan kenaikan dalam persen; kenaikan di atas 50% diberi peringatan merah; bos melihat angka lama → baru sebelum menyetujui | [Kemungkinan Besar] |
| U8 | Pesan Telegram berisi angka gaji | Angka tersimpan di chat bos | Hanya ke akun bos/pembangun, yang memang boleh melihat gaji. Penghapusan otomatis pesan tetap di daftar tunda | [Kemungkinan Besar] |
| U9 | ID karyawan baru bentrok dengan ID mesin orang lain | Tap orang lain masuk ke karyawan baru | Pemeriksaan ID mesin sama dengan mutasi (constraint dan pesan jelas) | [Pasti] |
| U10 | Karyawan baru dengan penghasilan dari tempat kerja lain tahun ini | PPh akhir tahun kurang tepat | Tidak bisa lewat web di 9b-2; pratinjau mengingatkan; diisi lewat data awal (9d) | [Kemungkinan Besar] |
| U11 | Pengajuan menumpuk tanpa diputuskan | HRD bingung status | Hangus 7 hari; kabar ke HRD; tabel menampilkan "menunggu" | [Menebak] |
| U12 | Batal karyawan baru sesudah ada tap atau perintah lain | Riwayat rusak | Ditolak bila sesudah persetujuan ada perubahan apa pun pada orang itu (sama dengan 9b-1) | [Pasti] |

## Yang dipasang ke Supabase

Migrasi 0042 dan Edge Function lewat workflow "Pasang"; halaman lewat "Terbitkan demo", sesudah uji GitHub lulus.

## Yang belum pasti

- [Menebak] Hangus 7 hari, batas Rp1 miliar, dan peringatan kenaikan di atas 50%: angka tebakan yang wajar. Mohon dikoreksi.
- [Kemungkinan Besar] Alur PIN rilis bisa dipakai ulang untuk pengajuan tanpa mengubah perilaku rilis. Uji rilis lama (180, 200, 8b-x) harus tetap lulus.

## Tidak termasuk

- Nomor rekening: butuh enkripsi dan kunci tersendiri; diusulkan paket terpisah sebelum data asli (9d).
- Pajak awal tahun lewat web.
- Unggah banyak karyawan sekaligus (templat unggah, 9d).
- Tipe upah harian/borongan: demo hanya bulanan.

## Keputusan pemilik

| No | Pertanyaan | Saran Claude | Alasan |
| --- | --- | --- | --- |
| K1 | Perlukah karyawan baru dan ubah gaji disetujui bos/pembangun dengan PIN? | **Perlu** | Sama dengan rilis gaji: uang tidak boleh diubah satu orang. Persetujuan juga meninggalkan jejak siapa menyetujui |
| K2 | Bolehkah akun pembangun (akunmu) menyetujui pengajuan yang ia buat sendiri? | **Boleh**, dicatat sebagai "disetujui sendiri" | Keputusan tetapmu: akun pembangun bisa semua, dan pembatasan harus ditanyakan. Di demo hanya ada satu akun yang bisa menyetujui. Untuk perusahaan sungguhan bisa diubah lewat kuesioner 9d |
| K3 | Gaji pokok + tunjangan di bawah UMK: ditolak atau hanya diperingatkan? | **Ditolak** untuk karyawan baru dan ubah gaji pada 12 bulan pertama; sesudah itu peringatan | Membayar di bawah UMK melanggar aturan upah minimum untuk masa kerja di bawah 1 tahun. Mesin hitung memang sudah memakai batas 12 bulan itu |
| K4 | Orang rahasia: siapa yang boleh mengubah gajinya dan memasang/mencabut tanda rahasia? | **Hanya pembangun** lewat web (bos belum punya akses web); HRD ditolak untuk orang rahasia, dan karyawan baru dari HRD selalu tidak rahasia | Sesuai F15: HRD tidak boleh melihat gaji orang rahasia, jadi juga tidak boleh mengubahnya |
