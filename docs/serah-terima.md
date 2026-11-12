# Catatan serah terima

File ini ditulis supaya siapa pun yang melanjutkan proyek (manusia, Claude di chat lain, atau Claude di sesi baru) tahu posisi terakhir tanpa harus membaca riwayat chat. **Perbarui file ini setiap kali satu langkah selesai.**

Terakhir diperbarui: 13 November 2026, 02.40 WIB, cabang `main` (Tahap 3 selesai dan terpasang di Supabase).

## Aturan sebelum mengubah apa pun

1. Tarik isi GitHub terbaru, lalu baca `CLAUDE.md` dan file ini.
2. **GitHub adalah satu-satunya sumber kebenaran.** Apa pun yang dipasang ke Supabase harus sudah ada di GitHub lebih dulu, dan dipasang lewat workflow "Pasang ke Supabase", bukan langsung dari chat (aturan 8 di CLAUDE.md). Claude memicunya dengan mendorong main ke cabang `pasang` setelah "buat" untuk paket yang menyebut pemasangan.
3. **Satu proyek dikerjakan di satu chat dalam satu waktu.** Kalau berpindah chat, mulai dari file ini.
4. Setiap perubahan dijelaskan ke pemilik proyek dalam satu paragraf bahasa sederhana: apa yang diubah, kenapa, dan cara mengeceknya.

Alasan aturan 2–4: pada 12 Nov 2026 pukul 21.14–21.16 WIB, migrasi 0001–0004 dipasang ke Supabase oleh sesi Claude lain, dan file 0004 tidak dikirim ke GitHub. Pemilik proyek tidak tahu perubahan itu terjadi. File asli ditemukan kembali dan sidiknya cocok (lihat di bawah).

## Posisi sekarang: Tahap 3 (pembaca tap) lulus dan terpasang; berikutnya Tahap 4

Ringkasan Tahap 3 ada di bagian "Tahap 3" di bawah dan lengkapnya di `docs/laporan-tahap-3.md`.

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

## Rencana Tahap 3 sampai 9 (PRD bagian 17)

⏳ = syarat yang menunggu waktu atau orang lain; berjalan di belakang (aturan 10).

| Tahap | Yang dibangun | Hasil yang bisa dilihat pemilik | Syarat ⏳ |
| --- | --- | --- | --- |
| 3 | ~~Pembaca tap: pemetaan ID mesin, koreksi jam mesin, cek cakupan file~~ **Selesai 13 Nov 2026** | Tabel hadir/telat/lupa tap/alpha per orang per hari (U1, U4, U6; kasus 20→21 Maret) | U9 dipindah ke berjalan berdampingan (keputusan di atas) |
| 4 | Hitung gaji, halaman demo sederhana, unggah cadangan lewat web | Angka gaji per orang dan halaman web pertama (U2, U3, U5, U10) | Tabel TER/PTKP dan batas JP 2026 dicek ke sumber resmi; U2 pembanding manusia dipindah ke berjalan berdampingan |
| 5 | Pintu Telegram untuk file, antrean kerja, pemberitahuan segera | Bot menjawab "file diterima" | Pemilik membuat bot di @BotFather dan memasukkan token ke secret GitHub |
| 6 | Rekap Sheets, lembar siap cetak, file bank, bahan tunai | Sheets terisi otomatis | Keputusan (a)/(b) di atas |
| 7 | Perintah HRD lewat chat | Koreksi lewat chat | — |
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
| Cadangan | Artifact GitHub 30 hari | Tidak boleh untuk data gaji asli; Supabase Pro + cadangan sendiri di tempat tertutup | Sebelum klien pertama |
| Kecepatan muat | Sudah memakai COPY (13 Nov 2026) | Tetap; data asli masuk lewat jalur unggah, bukan CSV di repo | Selesai untuk demo |
| Wilayah Supabase | Mumbai | Dipilih saat membuat proyek klien; Singapura kemungkinan lebih dekat (Kemungkinan Besar) | Saat membuat proyek klien |
| Pemilik akun | Akun pembangun (banajaka35) | Akun milik perusahaan, pembangun diundang sebagai pengelola | Saat pemasangan pertama |

## Belum dikerjakan, ditunda

- Tabel TER dan PTKP: Tahap 4.
- Data awal struktur Pabrik B: Tahap 4 (U5).
- Batas upah Jaminan Pensiun 2026: perlu dicek.
- Peringatan advisor `public.rls_auto_enable()` adalah bawaan Supabase, dibiarkan.

## Sisa tes sambungan

- Sel A1 Google Sheets "PROJECT ABSENSI": sudah dikosongkan (13 Nov 2026).
- File "TES CLAUDE - boleh dihapus.txt" di Drive: sudah dipindah ke Sampah (13 Nov 2026).
- Cabang `tes-claude`: sudah dihapus pemilik (13 Nov 2026).
