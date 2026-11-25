# Daftar pertanyaan untuk HRD PT baru

Dipakai di langkah 1 panduan pasang (`docs/pasang/README.md`). Pertanyaan boleh dicetak, dibacakan, atau dikirim lewat
WhatsApp. HRD cukup menjawab dengan kalimat biasa; yang mengubah jawaban menjadi isian sistem adalah pembangun bersama Claude
(langkah 4).

Setiap pertanyaan punya:
- **Contoh** jawaban dari Pabrik A (perusahaan karangan di demo), supaya HRD paham maksud pertanyaannya;
- **Isian** (untuk pembangun/Claude): tabel atau pengaturan sistem yang diisi jawaban itu. HRD boleh mengabaikan baris ini.

Bila jawaban HRD tidak cocok dengan pilihan sistem, **jangan dipaksakan**: catat sebagai temuan dan tanyakan ke pemilik proyek
(lihat README bagian "Bila aturan PT tidak cocok").

Data karyawan per orang (nama, gaji, PTKP, dan seterusnya) **tidak** ditanyakan di sini; itu diisi lewat templat
(`docs/pasang/4-isi-templat.md`).

---

## A. Perusahaan dan mesin absen

**A1. Nama perusahaan dan kabupaten/kota tempat bekerja?**
Contoh: Pabrik A, Kabupaten Langkat.
Isian: `aturan.upah_minimum` (wilayah); nama PT untuk Sheets dan pesan bot.

**A2. Berapa upah minimum (UMK) yang berlaku untuk kabupaten/kota itu tahun ini, dan mulai tanggal berapa?**
Contoh: Rp3.402.892 sejak 1 Januari 2026.
Isian: `aturan.upah_minimum` (nilai, berlaku_dari). Angkanya dicek ulang ke keputusan gubernur, jangan hanya dari ingatan.

**A3. Ada berapa mesin absen (fingerprint)? Di mana letaknya, dan merek/tipenya apa?**
Contoh: 2 mesin, "Gerbang pabrik" dan "Kantor".
Isian: `induk.mesin` (kode, nama, zona waktu). Merek/tipe dipakai untuk memastikan file mesin bisa dibaca (contoh file diminta
di langkah 1 README).

**A4. Apakah semua mesin di zona waktu yang sama (WIB/WITA/WIT)?**
Contoh: semua WIB.
Isian: `induk.mesin` (zona).

**A5. Bisakah HRD mengirimkan satu contoh file hasil tarikan mesin (satu minggu cukup), persis seperti keluar dari aplikasi
mesin (jangan dibuka lalu disimpan ulang di Excel)? Yang dibutuhkan "log/data absensi" (satu baris setiap tap), bukan rekap
jam masuk-pulang per hari.**
Contoh: file `.xls` dengan kolom Nama, No.ID, Tgl/Waktu, Status (bentuk file mesin asli pemilik); `.xlsx`, `.csv`, `.txt`, dan
`attlog.dat` juga bisa dibaca.
Isian: tidak ada; contoh file diperiksa dengan `node sistem/urai/cek_file.ts FILE` (paket F1) sebelum pemasangan. Hasilnya harus
DITERIMA dengan jumlah ID dan rentang tanggal yang masuk akal. Bila DITOLAK karena judul kolomnya belum dikenal (paket F2),
HRD cukup mengirim file itu sekali lewat bot: bot menanyakan kolom ID dan tanggal-jam dengan contoh hasil bacaan, lalu menyimpan
profil format untuk mesin itu (pembangun diberi tahu dan bisa menghapusnya dengan `/profilmesin`). Bentuk rekap dan file rusak
tetap ditolak; catat sebagai temuan.

## B. Divisi dan shift

**B1. Sebutkan semua divisi/bagian, jumlah karyawan kira-kira, dan mesin absen yang dipakai setiap divisi.**
Contoh: Produksi (600 orang, mesin gerbang), Quality Control, Keamanan, Gudang dan Logistik (mesin gerbang), Kantor (mesin kantor).
Isian: `induk.divisi` (kode, nama, mesin_utama).

**B2. Untuk setiap divisi: kerjanya bergilir (shift/regu) atau jam tetap Senin–Sabtu?**
Contoh: Produksi, QC, Keamanan bergilir 4 regu; Gudang bergilir 2 regu; Kantor jam tetap.
Isian: `induk.divisi` (pola: rotasi atau mingguan; jumlah_regu).

**B3. Sebutkan setiap jenis jam kerja: jam masuk, jam pulang, lama istirahat, dan apakah istirahat dibayar.**
Contoh: Pagi 07.00–15.00, Siang 15.00–23.00, Malam 23.00–07.00, Kantor 08.00–16.00, Kantor Sabtu 08.00–13.00; istirahat 60 menit
tidak dibayar (Sabtu tanpa istirahat).
Isian: `induk.kode_jadwal` (kode, jam_masuk, jam_pulang, istirahat_menit, istirahat_dibayar).

**B4. Untuk divisi bergilir: bagaimana urutan gilirannya? Berapa hari satu putaran, dan regu mana masuk shift apa pada satu
tanggal tertentu?**
Contoh: Produksi 8 hari: Pagi, Pagi, Siang, Siang, Malam, Malam, Libur, Libur; tiap regu bergeser 2 hari; pada 1 Januari 2026
regu 0 masuk Pagi hari pertama. Gudang: seminggu pagi, seminggu siang, Minggu libur.
Isian: `induk.pola_rotasi` (siklus, jangkar, geser_per_regu, berlaku_dari). Bila HRD punya tabel jadwal bulan lalu, minta
salinannya; urutan dicocokkan dari tabel itu.

**B5. Untuk divisi jam tetap: hari apa saja masuk, dan memakai jam kerja yang mana? Apakah ada jadwal khusus Ramadan?**
Contoh: Kantor Senin–Jumat 08.00–16.00, Sabtu 08.00–13.00, Minggu libur; Ramadan 19 Feb–20 Mar 2026 pulang lebih awal.
Isian: `induk.jadwal_hari` (hari_ke, kode, berlaku_dari, berlaku_sampai).

**B6. Divisi mana yang jalan 7 hari seminggu dengan libur bergilir?**
Contoh: Produksi, QC, Keamanan.
Isian: tabel `aturan.pengaturan`, kunci `operasi_7_hari` per divisi. Semua "pengaturan `...`" di dokumen ini masuk tabel yang sama.

**B7. Pola hari kerja untuk batas 40 jam seminggu: 5 hari kerja, 6 hari dengan satu hari pendek, atau 6 hari dengan kelebihan jam
dibayar lembur? Adakah divisi yang polanya berbeda dari perusahaan?**
Contoh: 6 hari dengan hari pendek. (Pabrik B: perusahaan 5 hari, Gudang 6 hari dengan hari pendek.)
Isian: pengaturan `pola_hari_kerja` (5_hari, 6_hari_hari_pendek, 6_hari_lebih_dibayar), cakupan perusahaan atau per kode divisi.

## C. Libur dan kalender

**C1. Selain libur nasional dan cuti bersama pemerintah, adakah hari libur khusus perusahaan (ulang tahun PT, libur pabrik)?**
Contoh: tidak ada.
Isian: `induk.kalender` (tanggal, jenis, keterangan). Libur nasional dan cuti bersama pemerintah diisi dari SKB 3 Menteri, bukan
dari jawaban HRD.

**C2. Cuti bersama dibayar seperti biasa, atau memotong jatah cuti tahunan?**
Contoh: dibayar. (Sejak 28 Okt 2026 cuti bersama tidak boleh memotong cuti; sistem memberi tanda bila dipilih "potong cuti".)
Isian: pengaturan `cuti_bersama` (dibayar, potong_cuti). Pengaturan bertanggal: bila aturan PT berubah di tengah tahun, tulis dua
baris dengan `berlaku_sampai` (contoh Pabrik B: potong cuti sampai 28 Okt 2026, sesudahnya dibayar).

**C3. Jatah cuti tahunan berapa hari, dan mulai berlaku sesudah berapa bulan bekerja?**
Contoh: 12 hari sesudah 12 bulan.
Isian: `aturan.cuti` (jatah_hari, berlaku_setelah_bulan).

**C4. Izin di luar alasan yang dibayar menurut undang-undang (misalnya izin urusan pribadi): dibayar atau dipotong?**
Contoh: dipotong (tidak dibayar).
Isian: pengaturan `izin_dibayar` (ya, tidak).

## D. Periode gaji dan gajian

**D1. Periode absen ditutup tanggal berapa setiap bulan (tutup buku)?**
Contoh: tanggal 20 (periode 21 bulan lalu sampai 20 bulan ini). Jawaban "akhir bulan" juga bisa.
Isian: pengaturan `tanggal_tutup_buku` (angka; 0 = akhir bulan).

**D2. Gaji dibayar tanggal berapa?**
Contoh: tanggal 25.
Isian: pengaturan `tanggal_gajian`.

**D3. Sistem mulai dipakai untuk periode yang mana? (Untuk uji banding, sebaiknya satu periode yang sudah dihitung manual oleh HRD.)**
Contoh: periode 21 Januari – 20 Februari 2026, dibayar 25 Februari.
Isian: `fakta.periode` (tanggal_awal, tanggal_akhir, tanggal_bayar) untuk periode pertama.

**D4. Siapa yang menyetujui gaji sebelum dibayar: cukup HRD, atau HRD mengajukan lalu bos menyetujui?**
Contoh: HRD mengajukan, bos menyetujui.
Isian: pengaturan `persetujuan_rilis` (hrd, hrd_lalu_bos).

**D5. Setelah gaji disetujui, apakah rincian gaji langsung dikirim ke setiap karyawan lewat Telegram, atau hanya bila karyawan
memintanya?**
Contoh: langsung dikirim.
Isian: pengaturan `kirim_rincian` (otomatis, diminta).

## E. Absen, telat, dan lembur

**E1. Berapa menit paling awal karyawan boleh tap sebelum jam masuk, dan paling lambat sesudah jam pulang, agar tap itu dihitung
untuk shift tersebut? Berapa jarak minimal dua tap supaya tidak dianggap tap ganda?**
Contoh: 120 menit sebelum masuk, 360 menit sesudah pulang, jarak minimal 60 menit.
Isian: `aturan.jendela_tap` (menit_sebelum_masuk, menit_sesudah_pulang, jarak_minimal_menit).

**E2. Telat berapa menit masih ditoleransi? Pulang cepat berapa menit masih ditoleransi?**
Contoh: telat 5 menit, pulang cepat 0 menit.
Isian: `aturan.toleransi` (telat_menit, pulang_cepat_menit).

**E3. Lembur dihitung otomatis dari jam tap, atau hanya bila ada perintah/persetujuan atasan?**
Contoh: otomatis.
Isian: pengaturan `lembur` (otomatis, wajib_perintah).

**E4. Lembur minimal berapa menit baru dihitung? Dihitung per kelipatan berapa menit, dan dibulatkan ke bawah atau ke terdekat?**
Contoh: minimal 60 menit, kelipatan 30 menit, dibulatkan ke bawah.
Isian: `aturan.lembur` (menit_minimal, kelipatan_menit, cara_bulat).

**E5. Upah dasar lembur memakai gaji pokok + tunjangan tetap penuh, atau 75% (bila ada tunjangan tidak tetap besar)?**
Contoh: penuh.
Isian: `aturan.lembur` (dasar_upah: penuh, tujuh_puluh_lima). Pengali lembur (1,5x, 2x, dan seterusnya) mengikuti PP 35/2021 dan
**tidak** ditanyakan: tabel `aturan.pengali_lembur` disalin dari susunan Pabrik A.

## F. Tunjangan, potongan, THR

**F1. Apakah ada uang makan? Berapa per hari, dan apa syaratnya? Atau uang makan dibayar di luar sistem?**
Contoh: Rp15.000 per hari hadir, tidak telat lebih dari 60 menit.
Isian: pengaturan `uang_makan` (dihitung, di_luar_sistem) dan `aturan.komponen_lain` kode `uang_makan`.

**F2. Apakah ada premi hadir (bonus tidak pernah alpha/telat)? Berapa per periode?**
Contoh: Rp100.000 per periode, tanpa alpha dan tanpa telat.
Isian: pengaturan `premi_hadir` (hidup, mati) dan `aturan.komponen_lain` kode `premi_hadir`.

**F3. Apakah ada tunjangan shift malam? Berapa per hari?**
Contoh: Rp10.000 per hari masuk shift malam.
Isian: pengaturan `tunjangan_shift_malam` (hidup, mati) dan `aturan.komponen_lain` kode `tunjangan_shift_malam`.

**F4. Adakah tunjangan atau potongan lain yang rutin (tunjangan jabatan, transport, potongan koperasi)? Sebutkan nama, nominal,
dan syaratnya.**
Contoh: tidak ada (tunjangan tetap per orang diisi di templat karyawan).
Isian: bila jawabannya bukan uang makan/premi/shift malam, **temuan**: belum ada komponen umum di mesin hitung; tanyakan ke
pemilik proyek sebelum dipasang.

**F5. Potongan denda dan cicilan kasbon dalam satu periode paling banyak berapa persen dari gaji?**
Contoh: 50%.
Isian: `aturan.batas_potongan` (persen per-sepuluh-ribu; komponen denda, kasbon, ganti rugi).

**F6. THR dibayar tanggal berapa, untuk hari raya apa, dan bagaimana menghitung THR karyawan yang belum setahun (per bulan penuh
atau per hari)?**
Contoh: dibayar 14 Maret 2026 untuk Idul Fitri 21 Maret 2026, prorata per bulan penuh.
Isian: `aturan.thr` (tanggal_bayar, hari_raya, cara_prorata: bulan_penuh, hari).

**F7. Apakah perusahaan ikut BPJS Kesehatan dan BPJS Ketenagakerjaan? Adakah karyawan yang tidak ikut?**
Contoh: semua ikut.
Isian: tarif `aturan.bpjs` mengikuti peraturan dan **tidak** ditanyakan (disalin dari susunan Pabrik A, lalu `aturan_resmi.sql`).
Karyawan yang tidak ikut BPJS belum bisa ditandai lewat templat (temuan 9d); sesudah pasang diubah per orang lewat web HRD "Ubah gaji" (isian BPJS, perlu persetujuan).

## G. Cara bayar dan pembulatan

**G1. Gaji dibayar transfer, tunai, atau campuran? Bila tunai, dibulatkan ke kelipatan berapa (Rp100, Rp500, Rp1.000)?**
Contoh: kebanyakan transfer, Gudang tunai, pembulatan ke Rp1.000 (sisa dibawa ke periode berikut).
Isian: pengaturan `pembulatan_tunai` (100, 500, 1000); cara bayar per orang di templat karyawan.

**G2. PPh 21 per bulan dibulatkan ke bawah atau ke rupiah terdekat?**
Contoh: ke bawah. (Bila HRD tidak tahu, pakai "ke bawah" dan cocokkan saat uji banding.)
Isian: pengaturan `pembulatan_pph21` (bawah, terdekat).

**G3. Berapa gaji tiap karyawan yang sudah dipotong PPh dan BPJS dari Januari tahun ini sampai sebelum sistem dipakai?**
Contoh: diisi untuk Januari 2026 di Pabrik A.
Isian: `induk.pajak_awal_tahun`; dibutuhkan agar PPh akhir tahun benar. Untuk PT, cara mengisinya belum dibuat (lihat temuan
di README); sementara catat jawabannya.

## H. Gaji rahasia dan peringatan

**H1. Adakah karyawan yang gajinya tidak boleh dilihat HRD (misalnya manajer)? Siapa saja yang boleh melihatnya?**
Contoh: 3 orang; hanya bos yang boleh melihat angkanya.
Isian: kolom `gaji_rahasia` di templat karyawan. Orang bergaji rahasia wajib dibayar transfer (aturan 8d).

**H2. Bila satu divisi hampir tidak ada yang tap pada satu hari (mesin mati?), mulai berapa persen sistem perlu menganggapnya
"mesin tidak mengirim" dan bukan alpha massal? Berlaku untuk divisi dengan minimal berapa orang?**
Contoh: 50% karyawan aktif divisi itu, untuk divisi minimal 3 orang.
Isian: pengaturan `ambang_tanpa_tap_massal` (per-sepuluh-ribu: 5000 = 50%) dan `minimal_orang_tanpa_tap_massal`.

---

## Pemeriksa otomatis

Pemeriksa di `sistem/uji/jalankan_simulasi.sh` gagal bila ada tabel yang diisi susunan Pabrik A atau Pabrik B, atau pengaturan
di `aturan.daftar_pengaturan`, yang tidak disebut di salah satu baris "Isian" di atas. Pertanyaan baru wajib ditambahkan bila
sistem mendapat isian baru.
