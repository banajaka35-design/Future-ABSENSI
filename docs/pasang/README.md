# Panduan memasang sistem untuk PT baru

Paket 9d, 25 November 2026. Pintu masuk untuk siapa pun (pemilik proyek atau sesi Claude) yang memasang sistem untuk perusahaan
sungguhan. Baca bersama `CLAUDE.md` (aturan kerja). Semua aturan kerja repo tetap berlaku di repo PT.

## Prinsipnya

- **Kode sistem dipakai ulang tanpa diubah**: pembaca file mesin, mesin hitung gaji, bot Telegram, web HRD, rekap Sheets, dan
  semua uji.
- **Yang dibuat baru per PT** hanya: susunan perusahaan (aturan dan jadwal PT), data karyawan, dan akun atas nama PT.
- **Data karyawan asli tidak pernah masuk repo.** Data simulasi Pabrik A/B tetap di repo karena dipakai uji, tetapi tidak bisa
  termuat ke database PT: di repo yang bukan repo demo, Pasang menolak berjalan sebelum susunan PT ditunjuk (penjaga 9d).

## Kalimat pembuka untuk Claude

> Baca CLAUDE.md dan docs/pasang/README.md di repo <akun-PT>/absensi-pt-abc. Ini pemasangan PT ABC. Kerjakan langkah <nomor>.
> Jawaban wawancara HRD terlampir.

## Langkah

| No | Langkah | Dokumen | Siapa |
| --- | --- | --- | --- |
| 1 | Wawancara HRD dengan daftar pertanyaan; minta satu contoh file mesin dan rekap gaji manual satu periode; periksa contoh file dengan `node sistem/urai/cek_file.ts FILE` (tidak menyimpan apa pun) | `1-pertanyaan-hrd.md` (A5) | Pemilik proyek + HRD; Claude memeriksa file |
| 2 | Buat repo privat PT dan salin repo ini ke sana; matikan workflow khusus demo | `2-daftar-periksa-akun.md` | PT/pemilik membuat repo; Claude menyalin |
| 3 | Buat akun atas nama PT dan isi secret | `2-daftar-periksa-akun.md` | Pemilik proyek + PT |
| 4 | Susun file susunan PT dari jawaban wawancara | bagian "Langkah 4" di bawah | Claude |
| 5 | HRD mengisi templat karyawan | `4-isi-templat.md`, `templat/` | HRD |
| 6 | Pasang ke Supabase PT | bagian "Langkah 6" di bawah | Claude, lewat workflow |
| 7 | Uji banding 1–2 periode dengan hitungan manual HRD | `5-uji-banding.md` | HRD + Claude |
| 8 | Serahkan petunjuk pemakaian ke HRD | `6-petunjuk-hrd.md` | Pemilik proyek |
| – | Perawatan tahunan dan menarik perbaikan kode | `7-perawatan.md` | Pemilik proyek + Claude |

## Langkah 4: menyusun file susunan PT

1. Salin `db/data_awal/pabrik_b_struktur.sql` (paling sederhana: satu mesin, empat divisi, ada periode; Pabrik A bila PT punya
   jadwal kantor Sabtu pendek atau jadwal Ramadan) menjadi
   `db/data_awal/pt_<nama>_susunan.sql` di repo PT.
2. Ganti setiap bagian dengan jawaban wawancara, mengikuti baris "Isian" di `1-pertanyaan-hrd.md`. Beri komentar nomor
   pertanyaan asal di setiap bagian (misalnya `-- B3: jam kerja`), supaya mudah dicocokkan saat uji banding.
3. Bagian yang **tidak** diganti (aturan pemerintah): kalender libur nasional dan cuti bersama, pengali lembur, dan tarif BPJS.
   Angka resmi terbaru (batas JP, kalender tahun berikutnya) ditambahkan sendiri oleh `db/data_awal/aturan_resmi.sql` saat Pasang.
4. File berisi periode pertama (pertanyaan D3).
5. Coba di database sementara sebelum Pasang (uji di repo PT):

   ```
   GITHUB_REPOSITORY=<akun-PT>/absensi-pt-abc SUSUNAN_PERUSAHAAN=db/data_awal/pt_<nama>_susunan.sql \
     DATA_KARYAWAN=<folder templat terisi, di luar repo> DB_URL=<database sementara> db/pasang_supabase.sh pasang
   ```

   Hasilnya harus "Pemeriksaan: 11 lulus, 0 gagal".

## Langkah 6: Pasang ke Supabase PT

- Workflow "Pasang ke Supabase" di repo PT diberi isian `SUSUNAN_PERUSAHAAN` dan `DATA_KARYAWAN`. Tanpa isian itu, Pasang di repo
  PT **ditolak** sebelum database disentuh (dibuktikan uji "9d: pemasangan di repo PT tanpa susunan" di
  `sistem/uji/jalankan_simulasi.sh`).
- Pasang perusahaan memuat: migrasi, susunan PT, aturan pemerintah, karyawan PT. **Tidak** memuat data simulasi, isian pajak
  karangan, dan tidak menghitung apa pun; periode dihitung saat file mesin pertama masuk lewat bot.
- Pasang aman diulang: susunan dan karyawan yang sudah ada dilewati, tidak dobel.

## Bila aturan PT tidak cocok dengan sistem

Contoh: upah harian/borongan, tunjangan yang bukan uang makan/premi/shift malam, pola jadwal yang tidak bisa ditulis sebagai
siklus. **Berhenti dan laporkan ke pemilik proyek sebagai temuan.** Jangan diakali dengan data (misalnya memasukkan tunjangan ke
gaji pokok), karena akan merusak dasar lembur, BPJS, dan PPh.

## Belum ada (temuan 9d, harus dibuat sebelum PT pertama; P1 sudah selesai)

| No | Yang belum ada | Akibatnya | Usulan |
| --- | --- | --- | --- |
| P1 | ~~Periode bulanan otomatis~~ **Selesai 25 Nov 2026** (`docs/laporan-p1.md`): periode berikutnya dibuat saat file mesin masuk | – | – |
| P2 | **Jalur memuat data karyawan asli** tanpa masuk repo | Langkah 6 belum bisa dijalankan dengan data sungguhan | Diputuskan bersama PT: folder tertutup + workflow, atau lewat bot |
| P3 | **Mengubah aturan PT di database yang sudah terpasang** | Kesalahan aturan saat uji banding tidak bisa diperbaiki lewat workflow | Paket kecil: file perubahan aturan PT yang dijalankan setiap Pasang |
| P4 | **Terbit web HRD ke alamat PT** | Web HRD hanya ada di situs demo; bot tetap bisa dipakai | Paket kecil: workflow terbit ke proyek Cloudflare PT dan `ASAL_WEB` |
| P5 | **Kolom BPJS, jabatan, saldo cuti awal di templat** | Harus diubah per orang lewat web HRD sesudah pasang | Kolom tambahan yang boleh kosong di pemuat |
| P6 | **Isian pajak awal tahun untuk PT** | PPh akhir tahun tertahan bila sistem mulai di tengah tahun | Templat isian pajak awal tahun |
| P7 | **Workflow Pasang membaca isian PT** | Isian `SUSUNAN_PERUSAHAAN`/`DATA_KARYAWAN` belum diteruskan oleh workflow | Diubah di repo PT saat P2 diputuskan |

Ketujuhnya sengaja tidak dikerjakan di 9d karena bentuknya bergantung pada PT (keputusan pemilik 25 Nov 2026: siapkan kerangka,
jangan bangun yang belum jelas kebutuhannya).
