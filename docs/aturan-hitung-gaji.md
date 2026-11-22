# Aturan hitung gaji

Versi 5 · 17 November 2026 (versi 1: 16 Nov, paket 4b-1; versi 2: bagian H–K, paket 4b-2; versi 3: bagian L–N, paket 4b-3; versi 4: bagian O, paket 4b-4; versi 5: L2, L3, L6, O2, paket 4b-5) · setiap versi ditulis **sebelum** kodenya. Kode SQL (`hitung.hitung_gaji`) dan kalkulator pembanding (`sistem/uji/u2_pembanding.py`) sama-sama ditulis dari dokumen ini, terpisah satu sama lain, dan tidak berbagi kode. Kalau keduanya berbeda, yang diperiksa dulu dokumen ini.

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
- **D1b Datang awal yang disetujui** (versi kode 7, permintaan perubahan 06; PRD v2 B5): bila ada perintah `setujui_datang_awal` (tidak dibatalkan) untuk orang itu atau divisinya pada tanggal itu, menit lembur hari kerja = (menit lebih, bila boleh menurut D5) + menit datang awal. Menit datang awal = jadwal masuk − tap masuk, dibulatkan ke bawah per menit; hanya untuk hari `hadir` asal mesin dengan tap masuk dan pulang, tanpa lupa tap, tidak ambigu, tanpa tanda `jendela_bertumpuk`. Hasilnya memakai D4 dan seterusnya; hari itu diberi tanda `lembur_datang_awal_disetujui`. Tanpa persetujuan: menit datang awal tidak dihitung (B05). Bagian sore yang tidak boleh tetap bertanda `lembur_tidak_dibayar_tanpa_izin`.
- **D2 Hari libur, tanpa jadwal** (status `lembur_hari_libur`): menit = menit hadir, dikurangi 60 menit istirahat bila menit hadir lebih dari 240. Tidak ada tap pulang → 0 dan diberi tanda.
- **D3 Hari libur nasional dengan jadwal** (operasi 7 hari, status `hadir`, jenis hari `libur_nasional`): menit = (lama jadwal − istirahat jadwal bila tidak dibayar) − menit telat − menit pulang cepat + menit lebih. Lupa tap → tanpa menit lebih, diberi tanda (C05).
- **D4 Menit dibayar**: kurang dari menit minimal (`aturan.lembur`, 60) → 0; selebihnya dibulatkan ke bawah per kelipatan (30). Pembulatan ke bawah diberi tanda peringatan (D03).
- **D5 Izin lembur** (pengaturan `lembur` divisi pada tanggal itu): `otomatis` → dibayar kecuali ada perintah `batalkan_lembur` untuk orang itu atau divisinya pada tanggal itu (D05); `wajib_perintah` → dibayar hanya bila ada perintah `setujui_lembur` (D04, F12). Perintah yang dibatalkan `batalkan_perintah` tidak berlaku. Menit yang tidak dibayar tetap tercatat.
- **D6 Tabel pengali**: hari kerja → `kerja`. Hari libur: pola divisi `5_hari` → `libur_5_hari`; pola lain → `libur_6_hari_terpendek` bila tanggal itu jatuh di hari kerja terpendek jadwal mingguan orang itu (hari dengan jam kerja paling sedikit dalam jadwal minggu itu, dan lebih sedikit dari hari lain), selain itu `libur_6_hari`. Divisi rotasi tidak punya hari terpendek.
- **D7 Satuan** = Σ pengali (×10) jam ke-k × menit pada jam ke-k. Menit di luar jam terakhir tabel memakai pengali jam terakhir dan diberi tanda.
- **D8 Dasar upah lembur** per orang per periode: P = gaji pokok + tunjangan tetap bulanan pada tanggal akhir; T = total C1+C2+C3 periode itu. Bila P × 10000 < 7500 × (P + T) → dasar = bulat(75% × (P + T)), selain itu dasar = P. Untuk lembur tanggal 28 Okt 2026 atau sesudahnya yang memakai dasar 75%, diberi tanda "perlu dikonfirmasi HRD" (permintaan perubahan 01, D11b).
- **D9 Rupiah lembur** per hari = bulat( satuan × dasar ÷ (173 × 60 × 10) ). Komponen lembur = jumlah rupiah semua hari.
- **D10 Peringatan** (tidak mengubah angka; **versi 2**, keputusan pemilik 17 Nov 2026): hanya lembur **hari kerja** (tabel `kerja`) yang dihitung. Menit dibayar satu hari lebih dari 240 → "lewat batas 4 jam"; 240 atau lebih → "wajib diberi makan"; jumlah menit dibayar hari kerja satu minggu (Senin–Minggu) lebih dari 1.080 → "lewat batas 18 jam". Kerja di hari libur tidak memberi peringatan; jumlahnya tercatat di bukti komponen lembur. (Versi 1 ikut menghitung hari libur sesuai Penjelasan Pasal 116 dan menghasilkan 1.859 peringatan, kebanyakan shift terjadwal di hari libur nasional.)

## E. BPJS

- **E1 Upah dasar** = gaji pokok + tunjangan tetap bulanan pada tanggal akhir periode. Aturan BPJS dibaca pada **tanggal bayar**.
- **E2** Batas atas dipakai bila ada. Kesehatan: batas bawah = UMK yang berlaku pada tanggal bayar (Perpres 64/2020); lebih dari satu wilayah UMK → hitung ditolak (belum didukung).
- **E3 Iuran** = bulat( upah dasar terjepit × persen ÷ 10000 ), per program dan bagian. Kesehatan hanya bila `bpjs_kesehatan`; JHT, JP, JKK, JKM hanya bila `bpjs_ketenagakerjaan`. Iuran penuh walau masa aktif tidak penuh.
- **E4** Bagian karyawan = potongan gaji. Bagian perusahaan dicatat (kelompok `perusahaan`), tidak mengubah gaji bersih.

## F. PPh 21 (Januari–November)

- **F1 Bruto pajak** = jumlah semua pendapatan (B, C, D, termasuk potongan hari tidak dibayar) + iuran perusahaan JKK, JKM, dan Kesehatan. JHT dan JP perusahaan tidak masuk.
- **F2 Masa pajak** = bulan tanggal bayar. Masa terakhir (Desember, atau periode tempat pegawai berhenti) dihitung menurut bagian L (versi 3); masa lain memakai TER.
- **F3 Kategori TER** dari status PTKP yang berlaku pada 1 Januari tahun tanggal bayar, atau pada tanggal mulai kerja bila lebih akhir. Tarif dari `aturan.tarif_ter` pada tanggal bayar.
- **F4 PPh** = bruto × persen ÷ 10000, dibulatkan menurut pengaturan `pembulatan_pph21` (`bawah` bawaan, atau `terdekat`). Bruto 0 atau kurang → 0.

## G. Ringkasan

- **G1 Gaji bersih** = jumlah semua komponen kelompok `pendapatan` dan `potongan` (potongan bernilai negatif). **Dibayar** = gaji bersih (pembulatan tunai di paket 4b-2). Gaji bersih negatif diberi tanda.
- **G2 Peringatan**: masa kerja kurang dari 12 bulan pada tanggal akhir dan gaji pokok + tunjangan tetap di bawah UMK → "di bawah UMK" (E08, Pasal 140); gaji pokok kurang dari 75% dari gaji pokok + tunjangan tetap → "gaji pokok di bawah 75%" (Pasal 150).
- **G3** Setiap komponen punya teks bukti yang menyebut angka-angka hitungannya.
- **G4 Versi**: setiap hitung membuat versi baru; sidik hasil sama untuk masukan sama.

## H. THR (versi 2)

- **H1** Aturan THR (`aturan.thr`) yang tanggal bayarnya jatuh di dalam periode → THR dihitung di periode itu. Tidak ada → tidak ada THR.
- **H2 Penerima** = orang yang punya baris hasil harian pada tanggal bayar THR (sedang aktif).
- **H3 Masa kerja** = bulan penuh dari tanggal mulai kerja sampai hari raya (`age(hari_raya, mulai)` dalam bulan). Kurang dari 1 → 0. Cara `hari` (bila diisi): hari ÷ 365, paling banyak 1.
- **H4 THR** = bulat( (gaji pokok + tunjangan tetap pada tanggal bayar THR) × min(bulan, 12) ÷ 12 ). Komponen `thr`, kelompok pendapatan, ikut bruto pajak (F1). THR tidak ikut dasar lembur (D8) dan tidak ikut dasar batas potongan (I3).

## I. Denda, kasbon, batas potongan (versi 2)

- **I1 Denda** hanya dari `aturan.tingkat_denda` yang berlaku (setiap baris wajib punya dasar pasal): per hari, `telat` bila menit telat di rentang [dari, sampai); `pulang_cepat` sama; `lupa_tap` bila ada lupa tap; `alpha` per hari alpha. Tidak ada baris → tidak ada denda.
- **I2 Kasbon**: saldo sebelum periode = jumlah `pinjam` − jumlah `pelunasan` (dicatat sampai tanggal akhir periode) − potongan kasbon di versi gaji terakhir semua periode yang berakhir sebelum periode ini. Diminta = cicilan terakhir yang dicatat (`cicilan`, sampai tanggal akhir) bila ada, selain itu seluruh saldo; paling banyak saldo.
- **I3 Batas** = persen `aturan.batas_potongan` (Pabrik A 50%) × dasar, dibulatkan ke bawah; dasar = jumlah pendapatan periode itu **tanpa THR** (B, C, D), paling kecil 0.
- **I4 Urutan**: denda dipotong dulu sampai batas; lalu kasbon mengisi sisa batas. Denda yang melewati batas hangus (tidak dibawa); kasbon yang tidak terpotong tetap di saldo dan dipotong periode berikutnya (E07).
- **I5** Komponen `denda` dan `kasbon` kelompok potongan. Tidak mengurangi bruto pajak.

## J. Pembayaran tunai dan sisa (versi 2)

- **J1 Sisa lalu** = sisa pembulatan orang itu di versi gaji terakhir periode sebelumnya (periode dengan tanggal akhir terbesar sebelum tanggal awal periode ini); tidak ada → 0.
- **J2** Cara bayar = cara bayar pada tanggal akhir periode. **Tunai**: dibayar = (gaji bersih + sisa lalu) dibulatkan ke bawah ke kelipatan pengaturan `pembulatan_tunai` (Pabrik A 1.000); sisa = gaji bersih + sisa lalu − dibayar (E09). **Transfer**: dibayar = gaji bersih + sisa lalu, sisa 0.
- **J3** Gaji bersih + sisa lalu negatif → dibayar 0, sisa = nilai negatif itu, diberi tanda.
- **J4** Ringkasan menyimpan sisa lalu, dibayar, dan sisa pembulatan. Bila periode sebelumnya dihitung ulang, periode ini perlu dihitung ulang juga (sisa lalu dan saldo kasbon berubah) [batasan dicatat].

## K. Ringkasan versi 2

- G1 berubah: dibayar mengikuti J2; gaji bersih tetap = jumlah rincian pendapatan dan potongan.

## L. PPh masa terakhir (versi 3)

- **L1 Masa terakhir** = periode yang tanggal bayarnya di bulan Desember, atau periode yang memuat tanggal berhenti pegawai (status kerja `berhenti` di antara tanggal awal dan akhir).
- **L2 Data setahun lengkap** (dinilai per orang, **versi 5**) bila untuk setiap bulan 1 sampai (bulan bayar − 1) tahun itu: bulan itu tercakup isian pajak awal tahun orang itu (L6), atau ada periode perusahaan yang tanggal bayarnya di bulan tersebut dan punya hasil hitung gaji. Tidak lengkap → PPh masa itu **tidak dihitung** (nilai 0), tanda `pph_masa_terakhir_tertahan`; periode itu tidak boleh diajukan (fungsi `hitung.periode_bisa_diajukan`).
- **L3 Unsur setahun** (**versi 5**: isian pajak awal tahun L6, ditambah semua periode yang dibayar di tahun itu sebelum periode ini **di bulan sesudah bulan terakhir isian**, versi gaji terakhirnya, ditambah periode ini; bulan isian dihitung sebanyak `bulan_kerja` isian): bruto = jumlah bruto pajak; iuran = jumlah iuran JHT + JP bagian karyawan; bulan = banyak periode itu yang memuat orang ini; PPh sudah dipotong = jumlah PPh 21 periode sebelumnya (dikurangi pengembaliannya bila ada).
- **L4** Biaya jabatan = min(5% × bruto dibulatkan ke bawah, 500.000 × bulan). Neto = bruto − biaya jabatan − iuran. PTKP = nilai setahun status PTKP (acuan sama dengan F3). PKP = ke bawah ribuan dari (neto − PTKP), paling kecil 0.
- **L5** PPh setahun = tarif Pasal 17 berlapis (`aturan.tarif_pasal17`, berlaku tanggal bayar) atas PKP, dibulatkan ke bawah ke rupiah. PPh masa terakhir = PPh setahun − PPh sudah dipotong. Positif → komponen `pph21` (potongan). Negatif → `pph21` 0 dan komponen `pengembalian_pph21` (pendapatan, tidak ikut bruto pajak, tidak ikut dasar lembur dan batas potongan).

- **L6 Isian pajak awal tahun** (**versi 5**): tabel `induk.pajak_awal_tahun`, satu baris per karyawan per tahun, diisi HRD dari sistem lama (bukti potong) untuk bulan-bulan sebelum sistem dipakai: `sampai_bulan` (1–11), `bulan_kerja` (banyak bulan bekerja di bagian itu, untuk batas biaya jabatan), `bruto`, `iuran` (JHT + JP bagian karyawan), `pph` (PPh 21 yang sudah dipotong). Periode sistem yang tanggal bayarnya di bulan ≤ `sampai_bulan` tidak ikut dijumlah (isian yang dipakai), supaya tidak terhitung dua kali.

## M. Saldo cuti (versi 3)

- **M1 Cuti terpakai** periode ini = banyak hari berstatus `cuti`, ditambah hari jenis `cuti_bersama` berstatus `libur` bila pengaturan `cuti_bersama` divisi pada tanggal itu = `potong_cuti` **dan** tanggalnya sebelum 28 Okt 2026. Sejak 28 Okt 2026 hari itu tidak memotong; bila pengaturannya masih `potong_cuti` diberi tanda `potong_cuti_tidak_berlaku_uu27` (C02b).
- **M2 Saldo awal** dari tabel baru `induk.saldo_cuti_awal` (diisi HRD, tanggal = tanggal awal sebuah periode). Saldo dihitung hanya bila periode-periode dari tanggal saldo awal sampai periode ini bersambung tanpa celah; selain itu saldo kosong (belum pasti), tanpa tanda.
- **M3 Saldo akhir** = saldo awal + jatah (`aturan.cuti`, 12 hari) untuk setiap ulang tahun kerja (mulai + 12, 24, … bulan) yang jatuh setelah tanggal saldo awal sampai tanggal akhir periode − cuti terpakai semua periode itu. Cuti hangus belum dihitung.
- **M4** Ringkasan menyimpan cuti terpakai dan saldo cuti.

## N. Pecahan uang tunai (versi 3)

- **N1** Untuk setiap orang dibayar tunai: dibayar dipecah rakus ke pecahan 100.000, 50.000, 20.000, 10.000, 5.000, 2.000, 1.000 (hanya pecahan yang ≥ pembulatan tunai). Fungsi `hitung.pecahan_tunai(versi)` mengembalikan lembar per pecahan untuk satu versi gaji; jumlahnya harus sama dengan total dibayar tunai (U12).

## O. Tanda anomali sebelum rilis (versi 4, U10)

Dasar: PRD v3.1 bagian H1 ("gaji berubah >15%, lembur divisi naik >30%") dan U10. Tanda tidak mengubah angka gaji dan tidak menahan pengajuan; HRD memeriksanya sebelum rilis. Fungsi `hitung.anomali_gaji(periode)` menghitungnya dari versi gaji terakhir, tidak disimpan.

- **O1 Periode lalu** = periode dengan tanggal awal terbesar sebelum tanggal awal P yang punya versi gaji. Tidak ada → O2 dan O3 tidak diperiksa.
- **O2 Gaji berubah** (`gaji_berubah`, **versi 5**): untuk orang yang punya ringkasan gaji di P dan di periode lalu, nilai banding = jumlah komponen `gaji_pokok`, `tunjangan_tetap`, dan `potongan_tidak_dibayar`. Lembur, uang makan, tunjangan shift malam, premi, THR, dan pengembalian PPh tidak dibanding (versi 4 membanding semua pendapatan kecuali THR; di Pabrik A hasilnya 430–504 tanda per periode, kebanyakan karena lembur hari raya; lembur sudah punya tanda O3). Tanda bila nilai lalu > 0 dan |nilai P − nilai lalu| × 100 > 15 × nilai lalu (lebih dari 15%, naik atau turun). Isi tanda: nilai lalu, nilai P.
- **O3 Lembur divisi naik** (`lembur_divisi_naik`): divisi orang = divisi di hari terakhirnya di hasil harian periode itu. Jumlah komponen `lembur` per divisi di P dibanding periode lalu. Tanda bila jumlah P × 100 > 130 × jumlah lalu (lebih dari 30%), termasuk bila jumlah lalu 0 dan jumlah P > 0.
- **O4 Aktif tanpa tap** (`aktif_tanpa_tap`): orang dengan gaji bersih > 0 di P yang tidak punya satu pun hari dengan asal `mesin` di hasil harian P (termasuk yang tidak wajib tap dan yang seluruh harinya dari perintah HRD; isi tanda menyebut asal harinya). Diperiksa juga di periode pertama.

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
| K19 | THR, masa kerja 24 bulan, upah 4.000.000 | Rp4.000.000 | E03 |
| K20 | THR, masa kerja 6 bulan, upah 4.000.000 | Rp2.000.000 | E03 |
| K21 | THR, masa kerja kurang dari 1 bulan | Rp0, tidak ada komponen THR | Permenaker 6/2016 |
| K22 | Pendapatan 4.000.000, denda 500.000, saldo kasbon 2.000.000 | batas 2.000.000: denda 500.000 + kasbon 1.500.000; sisa kasbon 500.000 dipotong periode berikutnya | E07 |
| K23 | Pendapatan 4.000.000, denda 2.500.000, saldo kasbon 2.000.000 | denda 2.000.000, kasbon 0, saldo kasbon tetap 2.000.000 | E07 |
| K24 | Gaji bersih 3.847.263 tunai, pembulatan 1.000, tanpa sisa lalu | dibayar 3.847.000, sisa 263; periode berikutnya dibayar ditambah 263 | E09 |
| K25 | Berhenti tengah periode, pendapatan prorata 1.500.000, sisa kasbon 300.000 | batas 750.000 → kasbon 300.000 terpotong penuh, saldo 0 | E12 (bagian kasbon) |
| K26 | Shift 7 jam di hari libur nasional; lembur hari kerja 250 menit | yang pertama tanpa peringatan; yang kedua "lewat batas 4 jam" | D10 versi 2 |
| K27 | Gaji transfer | tidak dibulatkan, sisa 0 | J2 |
| K28 | PPh setahun: bruto 401.920.000, pengurang 3.600.000, K/0, 12 bulan | PPh setahun Rp52.455.000 | Ilustrasi PMK 168 (Tuan A) |
| K29 | PPh Desember Tuan A: 52.455.000 − (10 × 3.920.800 + 9.028.800) | Rp4.218.200 | Ilustrasi PMK 168 (DDTCNews) |
| K30 (E11) | 12 periode lengkap, gaji tetap 4.000.000 TK/0, BPJS tidak ikut | Desember = PPh setahun (bruto 48.000.000 − biaya jabatan 2.400.000 = 45.600.000 < PTKP 54.000.000 → 0) − TER Jan–Nov (0) = 0 | hitungan Claude |
| K31 (E11) | 12 periode lengkap, gaji 10.000.000 TK/0, tanpa BPJS | TER Jan–Nov 2% × 10 jt = 200.000 × 11 = 2.200.000; setahun: bruto 120 jt − BJ 6 jt = 114 jt − PTKP 54 jt = PKP 60 jt → 3.000.000; Desember = 800.000 | hitungan Claude |
| K32 (E12) | Berhenti di periode Juni, data Jan–Mei lengkap, gaji 10.000.000 TK/0 | 6 bulan: bruto 60 jt − BJ 3 jt = 57 jt − PTKP 54 jt = PKP 3 jt → 150.000; sudah dipotong 5 × 200.000 = 1.000.000 → pengembalian 850.000 | hitungan Claude |
| K33 | Data setahun tidak lengkap (Desember tanpa periode Januari) | PPh 0, tanda tertahan, periode tidak bisa diajukan | L2 |
| K34 (C02) | Cuti bersama 16 Feb 2026, pengaturan potong cuti, tidak masuk | cuti terpakai 1 | M1 |
| K35 (C02b) | Cuti bersama 24 Des 2026, pengaturan potong cuti | cuti terpakai 0, tanda potong cuti tidak berlaku | M1 |
| K36 | Saldo awal 5 hari pada awal periode, 2 hari cuti, ulang tahun kerja di periode itu | saldo akhir 5 + 12 − 2 = 15 | M3 |
| K37 (U12) | Dibayar tunai 3.847.000 | 38 × 100.000, 2 × 20.000, 1 × 5.000, 1 × 2.000 | N1 |
| K38 (O2) | Pendapatan 4.000.000 periode lalu, naik gaji jadi 4.700.000 | tanda gaji berubah (17,5%) | O2 |
| K39 (O2) | 4.000.000 → 4.600.000 | tidak ada tanda (tepat 15%, bukan lebih) | O2 |
| K40 (O2) | 4.000.000 → 4.000.000 + THR 4.000.000 | tidak ada tanda (THR tidak dibanding) | O2 |
| K41 (O2) | 4.000.000 → 3.000.000 | tanda gaji berubah (turun 25%) | O2 |
| K42 (O3) | Divisi satu orang upah 4.000.000: lembur 120 menit (Rp80.925) → 2 × 120 menit (Rp161.850) | tanda lembur divisi naik | O3, K3 |
| K43 (O3) | Lembur divisi Rp80.925 → Rp80.925 | tidak ada tanda | O3 |
| K44 (O4) | Seluruh hari periode berstatus sakit dari perintah HRD, tanpa tap mesin, gaji dibayar | tanda aktif tanpa tap | O4 |
| K45 (O4) | Sama, tetapi satu hari ada tap mesin | tidak ada tanda | O4 |
| K46 (O1) | Periode pertama | hanya O4 yang diperiksa | O1 |
| K47 (O2 v5) | Upah tetap 4.000.000 dua periode, lembur Rp80.925 lalu Rp809.250 | tidak ada tanda gaji berubah (lembur tidak dibanding) | O2 versi 5 |
| K48 (L6) | Desember 2027 saja di sistem; isian awal tahun Jan–Nov: bulan kerja 11, bruto 110.000.000, iuran 0, PPh 2.200.000; gaji Desember 10.000.000 TK/0 tanpa BPJS | tidak tertahan; PPh Desember 3.000.000 − 2.200.000 = **800.000** (sama dengan K31) | L2, L3, L6 |
| K49 (L2 v5) | Sama dengan K48, orang lain tanpa isian | PPh 0, tanda tertahan; periode tidak bisa diajukan | L2 |
| K50 (L6) | Isian sampai bulan 10 (bulan kerja 10, bruto 100.000.000, PPh 2.000.000), periode sistem bayar November dan Desember 10.000.000 | November TER 200.000; Desember 800.000 | L3, L6 |
| K51 (F13b) | Karyawan baru, hari kerja pertama sakit (perintah HRD), 2 hari kerja berikutnya tanpa tap | 2 hari alpha; pemberitahuan belum terdaftar di mesin | permintaan perubahan 02 |

Catatan K9/K10: aturan "yang lebih besar" yang disetujui untuk tanggal sesudah 28 Okt 2026 selalu memberi angka yang sama dengan aturan 75% lama (aturan lama memilih 75% justru bila nilainya lebih besar). Bedanya hanya tanda konfirmasi.

## Batasan

Belum dihitung: cuti hangus, zakat, sakit lebih dari 4 bulan, ganti rugi (belum ada tempat datanya), bonus dan penyesuaian manual, THR untuk pekerja yang berhenti dalam 30 hari sebelum hari raya.
