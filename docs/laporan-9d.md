# Laporan paket 9d: kerangka pasang untuk PT baru

Di-"buat" 25 November 2026 13.38 WIB, commit kode c9ff51e, menurut `docs/rencana-9d.md` versi 2 (diperbarui 13.37). Tidak ada pemasangan Supabase,
tidak ada migrasi, tidak ada perubahan Edge Function. Sidik gaji periode 4 di Supabase tetap `c427e5a53c5f`.

## Yang dibuat

| No | Isi | File |
| --- | --- | --- |
| 1 | Daftar pertanyaan HRD: 38 pertanyaan dalam 8 kelompok (A–H), setiap pertanyaan dengan contoh Pabrik A dan isian sistem | `docs/pasang/1-pertanyaan-hrd.md` |
| 2 | Daftar periksa akun: biaya yang disepakati dulu, repo privat (bukan Fork, Claude yang menyalin), workflow yang dimatikan, yang boleh dan tidak boleh dihapus, akun Supabase/Telegram/Sheets/Brevo atas nama PT, 11 secret, keputusan yang diambil ulang | `docs/pasang/2-daftar-periksa-akun.md` |
| 3 | Cara pasang memilih perusahaan + penjaga | `db/pasang_supabase.sh`, `db/data_awal/muat_karyawan.py` |
| 4 | Templat karyawan (3 file CSV, judul kolom sama dengan data simulasi) dan cara mengisinya | `docs/pasang/templat/`, `docs/pasang/4-isi-templat.md` |
| 5 | Cara uji banding 1–2 periode | `docs/pasang/5-uji-banding.md` |
| 6 | Petunjuk pemakaian HRD (bot dan web) | `docs/pasang/6-petunjuk-hrd.md` |
| 7 | Perawatan tahunan dan cara menarik perbaikan kode ke repo PT | `docs/pasang/7-perawatan.md` |
| 8 | Panduan utama: alur 8 langkah, kalimat pembuka untuk Claude, cara menyusun file susunan PT, daftar yang belum ada | `docs/pasang/README.md` |

### Perubahan kode (isi 3)

- `db/pasang_supabase.sh`:
  - isian baru `SUSUNAN_PERUSAHAAN` (file SQL susunan PT) dan `DATA_KARYAWAN` (folder templat terisi);
  - **penjaga**: tanpa `SUSUNAN_PERUSAHAAN`, data simulasi Pabrik A hanya dimuat bila `GITHUB_REPOSITORY` =
    `banajaka35-design/future-absensi` (diisi otomatis oleh GitHub Actions). Di repo lain, atau di luar GitHub, pemasangan ditolak
    (kode keluar 3) **sebelum database disentuh**. Penanda sengaja bukan file di repo, karena file ikut tersalin ke repo PT;
  - pemasangan perusahaan: migrasi → susunan PT → aturan pemerintah (`aturan_resmi.sql`) → karyawan PT → 11 pemeriksaan
    (mesin, divisi, periode, UMK, BPJS, karyawan, riwayat, regu, ID mesin untuk wajib tap, orang rahasia dibayar transfer).
    Tidak memuat data simulasi, isian pajak karangan, dan tidak menghitung; aman diulang;
  - perintah `mode` menulis jenis pemasangan tanpa menyentuh database (dipakai uji).
- `db/data_awal/muat_karyawan.py`: menerima nama folder selain `A`/`B`; `mutasi_regu.csv` boleh tidak ada; membaca CSV ber-BOM
  dari Excel. Keluaran untuk Pabrik A dan B **sama persis** dengan versi lama (md5 `ca5e1bdd…` dan `8743bdbb…`).

## Hasil uji [Pasti, diukur 25 Nov]

| Uji | Hasil |
| --- | --- |
| Database lokal (`db/uji/jalankan.sh`) | 917 lulus, 0 gagal (sama dengan sebelum) |
| Simulasi lokal (`jalankan_simulasi.sh`) | 153 lulus, 0 gagal (139 + 14 baru) |
| Jalur demo lengkap di database lokal (`GITHUB_REPOSITORY` demo, tanpa susunan) | Pemeriksaan 33 lulus, 0 gagal; **sidik gaji periode 1–4 = Supabase** (`d7a6e443b8c5`, `c642bd4a9b7c`, `45a6ca644ca5`, `c427e5a53c5f`) |
| GitHub "Uji database" | commit c9ff51e, run 45566189081: success (database 917, simulasi 153, pemicu 12, pemulihan cadangan 10; semua 0 gagal) |

Pemeriksaan baru di uji simulasi (14):
- penjaga: repo demo → demo; repo lain, di luar GitHub, atau susunan tanpa folder karyawan → ditolak; Pasang di repo PT tanpa
  susunan berhenti dengan kode 3 dan database tetap tanpa skema proyek;
- U5 Pabrik B kini dipasang **lewat jalur PT**: pemeriksaan pemasangan 11/11; tidak ada mesin MA*, periode Pabrik A, isian pajak,
  atau hitungan saat pasang; Pasang ulang melewati susunan dan karyawan. Sesudah itu U5/U1 (kunci jawaban), U5/U2 (pembanding
  sampai rupiah), U5/U3 tetap lulus. Catatan: jalur PT ikut menjalankan `aturan_resmi.sql`, yang dulu tidak dijalankan untuk
  Pabrik B di uji; U5 tetap lulus;
- kerangka: semua dokumen yang ditunjuk README ada; 18 tabel susunan Pabrik A/B dan 16 kunci pengaturan semuanya disebut di
  paragraf "Isian" daftar pertanyaan; judul kolom templat = data simulasi; setiap kolom templat dijelaskan.
  Uji pertanyaan dibuktikan bisa gagal: `aturan.thr` dan `izin_dibayar` dihapus sementara → GAGAL menyebut keduanya.

### Uji coba manual panduan (gerbang 3 Tahap 9, cara manusia)

1. Claude menjawab 38 pertanyaan untuk Pabrik B dari `docs/data-simulasi.md` dan `data/simulasi/B/induk/` (jawaban di luar repo).
2. Mengikuti README langkah 4, tetapi **menyalin file Pabrik A** (bukan Pabrik B seperti saran README), supaya tidak sekadar
   menyalin jawaban yang sudah benar; setiap bagian diganti dari jawaban.
3. Templat terisi = salinan CSV Pabrik B di folder sementara di luar repo.
4. Pasang dengan `GITHUB_REPOSITORY=pt-uji/absensi-pt-b`: pemeriksaan 11 lulus, 0 gagal.
5. Dibandingkan dengan pemasangan dari `pabrik_b_struktur.sql` tulisan tangan: **23 tabel sama persis** (susunan, aturan,
   periode, karyawan, riwayat, status kerja, regu, ID mesin).

Langkah yang macet dan sudah diperbaiki di dokumen:
- pola hari kerja bisa berbeda per divisi (Pabrik B: Gudang 6 hari) → pertanyaan B7 diperluas;
- pengaturan bisa berubah di tengah tahun (cuti bersama Pabrik B) → catatan bertanggal di C2;
- kalender libur nasional ada di file susunan dan tidak boleh diganti → README langkah 4 butir 3.

## Temuan (dicatat di `docs/pasang/README.md` bagian "Belum ada")

Semua [Pasti, diperiksa di kode], sengaja tidak dikerjakan di 9d karena bentuknya bergantung pada PT:

| No | Temuan |
| --- | --- |
| P1 | **Tidak ada pembuatan periode bulanan otomatis.** Periode hanya dari data awal (`pabrik_a_tahap3.sql`, susunan Pabrik B). Demo punya 4 periode tetap. PT pertama butuh paket kecil sebelum periode kedua |
| P2 | Jalur memuat data karyawan asli tanpa masuk repo belum ada |
| P3 | Aturan PT di database yang sudah terpasang tidak bisa diubah lewat workflow (Pasang melewati susunan yang sudah terisi) |
| P4 | Web HRD hanya terbit ke situs demo; `ASAL_WEB` bawaannya situs demo |
| P5 | Templat belum punya kolom BPJS, jabatan, saldo cuti awal (pemuat tidak membacanya) |
| P6 | Isian pajak awal tahun untuk PT belum ada templatnya |
| P7 | Workflow Pasang belum meneruskan `SUSUNAN_PERUSAHAAN`/`DATA_KARYAWAN` (di repo PT Pasang akan ditolak sampai diubah, sesuai penjaga) |

Temuan lain: hanya `tipe_upah = bulanan` yang dihitung mesin gaji (`hitung.hitung_gaji` tidak membaca `tipe_upah`)
[Kemungkinan Besar]; upah harian/borongan dicatat sebagai "aturan PT tidak cocok" di README.

## Yang belum

- Gerbang 1 Tahap 9 ("HRD menjalankan satu bulan penuh tanpa bantuan"): menunggu PT pertama (aturan 10).
- P1–P7 di atas, sebelum PT pertama.
- Daftar pertanyaan belum diuji ke HRD sungguhan.
