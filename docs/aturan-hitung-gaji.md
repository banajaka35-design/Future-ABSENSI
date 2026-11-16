# Aturan hitung gaji (paket 4b-1)

Versi 1 · 16 November 2026 · ditulis **sebelum** kode hitung gaji. Kode SQL (`hitung.hitung_gaji`) dan kalkulator pembanding (`sistem/uji/u2_pembanding.py`) sama-sama ditulis dari dokumen ini, terpisah satu sama lain, dan tidak berbagi kode. Kalau keduanya berbeda, yang diperiksa dulu dokumen ini.

Dasar hukum dan labelnya: `docs/cek-aturan-hukum.md`. Kasus uji dengan angka harapan: bagian "Kunci" di bawah dan kasus jebakan v1.2.

Semua rupiah bilangan bulat. "bulat(x)" = setengah ke atas ke rupiah terdekat, sekali per komponen (kontrak data bagian 7). Persen disimpan per sepuluh ribu.

## A. Masukan

- Periode P (tanggal awal, akhir, bayar) dan hasil harian dari **versi baca tap terakhir** P. Belum ada → hitung ditolak.
- Orang yang dihitung: setiap karyawan yang punya baris hasil harian di versi itu.
- Data karyawan, pengaturan, dan aturan dibaca **pada tanggal yang disebut tiap aturan** (pola bertanggal).

## B. Upah tetap (gaji pokok dan tunjangan tetap)

- **B1 Pembagi** = banyak tanggal dalam periode yang termasuk hari kerja pola perusahaan pada tanggal akhir periode: pola `5_hari` → Senin–Jumat; pola lain → Senin–Sabtu. Tanggal merah tetap dihitung (upah bulanan tidak berkurang karena libur).
- **B2 Hari aktif** = tanggal yang punya baris hasil harian (baca tap hanya membuat baris untuk masa aktif) dan termasuk hari pola B1.
- **B3 Gaji pokok** = bulat( Σ gaji pokok yang berlaku di tiap hari aktif ÷ pembagi ). **Tunjangan tetap** sama. Karyawan penuh satu periode dengan gaji tetap mendapat persis gaji bulanannya. Karyawan baru, berhenti, dan naik gaji otomatis prorata (C10, E01, E02).
- **B4 Hari tidak dibayar** = hari berstatus `alpha`, atau `izin` bila pengaturan `izin_dibayar` = `tidak` (bawaan), dengan jenis hari `kerja` atau `cuti_bersama` (hari apa pun dalam minggu). Komponen **potongan hari tidak dibayar** = −bulat( Σ (gaji pokok + tunjangan tetap) hari itu ÷ pembagi ). Alpha di hari libur nasional tidak dipotong (Pasal 125 ayat 1) dan diberi tanda.
- **B5** Status `sakit`, `cuti`, `dinas_luar`, `libur`, `hadir`, `lembur_hari_libur` dibayar penuh. Status `menunggu` atau `tanpa_tap_massal` tidak dipotong dan diberi tanda "belum pasti".

## C. Tunjangan tidak tetap

Nominal dari `aturan.komponen_lain` yang berlaku pada tanggalnya; hidup/mati dari pengaturan divisi orang itu pada tanggalnya.

- **C1 Uang makan** (pengaturan `uang_makan` = `dihitung`): nominal × banyak hari berstatus `hadir` dengan telat paling lama 60 menit (syarat di isian Pabrik A; angka tetap 60).
- **C2 Tunjangan shift malam** (`tunjangan_shift_malam` = `hidup`): nominal × banyak hari `hadir` dengan kode jadwal yang jam pulangnya lewat tengah malam.
- **C3 Premi hadir** (`premi_hadir` = `hidup`, dilihat pada tanggal akhir periode): nominal sekali bila dalam periode tidak ada hari `alpha` dan tidak ada hari dengan telat (E13).

## D. Lembur

- **D1 Hari kerja** (status `hadir`, jenis hari `kerja` atau `cuti_bersama`): menit = menit lebih (lewat jam pulang jadwal).
- **D2 Hari libur, tanpa jadwal** (status `lembur_hari_libur`): menit = menit hadir, dikurangi 60 menit istirahat bila menit hadir lebih dari 240. Tidak ada tap pulang → 0 dan diberi tanda.
- **D3 Hari libur nasional dengan jadwal** (operasi 7 hari, status `hadir`, jenis hari `libur_nasional`): menit = (lama jadwal − istirahat jadwal bila tidak dibayar) − menit telat − menit pulang cepat + menit lebih. Lupa tap → tanpa menit lebih, diberi tanda (C05).
- **D4 Menit dibayar**: kurang dari menit minimal (`aturan.lembur`, 60) → 0; selebihnya dibulatkan ke bawah per kelipatan (30). Pembulatan ke bawah diberi tanda peringatan (D03).
- **D5 Izin lembur** (pengaturan `lembur` divisi pada tanggal itu): `otomatis` → dibayar kecuali ada perintah `batalkan_lembur` untuk orang itu atau divisinya pada tanggal itu (D05); `wajib_perintah` → dibayar hanya bila ada perintah `setujui_lembur` (D04, F12). Perintah yang dibatalkan `batalkan_perintah` tidak berlaku. Menit yang tidak dibayar tetap tercatat.
- **D6 Tabel pengali**: hari kerja → `kerja`. Hari libur: pola divisi `5_hari` → `libur_5_hari`; pola lain → `libur_6_hari_terpendek` bila tanggal itu jatuh di hari kerja terpendek jadwal mingguan orang itu (hari dengan jam kerja paling sedikit dalam jadwal minggu itu, dan lebih sedikit dari hari lain), selain itu `libur_6_hari`. Divisi rotasi tidak punya hari terpendek.
- **D7 Satuan** = Σ pengali (×10) jam ke-k × menit pada jam ke-k. Menit di luar jam terakhir tabel memakai pengali jam terakhir dan diberi tanda.
- **D8 Dasar upah lembur** per orang per periode: P = gaji pokok + tunjangan tetap bulanan pada tanggal akhir; T = total C1+C2+C3 periode itu. Bila P × 10000 < 7500 × (P + T) → dasar = bulat(75% × (P + T)), selain itu dasar = P. Untuk lembur tanggal 28 Okt 2026 atau sesudahnya yang memakai dasar 75%, diberi tanda "perlu dikonfirmasi HRD" (permintaan perubahan 01, D11b).
- **D9 Rupiah lembur** per hari = bulat( satuan × dasar ÷ (173 × 60 × 10) ). Komponen lembur = jumlah rupiah semua hari.
- **D10 Peringatan** (tidak mengubah angka): menit dibayar satu hari lebih dari 240 → "lewat batas 4 jam"; 240 atau lebih → "wajib diberi makan"; jumlah menit dibayar satu minggu (Senin–Minggu) lebih dari 1.080 → "lewat batas 18 jam". Lembur hari libur ikut dihitung (Penjelasan Pasal 116).

## E. BPJS

- **E1 Upah dasar** = gaji pokok + tunjangan tetap bulanan pada tanggal akhir periode. Aturan BPJS dibaca pada **tanggal bayar**.
- **E2** Batas atas dipakai bila ada. Kesehatan: batas bawah = UMK yang berlaku pada tanggal bayar (Perpres 64/2020); lebih dari satu wilayah UMK → hitung ditolak (belum didukung).
- **E3 Iuran** = bulat( upah dasar terjepit × persen ÷ 10000 ), per program dan bagian. Kesehatan hanya bila `bpjs_kesehatan`; JHT, JP, JKK, JKM hanya bila `bpjs_ketenagakerjaan`. Iuran penuh walau masa aktif tidak penuh.
- **E4** Bagian karyawan = potongan gaji. Bagian perusahaan dicatat (kelompok `perusahaan`), tidak mengubah gaji bersih.

## F. PPh 21 (Januari–November)

- **F1 Bruto pajak** = jumlah semua pendapatan (B, C, D, termasuk potongan hari tidak dibayar) + iuran perusahaan JKK, JKM, dan Kesehatan. JHT dan JP perusahaan tidak masuk.
- **F2 Masa pajak** = bulan tanggal bayar. Masa Desember → PPh tidak dihitung di paket ini; diberi tanda "PPh Desember (hitung ulang setahun) belum dihitung", nilai 0.
- **F3 Kategori TER** dari status PTKP yang berlaku pada 1 Januari tahun tanggal bayar, atau pada tanggal mulai kerja bila lebih akhir. Tarif dari `aturan.tarif_ter` pada tanggal bayar.
- **F4 PPh** = bruto × persen ÷ 10000, dibulatkan menurut pengaturan `pembulatan_pph21` (`bawah` bawaan, atau `terdekat`). Bruto 0 atau kurang → 0.

## G. Ringkasan

- **G1 Gaji bersih** = jumlah semua komponen kelompok `pendapatan` dan `potongan` (potongan bernilai negatif). **Dibayar** = gaji bersih (pembulatan tunai di paket 4b-2). Gaji bersih negatif diberi tanda.
- **G2 Peringatan**: masa kerja kurang dari 12 bulan pada tanggal akhir dan gaji pokok + tunjangan tetap di bawah UMK → "di bawah UMK" (E08, Pasal 140); gaji pokok kurang dari 75% dari gaji pokok + tunjangan tetap → "gaji pokok di bawah 75%" (Pasal 150).
- **G3** Setiap komponen punya teks bukti yang menyebut angka-angka hitungannya.
- **G4 Versi**: setiap hitung membuat versi baru; sidik hasil sama untuk masukan sama.

## Kunci (angka harapan, ditulis sebelum kode)

Upah contoh kasus jebakan: gaji pokok 3.500.000 + tunjangan tetap 500.000 = 4.000.000; upah sejam = 4.000.000 ÷ 173.

| No | Kejadian | Harapan | Asal |
| --- | --- | --- | --- |
| K1 | PPh TER: K/0, bruto 30.160.000, masa Januari | Kategori A, 13% → Rp3.920.800 | Ilustrasi Lampiran PMK 168/2023 (lewat DDTCNews) |
| K2 | PPh TER: TK/0, bruto 10.454.000 | 2,5% → Rp261.350 | Kasus E04 |
| K3 | Lembur hari kerja 120 menit | 15×60 + 20×60 = 2.100 satuan → Rp80.925 | Kasus D01 |
| K4 | Lembur hari kerja 59 menit | Rp0, menit tetap tercatat | D02 |
| K5 | Lembur hari kerja 95 menit | dibayar 90 menit → Rp57.803 + tanda pembulatan | D03 |
| K6 | Libur pola 6 hari 480 menit | 7×20×60 + 1×30×60 → Rp393.064 | D06 |
| K7 | Libur di hari terpendek pola 6 hari 420 menit | 5×20×60 + 30×60 + 40×60 → Rp393.064 | D07 |
| K8 | Libur pola 5 hari 600 menit | 8×20×60 + 30×60 + 40×60 → Rp531.792 | D08 |
| K9 | Pokok 2.000.000 + tetap 500.000 + tidak tetap 1.500.000, lembur 120 menit | dasar 3.000.000 → Rp60.694 | D11 |
| K10 | Sama dengan K9, tanggal 2 Nov 2026 | Rp60.694 + tanda "perlu dikonfirmasi HRD" | D11b |
| K11 | BPJS Kesehatan karyawan, upah 15.000.000 | 1% × 12.000.000 = Rp120.000 | E05 |
| K12 | BPJS JP karyawan, upah 15.000.000, bayar 25 Mar 2026 | 1% × 11.086.300 = Rp110.863 | E06 + batas JP resmi |
| K13 | BPJS Kesehatan karyawan, upah 3.000.000, UMK 3.402.892 | dasar UMK → Rp34.029 | Perpres 64/2020 |
| K14 | Masuk tengah periode, 13 dari 26 hari pola, upah 4.000.000 | gaji pokok 1.750.000 + tetap 250.000 = 2.000.000 | E01 |
| K15 | Naik 4.000.000 → 5.000.000 di hari ke-14 dari 26 (13 hari tiap tarif) | (13×4 jt + 13×5 jt) ÷ 26 = 4.500.000 | E02 |
| K16 | Satu alpha, premi hadir hidup | premi 0; potongan −bulat(4.000.000 ÷ pembagi) | E13, B4 |
| K17 | Pokok + tetap 3.300.000, masa kerja 8 bulan, UMK 3.402.892 | tanda "di bawah UMK" | E08 |
| K18 | Satu periode penuh: total gaji bersih = jumlah semua rincian | selisih 0 | U3 / E10 |

Catatan K9/K10: aturan "yang lebih besar" yang disetujui untuk tanggal sesudah 28 Okt 2026 selalu memberi angka yang sama dengan aturan 75% lama (aturan lama memilih 75% justru bila nilainya lebih besar). Bedanya hanya tanda konfirmasi.

## Batasan paket ini

Tidak dihitung: THR, kasbon, denda, batas potongan 50%, pembulatan tunai, saldo cuti, PPh Desember, sakit lebih dari 4 bulan, bonus dan penyesuaian manual. Angka-angka itu 0 atau tidak muncul.
