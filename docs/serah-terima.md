# Catatan serah terima

File ini ditulis supaya siapa pun yang melanjutkan proyek (manusia, Claude di chat lain, atau Claude di sesi baru) tahu posisi terakhir tanpa harus membaca riwayat chat. **Perbarui file ini setiap kali satu langkah selesai.**

Terakhir diperbarui: 23 November 2026 (**Tahap 7 ditutup**, `docs/laporan-tahap-7.md`); sebelumnya 22 November 2026 malam (paket 7c-2 terpasang; 7b, 7c-1, 7d selesai diuji; gerbang Tahap 7 lulus untuk izin; paket 7a terpasang, `docs/laporan-7a.md`; pemeriksaan Tahap 7 dan gerbang 8 hari, `docs/rencana-tahap-7.md`); sebelumnya 20 November 2026 siang, cabang `main` (Tahap 6: 6a, 6a-2, 6a-3, 6a-4, 6e, 6f selesai; G1, H1, G1-2 selesai; **G1-3 selesai dan terpasang**, `docs/laporan-g1-3.md`; **D1 pengaman halaman demo publik selesai**, `docs/laporan-d1.md`; **E1 enkripsi cadangan selesai**, `docs/laporan-e1.md`; **Tahap 8: 8a selesai**, `docs/laporan-8a.md`; **8b terpasang**, `docs/laporan-8b.md`; **8b-2 terpasang dan lulus uji nyata 20 Nov 2026**, `docs/laporan-8b-2.md`; **8b-3 terpasang 20 Nov 2026**, `docs/laporan-8b-3.md`; **8b-4 tombol tetap terpasang 20 Nov 2026**, `docs/laporan-8b-4.md`; **8b-5 terpasang 20 Nov 2026**, `docs/laporan-8b-5.md`; uji nyata berjalan).

## MULAI DARI SINI (sesi berikutnya, disiapkan 22 Nov 2026 20.40 WIB)

**Posisi:** Tahap 7 (perintah HRD lewat chat) **SELESAI 23 Nov 2026** — semua isi PRD v2 Tahap 7 sudah terpasang di Supabase dan lulus uji nyata 21–22 Nov 2026. **Gerbang Tahap 7 ("izin susulan mengubah hasil setelah hitung ulang") LULUS 22 Nov 2026** (`docs/laporan-7a.md`).

| Paket | Isi | Migrasi | Laporan | Uji nyata |
| --- | --- | --- | --- | --- |
| 7a | `/izin`, `/sakit`, `/cuti` (termasuk susulan), tombol "Perintah HRD" | 0032 | `docs/laporan-7a.md` | Selesai (gerbang) |
| 7d | `/batalperintah`, `/perintahku` | 0033 | `docs/laporan-7d.md` | Selesai |
| 7b | `/kasbon`, `/cicilan`, `/lunas`; kasbon bisa dibatalkan (mesin hitung v6) | 0034 | `docs/laporan-7b.md` | Selesai |
| 7c-1 | `/setujuilembur`, `/batalkanlembur` per orang/divisi (B4) | 0035 | `docs/laporan-7c.md` | Selesai |
| 7c-2 | `/setujuiawal`: jam datang awal disetujui jadi lembur (B5, PP06, kasus B05b; mesin hitung v7) | 0036 | `docs/laporan-7c2.md` | Selesai |

**Keadaan demo sekarang [Pasti, 22 Nov 20.37]:** semua perintah uji sudah dibatalkan; sidik hasil gaji periode 3 = `45a6ca644ca5`, periode 4 = `c427e5a53c5f` (sama dengan sebelum uji). Perintah chat no. 1604–1611 tetap tercatat (fakta hanya bertambah).

**23 Nov 2026 13.26 WIB:** uji tolak 7c-2 lulus [Pasti] (bot menolak, gudang: 0 draf, 0 perintah, 0 antrean baru). **TAHAP 7 DITUTUP** — `docs/laporan-tahap-7.md`.

**Langkah berikutnya:**
1. Pilih tahap berikutnya bersama pemilik. Yang masih terbuka (tidak menghalangi Tahap 7):
   - sisa Tahap 8 menunggu akun Telegram ketiga (`/undang bos` → `/gabung`, bos menyetujui, bos melihat total lengkap); 8e (keberatan) ditunda;
   - gerbang "demo hidup 8 hari tanpa dipakai" belum pernah benar-benar teruji (proyek dipakai tiap hari);
   - ~~temuan Cadangan malam~~ → **paket E2 (23 Nov, sedang dikerjakan):** kode + uji CI selesai; sisa: uji nyata Cadangan malam hijau (manual) dan hijau lagi sesudah Pasang/Isi Sheets berikutnya (berjalan di belakang, aturan 10). Lihat `docs/laporan-e2.md`;
   - usulan kecil: kata `menu` dikenali sebagai `/bantuan`.

**Cara kerja yang disepakati (tetap berlaku):** keputusan di Tahap 7 diambil Claude dan dicatat dengan label, kecuali yang tidak bisa dibatalkan, mengubah gaji/uang, atau membatasi akun pemilik (ditanyakan). "Buat" hanya untuk daftar paket yang sudah ditulis. Setiap uji nyata dicek di Supabase dan Sheets.

**Kalimat pembuka untuk chat baru:**

> Baca CLAUDE.md dan docs/serah-terima.md (bagian "MULAI DARI SINI") di repo banajaka35-design/Future-ABSENSI cabang main, lalu lanjutkan langkah berikutnya.


## Aturan sebelum mengubah apa pun

1. Tarik isi GitHub terbaru, lalu baca `CLAUDE.md` dan file ini.
2. **GitHub adalah satu-satunya sumber kebenaran.** Apa pun yang dipasang ke Supabase harus sudah ada di GitHub lebih dulu, dan dipasang lewat workflow "Pasang ke Supabase", bukan langsung dari chat (aturan 8 di CLAUDE.md). Claude memicunya dengan mendorong main ke cabang `pasang` setelah "buat" untuk paket yang menyebut pemasangan.
3. **Satu proyek dikerjakan di satu chat dalam satu waktu.** Kalau berpindah chat, mulai dari file ini.
4. Setiap perubahan dijelaskan ke pemilik proyek dalam satu paragraf bahasa sederhana: apa yang diubah, kenapa, dan cara mengeceknya.

Alasan aturan 2–4: pada 12 Nov 2026 pukul 21.14–21.16 WIB, migrasi 0001–0004 dipasang ke Supabase oleh sesi Claude lain, dan file 0004 tidak dikirim ke GitHub. Pemilik proyek tidak tahu perubahan itu terjadi. File asli ditemukan kembali dan sidiknya cocok (lihat di bawah).

## Posisi sekarang: Tahap 5 selesai (5a–5e, 5d-2, 5e-2); berikutnya Tahap 6 (tulis daftar paket dulu)

**18 Nov 2026:** PRD v3.1 tidak tersedia; pemilik memutuskan memakai PRD v2 (rangkuman dan bagian yang mungkin berbeda di `docs/rencana-tahap-6.md` bagian "Acuan PRD"). **Keputusan 1 = (a)**: Sheets hanya rekap. **Keputusan 2 = (1)**: akun layanan Google + workflow GitHub. Aturan gaji rahasia (F15) tetap. **Paket 6a di-"buat" 18 Nov 2026 dan dibuat** (rancangan `docs/rekap-sheets.md`, laporan `docs/laporan-tahap-6a.md`): penulis, pemeriksa, Sheets tiruan, workflow "Isi Sheets"; uji lokal 30 lulus 0 gagal; Supabase tidak diubah. **Uji nyata lulus 18 Nov 2026** (run 44232081983): Sheets "PROJECT ABSENSI" terisi, pemeriksa 0 beda, dicek langsung di Sheets dan Supabase (3 contoh orang di laporan). Akun layanan `isi-sheets@future-absensi.iam.gserviceaccount.com` di proyek Google Cloud ID `future-absensi` (ada proyek kedua bernama sama, ID `future-absensi-515103`, tidak dipakai; boleh dihapus pemilik). Spreadsheet juga punya editor `jakabuana444@gmail.com` (konektor Drive/Sheets Claude); tab milik sistem dikunci untuk akun layanan + pemilik. **Gerbang Tahap 6 versi PRD v2 terpenuhi untuk 6a.** Diskusi portofolio 18 Nov 2026: 6b dan 6c ditunda; cara bayar berpola + daftar transfer/tunai dipisah (permintaan perubahan 03): **paket 6a-2 dibuat dan terpasang 18 Nov 2026** (laporan `docs/laporan-tahap-6a-2.md`): Pabrik A hanya Gudang tunai (158), Sheets 8 tab Gaji dengan isi amplop; Reset + Pasang lulus, total gaji bersih sama persis dengan sebelum paket. **Catatan penting: workflow Reset tidak menjalankan `pasang_pintu.sh`; sesudah Reset selalu jalankan Pasang.** Bot pulih: `/unggah` dibalas tautan, tercatat di `fakta.tautan_unggah` (18 Nov 2026 11.39 WIB). **Paket 6a-2 selesai.** Analisa ulang G1 (18 Nov 2026) menemukan kebocoran: total Ringkasan (Sheets dan demo) dikurangi gaji yang terlihat = gaji orang rahasia (Pabrik B: 1 orang → gaji persis). Pemilik setuju: total HRD tanpa orang rahasia (permintaan perubahan 04, F15b). **Paket 6a-3 selesai 18 Nov 2026** (`docs/laporan-tahap-6a-3.md`): Sheets dan halaman demo tanpa orang rahasia, total − jumlah yang terlihat = 0 (dicek langsung di Sheets dan halaman terbit; uji Pabrik B dengan 1 orang rahasia lulus). **Temuan sesudahnya (18 Nov 2026):** tanda anomali "lembur divisi KTR naik" di halaman demo membuka lembur gabungan orang rahasia (237.717); **paket 6a-4 selesai 18 Nov 2026** (`docs/laporan-tahap-6a-4.md`): tanda divisi berahasia tanpa angka; uji GitHub 453 + 88 lulus; demo terbit (pemeriksa 0 beda). Halaman terbit dicek langsung: sesuai. Keputusan pemilik: isi Sheets otomatis sesudah file Telegram dimajukan sebelum G1; nama orang rahasia di daftar "gaji berubah" tetap ditampilkan (transparan). **Paket 6e (Sheets otomatis sesudah file masuk) di-"buat" 18 Nov 2026; kode selesai, uji GitHub lulus (commit e23dedf: pintu 38, penyambung 23, database 453, simulasi 92). **Paket 6e selesai 18 Nov 2026** (`docs/laporan-tahap-6e.md`): terpasang; uji nyata lewat bot lulus, file masuk → Sheets SELESAI dan dikabarkan di Telegram dalam 172 detik (diukur sekali); gaji tidak berubah. **Paket 6f selesai dan terpasang 18 Nov 2026** (`docs/laporan-tahap-6f.md`): batas harian kode email, izin fungsi bawaan Supabase dicabut (peringatan keamanan 0), header keamanan halaman, pengamanan workflow, pesan tolak file berisi alasan; bug B2 (pemeriksaan data awal menggagalkan Pasang sesudah ada kiriman sungguhan) ditemukan dan diperbaiki. Header halaman terbit dan bot sesudah Pasang dicek langsung: sesuai. Daftar G1 versi 2 ditulis ulang (`docs/rencana-grafik-demo.md`). **Paket G1 selesai dan terbit 18 Nov 2026** (`docs/laporan-grafik-demo.md`): tiga grafik tanpa orang rahasia, saring transfer/tunai, isi amplop; uji GitHub lulus, pemeriksa demo 0 beda, 5 angka dicocokkan langsung dengan Supabase. Cek langsung menemukan 2 hal yang diperbaiki (daftar melebar di HP; teks tanda angka sementara salah sebut "akhir tahun"). Analisa ulang sesudah G1: daftar paket G1-2 (`docs/rencana-perbaikan-g1.md`, celah status rahasia lama C1, demo tidak terbit sesudah file Telegram C2), **menunggu "buat"**. Repo tetap private (keputusan pemilik 18 Nov 2026); **paket H1 (hemat menit GitHub) di-"buat" dan dikerjakan lebih dulu** (`docs/rencana-hemat-menit.md`): uji hanya untuk main dan dilewati bila hanya `docs/` berubah; Pasang/Reset mencari commit main terdekat yang lulus. **H1 selesai dan terbukti 18 Nov 2026**: push docs saja 0 run; Pasang lewat cabang `pasang` lulus tanpa uji ulang. Pemakaian 1–18 Nov: ±1.086 menit (cek ulang 25 Nov 2026). **G1-2 selesai 18 Nov 2026** (`docs/laporan-g1-2.md`, permintaan perubahan 05, kasus F15c): rahasia per periode di demo dan Sheets, tanda anomali ikut periode lalu, demo terbit sendiri sesudah Isi Sheets (dibuktikan run 44301225340). **Temuan T1 [Pasti]: balasan bot sesudah file diproses menulis total gaji bersih termasuk orang rahasia (`api.pintu_kerjakan`, migrasi 0015) → bocor F15b lewat Telegram.** **G1-3 selesai dan terpasang 19 Nov 2026** (rencana `docs/rencana-g1-3.md`, laporan `docs/laporan-g1-3.md`): migrasi 0024, total di balasan bot dan halaman unggah tanpa orang rahasia (F15c) dengan keterangan "tidak termasuk N orang rahasia"; antrean hanya menyimpan nomor versi gaji (total dihitung saat dibaca, C1); 3 baris lama dibersihkan; bot hanya melayani chat pribadi (C2); uji GitHub lulus (database 467, pintu 48, penyambung 23, simulasi 119), uji gagal dengan aturan lama dibuktikan. Uji nyata lewat bot (kiriman no. 19): angka keempat periode di bot = Sheets = Supabase; gaji tidak berubah. **Catatan terbuka sesudah G1-3:** T2 riwayat versi Sheets (paket sendiri sebelum HRD sungguhan); jalur bos untuk melihat total lengkap belum ada (F15 menyebut bos boleh melihat; perlu keputusan pemilik); 3 pesan bot lama 18 Nov dibiarkan (keputusan pemilik). Evaluasi ulang sesudah G1-3 (19 Nov 2026) menemukan 6 celah; urutan yang disetujui pemilik: **D1 pengaman halaman demo publik (selesai 19 Nov 2026**, `docs/laporan-d1.md`: Terbitkan demo hanya jalan bila semua karyawan di Supabase data simulasi; uji GitHub 123 simulasi lulus; picu lewat tombol lulus, halaman dicek), lalu **E1 enkripsi cadangan (selesai 19 Nov 2026**, `docs/laporan-e1.md`, panduan `docs/cadangan.md`: Cadangan malam, Pasang, Reset hanya mengunggah `.dump.gpg` dengan secret `CADANGAN_KUNCI` milik pemilik; kunci kosong → GAGAL, Pasang/Reset berhenti sebelum menyentuh Supabase; uji pemulihan malam memakai file terenkripsi, run 44485626472: 55 tabel / 1.373.892 baris sama; 30 artifact lama tanpa enkripsi dibiarkan sampai habis, paling lambat sekitar 19 Des 2026), berikutnya **jalur gaji orang rahasia untuk bos** lewat chat pribadi bot dengan PIN di Tahap 8, termasuk aturan "orang rahasia wajib dibayar transfer" (saran Claude: pilihan (a), belum diputuskan pemilik). Akses Sheets HRD lihat saja dan akses pembangun/Claude dicatat di tabel "Sebelum dipasang". Status 60 menit untuk tautan unggah dibiarkan. **Tahap 8 (19 Nov 2026)**: acuan PRD v2 bagian 13 (gerbang: pesan sampai ke akun uji, dan pendaftaran dengan kode salah ditolak); dipecah 8a–8e (`docs/rencana-tahap-8.md`). **8a selesai dan terpasang 19 Nov 2026** (`docs/laporan-8a.md`, migrasi 0025): `/kode`, `/daftar`, konfirmasi nama dan divisi, kode 60 menit sekali pakai (hanya sidik disimpan), 5 salah per jam terkunci, ganti HP lewat HRD; uji GitHub lulus (database 506, pintu 56); uji nyata `/kode 10001` membuat kode di Supabase (sidik cocok). **Menunggu orang lain (aturan 10):** akun Telegram kedua untuk uji nyata `/daftar` kode salah dan pendaftaran berhasil. **Keputusan terbuka:** HRD boleh mendaftarkan karyawan sebelum tanggal mulai? (sekarang ditolak; 11 karyawan simulasi mulai 24 Nov 2026 atau sesudahnya). **8b terpasang 19 Nov 2026** (`docs/laporan-8b.md`, migrasi 0026): `/pin`, `/ajukan`, persetujuan bos, `/rilis` dengan PIN; periode dirilis tidak dihitung ulang; status periode `dihitung` sesudah hitung; daftar karyawan sebelum tanggal mulai diizinkan (keputusan pemilik); isian pajak Januari 2026 KARANGAN 38 orang → periode 1–3 bisa diajukan (gaji periode 2 +198.383, periode 3 +1.247.818). Uji GitHub lulus (database 551, simulasi 127, pintu 62). **Uji nyata belum**: pengaturan demo ternyata "HRD lalu bos" dan belum ada akun bos.

**KEPUTUSAN PEMILIK (19 Nov 2026 16.43 WIB): akun pembangun (akun pemilik) harus bisa melakukan semua yang bisa dilakukan akun lain**, supaya pemilik bisa langsung bertindak saat ada kendala. Pembatasan apa pun pada akun pembangun ditanyakan dulu ke pemilik, tidak dipasang sendiri. Untuk perusahaan sungguhan diputuskan ulang (tabel "Sebelum dipasang").

**8b-2 selesai dan terpasang 20 Nov 2026** (`docs/rencana-8b-2.md`, `docs/laporan-8b-2.md`, migrasi 0027, commit 49492f8; uji GitHub database 567, pintu 67; Pasang run 44660004407; sidik 0027 `dfeb1fd7075d` cocok di Supabase): `/setujui <nomor> <PIN>` dan `/tolak <nomor> <PIN>` untuk pembangun (keputusan pemilik A dan B, 20 Nov 2026). **Uji nyata 8b + 8b-2 lulus 20 Nov 2026 09.37 WIB**: periode 2 dirilis oleh pembangun (tercatat "oleh pembangun"). Temuan sesudahnya: urutan rilis tidak dijaga (periode 2 dirilis sebelum periode 1; dibiarkan di demo, keputusan pemilik), lupa PIN, akun HRD/bos tidak bisa ditambah, rilis tidak dikabarkan, pengajuan menggantung, kemudahan bot. **Paket 8b-3 terpasang 20 Nov 2026** (`docs/rencana-8b-3.md`, `docs/laporan-8b-3.md`, migrasi 0028, commit 687ce87; database 603, pintu 77, simulasi 128). **Paket 8b-4 (tombol tetap di bawah kolom ketik) terpasang 20 Nov 2026** (`docs/rencana-8b-4.md`, `docs/laporan-8b-4.md`, commit fdf9a90, tanpa migrasi; pintu 82). Uji nyata 8b-3 + 8b-4 (20 Nov 2026 11.13–11.16 WIB): tombol tetap tampil; Ajukan → Setujui (PIN) → Rilis (PIN) periode 1 berhasil, tercatat "oleh pembangun"; periode 3 kini bisa diajukan. Temuan: Sheets tidak ikut berubah sesudah rilis; tombol tetap tertutup sesudah PIN. **Paket 8b-5 terpasang 20 Nov 2026** (`docs/rencana-8b-5.md`, `docs/laporan-8b-5.md`, commit 974f090, tanpa migrasi; pintu 85). **Uji nyata 8b-5 lulus 20 Nov 2026 12.14–13.56 WIB**: Ajukan periode 3 → bot memicu Isi Sheets ("status periode", GitHub run 44679736766) → Sheets "Diajukan, menunggu persetujuan"; Tolak (PIN) tanpa "Reply to" → periode 3 kembali dihitung ("ditolak pembangun") → Sheets "Bisa diajukan" (12.20 WIB), sama dengan Supabase; tombol tetap muncul lagi lewat ikon tombol di kolom ketik (Telegram Desktop melipatnya). Catatan: tombol tetap yang tertutup force reply sebelum 8b-5 kembali lewat `/bantuan`. Usulan kecil belum di-"buat": kata `menu` dikenali sebagai `/bantuan`. **Paket 8c (pesan rincian gaji) terpasang 20 Nov 2026** (`docs/rencana-8c.md`, `docs/laporan-8c.md`, migrasi 0029, commit a791fc4; database 627, pintu 92, simulasi 128; periode 1 dan 2 kini `dikunci`, semua 2.021 baris antrean `tanpa_akun`). Uji nyata `/contohgaji 10001 2` cocok dengan Supabase dan Sheets; temuan sisa pembulatan lalu diperbaiki di **paket 8c-2 (terpasang 20 Nov 2026, migrasi 0030)**. Uji nyata `/contohgaji 10735 2` (15.26 WIB) cocok dengan Sheets dan Supabase (bersih 6.798.540 + sisa lalu 942 = dibayar 6.799.000 + sisa 482). **Gerbang Tahap 8 "pesan sampai ke akun uji" LULUS 20 Nov 2026 15.31 WIB**: akun Telegram kedua pemilik mendaftar sebagai karyawan 10735 (`/kode` → `/daftar` → Ya), rincian gaji periode 2 terkirim otomatis (`fakta.kirim_gaji` periode 2 = terkirim; periode 1 tetap tanpa_akun, bisa `/gaji 1`), tombol Gaji saya/Bantuan tampil di HP. Temuan: kalimat "akan dikirim setelah gaji dirilis" janggal → **paket 8c-3** (`docs/rencana-8c-3.md`). Akun kedua kini berperan karyawan; `/undang`/`/gabung` butuh akun ketiga. Uji nyata `/gaji 1` di akun kedua (16.08 WIB) lulus: rincian periode 1 sama dengan gudang (bersih 4.515.942, dibayar 4.515.000, sisa 942 = sisa lalu periode 2), `fakta.kirim_gaji` periode 1 berubah tanpa_akun → terkirim. **Paket 8d (jalur bos, keputusan (a) bot dengan PIN dan (i) orang rahasia wajib transfer) terpasang 20 Nov 2026** (`docs/rencana-8d.md`, `docs/laporan-8d.md`, migrasi 0031, commit e0650c6; database 643, pintu 98). **Langkah berikutnya: gerbang Tahap 8 "pesan sampai ke akun uji" + `/undang`/`/gabung` menunggu akun Telegram kedua; uji nyata `/lengkap` lulus 17.04 WIB (`docs/laporan-8d.md`); **8d-2** (kalimat pilihan periode) dibuat. Sisa Tahap 8 menunggu akun Telegram ketiga (pemilik belum punya, 20 Nov 2026 17.06 WIB): kode salah ditolak (uji nyata), kalimat "Terdaftar" baru, `/undang bos` → `/gabung`, bos menyetujui dengan tombol, bos melihat total lengkap. **8e (keberatan) ditunda** sampai Tahap 8 ditutup (saran Claude 17.05 WIB, pemilik "lakukan yang bisa sekarang").** **Paket 8d-2 terpasang 20 Nov 2026** (`docs/rencana-8d-2.md`, commit 6c02182, tanpa migrasi; pintu 98). **Untuk sesi berikutnya (disetujui pemilik 20 Nov 2026 18.14 WIB, dikerjakan besok):** (1) periksa status Tahap 7 (perintah HRD lewat chat: sakit, izin, cuti, berhenti, lembur, karyawan baru) terhadap kode dan Supabase; [Kemungkinan Besar] belum dibangun karena tidak ada rencana/laporan Tahap 7 di repo dan masukan HRD hanya dari file simulasi; bila benar, tulis daftar paket Tahap 7 untuk "buat" (hanya pemeriksaan, tanpa mengubah apa pun sebelum "buat"); (2) cek gerbang "demo masih hidup setelah 8 hari" (sekitar 21 Nov 2026); (3) sisa Tahap 8 menunggu akun Telegram ketiga. **Hasil 21 Nov 2026 pagi:** (1) [Pasti] Tahap 7 belum dibangun: bot dan migrasi 0015–0031 tidak menulis `fakta.perintah_hrd`; di Supabase 1.603 perintah, semua `asal = file`, 0 dari chat. Daftar paket 7a–7d dan 4 keputusan untuk pemilik ditulis di `docs/rencana-tahap-7.md` (**belum di-"buat"**). Acuan PRD v2 bagian 13 ditempel pemilik 10.08 WIB: Tahap 7 = izin, sakit, kasbon, dan persetujuannya; gerbang = izin susulan mengubah hasil setelah hitung ulang; rencana diperbarui ke versi 2 (7a izin/sakit/cuti, 7b kasbon, 7c persetujuan, 7d batalkan). Arti "persetujuannya" = (a) persetujuan lembur (B4) dan jam sebelum jadwal (B5); kasbon tanpa persetujuan bos (C10); tukar shift [Pasti] cukup perintah HRD (`docs/rencana-tahap-7.md` bagian 3a). Cara menulis = (a) perintah tetap. Mulai 10.13 WIB Claude memutuskan sendiri di Tahap 7 kecuali keputusan tak bisa dibatalkan, mengubah gaji/uang, atau membatasi akun pemilik. **Paket 7a di-"buat" 10.39 WIB dan terpasang 21 Nov 2026** (`docs/laporan-7a.md`, migrasi 0032 sidik `a0d560b9e134`, commit e2530ec; uji GitHub database 678, pintu 105, penyambung 23; Pasang run 44864570653, pemeriksaan 33 lulus). **Uji nyata 22 Nov 2026: GERBANG TAHAP 7 LULUS** [Pasti]: perintah no. 1604 (chat, pembangun) mengubah 10067 30 Mar 2026 `alpha` → `izin`; periode 3 dan 4 dihitung ulang dalam sekitar 45 detik; premi hadir +Rp100.000, dibayar +Rp84.539 (hanya orang itu); Sheets cocok (`docs/laporan-7a.md`). Uji tolak `/izin 10067 25-02-2026` lulus (ditolak, tidak ada yang dicatat). **Uji nyata 7a selesai.** Temuan: teks konfirmasi tidak menyebut periode 4 yang ikut dihitung ulang. Urutan berikutnya (keputusan Claude): **7d dulu**, lalu 7b, 7c. **Paket 7d di-"buat" 10.47 dan terpasang 22 Nov 2026** (`docs/laporan-7d.md`, migrasi 0033 sidik `f4747ab411ca`, commit b900eb8; perintahnya `/batalperintah`, bukan `/batal`). **Uji nyata 7d selesai 22 Nov 2026** [Pasti]: perintah no. 1605 membatalkan 1604; 10067 30 Mar 2026 kembali `alpha`, gaji periode 3 sama persis dengan sebelum uji 7a (0 dari 1.010 orang berbeda), Sheets cocok; sekitar 51 detik; pembatalan kedua ditolak. Temuan: kabar Sheets menulis "sejak file masuk" untuk perintah chat. **Paket 7b (kasbon) di-"buat" 16.13 dengan pilihan (a) dan terpasang 22 Nov 2026** (`docs/laporan-7b.md`, migrasi 0034 sidik `f7ea788433d5`, `hitung.hitung_gaji` versi kode 6 = versi 5 + syarat kasbon dibatalkan; CI database 720, simulasi 129 dengan U1 lulus, pintu 112). **Uji nyata 7b selesai** [Pasti]: kasbon no. 1606 memotong Rp250.000 di periode 4 (sekitar 22 detik, Sheets cocok); `/batalperintah 1606` (no. 1607) mengembalikan gaji periode 4 sama persis (0 orang berbeda dari versi sebelum kasbon); `/lunas 10067 5.000.000` tidak mencatat apa pun. **Paket 7c-1 di-"buat" 17.12 dan terpasang 22 Nov 2026** (`docs/laporan-7c.md`, migrasi 0035 sidik `572cb01ee415`; mesin hitung tidak diubah; satu run CI gagal karena uji 7c mengganggu uji pengingat, sudah diperbaiki sebelum dipasang). **Uji nyata 7c-1** [Pasti]: `/batalkanlembur 10067 26-11-2026` (no. 1608) → lembur Rp80.925 → Rp0, dibayar Rp4.380.000 (sekitar 21 detik, Sheets cocok); `/batalperintah 1608` (no. 1609) → kembali sama persis (0 orang berbeda). Uji tolak `/setujuilembur XYZ` lulus. **Uji nyata 7c-1 selesai.** **Isi Tahap 7 menurut PRD (izin, sakit, kasbon, persetujuan lembur) sudah jalan lewat chat; yang belum: B5 jam sebelum jadwal masuk (paket 7c-2).** Keputusan pemilik 7c-2: datang awal yang disetujui **digabung** dengan menit lewat jam pulang; persetujuan datang awal **terpisah** (`/setujuiawal`). **Paket 7c-2 di-"buat" 19.07 (dengan pemeriksaan celah) dan terpasang 22 Nov 2026** (`docs/laporan-7c2.md`, migrasi 0036 sidik `80c7c7342d68`, `hitung.hitung_gaji` versi kode 7, permintaan perubahan 06 / kasus B05b). Bukti: sidik hasil periode 3 dan 4 versi 7 sama dengan versi 6. **Uji nyata 7c-2** [Pasti]: `/setujuiawal 10060 21-11-2026` (no. 1610) → lembur 690 → 720 menit, dibayar Rp4.472.088 → Rp4.494.342, hanya 10060 berubah, Sheets cocok; `/batalperintah 1610` (no. 1611) → sidik hasil periode 4 kembali `c427e5a53c5f`. Sisa: uji tolak `/setujuiawal 10060 25-02-2026`. **Semua isi PRD Tahap 7 (izin, sakit, kasbon, persetujuan lembur B4, datang awal B5) sudah jalan lewat chat.** Lalu 7c (persetujuan lembur). (2) Gerbang "demo hidup 8 hari": [Pasti] Supabase `ACTIVE_HEALTHY`, Cadangan malam terjadwal hijau 9 malam berturut-turut (12–20 Nov); **tetapi syarat "tanpa dipakai" belum pernah teruji** karena proyek dipakai setiap hari (Pasang terakhir 20 Nov 16.56 WIB). Saran: anggap lulus dengan catatan, atau uji ulang dengan membiarkan proyek 8 hari tanpa Pasang/bot. Temuan sampingan [Kemungkinan Besar]: 6 run Cadangan sesudah Pasang/Isi Sheets (17–20 Nov) GAGAL karena selisih 1 baris di tabel yang sedang diisi bot saat itu (`pesan_telegram`, `minta_gaji`), bukan karena cadangan rusak; jumlah baris sumber dihitung sesudah cadangan diambil. Belum diperbaiki (perlu paket). Usulan awal 8b-2 (19 Nov 2026): migrasi 0027, pembangun boleh Setujui/Tolak seperti bos dengan PIN, tercatat "oleh pembangun", perintah `/setujui <nomor> <PIN>`, pembangun ikut menerima pesan pengajuan; uji; Pasang; uji nyata penuh oleh pemilik (`/pin` → `/ajukan` 21 Feb–20 Mar → `/setujui` → `/rilis`; periode itu lalu terkunci permanen di demo). Sesudah itu 8c (pesan rincian gaji ke karyawan), 8d (jalur bos/pembangun melihat gaji orang rahasia; tanyakan apakah termasuk "bisa semua"), 8e (keberatan, ikut atau ditunda).

Kalimat pembuka untuk chat baru:

> Baca CLAUDE.md dan docs/serah-terima.md di repo banajaka35-design/Future-ABSENSI cabang main, lalu docs/laporan-8b.md. Lanjutkan paket 8b-2: buat. Token dibuat pemilik 18 Nov 2026, secret `GTHUB_PICU_TOKEN`, **habis 16 Februari 2027** (buat ulang sebelum tanggal itu). Sesudahnya G1 ditulis ulang (potongan 4 nilai, tanda angka sementara periode PPh tertahan, uji ukuran batang, tampilan gelap bukan janji G1, keterangan THR); sesudahnya isi Sheets otomatis sesudah file Telegram, lalu Tahap 8. Urutan berikutnya yang dibahas: grafik di halaman demo, isi Sheets otomatis sesudah file Telegram, Tahap 8.

**Mulai 18 Nov 2026 dari sini:** draf daftar paket Tahap 6 ada di `docs/rencana-tahap-6.md` (belum di-"buat"). Langkah pertama: pemilik menempelkan teks PRD v3.1 yang diminta di bagian "Yang dibutuhkan dari PRD", lalu keputusan (a)/(b) dan cara menulis ke Sheets. Kalimat pembuka untuk chat baru:

> Baca CLAUDE.md, docs/serah-terima.md, dan docs/rencana-tahap-6.md di repo banajaka35-design/Future-ABSENSI cabang main. Ini teks PRD yang diminta: [tempel]. Lanjutkan Tahap 6.


Tahap 3 (pembaca tap) lulus dan terpasang 13 Nov 2026 (bagian "Tahap 3" di bawah, lengkapnya di `docs/laporan-tahap-3.md`). Tahap 4 dipecah jadi paket kecil: **4a** (catatan, cek hukum, isian aturan; selesai 16 Nov 2026, lihat bagian "Paket 4a"), **4b** (hitung gaji), **4c** (halaman web). Permintaan perubahan 01 disetujui pemilik 16 Nov 2026 (usulan 1 dan 2; dikerjakan di 4b). Naskah resmi UU 27/2026 sudah dibaca 16 Nov 2026 (PDF JDIH BPK, diunduh pemilik ke folder Downloads komputernya); pasal 115, 116, 118, 125, 134, 135, 140, 150, 310, 312 cocok dengan catatan dan labelnya kini [Pasti]. Temuan baru: UMK hanya berlaku untuk masa kerja kurang dari 1 tahun (Pasal 140 ayat 1); batas potongan 50% dan THR tidak ada di UU, diserahkan ke PP (lama tetap berlaku lewat Pasal 310), isinya dicek di 4b. **Berikutnya: daftar paket 4b.**

## Diskusi 16 Nov 2026 (keputusan pemilik proyek)

| Hal | Isi |
| --- | --- |
| Sumber tanggal merah | **SKB 3 Menteri resmi** (terbit setahun sekali). API kalender online tidak dipakai sebagai sumber utama (milik pihak ketiga, bisa salah atau mati); API hanya boleh sebagai pembanding |
| Libur nasional dan cuti bersama | Libur nasional wajib untuk semua perusahaan. Cuti bersama dipilih per perusahaan oleh HRD (mana yang dipakai) |
| Kalender 2027 | Sudah diumumkan pemerintah (SKB 15 Sep 2026); daftar tanggal sudah dicek (`docs/cek-aturan-hukum.md` bagian 5); **belum dimasukkan ke Supabase** |
| UU 27/2026 tentang Pelindungan Ketenagakerjaan | Berlaku sejak 28 Okt 2026, mencabut UU 13/2003 dan sebagian UU Cipta Kerja. Antara lain: lembur maks 4 jam/hari dan 18 jam/minggu dengan persetujuan pekerja; cuti bersama tidak mengurangi cuti tahunan (Pasal 118 ayat 6). PRD v3.1 masih memakai aturan lama. Tidak menghalangi Tahap 3; **wajib dicek ke teks resmi UU sebelum rumus gaji (paket 4b)**. Hasil cek pertama: `docs/cek-aturan-hukum.md` |
| Prinsip isian, bukan kode | Perbedaan gaji, lembur, dan aturan per karyawan atau per perusahaan disimpan sebagai **isian (data)**, bukan kode. Batas bawah hukum (UMK, rumus lembur minimal, BPJS, PPh 21) tidak boleh dilanggar; batas bawah ini dijaga mesin hitung, bukan pilihan HRD |

**Pertanyaan yang wajib masuk kuesioner pemasangan** (Tahap 9, dicatat 16 Nov 2026):

1. Hari kerja 5 atau 6 hari seminggu?
2. Ada bagian yang bekerja 7 hari atau bergiliran (shift)? Bagian mana?
3. Cuti bersama mana saja yang dipakai perusahaan?
4. Ada libur khusus perusahaan (ulang tahun perusahaan, libur daerah, dan sebagainya)?
5. Bayaran bila karyawan masuk di tanggal merah?
6. Bila tanggal merah jatuh di hari libur mingguan karyawan, apa yang terjadi (diganti hari lain atau tidak)?
7. Siapa yang tetap wajib masuk di tanggal merah (satpam, produksi, dan sebagainya)?
8. Ada libur keagamaan tambahan untuk karyawan tertentu?

## Paket 4a (16 Nov 2026): cek aturan hukum dan isian TER/PTKP

| Hal | Isi |
| --- | --- |
| Dokumen | `docs/cek-aturan-hukum.md` (tabel aturan → angka → pasal/sumber → label), `docs/permintaan-perubahan-01.md` (cuti bersama dan dasar lembur setelah UU 27/2026; menunggu keputusan) |
| Migrasi 0008 | `0008_ter_ptkp.sql`: tarif TER bulanan PPh 21 (A 44, B 40, C 41 lapisan; Lampiran PP 58/2023) dan PTKP 8 status (PMK 101/2016). Hanya menambah baris |
| Uji | `db/uji/050_aturan_resmi.sql`: jumlah lapisan, tanpa celah, batas "sampai dengan", kasus E04 (Rp261.350), PTKP |
| Hasil (diukur 16 Nov 2026) | Uji lokal Postgres 16: 178 lulus, 0 gagal. GitHub "Uji database" commit 00a8b29: lulus (termasuk uji simulasi Tahap 3), sekitar 4 menit. "Pasang ke Supabase" lewat cabang `pasang`: lulus, sekitar 2,5 menit (cadangan dulu, hanya 0008 dipasang). "Cadangan malam" otomatis sesudahnya: lulus |
| Dicek langsung di Supabase | 0008 terpasang 16 Nov 2026 18.57 WIB, sidik `94184888ffef` sama dengan repo; TER A 44 / B 40 / C 41; PTKP 8 status sesuai PMK 101/2016; bruto 10.454.000 kategori A = 250 (2,5%); karyawan 1.044 dan hasil harian 119.853 tidak berubah; skema `uji` tidak tertinggal; tidak ada transaksi menggantung |

**Temuan paket 4a:**

- **Batas upah JP di Supabase salah** [Pasti]: tercatat 10.547.000 sejak 1 Jan 2026 tanpa akhir. Yang benar 10.547.400 (Mar 2025–Feb 2026) dan **11.086.300 sejak 1 Mar 2026** (surat BPJS Ketenagakerjaan B/1226/022026). Belum dibetulkan (lihat temuan berikut).
- **Kalender dan BPJS tidak bisa diisi lewat migrasi** [Pasti]: keduanya dimuat `db/data_awal/pabrik_a_struktur.sql`, dan pemasangan hanya memuatnya kalau tabel masih kosong. Migrasi yang mengisi kalender lebih dulu membuat pemasangan dari nol berhenti "setengah ada"; perbaikan JP lewat migrasi tertimpa saat Reset. Mengubah alur pemasangan tidak ada di daftar paket, jadi kalender 2027 dan JP **tidak dikerjakan** dan diusulkan sebagai paket kecil tersendiri.
- **UMK Langkat 2026 = 3.402.892 sudah benar** [Pasti] (SK Gubernur Sumut 188.44/908/KPTS/2025).
- **Naskah resmi UU 27/2026 belum terbaca** (situs JDIH ditolak jaringan kerja Claude). Isi pasal diambil dari salinan pindai tidak resmi + berita [Kemungkinan Besar].
- **Upah sejam menurut UU 27/2026 = (pokok + tunjangan tetap) ÷ 173**; kasus D11 (dasar 75% dari seluruh upah) mungkin tidak berlaku untuk tanggal sesudah 28 Okt 2026 [Menebak]. Masuk permintaan perubahan 01.
- **Data simulasi punya periode sesudah UU baru** (Pabrik A 21 Nov–20 Des 2026, Pabrik B Des 2026), termasuk cuti bersama 24 Des 2026. Pabrik B memakai "cuti bersama memotong cuti", yang tidak sah lagi untuk tanggal itu.
- **PTKP kemungkinan berubah untuk 2027** (pemerintah sedang menyiapkan PMK, berita 24 Okt 2026); kalau berubah, tabel TER kemungkinan ikut berubah. Dicek lagi sebelum gaji Januari 2027.
- Uji lama `010_pondasi.sql` "tarif TER tumpang tindih ditolak" masih lulus, tetapi sekarang baris pertamanya sudah ditolak karena menimpa tarif resmi 0008 (alasan berbeda, hasil sama). Uji baru di 050 menguji hal yang sama dengan jelas.

## Tahap 2 (gudang data): lulus dengan catatan

### Sudah terbukti

| Hal | Bukti |
| --- | --- |
| Migrasi 0001–0004 ada di GitHub dan di Supabase, sidiknya sama | `jejak.migrasi` di Supabase; sidik 0004 = `08ff638a00a1…d091dd` |
| Uji otomatis memasang 0001–0004 dari nol | GitHub Actions "Uji database": 63 lulus, 0 gagal |
| Struktur Pabrik A di Supabase | mesin 2, divisi 5, kalender 22, pengali lembur 44 |
| Karyawan di Supabase masih kosong | `induk.karyawan` = 0 (CSV berisi 1.044) |
| Secret `SUPABASE_DB_URL` (Session pooler) dibuat dan berfungsi | Workflow "Cek koneksi Supabase" tersambung, server Postgres 17.11 |
| Klien Postgres 17 bisa dipasang dari PGDG di GitHub Actions | psql 17.12 terpasang di workflow cek-koneksi |

### Temuan yang perlu diingat

- **Pengaturan koneksi diabaikan lewat Session pooler.** `PGOPTIONS=-c default_transaction_read_only=on` tidak berlaku (hasil `show` = off). Pengaman tidak boleh bergantung pada pengaturan koneksi; harus ada di dalam perintah atau skripnya (Kemungkinan Besar: pooler membuang opsi itu).
- **Data awal tidak bisa dijalankan dua kali.** `pabrik_a_struktur.sql` dan `muat_karyawan.py` memakai `insert` biasa. Pemasangan harus memeriksa dulu apakah datanya sudah ada.
- **Tombol "Run workflow" hanya muncul untuk workflow yang ada di cabang main** (Kemungkinan Besar, aturan GitHub). Karena itu penggabungan tahap-2b ke main dikerjakan sebelum workflow pasang-supabase dipakai.
- **Uji pemulihan ke postgres:17 polos** kemungkinan gagal kalau seluruh database dicadangkan, karena ada peran dan skema khusus Supabase. Cadangkan hanya skema milik proyek, dan siapkan peran dengan `db/uji/persiapan_peran.sql`.
- **Cadangan skema proyek belum bisa dipulihkan utuh begitu saja** (Terbukti di Postgres 16 lokal): 18 galat "no default operator class for access method gist", karena ekstensi `btree_gist` ada di skema `extensions` yang tidak ikut dicadangkan. Uji pemulihan (langkah 4) membuat ekstensi itu lebih dulu; di Postgres 16 lokal galatnya menjadi nol.
- **Sentuhan harian lewat koneksi database belum tentu dihitung aktif oleh Supabase** (Menebak). Baru terbukti setelah gerbang "demo hidup setelah 8 hari".
- GitHub mematikan jadwal otomatis di repo yang 60 hari tanpa commit (Kemungkinan Besar).

- **Memuat data dari GitHub Actions ke Supabase sangat lambat kalau satu perintah per baris** (Terbukti, run #1: 22 menit, 0,254 detik per perintah). Sudah diperbaiki dengan COPY (paket 13 Nov (2)).

### Keputusan pemilik proyek (12 Nov 2026)

| Keputusan | Isi |
| --- | --- |
| Muat karyawan | Dilebur ke workflow pasang-supabase, tidak dibuat workflow terpisah, supaya cadangan diambil lebih dulu (F13) |
| Pengaman tombol | Workflow pasang-supabase hanya jalan kalau pemilik mengetik `PASANG` |
| Umur simpan cadangan | 30 hari (artifact GitHub; hanya untuk data simulasi, tidak untuk perusahaan sungguhan) |
| Urutan | Gabung tahap-2b ke main dikerjakan sebelum workflow pasang-supabase dijalankan |
| Cadangan malam | Pukul 02.20 WIB, disimpan 14 hari, ditambah sentuhan lewat jalur API (ikut saran) |
| Tempat uji (13 Nov 2026) | Untuk demo (data simulasi), tempat uji terpisah = Postgres sementara di GitHub Actions (semua uji otomatis jalan di sana, aturan F7); Supabase utama boleh direset. Supabase kedua khusus uji ditunda sampai Tahap 5 (bot Telegram) atau klien pertama, mana yang lebih dulu. Ini tafsiran gerbang PRD bagian 17 yang disetujui pemilik, bukan penghapusan gerbang |
| Gerbang Tahap 2 (13 Nov 2026) | **Lulus dengan catatan.** Uji "demo hidup setelah 8 hari tanpa dipakai" (PRD bagian 17) berjalan di belakang lewat Cadangan malam dan dicek sekitar 21 Nov 2026. Bila Supabase ternyata dijeda, diperbaiki saat itu (reset 3 menit) tanpa menghentikan tahap yang sedang jalan. Tahap 3 boleh dimulai sekarang (aturan 10 di CLAUDE.md) |
| U9 dan U2 (13 Nov 2026) | Tidak menghalangi gerbang Tahap 3 dan 4. Acuan untuk pembangunan adalah **bentuk file asli** (lihat "Bentuk file asli" di bawah); pencocokan dengan hitungan manusia (file asli ditandai tangan, gaji dihitung orang lain) dilakukan saat berjalan berdampingan di perusahaan pertama. Klaim portofolio tetap "diuji dengan data simulasi berformat mesin asli" (PRD bagian 1) |
| Cara kerja (13 Nov 2026) | "Buat" berlaku per paket yang ditulis lengkap; Claude yang memicu pemasangan lewat cabang `pasang` (tag ditolak jalur akses Claude, HTTP 403); tidak ada perkiraan waktu tanpa diukur |

## Langkah berikutnya (satu per satu, masing-masing menunggu "buat")

1. ~~Workflow `pasang-supabase`~~ **Selesai dibuat (12 Nov 2026, belum pernah dijalankan ke Supabase).** File: `.github/workflows/pasang-supabase.yml` dan `db/pasang_supabase.sh`. Diuji di Postgres 16 lokal (bukan 17, bukan Supabase) dengan empat keadaan: seperti Supabase sekarang (karyawan dimuat, 9 pemeriksaan lulus), pasang ulang (semua dilewati), database kosong (semua dimuat), dan struktur setengah ada (berhenti dengan GAGAL). Skema `uji` tidak tertinggal.
2. ~~Gabung tahap-2b ke main~~ **Selesai (12 Nov 2026, 23.02 WIB)**: main maju lurus ke tahap-2b, uji otomatis di main lulus, workflow "Pasang ke Supabase" terdaftar aktif.
3. ~~Pemilik menjalankan pasang-supabase~~ **Selesai (12 Nov 2026, run #1)**: cadangan tersimpan (artifact `cadangan-sebelum-pasang-1`, 23 KB, sampai 12 Des 2026), migrasi dilewati, struktur dilewati, karyawan dimuat, pemeriksaan 9 lulus 0 gagal. Dicek langsung di Supabase: karyawan 1.044, riwayat 1.044, status kerja 1.088, penugasan regu 1.056, pemetaan ID mesin 1.045; skema `uji` tidak tertinggal; tidak ada transaksi menggantung.
4. **Cadangan malam: dibuat 12 Nov 2026, belum pernah dijalankan.** File: `.github/workflows/cadangan-malam.yml`, `db/uji_pemulihan.sh`, `db/hitung_baris.sql`. Jalan setiap hari pukul 02.20 WIB (dari main) dan lewat tombol. Isi: cadangan skema proyek (disimpan 14 hari) → pulihkan ke Postgres 17 kosong dengan `btree_gist` disiapkan dulu, berhenti pada galat pertama → jumlah baris setiap tabel harus sama dengan Supabase → sentuhan lewat jalur API (butuh secret `SUPABASE_PUBLISHABLE_KEY`; tanpa itu hanya peringatan). Diuji di Postgres 16 lokal: pemulihan 39 tabel/10.858 baris sama persis; database tujuan yang tidak kosong ditolak; cadangan lama (selisih baris) terdeteksi GAGAL.
5. ~~Pemilik menambah secret `SUPABASE_PUBLISHABLE_KEY` dan menjalankan Cadangan malam~~ **Selesai (12 Nov 2026, run #1, sekitar 1,5 menit)**: cadangan 256 KB tersimpan (artifact `cadangan-malam-1`, sampai 26 Nov 2026); pemulihan ke Postgres 17 kosong tanpa galat, 39 tabel/10.858 baris sama dengan Supabase (dicek ulang langsung di Supabase: 39 tabel, 10.858 baris). **Belum tuntas:** sentuhan API menjawab HTTP 401. Artinya proyek hidup dan menjawab, tetapi belum terbukti kuncinya diterima: halaman `/rest/v1/` kemungkinan memang menolak kunci publik (Kemungkinan Besar). **Diperbaiki 12 Nov 2026, 23.45 WIB:** sentuhan kini ke `/auth/v1/settings` dan hanya HTTP 200 yang lulus; secret kosong atau kunci salah membuat workflow gagal. Terbukti di run #2 (13 Nov 2026, 00.0x WIB, commit 1790ef8): HTTP 200, kunci publik diterima; cadangan dan pemulihan 39 tabel/10.858 baris kembali sama.
6. Tunggu 8 hari tanpa dipakai (paling cepat sekitar 21 Nov 2026) untuk gerbang "demo masih hidup".

## Paket 13 Nov 2026: tutup pintu + aturan baru

- Migrasi `0005_cabut_izin_fungsi.sql`: izin menjalankan fungsi proyek dicabut dari PUBLIC, termasuk untuk fungsi baru (aturan bawaan global, karena aturan per skema tidak bisa mencabut izin bawaan Postgres; kesalahan ini tertangkap uji otomatis sebelum dipasang).
- Uji otomatis `db/uji/030_akses_katalog.sql`: katalog izin kosong untuk anon/authenticated, fungsi baru tertutup, pemicu tetap mencatat jejak walau peran penulis tidak punya izin fungsi.
- `db/cek_akses.sql` + `db/uji_akses_supabase.sh`: uji "tanpa login ditolak" di Supabase sungguhan, tingkat database dan internet (kunci publik harus diterima di `/auth/v1/settings`, lalu 5 permintaan data harus ditolak). Dijalankan di Cadangan malam.
- Cadangan malam juga jalan otomatis setelah "Pasang ke Supabase" berhasil.
- "Pasang ke Supabase" bisa dipicu dorongan ke cabang `pasang`; ditolak kalau bukan commit terbaru main atau uji otomatisnya belum lulus. Rencana awal memakai tag `pasang-*`, tetapi pengiriman tag ditolak jalur akses Claude (HTTP 403); pemilik memilih cabang khusus.

**Hasil paket (13 Nov 2026, diukur):** uji otomatis 68 lulus/0 gagal (sekitar 70 detik); Pasang ke Supabase lewat cabang `pasang` sekitar 2 menit: cadangan dulu, hanya 0005 dipasang, pemeriksaan 9 lulus; Cadangan malam jalan otomatis sesudahnya sekitar 1,5 menit: pemulihan 39 tabel/10.859 baris sama, uji tanpa login LULUS di kedua tingkat (katalog izin kosong; 5 permintaan dengan kunci publik ditolak HTTP 406, kunci yang sama diterima HTTP 200 di `/auth/v1/settings`). Dicek langsung di Supabase: sidik 0005 `21b4bc7a231c` sama dengan repo; celah fungsi 0, celah tabel 0; aturan bawaan fungsi baru `{postgres=X/postgres}` (PUBLIC tidak ada); karyawan 1.044; skema `uji` tidak tertinggal.

**Gerbang "ambil data tanpa login ditolak": terbukti di Supabase sungguhan**, dan diuji ulang setiap malam.

## Paket 13 Nov 2026 (2): pemuat cepat + Reset Supabase

- `db/data_awal/muat_karyawan.py` sekarang memakai COPY: 5 perintah menggantikan 5.277 INSERT. Diukur: di Supabase cara lama 1.341 detik = 0,254 detik per perintah (perjalanan bolak-balik dari server GitHub). Isi kelima tabel karyawan identik dengan cara lama (sidik isi sama, termasuk nomor id); jejak perubahan identik kecuali jam pencatatan.
- Workflow "Reset Supabase" (`.github/workflows/reset-supabase.yml`, `db/reset_supabase.sh`): tombol + kata RESET, atau Claude mendorong main ke cabang `reset`. Cadangan dulu (30 hari) → pengaman: semua karyawan harus data simulasi (cocok ID dan nama), kalau tidak ditolak → kosongkan skema proyek → pasang dari nol → pemeriksaan. Jejak perubahan ikut terhapus, jadi hanya untuk demo.
- Pemeriksaan izin pemicu (tombol/cabang) dipindah ke `db/periksa_pemicu.sh`, dipakai bersama Pasang dan Reset. Keduanya berbagi antrean `ubah-supabase` supaya tidak jalan bersamaan.
- Cadangan malam juga jalan otomatis setelah Reset berhasil.
- Uji lokal (Postgres 16): reset penuh 2,6 detik, hasil 39 tabel/10.859 baris, celah akses 0; database dengan satu karyawan bukan simulasi ditolak dan tidak disentuh.
- **Dijalankan di Supabase (13 Nov 2026, 00.37–00.43 WIB, diukur):** uji otomatis 61 detik (68 lulus); Reset Supabase sekitar 3 menit (cadangan 48 detik, kosongkan 8 detik, pasang dari nol + data awal 106 detik; sebelumnya muat karyawan saja 22 menit); Cadangan malam jalan otomatis sesudahnya sekitar 1,5 menit: pemulihan 39 tabel/10.859 baris sama, uji tanpa login LULUS (katalog kosong, 5 permintaan ditolak HTTP 406). Dicek langsung di Supabase: migrasi 0001–0005 terpasang ulang pukul 00.39–00.40 dengan sidik sama seperti repo; 39 tabel/10.859 baris; karyawan 1.044; contoh 10001 Eka Susanto, PRD, Rp4.100.000, transfer; celah fungsi 0; skema `uji` tidak tertinggal; tidak ada transaksi menggantung.
- Catatan: 106 detik untuk pasang dari nol jauh di atas 2,6 detik di lokal. Dugaan (Kemungkinan Besar): `db/pasang.sh` dan pemeriksaan isi membuka koneksi baru untuk setiap perintah kecil (puluhan koneksi), dan tiap koneksi ke pooler dari server GitHub butuh beberapa detik. Belum diukur per langkah; tidak mendesak.

## Sisa gerbang Tahap 2

- ~~Tempat uji terpisah dari utama~~: diputuskan pemilik 13 Nov 2026, lihat tabel keputusan (tempat uji = Postgres sementara di GitHub untuk demo).
- ⏳ Demo masih hidup setelah 8 hari tanpa dipakai: berjalan di belakang, cek sekitar 21 Nov 2026 (cara cek: Supabase menjawab dan run Cadangan malam terjadwal tetap hijau setiap hari). Tidak menghalangi Tahap 3.

## Bentuk file asli (dicek 13 Nov 2026, isi pribadi tidak dicatat)

Kedua file ada di folder Drive tertutup "PROJECT ABSENSI" milik banajaka35@gmail.com. Hanya bentuknya yang dipakai.

**File 1: ekspor mentah mesin finger** ("absen feb. 2026.xls", 275 baris, 8 orang). Sama dengan PRD bagian 5.

| Kolom | Isi |
| --- | --- |
| Nama | nama karyawan |
| No.ID | **18 digit**, harus dibaca sebagai teks (celah M1) |
| Tgl/Waktu | `dd/mm/yyyy jj.mm.dd` (pemisah jam titik) |
| (tanpa judul) | jam yang sama tanpa detik; terbukti salinan kolom Tgl/Waktu di semua 275 baris |
| Status | `C/Masuk` (137) atau `C/Keluar` (138) |

Data simulasi (`data/simulasi/*/mesin/*.csv.gz`) sudah berbentuk sama persis (5 kolom, judul sama, cara tulis jam sama). **Beda satu: ID simulasi 5 digit, ID asli 18 digit.** Pembaca tap di Tahap 3 wajib diuji juga dengan ID 18 digit.

**File 2: rekap HRD yang disusun dari data mesin** (file .xlsx berisi satu orang, November 2025; nama file memuat nama orang sungguhan, jadi tidak ditulis di sini). Kolom: No.ID (18 digit), NIP (sama dengan No.ID), Nama, Tgl/Waktu (`dd/mm/yyyy jj.mm`, kadang dengan detik). Tanpa kolom Status. Berisi tap tercatat dua kali (sekali dengan detik, sekali tanpa) — contoh salah salin manual yang harus dibuang otomatis oleh aturan "buang dobel" (PRD bagian 7). Ini contoh bentuk keluaran yang biasa dilihat HRD, bukan masukan mesin.

**Pertanyaan terbuka untuk Tahap 6 (Sheets):** bentuk file 2 pada dasarnya daftar tap per orang, sedangkan PRD celah D4 melarang log tap mentah di Sheets. Pilihan: (a) tetap PRD: Sheets hanya rekap, rincian tap lewat rincian gaji atau keberatan; (b) tambah satu tab "rincian tap per orang" seperti file 2. Diputuskan pemilik di Tahap 6.

## Tahap 3 (13 Nov 2026): pembaca tap — lulus

Paket di-"buat" pemilik 13 Nov 2026 dengan keputusan 1a (perintah HRD dari file simulasi ikut diproses) dan 2 (koreksi jam MA2: uji dengan dan tanpa koreksi di GitHub, demo memakai koreksi).

| Hal | Isi |
| --- | --- |
| Kode | `sistem/urai/` (pembaca file), migrasi 0006 (`fakta.terima_kiriman`, tabel `hitung.*`, `hitung.baca_tap`), migrasi 0007 (sidik tidak bergantung zona sesi) |
| Uji | `db/uji/040_baca_tap.sql`, `sistem/urai/uji_urai.ts`, `sistem/uji/jalankan_simulasi.sh` (U1 dengan/tanpa koreksi, U4, U6, sidik); semua jalan di GitHub Actions setiap dorongan |
| Hasil uji | U1, U4, U6, B11/B12, sidik: lulus. 16 uji pembaca, 163 uji database, 9 uji simulasi |
| Supabase | Terpasang lewat cabang `pasang` (commit c8062f4, lalu 0007). 178.425 tap mentah, 119.853 hari-orang, 528 anomali. Cadangan malam sesudahnya: 43 tabel / 490.128 baris pulih sama persis, uji tanpa login lulus |
| Lama hitung | `baca_tap` satu periode Pabrik A: Supabase 12,2 detik, GitHub 6 detik, komputer kerja 4,4 detik |
| Menjalankan ulang | `select hitung.baca_tap(<id periode>)` menambah versi baru; tampilan `hitung.versi_terakhir` memberi versi yang dipakai |

**Syarat yang dibawa ke tahap berikutnya (dari temuan Tahap 3):**

- Tahap 4: Pabrik B butuh data awal struktur (divisi, jadwal 5 hari, rotasi Keamanan) sebelum U5; cuti bersama "potong cuti" (C02) dihitung bersama saldo cuti.
- Tahap 5: Edge Function memanggil `hitung.baca_tap` lewat **koneksi database langsung**, bukan jalur API (batas 8 detik; Supabase butuh 12,2 detik untuk Pabrik A). Pembuka .xls (SheetJS 0.20.x dari CDN SheetJS) dipasang di Edge Function dan meneruskan sel ke `uraiBarisEkspor`. Putuskan apakah file yang sama boleh dikirim ulang setelah kirimannya dibatalkan. Status periode (terbuka → menunggu data → dihitung) dijalankan antrean kerja.
- Tahap 7: arti "berhenti tgl X" = hari kerja terakhir (dipakai mesin baca tap, sesuai C11); PRD bagian 9 menulis "nonaktif sejak tanggal itu", perlu diseragamkan.
- Angka tetap di `hitung.baca_tap` (daftar di laporan Tahap 3, temuan 8) dipindah ke tabel aturan bila perusahaan perlu mengubahnya.

## Paket data aturan resmi (16 Nov 2026)

| Hal | Isi |
| --- | --- |
| File baru | `db/data_awal/aturan_resmi.sql`: kalender 2027 (18 libur nasional, 8 cuti bersama, SKB 15 Sep 2026) dan batas upah JP (10.547.400 Mar 2025–Feb 2026; 11.086.300 sejak 1 Mar 2026). Aman dijalankan berulang |
| Diubah | `db/pasang_supabase.sh` (file ini dijalankan setiap pemasangan, sesudah struktur Pabrik A), `db/uji/jalankan.sh` (dijalankan dua kali; jalan kedua harus tidak mengubah apa pun), `db/data_awal/cek_data_awal.sql` (kalender 2026 dihitung terpisah; 5 pemeriksaan baru untuk kalender 2027 dan JP) |
| Tidak diubah | `pabrik_a_struktur.sql`, migrasi, `sistem/uji/jalankan_simulasi.sh` (uji simulasi tidak memakai tanggal 2027 atau JP) |
| Keterbatasan | Baris JP lama hanya bisa ditutup per 2 Jan 2026, jadi 1 Jan 2026 tetap memakai angka lama (detail di `docs/cek-aturan-hukum.md` bagian 6) |
| Pasang ke Supabase percobaan 1 (run 43863851023) | **Gagal sebelum menyentuh Supabase**: langkah "Pasang klien Postgres 17" putus saat mengunduh kunci dari postgresql.org (`curl: (55) unexpected eof`). Cadangan dan migrasi tidak sempat jalan. Dugaan [Kemungkinan Besar]: gangguan jaringan sesaat. Diulang dengan commit berikutnya |
| Pasang ke Supabase percobaan 2 (run 43864833126, commit 8561407) | **Lulus**, sekitar 2,5 menit: cadangan dulu, semua migrasi dan data lama dilewati, data aturan resmi dijalankan, pemeriksaan 21 lulus 0 gagal. Cadangan malam otomatis sesudahnya: lulus |
| Dicek langsung di Supabase (16 Nov 2026, 19.2x WIB) | Kalender 2026 tetap 22 tanggal; 2027: 18 libur nasional + 8 cuti bersama. JP per bagian: 10.547.400 (1 Mar 2025–31 Des 2025), 10.547.000 (1 Jan 2026 saja), 10.547.400 (2 Jan–28 Feb 2026), 11.086.300 (sejak 1 Mar 2026). Jejak perubahan: 34 baris baru (26 kalender + 2 penutupan + 6 baris JP), sesuai. Karyawan 1.044 dan hasil harian 119.853 tidak berubah; skema `uji` tidak tertinggal; tidak ada transaksi menggantung |
| Uji lokal (Postgres 16) | `db/uji/jalankan.sh`: 184 lulus, 0 gagal. `pasang_supabase.sh pasang` di database kosong: semua dimuat, pemeriksaan 21 lulus, sekitar 32 detik; dijalankan ulang: semua dilewati, pemeriksaan 21 lulus, isi JP tetap 4 baris per bagian |

## Paket 4b-1 (16 Nov 2026): inti hitung gaji Pabrik A

Laporan lengkap: `docs/laporan-tahap-4b-1.md`. Aturan yang diikuti kode: `docs/aturan-hitung-gaji.md` (ditulis dan di-commit sebelum kode, commit 884c361).

| Hal | Isi |
| --- | --- |
| Kode | Migrasi 0009 (`hitung.hitung_gaji`, tabel `rincian_gaji` dan `ringkasan_gaji`, fungsi bagian, pengaturan `izin_dibayar` dan `pembulatan_pph21`); `db/pasang_supabase.sh` menghitung gaji setelah baca tap; `db/data_awal/cek_gaji.sql` |
| Uji | `db/uji/060_hitung_gaji.sql` (64 uji, kunci K1–K18), pembanding `sistem/uji/u2_pembanding.py` di uji simulasi |
| Hasil | Uji database 248 lulus; uji simulasi 12 lulus; pembanding 4.037 orang-periode selisih 0; GitHub lulus; Pasang ke Supabase lulus (pemeriksaan 26 lulus); Cadangan malam otomatis sesudahnya |
| Dicek langsung di Supabase | 0009 sidik `ce63fb99f40e` sama dengan repo; 4 versi gaji, masing-masing dari baca tap terakhir; 4.037 ringkasan, 57.189 rincian; total gaji bersih = total rincian di tiap periode; celah tabel dan fungsi gaji 0; skema `uji` tidak tertinggal; tidak ada transaksi menggantung |
| Lama hitung | Supabase 7,4–12,2 detik per periode (di atas batas 8 detik jalur API; Tahap 5 harus lewat koneksi langsung) |

**Keputusan pemilik 17 Nov 2026:** peringatan lembur dipisah; batas 4 jam/18 jam dan wajib makan hanya untuk lembur hari kerja (dikerjakan di 4b-2).

## Paket 4b-2 (17 Nov 2026): THR, denda, kasbon, batas potongan, tunai, peringatan lembur

Laporan lengkap: `docs/laporan-tahap-4b-2.md`. Aturan: `docs/aturan-hitung-gaji.md` versi 2 (commit 91d1a7f sebelum kode; uji GitHub commit itu sengaja gagal karena kode belum ada, tidak dipasang).

| Hal | Isi |
| --- | --- |
| Kode | Migrasi 0010 (`hitung_gaji` versi 2, kolom `sisa_lalu`, `hitung.versi_kode_gaji()`); `pasang_supabase.sh` menghitung ulang periode dengan versi kode lama, urut tanggal; `cek_gaji.sql` +2 pemeriksaan |
| Uji | `db/uji/070_gaji_thr_kasbon_tunai.sql` (31 uji, K19–K27); pembanding versi 2 |
| Hasil | Uji database 278 lulus; simulasi 12 lulus; pembanding 4.037 orang-periode selisih 0; GitHub lulus; Pasang lulus (pemeriksaan 28 lulus) |
| Dicek di Supabase | 0010 sidik `257d665d9cf9` = repo; versi gaji 2 untuk 4 periode; THR periode 2 Rp3.247.308.342 (990 orang); dibayar + sisa = bersih + sisa lalu untuk semua; periode 1, 3, 4 gaji bersih sama dengan versi 1 |

## Paket 4b-3 (17 Nov 2026): PPh masa terakhir, saldo cuti, pecahan tunai

Laporan lengkap: `docs/laporan-tahap-4b-3.md`. Aturan: `docs/aturan-hitung-gaji.md` versi 3 (commit 9629875 sebelum kode; uji GitHub commit itu gagal karena tabel baru belum ada, tidak dipasang).

| Hal | Isi |
| --- | --- |
| Kode | Migrasi 0011 (`hitung_gaji` versi 3, tarif Pasal 17, saldo cuti awal, `pecahan_tunai`, `periode_bisa_diajukan`) |
| Uji | `db/uji/080_gaji_masa_terakhir_cuti_tunai.sql` (33 uji, K28–K37); satu uji Desember di 060 disesuaikan ke aturan v3 |
| Hasil | Uji database 311 lulus; simulasi 12 lulus; pembanding 4.037 orang-periode selisih 0; GitHub lulus (6aa63b8); Pasang lulus |
| Dicek di Supabase | 0011 sidik `a87c245ed7d0` = lokal; versi gaji 3 untuk 4 periode; angka sama dengan lokal; semua periode tertahan karena data Januari tidak ada (sesuai aturan) |

**Temuan penting:** perusahaan yang mulai di tengah tahun butuh isian "data pajak awal tahun", kalau tidak PPh Desember tahun pertama selalu tertahan. Belum dikerjakan; usul masuk paket berikutnya.

## Paket 4b-4 (17 Nov 2026): Pabrik B (U5) dan tanda anomali gaji (U10)

Laporan lengkap: `docs/laporan-tahap-4b-4.md`. Aturan: `docs/aturan-hitung-gaji.md` versi 4 bagian O (commit de0e945 sebelum kode; uji GitHub commit itu gagal karena fungsi belum ada, tidak dipasang).

| Hal | Isi |
| --- | --- |
| Kode | Migrasi 0012 (`hitung.anomali_gaji`); data awal uji Pabrik B (tidak dipasang ke Supabase); pemuat perintah lembur; alat uji U1 mengenal 3 kejadian Pabrik B (izin pemilik 17 Nov 2026) |
| Uji | `db/uji/090_anomali_gaji.sql` (16 uji, K38–K46); uji simulasi U5 dan U10 (anomali ditanam di salinan data uji B) |
| Hasil | Uji database 327 lulus; simulasi 24 lulus; pembanding B 750 orang-periode selisih 0; GitHub lulus; Pasang lulus |
| Dicek di Supabase | 0012 sidik `781aa7127a34`; gaji A tidak berubah; tanda anomali A: periode 3 gaji berubah 430, periode 4 504 (terlalu ramai) |

**Keputusan pemilik 17 Nov 2026:** temuan 1–3 dikerjakan di paket 4b-5 (selesai). Temuan 4 (nilai menit perintah lembur, pembagi upah Gudang Pabrik B) masuk daftar pertanyaan HRD.

## Paket 4b-5 (17 Nov 2026): perbaikan temuan 4b-3 dan 4b-4

Laporan lengkap: `docs/laporan-tahap-4b-5.md`. Aturan versi 5, permintaan perubahan 02 (F13b, disetujui), kasus jebakan v1.3 (commit 2e5ca40 sebelum kode; uji GitHub commit itu gagal di F13b dengan kode lama, tidak dipasang).

| Hal | Isi |
| --- | --- |
| Kode | Migrasi 0013: pembaca tap versi 2 (F13b), tanda gaji berubah versi 5, `induk.pajak_awal_tahun`, hitung gaji versi 4; pemasangan membaca ulang bila versi pembaca tap berubah |
| Hasil | Uji database 343 lulus; simulasi 24 lulus; pembanding A dan B selisih 0; GitHub lulus; Pasang lulus |
| Dicek di Supabase | 0013 sidik `c1c60afc5221`; baca tap versi 2 dan gaji versi 4 di 4 periode; hasil harian 0 baris berbeda dari versi 1; gaji bersih tidak berubah; tanda gaji berubah 20/25/17 (sebelumnya 54/430/504) |

**Pertanyaan untuk HRD (kuesioner pemasangan / wawancara):** apakah lembur dibayar sampai menit yang disetujui di perintah lembur; untuk divisi 6 hari di perusahaan berpola 5 hari, apakah Sabtu ikut pembagi upah.

**Untuk 4c:** PPh Desember demo tertahan karena data simulasi hanya 4 periode; tulis terus terang di halaman demo.

Juga masih perlu: cek naskah resmi Permenaker 6/2016 dan PP 36/2021.

## Paket 4c (17 Nov 2026): halaman demo — selesai

Keputusan pemilik: salinan tetap (halaman tidak menyentuh Supabase), Cloudflare Pages proyek `future-absensi-demo`, unggah cadangan lewat web **dipindah ke Tahap 5** (syarat gerbang Tahap 4 berubah). Syarat: `docs/halaman-demo.md`.

| Hal | Isi |
| --- | --- |
| Selesai (commit 0cd1c9b) | `web/demo/index.html`, `web/buat_data.py`, `web/periksa_data.py`, workflow "Terbitkan demo"; uji simulasi 25 lulus (angka demo = gudang); GitHub lulus |
| Terbit | https://future-absensi-demo.pages.dev/ ; secret `CLOUDFLARE_API_TOKEN` (Pages: Edit) dan `CLOUDFLARE_ACCOUNT_ID` diisi pemilik; terbit otomatis sesudah Pasang lulus |
| Dicek | Halaman terbit dibandingkan langsung dengan Supabase: 4 periode sama persis; rincian per orang termuat. Laporan: `docs/laporan-tahap-4c.md` |
| Untuk pemilik | Sesuaikan syarat gerbang Tahap 4 di PRD (unggah cadangan lewat web pindah ke Tahap 5) |

## Tahap 5 (mulai 17 Nov 2026)

Dipecah (urutan sekarang): **5a** ukur dan percepat hitung · **5b** pintu Telegram, antrean, kirim ulang tidak dobel, file rusak ditolak, unggah cadangan lewat web (butuh bot dari @BotFather dan token akses Supabase untuk memasang Edge Function lewat workflow) · **5c** pemberitahuan tingkat segera (U14), pengingat kirim file · **5d** unggah cadangan lewat web (dari Tahap 4) · **5e** login email untuk halaman unggah (keputusan pemilik 17 Nov 2026: tautan dari bot dulu di 5d, email menyusul).

**5a selesai** (`docs/laporan-kecepatan-5a.md`): migrasi 0014 (hitung gaji versi 5), sidik hasil sama persis dengan versi 4 di keempat periode Supabase; hitung gaji di Supabase 11,7–18,8 detik menjadi 5,0–6,2 detik. Batas waktu: jalur API umum 8 detik, Edge Function dengan sambungan langsung 2 menit per perintah dan 150 detik per fungsi (dokumen resmi Supabase); laporan 4b yang menyebut 8 detik sebagai penghalang diralat.

**5b selesai** (`docs/laporan-tahap-5b.md`): bot Telegram "Abaensi" terpasang (Edge Function `pintu-telegram`, migrasi 0015–0017). Uji nyata 17 Nov 2026: kirim ulang file → ditolak dobel; file rusak Excel → ditolak; tombol pilihan mesin bekerja; balasan sekitar 2 detik; akun pemilik berhak akses `pembangun`. Jalur file baru belum diuji nyata (semua file simulasi sudah ada di demo). Kesalahan ditemukan di uji nyata: parameter jsonb di postgres.js (diperbaiki 616651f); `index.ts` belum punya uji otomatis (ditutup di 5c).

**5c selesai** (`docs/laporan-tahap-5c.md`, rancangan `docs/pemberitahuan-segera.md`): migrasi 0018, penjadwal pg_cron 08.00 WIB, workflow "Picu pengingat". Uji nyata 17 Nov 2026: file rusak Excel → kiriman no. 19 ditolak dan pemberitahuan segera `terkirim` (U14); pengingat dengan tanggal pura-pura 22-12-2026 terkirim untuk MA2, bos dicatat dilewati (gerbang "pengingat file terkirim"). Keputusan pemilik: penerima = semua akun aktif `hrd` dan `pembangun`; file ditolak Excel/format termasuk segera; pengingat hari ke-1 dan ke-2 jam 08.00 WIB, hari ke-2 juga ke bos (dicatat dilewati bila belum ada akun bos). Temuan: sesudah "Pasang ke Supabase", peran `pintu` sempat ditolak database sekitar 1–2 menit (kata sandi baru belum berlaku di pooler; Kemungkinan Besar). Akibat uji: pengingat sungguhan hari ke-2 tanggal 22-12-2026 untuk MA2 tidak akan dikirim lagi.

**5d selesai** (`docs/laporan-tahap-5d.md`, rancangan `docs/unggah-web.md`): migrasi 0019, perintah `/unggah` (tautan 15 menit, beberapa file), halaman https://future-absensi-demo.pages.dev/unggah/ . Uji nyata 17 Nov 2026: kiriman no. 20 (rusak Excel, asal web) ditolak dan pemberitahuan segera terkirim; kiriman no. 21 (dobel) ditolak; satu tautan dipakai 2 kali. File sah lewat web hanya diuji otomatis. Batas ukuran file di Edge Function belum diukur.

**Temuan terbuka (dari 5c dan 5d):** pesan Telegram pertama sesudah setiap "Pasang ke Supabase" gagal tanpa balasan ("password authentication failed for user pintu"); percobaan berikutnya berhasil. Penyebab Kemungkinan Besar: pooler menyimpan kata sandi lama sampai satu kali gagal. **Diperbaiki di paket 5d-2** (commit 61c79ff, `docs/laporan-tahap-5d.md` bagian 5d-2): coba ulang di Edge Function, pesan gangguan + 503, skrip pasang masuk sebagai `pintu` dulu. Uji nyata: pesan pertama sesudah pemasangan dibalas.

**Gerbang Tahap 5** (PRD bagian 17: "U14 lulus; pengingat file terkirim"): terpenuhi. Unggah cadangan lewat web (pindahan dari Tahap 4): ada (5d). 5e selesai (di bawah).

**5e selesai** (`docs/laporan-tahap-5e.md`, rancangan `docs/login-email.md`): migrasi 0020, masuk halaman unggah dengan kode 6 angka lewat email (Brevo), hasilnya tautan unggah 5d. Uji nyata 17 Nov 2026: kode email no. 6 dipakai, kiriman no. 22 (rusak Excel, asal web) ditolak dan pemberitahuan segera terkirim. Penyiapan Brevo oleh pemilik: kunci `future-absensi` (Transactional email Read/write, mati bila 90 hari tidak dipakai), pemblokiran IP untuk kunci API dimatikan, secret `BREVO_API_KEY` dan `PEMBANGUN_EMAIL`. Email yang gagal terkirim tidak lagi menghabiskan jatah: **diperbaiki di paket 5e-2** (migrasi 0021, uji nyata masuk lewat email lulus).

## Rencana Tahap 3 sampai 9 (PRD bagian 17)

⏳ = syarat yang menunggu waktu atau orang lain; berjalan di belakang (aturan 10).

| Tahap | Yang dibangun | Hasil yang bisa dilihat pemilik | Syarat ⏳ |
| --- | --- | --- | --- |
| 3 | ~~Pembaca tap: pemetaan ID mesin, koreksi jam mesin, cek cakupan file~~ **Selesai 13 Nov 2026** | Tabel hadir/telat/lupa tap/alpha per orang per hari (U1, U4, U6; kasus 20→21 Maret) | U9 dipindah ke berjalan berdampingan (keputusan di atas) |
| 4 | 4a ✓ cek hukum + TER/PTKP · 4b-1 ✓ inti hitung gaji Pabrik A · 4b-2 ✓ THR, kasbon, tunai · 4b-3 ✓ PPh Desember, saldo cuti, U12 · 4b-4 ✓ Pabrik B, U10 · 4b-5 ✓ perbaikan temuan · 4c ✓ halaman demo (unggah cadangan lewat web pindah ke Tahap 5) | Angka gaji per orang dan halaman web pertama (U2, U3, U5, U10) | ~~TER/PTKP~~ ✓; ~~batas JP, kalender 2027~~ ✓; naskah resmi UU 27/2026 di Drive; keputusan permintaan perubahan 01; U2 pembanding manusia dipindah ke berjalan berdampingan |
| 5 | Pintu Telegram untuk file, antrean kerja, pemberitahuan segera, unggah cadangan lewat web (dari Tahap 4), hitung di bawah batas 8 detik API | Bot menjawab "file diterima" | Pemilik membuat bot di @BotFather dan memasukkan token ke secret GitHub |
| 6 | Rekap Sheets, lembar siap cetak, file bank, bahan tunai | Sheets terisi otomatis | Keputusan (a)/(b) di atas |
| 7 | ~~Perintah HRD lewat chat~~ **Selesai 23 Nov 2026** (gerbang lulus 22 Nov; 7a, 7b, 7c-1, 7c-2, 7d; `docs/laporan-tahap-7.md`) | Koreksi lewat chat | — |
| 8 | Pendaftaran karyawan, pesan gaji, keberatan, rilis dengan PIN | Rincian gaji sampai ke Telegram | — |
| 9 | Web penuh, coba aturan, paket pasang | Web siap didemokan | U11 waktu operator; wawancara 2–3 HRD (hanya untuk angka penghematan) |

Cara kerja yang disepakati: satu "buat" per tahap dengan daftar paket lengkap; di akhir tiap tahap pemilik melihat bukti (jumlah baris di Supabase, 3 contoh orang lengkap, hasil uji). Tiap tahap sebaiknya dimulai di chat baru dengan kalimat:

> Baca CLAUDE.md dan docs/serah-terima.md di repo banajaka35-design/Future-ABSENSI cabang main. Lalu tulis daftar paket Tahap 4 lengkap untuk saya "buat".

## Sebelum dipasang untuk perusahaan sungguhan

Workflow pasang-supabase bentuknya sudah bisa dipakai ulang, tetapi isinya masih khusus demo. Yang harus diubah sebelum perusahaan pertama (sesuai PRD bagian 13, 15, 18):

| Hal | Sekarang (demo) | Untuk perusahaan sungguhan | Kapan |
| --- | --- | --- | --- |
| Data awal | CSV karangan Pabrik A di repo | Data asli tidak boleh masuk repo; masuk lewat template unggah, Drive tertutup, atau bot | Tahap 9 (paket pasang) |
| Secret | Satu `SUPABASE_DB_URL` | Satu secret per perusahaan (kemungkinan lewat GitHub Environments); workflow memilih pemasangan | Saat pemasangan pertama |
| Cadangan | Artifact GitHub 14–30 hari, terenkripsi sejak E1 (`docs/cadangan.md`) | Tidak boleh untuk data gaji asli; Supabase Pro + cadangan sendiri di tempat tertutup | Sebelum klien pertama |
| Kecepatan muat | Sudah memakai COPY (13 Nov 2026) | Tetap; data asli masuk lewat jalur unggah, bukan CSV di repo | Selesai untuk demo |
| Wilayah Supabase | Mumbai | Dipilih saat membuat proyek klien; Singapura kemungkinan lebih dekat (Kemungkinan Besar) | Saat membuat proyek klien |
| Pemilik akun | Akun pembangun (banajaka35) | Akun milik perusahaan, pembangun diundang sebagai pengelola | Saat pemasangan pertama |
| Pengirim email kode (5e) | Brevo gratis, pengirim alamat Gmail pemilik | Domain sendiri yang diverifikasi di Brevo (supaya tidak masuk Spam); kunci Brevo milik perusahaan | Sebelum klien pertama |
| Hak akun pembangun | Akun pembangun (pemilik) bisa semua, termasuk menyetujui rilis seperti bos (keputusan pemilik 19 Nov 2026) | Diputuskan ulang: aturan "dua orang" (HRD mengajukan, bos menyetujui) tidak berlaku bila pembangun mengajukan dan menyetujui sendiri | Saat pemasangan pertama |
| Halaman demo publik (D1) | Terbit otomatis ke pages.dev sesudah setiap Isi Sheets; pengaman `db/cek_hanya_simulasi.sh` menolak terbit bila ada satu saja karyawan bukan simulasi | Proyek perusahaan tidak memakai workflow Terbitkan demo sama sekali; pengaman tetap dipasang di proyek demo | Sebelum klien pertama |
| Akses Sheets untuk HRD (T2) | Editor hanya akun pemilik, akun konektor Claude, dan akun layanan | HRD diberi akses **lihat saja**: riwayat versi (yang bisa memuat gaji orang yang belakangan dijadikan rahasia) hanya terbuka untuk akun dengan hak edit [Kemungkinan Besar] | Saat pemasangan pertama |
| Akses pembangun dan Claude ke gaji | Pembangun dan sesi Claude (penyambung Supabase, Sheets) bisa membaca semua gaji, termasuk orang rahasia | Pembangun tidak membaca gaji perusahaan kecuali diizinkan; penyambung Claude hanya dipakai untuk proyek demo | Saat pemasangan pertama |

## Belum dikerjakan, ditunda

- ~~Tabel TER dan PTKP~~: terisi lewat migrasi 0008 (paket 4a).
- ~~Batas upah Jaminan Pensiun dan kalender 2027~~: dibetulkan dan dimuat di paket "data aturan resmi" (16 Nov 2026).
- Peringatan advisor `public.rls_auto_enable()` adalah bawaan Supabase, dibiarkan.

## Sisa tes sambungan

- Sel A1 Google Sheets "PROJECT ABSENSI": sudah dikosongkan (13 Nov 2026).
- File "TES CLAUDE - boleh dihapus.txt" di Drive: sudah dipindah ke Sampah (13 Nov 2026).
- Cabang `tes-claude`: sudah dihapus pemilik (13 Nov 2026).
