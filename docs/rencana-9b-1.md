# Rencana paket 9b-1: perintah lewat web (tanpa angka uang)

Ditulis 25 November 2026. Acuan: `docs/rencana-tahap-9.md` (9b), `docs/laporan-tahap-7.md` (perintah yang cocok untuk web). Keputusan pemilik 25 Nov 08.52 WIB: 9b dibagi dua (9b-1 lalu 9b-2), dan "berhenti tanggal X" = **hari kerja terakhir** (pilihan 2a, sama dengan mesin hitung sekarang). **Belum di-"buat".**

## Gunanya

Ada perintah yang menyangkut banyak orang sekaligus atau mengubah data induk karyawan. Perintah seperti ini repot diketik di chat. 9b-1 memindahkannya ke web HRD dengan alur **isi → pratinjau → Simpan**, lalu periode yang kena dihitung ulang.

Karyawan baru dan ubah gaji menyangkut gaji, rekening, dan orang rahasia, jadi ditunda ke 9b-2.

## Keadaan sekarang [Pasti, dicek 25 Nov]

**Cara mesin hitung membaca perintah**
- Tambah libur dan absen manual divisi dibaca mesin hitung langsung dari `fakta.perintah_hrd`. Efeknya sudah diuji sejak Tahap 3 (F08, C06).
- Berhenti, aktif kembali, dan mutasi dibaca dari data induk, bukan dari daftar perintah:
  - `induk.status_kerja`: mulai, berhenti, aktif kembali;
  - `induk.karyawan_riwayat`: divisi, jabatan, gaji;
  - `induk.penugasan_regu`: regu;
  - `induk.pemetaan_id_mesin`: ID di mesin.
- Isi data induk sekarang: 1.044 karyawan, 44 berhenti, 12 pernah pindah regu, 0 ubah riwayat.
- Saat ini berhenti hanya menambah satu baris di status kerja. Riwayat dan ID mesin tidak ditutup.

**Penjagaan yang sudah ada dan yang belum**
- Tabel induk di atas tidak punya catatan perubahan (`jejak.catat_perubahan`) dan tidak punya penjaga bertanggal.
- Perintah chat (Tahap 7) memakai draf 15 menit, tombol Ya, dan pemeriksaan ulang saat simpan. Sesudah disimpan, periode yang kena dan periode sesudahnya yang sudah punya gaji masuk antrean hitung ulang. Tanggal di periode yang sudah dirilis atau dikunci ditolak.
- `fakta.perintah_hrd.asal` hanya menerima 'chat', 'file', 'sistem'.

**Keadaan divisi**
- Divisi KTR (mingguan, regu 0) memakai mesin MA2.
- GDG, KAM, PRD, dan QC (rotasi, 2–4 regu) memakai mesin MA1.
- Setiap orang hanya punya ID di satu mesin.

**Keadaan periode**
- Periode 1–2 dikunci; periode 3–4 dihitung.

## Isi paket

### 1. Migrasi `0041_perintah_web.sql`

**a. Daftar perintah dan pencatatan**
- `asal` di `fakta.perintah_hrd` boleh berisi `'web'`.
- Draf perintah web disimpan di tabel draf baru. Draf berlaku 15 menit, sekali pakai, dan terikat pada akun pembuatnya.

**b. Data induk**
- Kolom `perintah_id` ditambahkan di `induk.status_kerja`, `induk.karyawan_riwayat`, `induk.penugasan_regu`, dan `induk.pemetaan_id_mesin`, supaya setiap perubahan tahu asal perintahnya.
- `jejak.catat_perubahan` dipasang di keempat tabel itu, supaya semua perubahan data induk tercatat, termasuk perubahan lama dari file.

**c. Lima perintah**

| Perintah | Isian | Akibat |
| --- | --- | --- |
| Tambah libur | tanggal (1–31 hari), divisi atau semua, keterangan | Dicatat sebagai `tambah_libur` (dibaca mesin hitung seperti sekarang) |
| Absen manual divisi | tanggal, divisi, alasan wajib | Dicatat sebagai `absen_manual` dengan kolom divisi; semua orang di divisi itu dianggap hadir sesuai jadwal, asal data "manual" (F08) |
| Berhenti | ID, tanggal hari kerja terakhir, alasan | Dicatat sebagai `berhenti` + satu baris `berhenti` di status kerja |
| Aktif kembali | ID, tanggal mulai lagi, alasan | Dicatat sebagai `aktif_kembali` + satu baris `aktif_kembali` di status kerja |
| Mutasi | ID, tanggal berlaku, divisi baru dan/atau regu baru, jabatan (boleh kosong), ID mesin baru bila mesin berbeda | Dicatat sebagai `mutasi`. Riwayat lama ditutup sehari sebelum tanggal berlaku, lalu dibuka riwayat baru dengan **gaji dan semua isian uang disalin apa adanya**. Regu dan ID mesin diubah dengan cara yang sama bila perlu |

**d. Pratinjau (tanpa menyimpan apa pun)**

Pratinjau menunjukkan:
- siapa dan berapa orang yang kena;
- periode mana yang akan dihitung ulang;
- hal yang perlu diwaspadai, dan khusus perintah berhenti, periode yang menjadi masa kerja terakhir (lihat celah).

Pratinjau tidak memuat angka gaji.

**e. Simpan**
- Semua pemeriksaan diulang.
- Perintah dicatat dengan asal 'web' dan `oleh` = akun pembuatnya.
- Data induk diubah dalam transaksi yang sama.
- Periode yang kena masuk antrean dengan aturan yang sama seperti jalur chat.

**f. Batalkan perintah web**
- Pembatalan dicatat sebagai `batalkan_perintah`.
- Perubahan data induk dikembalikan: baris baru dihapus dan baris lama dibuka lagi. Keduanya tercatat di jejak.
- Pembatalan ditolak bila:
  - periodenya sudah dirilis atau dikunci, atau
  - sudah ada perubahan lebih baru untuk orang yang sama.

**g. Akses**
- Semua aksi masuk lewat `api.web_hrd` dan sesi web 9a: akun HRD atau pembangun, batas diam 30 menit, dan batas 300 permintaan per jam.
- Akun pembangun bisa semua, sama dengan HRD.

### 2. Edge Function

Aksi `perintah_pratinjau`, `perintah_simpan`, `perintah_batal`, dan `perintah_daftar` ditambahkan di jalur `hrd` yang sudah ada.

### 3. Halaman web HRD: tab baru "Perintah"

- Pilihan lima perintah, masing-masing dengan isian sendiri.
- Kotak pratinjau, lalu tombol Simpan.
- Sesudah simpan, status hitung ulang ditampilkan: "menunggu" → "selesai", diperbarui sampai antrean habis.
- Daftar perintah web terakhir, masing-masing dengan tombol Batalkan.
- Semua data ditampilkan dengan `textContent` (C2 9a).

### 4. Uji

**Uji database**
- Setiap perintah: pratinjau tidak mengubah apa pun (sidik gudang sama).
- Sesudah simpan, hasil hitung ulang sesuai kasus jebakan F08/C06 untuk absen manual dan aturan libur mendadak untuk tambah libur.
- Berhenti: tap sesudah tanggal X tidak dihitung, dan hari X sendiri tetap dibayar (2a).
- Aktif kembali: tap sesudah tanggal mulai lagi dihitung kembali.
- Mutasi:
  - gaji pokok, tunjangan, cara bayar, rekening, dan tanda rahasia di riwayat baru sama persis dengan yang lama;
  - jadwal mengikuti divisi atau regu baru mulai tanggal berlaku;
  - mutasi KTR → PRD tanpa ID mesin MA1 ditolak.
- Batal: data induk kembali persis seperti sebelumnya, dan hasil hitung ulang sama dengan sebelum perintah.
- Penolakan:
  - periode dirilis atau dikunci;
  - karyawan sudah berhenti (untuk berhenti atau mutasi);
  - karyawan belum berhenti (untuk aktif kembali);
  - regu di luar jumlah regu divisi;
  - ID mesin sudah dipakai orang lain;
  - draf kedaluwarsa atau sudah dipakai;
  - akun bukan HRD/pembangun;
  - sesi tidak berlaku.
- Jalur chat dan file lama tetap lulus.

**Uji halaman**
- Tidak ada `innerHTML` untuk data.
- Sidik skrip terdaftar di header keamanan.

## Analisa celah

| No | Celah | Akibat bila dibiarkan | Penutup | Label |
| --- | --- | --- | --- | --- |
| C1 | `asal` tidak menerima 'web' | Simpan gagal, atau perintah web tercatat sebagai 'chat' sehingga tidak bisa ditelusuri | Tambah 'web' ke check | [Pasti] |
| C2 | Tabel induk tidak punya catatan perubahan | Data induk berubah tanpa jejak siapa dan kapan | Pasang `jejak.catat_perubahan` dan kolom `perintah_id` | [Pasti] |
| C3 | Tanggal di periode dirilis atau dikunci | Gaji yang sudah dibayar berubah diam-diam | Ditolak, sama dengan chat. Untuk mutasi, yang diperiksa tanggal berlaku; untuk berhenti, tanggal X | [Pasti] |
| C4 | Tanggal di masa depan belum punya periode (contoh: berhenti akhir bulan depan) | Jalur chat menolak ("tanpa periode"), padahal HRD sering tahu lebih dulu | Berhenti, aktif kembali, dan mutasi boleh sampai 62 hari ke depan walau periode belum ada; antrean hanya untuk periode yang sudah ada. Tambah libur dan absen manual tetap wajib punya periode | [Menebak] (62 hari = dua periode; mohon dikoreksi bila salah) |
| C5 | Berhenti padahal masih ada tap sesudah tanggal X | Hari kerja sungguhan tidak dibayar karena tanggal salah ketik | Pratinjau menyebut jumlah tap sesudah X dan tanggal tap terakhir | [Pasti] |
| C6 | Berhenti memicu aturan masa terakhir (cuti tunai dan lainnya, sudah ada sejak 0011) | HRD tidak sadar akibat uangnya | Pratinjau menyebut "periode N menjadi masa kerja terakhir; sisa cuti dibayar tunai sesuai aturan". Tidak ada angka, jadi aman untuk orang rahasia | [Kemungkinan Besar] (kalimatnya disesuaikan setelah membaca ulang 0011) |
| C7 | Mutasi ke divisi dengan mesin lain (KTR ↔ yang lain) | Tap orang itu tidak dikenali dan ia dianggap alpha | ID mesin baru wajib diisi bila mesin berbeda; bentrok ID ditolak oleh constraint yang sudah ada | [Pasti] |
| C8 | Mutasi ke divisi rotasi tanpa regu, atau regu di luar jumlah regu | Jadwal kosong, sehingga hasil harian salah | Regu wajib 1..jumlah regu untuk divisi rotasi, dan 0 untuk mingguan | [Pasti] |
| C9 | Mutasi menyalin isian uang | Gaji berubah tanpa sengaja, atau tanda rahasia hilang | Isian uang disalin di database (tidak lewat halaman), dan uji membandingkan semua kolomnya. Halaman tidak pernah menampilkan atau mengirim gaji | [Pasti] |
| C10 | Pembatalan saat ada perubahan lebih baru | Pengembalian merusak riwayat | Ditolak dengan alasan "batalkan perubahan yang lebih baru dulu" | [Pasti] |
| C11 | Dua kali klik Simpan, atau dua HRD bersamaan | Perintah ganda | Draf sekali pakai dan dikunci saat simpan (`for update`), sama dengan chat | [Pasti] |
| C12 | Tambah libur di hari yang sudah ada tap | Tap hari itu menjadi lembur hari libur, sehingga uang lembur bertambah | Pratinjau menyebut jumlah orang yang sudah tap di tanggal itu. Aturan lemburnya sudah ada dan tidak diubah | [Pasti] |
| C13 | Absen manual divisi menimpa orang yang sakit, cuti, atau izin | Orang sakit tercatat hadir | Mengikuti urutan mesin hitung yang sudah ada; pratinjau menyebut jumlah orang yang sudah punya sakit/izin/cuti di tanggal itu | [Kemungkinan Besar] (urutan dibaca ulang saat membuat) |
| C14 | Hitung ulang beberapa periode sekaligus | Halaman terlihat macet | Lewat antrean (tidak menunggu di permintaan web); halaman menampilkan status antrean | [Pasti] |
| C15 | Sheets tidak ikut berubah sesudah hitung ulang. **Sudah terjadi di jalur chat sekarang** (dicek 25 Nov): Isi Sheets hanya dipicu oleh file masuk, tombol, dan perubahan status rilis; tidak dipicu perintah chat | Angka web dan Sheets berbeda sampai ada pemicu lain | Sesudah antrean sebuah perintah habis, Edge Function memicu Isi Sheets sekali, dengan cara yang sama seperti `statusBerubah`. Ini berlaku untuk perintah web **dan** perintah chat (perbaikan kecil di `inti.ts`) | [Kemungkinan Besar] (sesudah perintah chat sebelumnya selalu ada file atau rilis yang memicu, jadi celahnya belum pernah terlihat) |
| C16 | Perintah memakai nama divisi atau ID karyawan yang ditulis bebas | Salah ketik membuat orang yang salah kena | Divisi dipilih dari daftar; ID diperiksa, dan pratinjau menampilkan nama orang itu | [Pasti] |

## Yang dipasang ke Supabase

- Migrasi 0041 lewat workflow "Pasang ke Supabase" (cabang `pasang`), sesudah uji commit itu lulus.
- Edge Function ikut terpasang lewat workflow yang sama.
- Halaman diterbitkan lewat "Terbitkan demo".

## Yang belum pasti

- [Menebak] Lama hitung ulang satu periode lewat antrean ≈ 20–30 detik. Angka ini dari 9c dan Tahap 7, belum diukur untuk 9b-1; perintah yang mengenai dua periode bisa dua kali lipat.
- [Kemungkinan Besar] Menghapus baris status kerja saat pembatalan aman bagi semua pembaca. Pembaca yang tercatat sekarang: 0010, 0011, 0013, 0014, 0016, 0025, 0026, 0034, 0036. Akan diperiksa satu per satu saat membuat.
- Batas 62 hari ke depan (C4) adalah tebakan.

## Uji nyata sesudah terpasang (oleh pemilik, dipandu)

1. Tambah libur satu divisi di periode 4. Lihat pratinjau, simpan, dan tunggu selesai. Hasil harian di gudang dan Sheets berubah sesuai pratinjau.
2. Batalkan perintah itu. Sidik periode 4 kembali seperti sebelumnya.
3. Mutasi satu orang KTR ke PRD tanpa ID mesin harus ditolak, lalu dicoba lagi dengan ID mesin dan dibatalkan.

## Tidak termasuk

- Karyawan baru dan ubah gaji (9b-2).
- Perintah satu orang yang sudah ada di chat (sakit, izin, cuti, kasbon, lembur).
- Tukar shift lewat web.
- Unggah file berisi banyak perintah.
- Tampilan 9a-2.
