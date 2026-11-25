# Kasus Jebakan — Tahap 0

Versi 1.4 · dikunci 12 November 2026, ditambah 16 November 2026 lewat permintaan perubahan 01 (C02b, D11b), 17 November 2026 lewat permintaan perubahan 02 (F13b), dan 22 November 2026 lewat permintaan perubahan 06 (B05b); kasus lain tidak berubah · acuan: PRD v3.1, UU 27/2026

Daftar ini ditulis **sebelum** pembaca tap dan mesin hitung dibuat. Setiap kasus menyebut kejadian dan hasil yang diharapkan. Kode dinyatakan benar hanya kalau semua kasus di sini lulus (uji U1, U2, U4, U6, U10, U12, U14). Kasus tidak boleh diubah agar kode lulus; perubahan hanya lewat permintaan perubahan (PRD v3 bagian 3).

Sumber kasus: **Asli** = pola dari file mesin asli Februari 2026 (identitas disamarkan P1–P8), **PRD** = rancangan, **Aturan** = aturan pemerintah di PRD v3 bagian 8.

## Aturan uji v0

Angka di bawah hanya untuk menguji; di sistem semuanya isian tabel aturan.

| Aturan | Nilai uji |
| --- | --- |
| Shift Pagi / Siang / Malam | 07:00–15:00 / 15:00–23:00 / 23:00–07:00 |
| Jadwal kantor pola file asli | Senin–Kamis 07:30–16:00, Jumat 07:30–16:30; mulai 19 Feb (Ramadan) 08:00–15:00, Jumat 08:00–15:30 |
| Jendela tap | 2 jam sebelum masuk sampai 6 jam sesudah pulang |
| Dua tap dianggap satu | Berjarak kurang dari 60 menit |
| Toleransi telat | 5 menit |
| Lembur | Dihitung bila lebih dari 60 menit, dibulatkan ke bawah per 30 menit; pengaturan "otomatis" kecuali disebut lain |
| Upah contoh | Upah pokok Rp3.500.000 + tunjangan tetap Rp500.000 = Rp4.000.000; upah sejam = 4.000.000 / 173 = Rp23.121,39 |
| Pembulatan | Ke rupiah terdekat, sekali per komponen |
| Waktu | WIB; hari kerja shift malam = tanggal jam masuk |

## A. Membaca file

| ID | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| A01 | Tap 07:05 berstatus "C/Keluar" pada shift kantor | Dibaca sebagai masuk; status kolom diabaikan; tercatat sebagai salah tekan | Asli (15 dari 275 tap) |
| A02 | Tap pulang 15:01:34 lalu 15:04:42 | Satu pulang = 15:04:42; tap 15:01:34 tercatat, diabaikan | Asli (P2, P3 26 Feb) |
| A03 | Pagi 07:26:46 "Keluar" lalu 07:31:30 "Masuk", sore 15:05:11 | Masuk 07:26:46, pulang 15:05:11 | Asli (P1 26 Feb) |
| A04 | File punya kolom tanpa judul berisi waktu tanpa detik | Kolom diabaikan; tidak ada tap ganda karenanya | Asli |
| A05 | ID 18 digit berawalan 19 (contoh karangan: 198001012010011001) | Disimpan sebagai teks, digit utuh | Asli |
| A06 | Dua baris identik persis | Dihitung satu tap | PRD A1 |
| A07 | File yang sama dikirim dua kali | Jumlah tap di gudang tidak bertambah; gaji tidak berubah | PRD A1, U4 |
| A08 | Tap "07.26" dan "07.26.44" pada orang dan hari yang sama | Satu tap (jarak kurang dari 60 menit) | Asli (file rekap manual 28/11) |
| A09 | Tap yang sama dikirim sebagai ekspor aplikasi dan sebagai attlog.dat | Hasil per orang per hari sama persis | PRD U6 |
| A10 | File berisi tanggal 02/03 dan 13/03 dalam format hari/bulan | Semua dibaca hari/bulan; file dengan pola campur ditolak dengan alasan | PRD A3 |
| A11 | ID 99999 tidak ada di data karyawan | Masuk daftar "ID tidak dikenal" untuk HRD; tidak dihitung | PRD A6 |
| A12 | Tap bertanggal 01/01/2000 (jam mesin tereset) | Ditolak sebagai tanggal mustahil dan dilaporkan | PRD A7 |

## B. Shift dan jendela tap

| ID | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| B01 | Shift Malam 10 Mar: tap 22:58 dan 11 Mar 07:04 | Hadir, hari kerja 10 Mar | PRD |
| B02 | Shift Siang: tap 14:55 dan 23:10 | Hadir; lembur tidak dibayar (10 menit) | PRD |
| B03 | Shift Pagi: tap 09:40 dan 15:02 | Telat 160 menit; tidak berubah menjadi shift lain | PRD B2 |
| B04 | Jadwal Pagi, ada tukar shift ke Siang di tanggal itu; tap 14:57 dan 23:01 | Dibaca shift Siang, hadir | PRD B3 |
| B05 | Shift Pagi: tap 05:30 dan 15:01 | Hadir; jam sebelum 07:00 tidak menjadi lembur | PRD B5 |
| B05b | Shift Pagi 07:00–15:00, hari kerja, tap 05:30 dan 15:45; HRD menyetujui datang awal orang itu di tanggal itu | 90 + 45 = 135 menit → dibayar 120 menit; tanda `lembur_datang_awal_disetujui` | Permintaan perubahan 06 |
| B06 | Shift Pagi: satu tap 06:58 saja | Hadir + lupa tap pulang | PRD |
| B07 | Shift Pagi: satu tap 15:03 saja | Hadir + lupa tap masuk | PRD |
| B08 | Shift Pagi: satu tap 11:00 saja | Hadir + lupa tap pulang, ditandai ambigu, masuk rekap harian HRD | PRD v3.1 |
| B09 | Shift Pagi: satu tap 02:00 (di luar jendela) | Tidak dipakai; ditandai ambigu; hari itu alpha sampai dikoreksi | PRD |
| B10 | Shift Malam Senin lalu Shift Pagi Selasa (jendela bertumpuk) | Ditandai jendela bertumpuk; kedua hari tetap terbaca | PRD |
| B11 | Shift Malam 20 Mar 23:00, pulang 21 Mar 07:02; tutup buku tanggal 20 | Hari 20 Mar "menunggu" sampai tap 21 Mar hingga 13:00 masuk; lalu hadir di periode 21 Feb–20 Mar | PRD A11 |
| B12 | Tap 07:02 tanggal 21 milik shift malam tanggal 20 | Tidak dihitung sebagai tap tunggal di periode baru | PRD A11 |
| B13 | Shift Pagi: tap 06:55 dan 13:30 | Pulang cepat 90 menit | PRD B7 |
| B14 | Kantor: tap 07:27 "Masuk", 14:32 "Masuk", 16:04 "Keluar" | Masuk 07:27, pulang 16:04; tap 14:32 tercatat, bukan pulang cepat | Asli (P6 18 Feb) |
| B15 | Shift Pagi: tap 07:00 dan 07:40 saja | Satu tap (jarak kurang dari 60 menit): hadir + lupa tap pulang | PRD |

## C. Kalender dan hari khusus

| ID | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| C01 | Tidak ada tap 17 Feb 2026 (Imlek) | Libur, bukan alpha | Asli |
| C02 | Tidak ada tap 16 Feb 2026 (cuti bersama), pengaturan "dibayar" / "potong cuti" | Libur dibayar / cuti dengan saldo berkurang 1 | Asli, PRD |
| C02b | Tidak ada tap 24 Des 2026 (cuti bersama Natal), pengaturan "potong cuti" berlaku sejak sebelum 28 Okt 2026 | Libur dibayar; saldo cuti **tidak** berkurang; peringatan "pengaturan potong cuti tidak berlaku sejak 28 Okt 2026 (UU 27/2026 Pasal 118 ayat 6)" | Permintaan perubahan 01 |
| C03 | Tidak ada tap di hari libur bergilir orang itu | Libur, bukan alpha | PRD B11 |
| C04 | Masuk 8 jam di hari libur bergilir (pola 6 hari) | Seluruh 8 jam lembur hari libur (lihat E06) | PRD |
| C05 | Operasi 7 hari: dijadwalkan dan masuk shift Pagi 21 Mar 2026 (Idul Fitri) | Seluruh jam kerja dibayar tarif lembur hari libur | PRD, Aturan |
| C06 | 20 Feb 2026: tidak ada tap dari 8 dari 8 karyawan (di atas ambang 50%) | Tidak menjadi alpha; pemberitahuan segera ke HRD; periode tidak bisa diajukan sampai HRD menetapkan (libur, absen manual, atau alpha) | Asli, PRD v3.1 |
| C07 | Jadwal Ramadan berlaku mulai 19 Feb; pulang 15:02 tanggal 23 Feb | Hadir, bukan pulang cepat | Asli |
| C08 | Pulang 15:02 tanggal 12 Feb (jadwal normal 16:00) | Pulang cepat 58 menit | Asli |
| C09 | Jumat 13 Feb pulang 16:21 (jadwal Jumat 16:30) | Pulang cepat 9 menit; hari Senin pulang 16:21 normal | Asli |
| C10 | Karyawan mulai 10 Feb | Hari sebelum 10 Feb tidak dihitung alpha; gaji prorata | PRD B8 |
| C11 | Karyawan berhenti 18 Feb, ada tap 19 Feb | Tap 19 Feb tidak dihitung; peringatan ke HRD | PRD |
| C12 | P3 tanpa tap 19 Feb (hari kerja biasa) | Alpha; setelah perintah "sakit tgl 19" menjadi sakit dan gaji dihitung ulang | Asli, PRD |
| C13 | Alpha 3 hari kerja berturut-turut | Peringatan alpha beruntun ke HRD | PRD |
| C14 | Divisi berisi 2 karyawan aktif; keduanya tanpa tap di hari kerja | Bukan anomali massal (di bawah minimal 3 karyawan aktif): keduanya alpha seperti biasa dan masuk rekap harian | PRD v3.1 |

## D. Lembur

| ID | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| D01 | Shift Pagi pulang 17:00 (hari kerja) | Lembur 120 menit = 1,5 + 2 = 3,5 × upah sejam = Rp80.925 | Aturan |
| D02 | Pulang 15:59 (lebih 59 menit) | Lembur Rp0; tercatat kelebihan jam | Aturan uji |
| D03 | Pulang 16:35 (lebih 95 menit) | Dibulatkan 90 menit = 1,5 + 2 × 0,5 = 2,5 × upah sejam = Rp57.803; tanda peringatan pembulatan ke bawah | Aturan uji |
| D04 | Pengaturan "wajib ada perintah", pulang 17:00 tanpa perintah | Tidak dibayar; tercatat kelebihan jam | PRD B4 |
| D05 | Lembur otomatis lalu dibatalkan lewat chat | Lembur Rp0 setelah hitung ulang | PRD |
| D06 | Hari libur, pola 6 hari, 8 jam | 7 × 2 + 1 × 3 = 17 × upah sejam = Rp393.064 | Aturan |
| D07 | Hari libur jatuh di hari kerja terpendek, pola 6 hari, 7 jam | 5 × 2 + 1 × 3 + 1 × 4 = 17 × upah sejam = Rp393.064 | Aturan |
| D08 | Hari libur, pola 5 hari, 10 jam | 8 × 2 + 1 × 3 + 1 × 4 = 23 × upah sejam = Rp531.792 | Aturan |
| D09 | Lembur 4,5 jam di hari kerja | Dibayar penuh; peringatan batas 4 jam dan wajib makan | Aturan |
| D10 | Total lembur 19 jam dalam satu minggu | Dibayar penuh; peringatan batas 18 jam | Aturan |
| D11 | Upah pokok 2.000.000 + tetap 500.000 + tidak tetap 1.500.000; lembur 2 jam | Dasar lembur 75% × 4.000.000 = 3.000.000; 3,5 × 3.000.000/173 = Rp60.694 | Aturan |
| D11b | Sama dengan D11, lembur tanggal 2 Nov 2026 | Rp60.694 (dasar terbesar) + tanda "dasar lembur 75% perlu dikonfirmasi HRD" | Permintaan perubahan 01 |
| D12 | Kantor Jumat pulang 18:26 (jadwal 16:30) | Lebih 116 menit, dibayar 90 menit = Rp57.803 | Asli (P4 6 Feb) |

## E. Gaji, pajak, dan pembayaran

| ID | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| E01 | Masuk tengah periode, 13 dari 26 hari kerja terjadwal | Gaji pokok + tetap prorata = Rp2.000.000 | PRD |
| E02 | Gaji naik dari 4.000.000 ke 5.000.000 berlaku hari ke-14 dari 26 | Prorata dua tarif sesuai tanggal berlaku | PRD |
| E03 | THR: masa kerja 24 bulan / 6 bulan | 1 × upah sebulan / 6/12 × upah sebulan | Aturan (perlu dicek teks) |
| E04 | Gaji Rp10.000.000, PTKP TK/0, JKK 0,24% | Bruto pajak = 10.000.000 + 24.000 + 30.000 + 400.000 = 10.454.000; PPh 21 = 2,5% × bruto = Rp261.350 | Aturan |
| E05 | Gaji Rp15.000.000 | BPJS Kesehatan karyawan = 1% × 12.000.000 = Rp120.000 | Aturan |
| E06 | Gaji di atas batas upah JP | JP karyawan = 1% × batas upah yang berlaku di tanggal itu (angka 2026 menunggu dicek) | Aturan |
| E07 | Denda + kasbon melebihi 50% upah | Potongan dibatasi 50%; hanya sisa kasbon yang dibawa ke periode berikut | PRD C1 |
| E08 | Pokok + tetap Rp3.300.000, masa kerja 8 bulan, Langkat 2026 | Peringatan di bawah UMK Rp3.402.892 | Aturan |
| E09 | Gaji bersih Rp3.847.263 dibayar tunai, pembulatan Rp1.000 | Dibayar Rp3.847.000; sisa Rp263 dibawa ke periode berikut dan tertulis di pesan gaji | PRD |
| E10 | Seluruh karyawan satu periode | Total gaji bersih = jumlah semua rincian; Sheets = gudang; selisih 0 | PRD U3 |
| E11 | Periode 21 Nov–20 Des dibayar 25 Des | PPh 21 dihitung ulang setahun (Pasal 17) | Aturan |
| E12 | Karyawan berhenti 10 Des dengan sisa kasbon Rp300.000 | Gaji terakhir prorata; PPh dihitung ulang; kasbon dipotong dalam batas 50% | PRD |
| E13 | Satu alpha dalam periode, premi kehadiran hidup | Premi kehadiran hangus | PRD |
| E14 | Koreksi sakit masuk setelah gaji dirilis | Slip lama tetap; selisih menjadi penyesuaian di periode berikut | PRD C8 |

## F. Temuan lapangan (v1.1)

| ID | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| F01 | File berisi ID "1,98E+17" (dibuka lalu disimpan di Excel) | File ditolak dengan pesan "kirim langsung dari mesin"; pemberitahuan segera | PRD M1 |
| F02 | File dari satu mesin hanya memuat 3 dari 8 karyawan aktif yang terdaftar di mesin itu | Tanda "file mungkin terpotong"; 5 orang yang hilang tidak dijadikan alpha; pemberitahuan segera | PRD M2 |
| F03 | Tap terakhir di file bertanggal 10 hari kerja sebelum tanggal kirim | Peringatan kemungkinan memori mesin penuh atau mesin mati; pemberitahuan segera | PRD M3 |
| F04 | Mesin lebih cepat 4 menit, koreksi berlaku sejak 1 Mar; tap mesin 07:08 tanggal 5 Mar, shift Pagi | Waktu baku 07:04; tidak telat (tanpa koreksi akan terbaca telat 8 menit) | PRD M4 |
| F05 | 6 dari 8 orang telat 6–8 menit di hari yang sama pada mesin yang sama, padahal biasanya tepat waktu | Pemberitahuan segera "kemungkinan jam mesin melenceng" | PRD M4 |
| F06 | ID mesin 0012 dipetakan ke karyawan X mulai 1 Mar; ada tap ID 0012 tanggal 27 Feb | Tap 27 Feb masuk daftar ID tidak dikenal untuk tanggal itu | PRD M5 |
| F07 | Karyawan X punya dua ID mesin; pagi tap dengan ID pertama, sore dengan ID kedua | Tap digabung: hadir dengan masuk dan pulang lengkap | PRD M6 |
| F08 | HRD mengirim "absen manual 20 Feb, divisi Kantor hadir semua" | Semua hadir, asal data "manual"; anomali C06 tertutup | PRD M7 |
| F09 | File dengan kolom waktu bernama "Waktu" (format baru yang belum dikenal) | Tidak dihitung otomatis: file ditahan, pembangun diberi tahu, HRD yang mengirim memilih kolom sekali dengan contoh hasil bacaan; dihitung hanya sesudah "Ya, simpan"; file berikutnya dari mesin dan judul kolom yang sama memakai profil itu, judul berbeda ditanyakan lagi; "Tidak" → ditolak dengan pesan format tidak dikenal dan pemberitahuan segera | PRD M8; permintaan perubahan 07 |
| F10 | Kiriman mingguan untuk minggu kedua tidak pernah masuk | Kalender cakupan menandai lubang; periode tidak bisa diajukan; muncul di ringkasan sebelum rilis | PRD M9 |
| F11 | Jadwal Pagi, tetapi tap 5 hari berturut-turut cocok shift Siang | Usulan tukar shift di rekap harian; sebelum disetujui hasil tetap mengikuti jadwal; setelah disetujui dihitung ulang sebagai Siang | PRD P1 |
| F12 | Pengaturan "wajib perintah"; 3 orang Produksi lembur tanggal 5; HRD mengirim "setujui lembur Produksi tgl 5" | Ketiganya dibayar setelah hitung ulang | PRD P2 |
| F13 | Karyawan baru mulai 1 Mar, tanpa tap 3 hari kerja pertama | Pemberitahuan segera "belum didaftar di mesin?"; tetap alpha sampai dikoreksi | PRD P3 |
| F13b | Karyawan baru, hari kerja pertamanya sakit (perintah HRD), lalu 2 hari masuk tetapi belum didaftar di mesin | 2 hari itu alpha, dan ada pemberitahuan "belum didaftar di mesin?" | Permintaan perubahan 02 (temuan U5 Pabrik B) |
| F14 | Sopir dengan pengaturan "tidak wajib tap", tanpa tap sebulan | Tidak alpha | PRD P4 |
| F15 | Karyawan di kelompok gaji rahasia; akun HRD meminta rinciannya | Ditolak di gudang data; akun bos bisa melihat | PRD O4, K17 |
| F15b | Akun HRD (atau Sheets/halaman demo untuk HRD) menjumlah semua gaji yang terlihat lalu membandingkannya dengan total | Total yang terlihat HRD tidak memasukkan orang rahasia, dengan keterangan "tidak termasuk N orang rahasia"; total dikurangi jumlah yang terlihat = 0. Total lengkap hanya untuk bos | Permintaan perubahan 04 |
| F15c | Status rahasia seseorang berubah di tengah riwayat (dicabut atau dipasang) | Gaji satu periode disembunyikan bila orang itu rahasia pada hari mana pun di periode itu, atau rahasia sekarang. Tanda anomali yang membandingkan dengan periode lalu tidak berangka bila orang itu, atau divisi itu, memuat orang rahasia di periode ini atau periode lalu | Permintaan perubahan 05 |
| F16 | HRD mengirim "tambah libur tgl 27 Nov" setelah semua orang terbaca alpha | Hari itu menjadi libur; alpha batal setelah hitung ulang | PRD O5 |
| F17 | Pengaturan "uang makan di luar sistem" | Komponen uang makan Rp0 di rincian gaji | PRD G1 |

Catatan cakupan F15b dan F15c (paket G1-3, 19 Nov 2026; isi kasus tidak diubah): berlaku untuk **semua** tempat yang menampilkan total ke HRD, termasuk balasan bot Telegram sesudah file diproses dan halaman unggah web (`docs/laporan-g1-3.md`).

## Keputusan yang sudah ditutup (v1.1)

1. **Tap tunggal di tengah shift:** diperlakukan seperti lupa tap pulang, ditandai ambigu, masuk rekap harian HRD (kasus B08).
2. **Hari tanpa tap massal:** di atas ambang 50% karyawan aktif satu divisi yang berisi minimal 3 karyawan aktif, tidak langsung alpha; pemberitahuan segera; periode tertahan sampai HRD menetapkan (kasus C06, C14, F08).
3. **Jadwal Ramadan:** jadwal bertanggal biasa dengan pengingat tahunan ke HRD (kasus C07).

Jumlah kasus: 84.
