# Laporan Tahap 3 — Pembaca tap

13 November 2026 · acuan: PRD v3.1 bagian 7 dan 17, kontrak data v1.0, kasus jebakan v1.1 · paket "buat" 13 Nov 2026 (keputusan 1a dan 2)

## Hasil singkat

File mesin finger masuk lewat pembaca file, lalu database menghasilkan status per orang per hari: hadir, telat, pulang cepat, lupa tap, alpha, sakit/izin/cuti, libur, lembur hari libur, atau menunggu data. Semua uji gerbang lulus di komputer kerja, di GitHub Actions, dan hasilnya sudah terpasang di Supabase.

| Gerbang PRD bagian 17 | Hasil | Bukti |
| --- | --- | --- |
| U1 hasil per orang per hari vs kunci jawaban | **Lulus** (dengan dan tanpa koreksi jam mesin) | `sistem/uji/u1_banding.py`, 119.853 hari-orang |
| U4 kirim ulang dan pembatalan | **Lulus** | `jalankan_simulasi.sh` dan `040_baca_tap.sql` |
| U6 dua bentuk file | **Lulus**, hasil identik | sidik hasil ekspor aplikasi = attlog.dat |
| Kasus 20→21 Maret (B11, B12) | **Lulus** | `040_baca_tap.sql` dan contoh orang 10004 di bawah |
| Dua kali hitung, sidik sama | **Lulus**, juga antar zona waktu sesi | `040_baca_tap.sql`; sidik periode 1 di komputer kerja = di Supabase (`be06f1493c68`) |
| U9 file asli | Dipindah ke berjalan berdampingan (keputusan 13 Nov 2026) | — |

Uji otomatis di GitHub: 16 uji pembaca file, 163 uji database (68 lama + 95 baru), 9 uji simulasi. Semua lulus.

## Yang dibangun

| Bagian | File | Isi |
| --- | --- | --- |
| Pembaca file | `sistem/urai/urai.ts` | Ekspor aplikasi (bentuk file asli) dan attlog.dat ZKTeco. TypeScript tanpa pustaka luar, bisa dipakai Edge Function di Tahap 5. Menolak ID rusak karena Excel (F01), format tidak dikenal (F09), tanggal campur (A10); membuang tanggal mustahil (A12) |
| Jalur masuk | `fakta.terima_kiriman` (migrasi 0006) | Satu pintu untuk semua kiriman: file dobel ditolak (A07), file yang ditolak tetap dicatat dengan alasan |
| Mesin baca tap | `hitung.baca_tap(periode)` (migrasi 0006, 0007) | Bakukan → buang dobel → jadwal → jendela → masuk/pulang → tap tunggal → ambigu → anomali. Setiap hitung membuat versi baru; versi lama tidak bisa diubah |
| Tabel hasil | `hitung.versi_hitung`, `tap_bersih`, `hasil_harian`, `anomali` | Sesuai kontrak data bagian 5 |
| Data simulasi | `db/data_awal/pabrik_a_tahap3.sql`, `pabrik_a_koreksi_jam.sql`, `muat_masukan_hrd.py`, `muat_tap_simulasi.sh` | 4 periode, koreksi jam MA2, 1.603 perintah HRD dari file, 16 file mesin lewat pembaca file |
| Uji | `db/uji/040_baca_tap.sql`, `sistem/urai/uji_urai.ts`, `sistem/uji/jalankan_simulasi.sh`, `sistem/uji/u1_banding.py` | Kasus jebakan A, B, C, F; U1, U4, U6, sidik |

## U1: rincian

Kelompok "wajib" harus cocok 100%. Kelompok "info" adalah kejadian yang tidak bisa diketahui sistem dari data, atau pola data simulasi yang tidak mungkin terjadi (lihat Temuan 3). Semua kelompok info tetap diperiksa terhadap aturan bawaannya.

| Kelompok | Cocok | Tidak cocok |
| --- | --- | --- |
| hadir, masuk dan pulang sama persis dengan tap (setelah koreksi jam) | 86.361 | 0 |
| kode jadwal sama dengan kunci | 86.361 | 0 |
| libur | 28.916 | 0 |
| sakit/izin/cuti dari perintah HRD | 1.470 | 0 |
| lupa tap masuk / lupa tap pulang | 665 / 620 | 0 |
| alpha | 517 | 0 |
| tidak wajib tap (sopir) | 372 | 0 |
| tap tunggal di tengah shift (B08) / dekat jam pulang (B07) | 169 / 3 | 0 |
| lembur hari libur | 133 | 0 |
| mesin mati, absen manual HRD | 116 | 0 |
| hadir dengan tukar shift yang dilaporkan | 107 | 0 |
| karyawan baru belum terdaftar: alpha / ada pemberitahuan (2 hari kerja atau lebih) | 45 / 43 | 0 |
| alpha di hari absen manual divisi: mengikuti perintah HRD | 1 | 0 |
| *info:* tukar shift tidak dilaporkan, ada usulan tukar shift | 60 | 0 |
| *info:* shift berurutan dengan tap tidak berurutan di data simulasi | 128 | 0 |
| *info:* lembur pagi di hari libur tepat setelah shift malam | 109 | 0 |
| *info:* hari sebelum tukar shift tidak dilaporkan | 61 | 0 |

Kelompok info: 358 hari-orang (0,3%).

## Angka terukur

| Yang diukur | Hasil |
| --- | --- |
| Data di Supabase | 178.425 tap mentah, 12 kiriman diterima + 4 ditolak (file lanjutan mesin kantor kosong), 178.833 tap bersih, 119.853 hari-orang, 528 anomali |
| Lama `baca_tap` satu periode Pabrik A (±1.000 orang, ±46.000 tap) | Supabase **12,2 detik** · GitHub Actions 5,9–6,3 detik · komputer kerja 4,4 detik |
| Pasang ke Supabase (cadangan, migrasi, muat 16 file, hitung 4 periode, pemeriksaan) | ±4 menit 20 detik |
| Cadangan malam sesudahnya | 5,1 MB; pemulihan 43 tabel / 490.128 baris sama persis; uji tanpa login lulus |
| Uji simulasi di GitHub Actions | 7 menit 17 detik |

Anomali di Supabase (versi terakhir): tap ambigu 341, usulan tukar shift 136, ID tidak dikenal 24, karyawan baru belum terdaftar 17, alpha beruntun 9, hari tanpa tap massal 1 (6 Feb, mesin kantor mati, sudah ditetapkan absen manual).

## Tiga contoh orang (Supabase)

**10004, Produksi, shift malam 20→21 Maret (B11, operasi 7 hari di hari raya)**

| Tanggal | Jadwal | Jenis hari | Status | Masuk | Pulang | Lebih (menit) |
| --- | --- | --- | --- | --- | --- | --- |
| 16 Mar | P | kerja | hadir | 06:31:11 | 15:12:57 | 12 |
| 18 Mar | S | cuti bersama | hadir | 14:46:47 | 23:06:31 | 6 |
| 19 Mar | S | libur nasional | hadir | 14:33:56 | 20 Mar 02:00:23 | 180 |
| 20 Mar | M | cuti bersama | hadir | 22:42:35 | 21 Mar 07:11:32 | 11 |

Tap 07:11 tanggal 21 dihitung di periode 21 Feb–20 Mar; di periode berikutnya tap itu bertanda "milik periode lain".

**10881, Kantor, mesin MA2 yang jamnya lebih cepat 4 menit (F04)**

| Tanggal | Jadwal | Status | Masuk (jam mesin 07:38:04 dikoreksi) | Pulang |
| --- | --- | --- | --- | --- |
| 2 Mar | KR 08–15 | hadir | 07:34:04 | 15:14:28 |
| 3 Mar | KR | hadir | 07:52:58 | 15:01:58 |
| 6 Mar | KR | alpha | — | — |
| 7 Mar | KR5 08–12 | hadir | 07:32:28 | 12:13:28 |

**10003, Produksi, periode 21 Feb–20 Mar (hari yang tidak biasa)**

| Tanggal | Jadwal | Status | Keterangan |
| --- | --- | --- | --- |
| 23 Feb | P | alpha | tanpa tap |
| 4 Mar | S | hadir | masuk 15:07:26, telat 7 menit |
| 6 Mar | M | sakit | dari perintah HRD (file) |
| 7 Mar | M | hadir | lupa tap masuk, pulang 8 Mar 07:04:42 |

## Temuan

1. **Hitung satu periode Pabrik A di Supabase 12,2 detik, di atas batas 8 detik jalur API** (Terbukti: peran `authenticator` di Supabase memakai `statement_timeout=8s`). Ini belum masalah di Tahap 3 karena hitungan dijalankan workflow lewat koneksi database langsung. Di Tahap 5, Edge Function harus memanggil `baca_tap` lewat koneksi database langsung, bukan lewat jalur API; kalau tidak bisa, hitungan dipecah per divisi. Untuk pasar sasaran 150–300 orang, lamanya kemungkinan di bawah 4 detik (Menebak: waktu hitung kira-kira sebanding dengan jumlah tap). Satu perbaikan sudah dipasang: kompilasi JIT Postgres dimatikan di fungsi ini, karena memakan lebih dari 1 detik per perintah (diukur di komputer kerja: 8,3 → 5,4 detik).
2. **File mesin asli berbentuk .xls, sedangkan pembaca Tahap 3 membaca CSV dan attlog.dat.** Inti pembaca menerima baris sel (`uraiBarisEkspor`), jadi .xls tinggal dibuka lalu diteruskan ke fungsi yang sama. Pembuka .xls yang aman (SheetJS 0.20.x) hanya tersedia dari CDN SheetJS, dan CDN itu ditolak jaringan komputer kerja Claude. Versi npm (0.18.5) punya celah keamanan yang diketahui. Pembuka .xls dipasang di Edge Function Tahap 5, yang bisa memuat CDN itu.
3. **Data simulasi punya tiga pola yang tidak mungkin terjadi** (kesalahan generator, bukan sistem): (a) lembur pagi di hari libur tepat setelah shift malam, dengan tap datang lembur lebih awal dari tap pulang shift malam; (b) shift malam lalu shift pagi, dengan tap datang lebih awal dari tap pulang; (c) "tap di tengah shift" ditaruh 3–5 jam setelah masuk tanpa melihat panjang shift (di shift Sabtu 5 jam, tap itu sebenarnya dekat jam pulang). Sistem memakai urutan waktu dan aturan PRD. Kunci jawaban tidak diubah (dikunci); di U1 ketiganya masuk kelompok info.
4. **Selisih jam MA2 sebesar 4 menit tidak terdeteksi otomatis.** Tanpa koreksi, jumlah hari telat Kantor 1–10 Maret tetap 44, sama seperti dengan koreksi, sehingga peringatan "jam mesin melenceng" (F05) tidak muncul. Deteksi otomatis hanya menangkap selisih yang membuat banyak orang telat tipis; koreksi jam tetap bergantung laporan HRD.
5. **Sidik hasil sempat ikut berubah menurut zona waktu sesi** (ditemukan setelah pemasangan pertama). Isi hasil sama persis; hanya sidiknya yang berbeda. Diperbaiki di migrasi 0007; sesudahnya sidik di komputer kerja sama dengan di Supabase.
6. **Pembatalan kiriman memakai perintah HRD `batalkan_kiriman` yang sudah ada di kontrak data**, bukan tabel baru `fakta.pembatalan_kiriman` seperti tertulis di daftar paket. Efeknya sama, tabelnya lebih sedikit. Keterbatasan: file yang sama persis tidak bisa dikirim ulang setelah dibatalkan (kunci unik sidik). Perlu diputuskan di Tahap 5.
7. **Arti "tanggal berhenti":** sistem menghitung tanggal berhenti sebagai hari kerja terakhir (ikut dihitung), sesuai kunci jawaban dan kasus C11. Tabel perintah di PRD bagian 9 menulis "nonaktif sejak tanggal itu". Perlu diseragamkan saat pembaca chat dibuat (Tahap 7).
8. **Angka tetap di kode, belum ada tabel aturannya:** tap tunggal dianggap dekat jam masuk/pulang bila dalam seperempat lama shift; usulan tukar shift bila tap masuk dalam 60 menit dari jam masuk shift lain; tap terakhir dianggap lama bila 7 hari sebelum dikirim; jam mesin melenceng bila minimal 5 orang dan separuhnya telat 1–15 menit; alpha beruntun 3 hari; karyawan baru belum terdaftar setelah 2 hari kerja (PRD: 2–3); file terpotong hanya dinilai untuk file yang mencakup minimal 24 jam. Semua angka ini bisa dipindah ke tabel aturan kalau perusahaan perlu mengubahnya (kuesioner Tahap 9).
9. **Belum dikerjakan di Tahap 3:** status periode (terbuka → menunggu data → dihitung) belum dijalankan otomatis oleh `baca_tap` (masuk antrean kerja Tahap 5); Pabrik B belum diuji karena butuh data awal struktur Pabrik B (masuk Tahap 4 bersama U5); rupiah apa pun (Tahap 4).
