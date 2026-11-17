# Cek aturan hukum untuk hitung gaji (Tahap 4)

Dicek 16 November 2026 oleh Claude (paket 4a). Tujuan: setiap angka yang dipakai mesin hitung gaji punya dasar hukum yang tertulis, dan jelas mana yang sudah pasti dan mana yang masih dugaan.

Label: **[Pasti]** = dibaca dari sumber resmi, atau dari dua sumber berbeda yang isinya sama · **[Kemungkinan Besar]** = dari salinan tidak resmi atau berita, belum dari naskah resmi · **[Menebak]** = belum ada sumber, hanya dugaan.

## Batasan pengecekan ini

- **Naskah resmi UU 27/2026 sudah dibaca (16 Nov 2026, 19.4x WIB):** file `UU Nomor 27 Tahun 2026.pdf` dari JDIH BPK (peraturan.bpk.go.id, 183 halaman, 12,8 MB; Lembaran Negara 2026 Nomor 179, Tambahan LN Nomor 7222), diunduh pemilik proyek ke komputernya lalu dibaca Claude lewat lapisan teks PDF. Semua pasal di tabel 1 dicocokkan dengan naskah itu, termasuk bagian Penjelasan. File tidak disimpan di repo.
- Ini bukan nasihat hukum. Untuk perusahaan sungguhan, pasal-pasal yang dipakai sebaiknya diperiksa juga oleh orang yang paham hukum ketenagakerjaan.

## 1. UU 27/2026 tentang Pelindungan Ketenagakerjaan

Disahkan, diundangkan, dan berlaku 28 Oktober 2026 (Pasal 313; LN 2026 Nomor 179) [Pasti, naskah resmi]. Mencabut UU 13/2003 dan Pasal 80 huruf a serta Pasal 81 lampiran UU 6/2023 (Pasal 311) [Pasti, naskah resmi].

| Hal | Isi | Pasal | Label | Dampak ke sistem |
| --- | --- | --- | --- | --- |
| Jam kerja normal | 7 jam/hari untuk 6 hari kerja, 8 jam/hari untuk 5 hari kerja; 40 jam/minggu | 115 ayat 2 | Pasti | Sama dengan aturan lama; pola hari kerja tetap isian per perusahaan |
| Batas lembur | Paling lama 4 jam/hari dan 18 jam/minggu; perlu persetujuan pekerja dan perintah tertulis atau digital | 116 ayat 1 | Pasti | Kasus D09/D10 (peringatan, tetap dibayar penuh) tetap berlaku. Pertanyaan baru di bawah soal pengaturan "lembur otomatis" |
| Upah lembur hari kerja | Jam pertama 1,5 × upah sejam, jam berikutnya 2 × | 116 ayat 2 | Pasti | Sama dengan `aturan.pengali_lembur` jenis `kerja` (dari PP 35/2021) |
| Upah sejam | **(Upah pokok + tunjangan tetap) ÷ 173** | 116 ayat 3, 125 ayat 5 | Pasti | **Bisa bentrok dengan kasus D11** (lihat bagian 4) |
| Lembur hari libur/istirahat | 6 hari kerja: jam 1–7 ×2, jam 8 ×3, jam 9–11 ×4; hari kerja terpendek: jam 1–5 ×2, jam 6 ×3, jam 7–9 ×4; 5 hari kerja: jam 1–8 ×2, jam 9 ×3, jam 10–12 ×4 | 125 ayat 3–4 | Pasti | Sama dengan isi `aturan.pengali_lembur` sekarang (44 baris) |
| Cuti tahunan | Paling sedikit 12 hari kerja setelah 12 bulan bekerja terus-menerus | 118 ayat 5 | Pasti | Sama dengan `aturan.cuti` (12 hari, setelah 12 bulan) |
| Cuti bersama | Cuti bersama yang ditetapkan Pemerintah Pusat **tidak mengurangi hak cuti tahunan** | 118 ayat 6 | Pasti | **Pilihan "cuti bersama potong cuti" tidak boleh lagi dipakai untuk tanggal sejak 28 Okt 2026.** Lihat `docs/permintaan-perubahan-01.md` |
| Istirahat panjang | 30 hari kalender setelah 5 tahun kerja berturut-turut; tahun itu tidak dapat cuti tahunan | 118 ayat 2c dan 4 | Pasti | Belum ada di sistem; dicatat untuk saldo cuti (Tahap 4b atau sesudahnya) |
| Upah minimum | Upah bulanan terendah (tanpa tunjangan, atau pokok + tunjangan tetap); **berlaku untuk pekerja dengan masa kerja kurang dari 1 tahun**; pengusaha dilarang membayar di bawahnya | 140 ayat 1, 2, 5 | Pasti | Batas bawah: gaji pokok (+ tunjangan tetap) tidak boleh di bawah UMK. Mesin hitung memberi peringatan, tidak diam-diam menaikkan |
| Ada tunjangan tidak tetap | Upah pokok paling sedikit sebesar upah minimum | 140 ayat 3 | Pasti | Pemeriksaan data karyawan di Tahap 4b |
| Komposisi upah | Upah pokok paling sedikit 75% dari (upah pokok + tunjangan tetap) | 150 | Pasti | Pemeriksaan data karyawan di Tahap 4b |
| Arti tunjangan tetap | Tambahan di luar upah pokok yang tetap besaran dan waktu bayarnya, **tidak dikaitkan dengan kehadiran atau prestasi** | Penjelasan 116 ayat 3 | Pasti | Uang makan per hari hadir, premi hadir, tunjangan shift malam = tidak tetap (sesuai isian demo sekarang); dicek di kuesioner pemasangan |
| Kesepakatan di bawah aturan | Kesepakatan upah yang lebih rendah dari peraturan batal demi hukum; yang berlaku peraturan | 135 ayat 4–5 | Pasti | Dasar prinsip "batas bawah hukum dijaga mesin hitung, bukan pilihan HRD" |
| Denda | Pekerja yang melanggar karena sengaja/lalai dapat didenda; pengaturan denda oleh Pemerintah | 135 ayat 7–9 | Pasti | Rinciannya menunggu PP; sampai itu `aturan.tingkat_denda` tetap wajib punya dasar pasal (celah C2) |
| Kebijakan pengupahan lain | THR, hal yang dapat diperhitungkan dengan upah (potongan), upah tidak masuk kerja, dan lainnya diatur dengan **Peraturan Pemerintah** | 134 ayat 4–5 | Pasti | UU tidak memuat angka batas potongan 50% atau rumus THR |
| Aturan pelaksana lama | Aturan pelaksana UU 13/2003 dan UU 6/2023 **masih berlaku** selama tidak bertentangan dengan UU ini | 310 | Pasti | PP 35/2021 dan PP 36/2021 masih dipakai untuk hal yang tidak diatur ulang UU 27/2026 |
| Batas waktu aturan pelaksana baru | Paling lama 1 tahun sejak diundangkan (sampai 28 Okt 2027) | 312 | Pasti | Rumus bisa berubah lagi sebelum Okt 2027; semua angka tetap disimpan bertanggal |

Tidak ada di UU 27/2026 [Pasti, dicari di seluruh naskah]: angka batas potongan upah 50%, rumus THR, rincian iuran BPJS. UU menyerahkannya ke Peraturan Pemerintah (Pasal 134 ayat 5). Sampai PP baru terbit, aturan lama tetap berlaku sepanjang tidak bertentangan (Pasal 310) [Pasti]. Isi aturan lama itu (PP 36/2021 tentang batas potongan, Permenaker 6/2016 tentang THR) belum dicek di paket ini [Menebak]; dicek di paket 4b sebelum rumusnya ditulis.

## 2. Pajak: TER PPh 21 dan PTKP

| Hal | Isi | Dasar | Label | Di Supabase |
| --- | --- | --- | --- | --- |
| Tarif TER bulanan | Kategori A 44 lapisan, B 40, C 41; 0% sampai 34% | Lampiran PP 58/2023, berlaku 1 Jan 2024 | **Pasti**: dua salinan lampiran (tabel ortax.org dan salinan pindai lampiran PP) isinya sama baris per baris; jumlah lapisan sama dengan ringkasan KPMG | Diisi migrasi 0008 |
| PTKP | TK/0 54 jt; TK/1 dan K/0 58,5 jt; TK/2 dan K/1 63 jt; TK/3 dan K/2 67,5 jt; K/3 72 jt (setahun) | PMK 101/PMK.010/2016 | Pasti (beberapa sumber pajak, termasuk berita DJP 2026: belum berubah) | Diisi migrasi 0008 |
| Kategori TER per status PTKP | A: TK/0, TK/1, K/0 · B: TK/2, TK/3, K/1, K/2 · C: K/3 | PP 58/2023 | Pasti | Diisi migrasi 0008 |
| Rencana perubahan PTKP 2027 | Pemerintah sedang menyiapkan PMK penyesuaian PTKP (berita 24 Okt 2026), belum terbit | — | Kemungkinan Besar akan berubah | Dicek lagi sebelum gaji Januari 2027. Bila berubah, kemungkinan besar tabel TER ikut berubah |
| Masa pajak Desember | Tidak memakai TER; dihitung ulang setahun dengan tarif Pasal 17 | PMK 168/2023 | Pasti | Belum ada; Tahap 4b |
| Cara pembulatan PPh 21 | Belum dicek | — | Menebak | Ditanyakan di Tahap 4b (kontrak data bagian 9 ayat 2) |

Uji otomatis `db/uji/050_aturan_resmi.sql` memeriksa jumlah lapisan, tidak ada celah antar lapisan, batas "sampai dengan", dan kasus jebakan E04 (TK/0, bruto 10.454.000 → 2,5% → Rp261.350).

## 3. BPJS dan upah minimum

| Hal | Di Supabase sekarang | Yang benar | Dasar | Label | Tindakan |
| --- | --- | --- | --- | --- | --- |
| Batas upah JP Jan–Feb 2026 | 10.547.000 (berlaku sejak 1 Jan 2026, tanpa akhir) | **10.547.400** (berlaku Mar 2025–Feb 2026) | Surat BPJS Ketenagakerjaan Feb 2025 (batas mulai Maret 2025) | Pasti | Dibetulkan 16 Nov 2026 (`db/data_awal/aturan_resmi.sql`); 1 Jan 2026 tetap angka lama, lihat bagian 6 |
| Batas upah JP sejak 1 Mar 2026 | (tidak ada) | **11.086.300** | Surat BPJS Ketenagakerjaan No. B/1226/022026 tgl 25 Feb 2026; diumumkan juga oleh akun resmi BPJS dan Antara | Pasti | Ditambahkan 16 Nov 2026 (`db/data_awal/aturan_resmi.sql`) |
| Persen iuran BPJS (Kes 1%/4%, JHT 2%/3,7%, JP 1%/2%, JKK 0,24%, JKM 0,3%) | sesuai | sama | Beberapa sumber 2026: tarif tidak berubah | Kemungkinan Besar | Tidak ada |
| Batas upah BPJS Kesehatan | 12.000.000 | sama | Kasus E05 | Kemungkinan Besar (tidak dicek ulang di paket ini) | Dicek di 4b |
| UMK Kabupaten Langkat 2026 | 3.402.892 | **sama** | SK Gubernur Sumut No. 188.44/908/KPTS/2025, 24 Des 2025 (dikutip detik, goodstats, UMSU) | Pasti | Tidak ada |

## 4. Bentrok dengan kasus jebakan dan pengaturan simulasi

| Kasus/pengaturan | Isi sekarang | Aturan baru | Label | Usulan |
| --- | --- | --- | --- | --- |
| C02 dan pengaturan `cuti_bersama = potong_cuti` (Pabrik B, `docs/data-simulasi.md`) | Cuti bersama boleh memotong saldo cuti | Pasal 118 ayat 6: tidak mengurangi cuti tahunan | Pasti (naskah resmi) | Permintaan perubahan 01 |
| D11 | Dasar lembur = 75% × (pokok + tetap + tidak tetap) bila pokok + tetap di bawah 75% | Pasal 116 ayat 3: upah sejam = (pokok + tetap) ÷ 173, tanpa menyebut 75% | Menebak apakah aturan 75% lama masih berlaku lewat Pasal 310 atau dianggap bertentangan | Pertanyaan terbuka di permintaan perubahan 01; diputuskan sebelum paket 4b |
| Pengaturan `lembur = otomatis` | Lembur dibayar tanpa perintah | Pasal 116 ayat 1: lembur butuh perintah tertulis/digital dan persetujuan pekerja | Menebak dampaknya | Membayar lembur yang terjadi tetap wajib; yang dipertanyakan adalah apakah sistem perlu mencatat perintah/persetujuan. Pertanyaan untuk kuesioner pemasangan |

## 5. Kalender 2027 (SKB 3 Menteri)

SKB Menteri Agama, Menteri Ketenagakerjaan, dan Menteri PANRB No. 1205, 3, dan 2 Tahun 2026, ditandatangani 15 Sep 2026. Daftar dibaca dari halaman berita resmi setneg.go.id dan cocok dengan Kompas, Katadata, Fortune (18 hari libur nasional, 8 cuti bersama) [Pasti untuk tanggal; nama hari dicek dengan kalender].

**Libur nasional (18 hari):** 1 Jan (Tahun Baru), 5 Jan (Isra Mikraj 1448 H), 6 Feb (Imlek), 8 Mar (Nyepi), 10–11 Mar (Idul Fitri), 26 Mar (Wafat Yesus Kristus), 28 Mar (Paskah), 1 Mei (Hari Buruh), 6 Mei (Kenaikan Yesus Kristus), 17 Mei (Idul Adha), 20 Mei (Waisak), 1 Jun (Hari Lahir Pancasila), 6 Jun (1 Muharam), 15 Agu (Maulid Nabi), 17 Agu (Hari Kemerdekaan), 25 Des (Natal), 26 Des (Isra Mikraj 1449 H).

**Cuti bersama (8 hari):** 5 Feb (Imlek), 9 Mar, 12 Mar, 15 Mar (Idul Fitri), 25 Mar (Wafat Yesus Kristus), 18 Mei (Idul Adha), 19 Mei (Waisak), 24 Des (Natal).

Catatan: tanggal Idul Fitri dan Idul Adha bisa digeser Keputusan Menteri Agama (disebut dalam SKB). Isra Mikraj muncul dua kali karena jatuh dua kali dalam tahun Masehi 2027.

Dimasukkan 16 Nov 2026 lewat `db/data_awal/aturan_resmi.sql` (paket data aturan resmi).

## 6. Yang belum dikerjakan dan alasannya

Daftar paket 4a menulis "migrasi 0008 berisi TER, PTKP, kalender 2027, dan perbaikan JP/UMK". Saat dikerjakan ternyata **kalender dan BPJS tidak bisa diisi lewat migrasi**: keduanya dimuat oleh `db/data_awal/pabrik_a_struktur.sql`, dan pemasangan (`db/pasang_supabase.sh`) hanya memuat file itu kalau tabelnya masih kosong. Kalau migrasi mengisi kalender 2027 lebih dulu, pemasangan dari nol (uji otomatis dan Reset) akan berhenti dengan "setengah ada"; perbaikan JP lewat migrasi akan tertimpa angka lama saat Reset. Mengubah alur pemasangan tidak tertulis di daftar paket, jadi tidak dikerjakan (aturan 7 CLAUDE.md). Yang dipasang hanya TER dan PTKP (tabel yang tidak diisi data awal).

**Diselesaikan di paket "data aturan resmi" (16 Nov 2026):** file `db/data_awal/aturan_resmi.sql` yang aman dijalankan berulang, dimuat setiap pemasangan sesudah struktur Pabrik A. `pabrik_a_struktur.sql` tidak diubah.

Keterbatasan [Pasti]: baris bertanggal hanya boleh ditutup, tidak boleh diubah nilainya, dan tanggal tutup harus sesudah tanggal mulai. Baris JP lama (10.547.000 sejak 1 Jan 2026) karena itu ditutup per 2 Jan 2026, sehingga **tanggal 1 Jan 2026 saja masih memakai 10.547.000** (selisih batas Rp400; iuran JP karyawan selisih paling banyak Rp4). Ini juga terjadi di setiap pemasangan dari nol, karena angka lama tetap dimuat dari `pabrik_a_struktur.sql`. Untuk perusahaan sungguhan data awal tidak memakai file ini (lihat serah terima, "Sebelum dipasang untuk perusahaan sungguhan").

## 7. Cek tambahan untuk paket 4b-1 (16 Nov 2026)

| Hal | Isi | Dasar | Label | Dipakai di |
| --- | --- | --- | --- | --- |
| Upah saat tidak bekerja | Upah tidak dibayar bila pekerja tidak bekerja (ayat 1), **kecuali** sakit, haid sakit, menikah/menikahkan/khitan/baptis anak/istri melahirkan/keluarga meninggal, kewajiban negara, ibadah, istirahat (cuti), tugas serikat, tugas pendidikan, mogok sah (ayat 2) | UU 27/2026 Pasal 149 ayat 1–2 | Pasti (naskah resmi) | Alpha tidak dibayar; sakit dan cuti dibayar; **izin tanpa alasan di ayat 2 tidak dibayar** (pengaturan `izin_dibayar`, bawaan `tidak`) |
| Upah sakit berkepanjangan | 4 bulan pertama 100%, 4 bulan kedua 75%, 4 bulan ketiga 50%, selanjutnya 25% | Pasal 149 ayat 3 | Pasti | Data simulasi tidak punya sakit lebih dari 4 bulan; dianggap 100%. Sakit panjang belum dihitung (dicatat sebagai batasan) |
| Cuti dibayar penuh | Pekerja yang memakai istirahat mingguan dan cuti tahunan berhak upah penuh | Pasal 123 ayat 1 | Pasti | Status `cuti` dibayar |
| Hari libur resmi | Pekerja tidak wajib bekerja pada hari libur resmi | Pasal 125 ayat 1 | Pasti | Alpha di hari libur nasional (operasi 7 hari) tidak memotong upah; diberi tanda |
| Lembur menurut Penjelasan | "Waktu kerja lembur" termasuk kerja pada hari istirahat mingguan dan hari libur resmi | Penjelasan Pasal 116 ayat 1 huruf c | Pasti | Peringatan batas 4 jam/hari dan 18 jam/minggu ikut menghitung lembur di hari libur (berbeda dengan PP 35/2021 lama) |
| Istirahat | Paling sedikit ½ jam setelah 4 jam kerja terus-menerus, tidak termasuk jam kerja | Pasal 118 ayat 2a | Pasti | Lembur di hari libur tanpa jadwal: dikurangi 60 menit istirahat bila hadir lebih dari 4 jam (angka tetap, sama dengan istirahat jadwal) |
| Saat PPh 21 terutang | Saat pembayaran atau terutangnya penghasilan, mana yang lebih dulu; dipotong per masa pajak | PMK 168/2023 Pasal 19 ayat 1–2 | Kemungkinan Besar (dari salinan teks pasal.id, belum naskah resmi) | Masa pajak = bulan tanggal bayar gaji |
| Pembulatan PKP | Penghasilan kena pajak dibulatkan ke bawah hingga ribuan rupiah | PMK 168/2023 Pasal 8 ayat 4 | Kemungkinan Besar | Hitung ulang Desember (paket 4b-2) |
| Pembulatan PPh 21 TER | Tidak ditemukan aturan pembulatan nominal PPh | — | Menebak | Pengaturan baru `pembulatan_pph21`, bawaan `bawah` (ke bawah ke rupiah) |
| Contoh resmi TER | Tuan A, K/0: gaji 20 jt + tunjangan 10 jt + JKK 100 rb + JKM 60 rb = bruto 30.160.000 × TER A 13% = **Rp3.920.800** (masa Januari) | Ilustrasi Lampiran PMK 168/2023, dikutip DDTCNews | Kemungkinan Besar (kutipan, bukan naskah lampiran) | Kasus uji K1 di `docs/kunci-gaji.md` |
| Batas bawah iuran BPJS Kesehatan | Batas paling rendah upah dasar iuran = UMK (bila tidak ada, UMP); batas atas Rp12 juta | Perpres 64/2020 Pasal 32 ayat 1–3 | Pasti (kutipan naskah di jdih.kemenkeu dan peraturan.go.id) | Dasar iuran Kesehatan dijepit antara UMK dan 12 juta |

## 8. Cek tambahan untuk paket 4b-2 (17 Nov 2026)

| Hal | Isi | Dasar | Label | Dipakai di |
| --- | --- | --- | --- | --- |
| Aturan THR yang berlaku | Masih Permenaker 6/2016; untuk Idul Fitri 2026 Kemnaker menerbitkan surat edaran yang mengulang aturan itu (dibayar paling lambat 7 hari sebelum hari raya). Belum ditemukan aturan THR baru sesudah UU 27/2026; UU menyerahkan THR ke PP (Pasal 134 ayat 4) | Permenaker 6/2016, SE Menaker 2026, UU 27/2026 Pasal 134 + 310 | Kemungkinan Besar (berita Bisnis.com Mar 2026, Hukumonline; naskah Permenaker belum dibaca) | THR |
| Besar THR | Masa kerja 12 bulan atau lebih: 1 bulan upah. Masa kerja 1 bulan sampai kurang dari 12 bulan: masa kerja ÷ 12 × 1 bulan upah. Kurang dari 1 bulan: tidak berhak | Permenaker 6/2016 Pasal 2–3 | Kemungkinan Besar | THR = bulat(upah × bulan penuh ÷ 12), paling banyak 1 bulan upah |
| Arti "1 bulan upah" THR | Upah tanpa tunjangan, atau upah pokok + tunjangan tetap | Permenaker 6/2016 Pasal 3 ayat 2 (dikutip detik, Bisnis) | Kemungkinan Besar | Upah = gaji pokok + tunjangan tetap pada tanggal bayar THR |
| THR dan pajak | THR pekerja swasta kena PPh 21 di masa pembayarannya | berita Bisnis.com 5 Mar 2026 | Kemungkinan Besar | THR masuk bruto pajak periode yang memuat tanggal bayar THR |
| Potongan upah yang boleh | Denda, ganti rugi, uang muka upah (harus diatur di perjanjian kerja/peraturan perusahaan/PKB); juga sewa, utang/cicilan utang, kelebihan bayar upah | PP 36/2021 Pasal 63 ayat 1–3 | Kemungkinan Besar (Hukumonline, prosiding Unisba; naskah PP belum dibaca) | Kasbon = uang muka upah/utang; denda hanya bila `aturan.tingkat_denda` punya dasar pasal |
| Batas potongan | Jumlah keseluruhan potongan (Pasal 63) paling banyak 50% dari setiap pembayaran upah yang diterima | PP 36/2021 Pasal 65 | Kemungkinan Besar | Batas dihitung dari upah periode itu (tanpa THR, karena THR "pendapatan non upah"); BPJS dan PPh tidak termasuk (kewajiban negara, bukan Pasal 63) [Menebak untuk bagian terakhir] |
| Masih berlaku sesudah UU 27/2026? | UU 27/2026 tidak mengatur ulang angka 50%; PP lama tetap berlaku sepanjang tidak bertentangan | UU 27/2026 Pasal 134 ayat 5, Pasal 310 | Pasti (naskah resmi UU) | — |

## 9. Cek tambahan untuk paket 4b-3 (17 Nov 2026)

| Hal | Isi | Dasar | Label | Dipakai di |
| --- | --- | --- | --- | --- |
| Hitung ulang masa terakhir | Di masa pajak terakhir (Desember, atau bulan pegawai berhenti) PPh setahun dihitung dengan tarif Pasal 17 atas penghasilan kena pajak setahun, dikurangi PPh yang sudah dipotong dengan TER di masa sebelumnya | PMK 168/2023 | Kemungkinan Besar (DDTCNews, kutipan ilustrasi lampiran) | PPh masa terakhir |
| Uji contoh resmi | Ilustrasi Tuan A (K/0, gaji 20 jt + tunjangan 10 jt + JKK 100 rb + JKM 60 rb per bulan, THR 20 jt Maret, bonus 20 jt Desember, iuran pensiun pegawai 100 rb/bulan, zakat lewat pemberi kerja 200 rb/bulan): **PPh Desember Rp4.218.200** | Ilustrasi Lampiran PMK 168/2023, dikutip DDTCNews | Kemungkinan Besar | Hitungan Claude dari unsur di bawah menghasilkan angka **sama persis** (bruto setahun 401.920.000; biaya jabatan 6.000.000; pengurang 3.600.000; PTKP K/0 58.500.000; PKP 333.820.000; PPh setahun 52.455.000; TER Jan–Nov 48.236.800). Ini menguji pemahaman Claude atas semua unsur sekaligus |
| Biaya jabatan | 5% dari penghasilan bruto, paling banyak Rp500.000 sebulan atau Rp6.000.000 setahun | PMK 168/2023 (sama dengan PMK 250/2008 lama) | Kemungkinan Besar | Batas = 500.000 × banyak bulan pegawai menerima gaji di tahun itu |
| Pengurang lain | Iuran pensiun/JHT/JP yang dibayar pegawai; zakat lewat pemberi kerja | UU PPh Pasal 21 ayat 3, PMK 168 | Kemungkinan Besar | Iuran JHT + JP karyawan; zakat belum ada tempat datanya (0) |
| Tarif Pasal 17 | 5% s.d. 60 jt; 15% 60–250 jt; 25% 250–500 jt; 30% 500 jt–5 M; 35% di atas 5 M | UU HPP (UU 7/2021) Pasal 17 ayat 1a | Pasti (diketahui luas; dicocokkan lewat contoh di atas) | Tabel baru `aturan.tarif_pasal17` |
| Pembulatan PKP | Ke bawah hingga ribuan rupiah penuh | PMK 168/2023 Pasal 8 ayat 4 | Kemungkinan Besar | PKP |
| Pegawai masuk atau berhenti di tengah tahun | Penghasilan tidak disetahunkan; PTKP penuh setahun; masa terakhir = bulan berhenti | PMK 168/2023 (praktik umum; naskah belum dibaca) | Menebak | PPh masa terakhir pegawai berhenti |
| Kelebihan potong | Bila PPh setahun lebih kecil dari yang sudah dipotong, kelebihannya dikembalikan ke pegawai di masa terakhir | PMK 168/2023 | Kemungkinan Besar | Komponen `pengembalian_pph21` (pendapatan, tidak ikut bruto pajak) |
| Cuti tahunan dan cuti bersama | 12 hari kerja setelah 12 bulan terus-menerus (Pasal 118 ayat 5); cuti bersama dari pemerintah tidak mengurangi cuti tahunan (ayat 6), berlaku sejak 28 Okt 2026 | UU 27/2026 | Pasti (naskah resmi) | Saldo cuti |

