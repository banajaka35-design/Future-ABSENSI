# Laporan paket 4b-4: Pabrik B (U5) dan tanda anomali gaji (U10)

17 November 2026 · acuan: `docs/aturan-hitung-gaji.md` versi 4 bagian O (commit de0e945, sebelum kode)

## Hasil singkat

| Uji | Hasil | Bukti |
| --- | --- | --- |
| U5/U1 Pabrik B: hasil per orang per hari vs kunci jawaban | **Lulus** (22.257 hari-orang), dengan 1 kelemahan diketahui (lihat temuan 1) | uji simulasi |
| U5/U2 Pabrik B: pembanding vs sistem | **Lulus**: 750 orang-periode, selisih 0 | uji simulasi |
| U5/U3 Pabrik B: pemeriksaan gaji | **Lulus** | `cek_gaji.sql` |
| U10: tiga anomali ditanam di salinan data uji Pabrik B | **Lulus**: ketiganya tertangkap, dan sebelum ditanam belum bertanda | uji simulasi |
| Kunci K38–K46 | **Lulus** | `db/uji/090_anomali_gaji.sql` (16 uji) |
| Uji lama (Pabrik A, K1–K37) | **Lulus** | uji database dan simulasi |

Kode hitung gaji dan pembaca tap **tidak diubah** untuk Pabrik B. Yang ditambah hanya data awal Pabrik B, pemuat perintah lembur, dan fungsi anomali.

**Bukti kunci jawaban ditulis lebih dulu:** uji GitHub commit de0e945 gagal karena fungsi anomali belum ada (bukan karena selisih angka), sama seperti 4b-3.

## Yang diubah

| Bagian | Isi |
| --- | --- |
| `db/data_awal/pabrik_b_struktur.sql` | 4 divisi, pola 5 hari (Gudang 6 hari), rotasi Keamanan, lembur wajib perintah, cuti bersama potong cuti sampai 27 Okt 2026 lalu dibayar (permintaan perubahan 01), 4 periode bulan kalender. **Tidak dipasang ke Supabase** |
| Pemuat | `muat_masukan_hrd.py` membaca 1.156 perintah lembur (menjadi persetujuan lembur); `muat_tap_simulasi.sh` bisa Pabrik B |
| Alat uji U1 | Mengenal tiga kejadian Pabrik B yang hasil sistemnya sudah benar (izin pemilik): cuti bersama potong cuti (1.016 hari, hasil libur), mesin MB1 mati 11 Mar tidak dilaporkan (177 hari, hasil "tanpa tap massal" sesuai kasus C06), mesin mati sebagian sehingga tap pulang tidak ada di file (11 hari, hasil lupa tap pulang) |
| Migrasi 0012 | `hitung.anomali_gaji(periode)`: gaji berubah >15%, lembur divisi naik >30%, aktif tanpa tap. Tidak mengubah angka, tidak disimpan |
| `cek_gaji.sql` | +2 pemeriksaan anomali |

## Angka terukur

| Yang diukur | Hasil |
| --- | --- |
| Uji database (komputer kerja) | 327 lulus, 0 gagal |
| Uji simulasi A + B (komputer kerja) | 24 lulus, 0 gagal, sekitar 4,5 menit |
| GitHub "Uji database" untuk commit kode | lulus |
| Pasang ke Supabase | lulus; 0012 sidik `781aa7127a34`; gaji Pabrik A tidak dihitung ulang (angka sama dengan 4b-3) |

**Pabrik B per periode (database uji):**

| Periode | Orang | Gaji bersih | Cuti terpakai | Lembur | THR |
| --- | --- | --- | --- | --- | --- |
| Feb | 184 | 883.418.575 | 191 | 27.993.493 | — |
| Mar | 188 | 1.478.695.594 | 694 | 25.092.198 | 615.349.996 |
| Apr | 188 | 905.174.359 | 14 | 31.829.773 | — |
| Des | 190 | 926.113.749 | 16 | 32.856.645 | — |

Cuti terpakai Maret besar karena 4 cuti bersama Idul Fitri dan Nyepi masih memotong cuti (sebelum UU 27/2026); Desember hanya hari cuti biasa (24 Des tidak memotong) [Pasti].

**Anomali yang ditanam dan isinya:** gaji pokok 20001 naik 50% ("dari Rp4.190.145 menjadi Rp6.035.014, 44%"); semua lembur Gudang April disetujui ("naik dari Rp3.886.273 menjadi Rp7.467.343"); 20002 dibuat tidak wajib tap dan ID mesinnya ditutup ("digaji Rp4.879.000 tanpa satu pun tap mesin").

## Di Supabase (Pabrik A, dicek langsung)

| Periode | Gaji bersih | Tanda anomali |
| --- | --- | --- |
| 1 (21 Jan–20 Feb) | 5.183.058.029 | aktif tanpa tap 4 |
| 2 (21 Feb–20 Mar) | 8.216.773.882 | aktif tanpa tap 4, gaji berubah 54 |
| 3 (21 Mar–20 Apr) | 5.706.405.590 | aktif tanpa tap 5, gaji berubah 430, lembur divisi naik 3 |
| 4 (21 Nov–20 Des) | 4.999.870.485 | aktif tanpa tap 4, gaji berubah 504, lembur divisi naik 1 |

## Temuan dan batasan

1. **Kelemahan sistem "belum terdaftar di mesin"** [Pasti]: karyawan baru 20190 (Pabrik B) sakit di hari pertamanya lalu 2 hari masuk tanpa terdaftar di mesin; pemberitahuan tidak muncul karena aturannya hanya melihat 2 hari kerja pertama. Keputusan pemilik: diperbaiki di paket terpisah (butuh permintaan perubahan 02 dan hitung ulang baca tap). Di alat uji dicatat sebagai info "kelemahan diketahui", bukan disembunyikan.
2. **Tanda "gaji berubah" terlalu ramai di Pabrik A** [Pasti]: 430 dari 1.010 orang di periode 3 dan 504 di periode 4. Penyebab utama dicek: lembur (selisih Rp446.934.068 di 430 orang periode 3), karena regu 7 hari bekerja di Idul Fitri dan Paskah yang dibayar sebagai lembur hari libur. Tanda sebanyak ini tidak akan dibaca HRD. Usul untuk diputuskan: tanda gaji berubah hanya membanding upah tetap dan potongan (tanpa lembur, karena lembur sudah punya tanda sendiri per divisi). Belum diubah: aturan O2 ditulis dari PRD dan perubahan butuh keputusan pemilik.
3. **Ralat dari daftar paket** [Pasti]: saya menulis "PPh Desember Pabrik B akan tertahan". Salah: periode Desember B dibayar 5 Jan 2027, jadi memakai TER biasa dan tidak tertahan. Yang tertahan hanya 4 orang berhenti di Maret dan 2 di April (tidak ada data Januari).
4. **Nilai menit di perintah lembur belum dipakai** [Pasti]: persetujuan berlaku untuk seluruh lembur hari itu, walau perintah menyebut misalnya 75 menit. Perlu aturan "dibayar sampai menit yang disetujui" bila HRD menginginkannya.
5. **Pembagi upah mengikuti pola perusahaan** [Menebak apakah ini yang diinginkan]: Pabrik B memakai pola 5 hari, jadi Sabtu Gudang (yang kerja 6 hari) tidak masuk pembagi. Untuk karyawan penuh sebulan tidak berpengaruh; untuk karyawan baru atau berhenti di Gudang, prorata hanya menghitung Senin–Jumat. Pertanyaan untuk kuesioner pemasangan.
6. **Kesalahan desain uji saya sendiri** [Pasti]: satu uji di 090 lupa bahwa THR kena PPh; harapannya diperbaiki (kode tidak diubah).
7. **Tanggal bayar dan UMK Pabrik B** adalah tebakan untuk data karangan (tanggal 5 bulan berikutnya, UMK sama dengan A).
8. Uji naik versi (0011 ke 0012) tidak dijalankan terpisah karena 0012 hanya menambah satu fungsi; pemasangan Supabase lulus dan angkanya tidak berubah.
