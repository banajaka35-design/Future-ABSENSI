# Laporan paket F2: HRD mengonfirmasi format file baru sekali lewat bot

Rencana: `docs/rencana-f2-konfirmasi-format.md`, di-"buat" 25 Nov 2026 16.46 dengan K1 (a) bot saja, K2 (a) HRD dan pembangun
boleh menyimpan profil, K3 (a) judul kolom berubah ditanyakan lagi. Permintaan perubahan 07 (kasus F09) disetujui sebelumnya.
Kasus jebakan lain tidak diubah.

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Migrasi 0044 `db/migrasi/0044_profil_format_mesin.sql` | `induk.profil_file_mesin` (satu profil aktif per mesin + sidik judul kolom; tidak bisa dihapus atau diubah isinya, hanya dinonaktifkan dengan siapa/kapan/alasan; jejak perubahan), `fakta.konfirmasi_format` (percakapan per file yang ditahan), fungsi `api.pintu_profil_mesin`, `pintu_konfirmasi_mulai/ambil/ubah/selesai`, `pintu_profil_daftar/hapus` (grant ke `pintu`) |
| Pembaca `sistem/urai/urai.ts` | `uraiTabel` menerima profil (kolom ID, tanggal-jam atau tanggal + jam, susunan dmy/mdy/ymd; baris judul dicari dengan sidik judul yang sama persis). Tanpa profil aturan F1 berlaku apa adanya: F09 tetap ditolak, kini membawa judul kolom, sidik, dan analisa isi kolom. Rekap, kolom ganda, dan file bukan tabel tidak membawa judul (C6). CSV dengan judul tak dikenal memilih pemisah yang memberi judul calon paling banyak kolom (alasan tolak tetap sama) |
| Bot `sistem/pintu/inti.ts` | File ditahan (belum dicatat sebagai kiriman), pembangun diberi tahu; HRD pengirim memilih kolom ID → tanggal-jam (atau dua kolom) lewat tombol `x|<no>|<aksi>|<nilai>` atau "Lainnya, ketik sendiri" (`force_reply`, ketikan hanya dicocokkan dengan judul yang ada); susunan tanggal ditanya hanya bila bisa dibaca dua cara (contoh nyata dari file); tanggal yang bercampur → tidak bisa disimpan (Pilih ulang / Tidak); contoh hasil bacaan 3 tap (awal, tengah, akhir) dengan nama hari + ringkasan, tanpa nama karyawan; "Ya, simpan" → profil disimpan, pembangun diberi tahu dengan contoh, file dihitung; "Tidak" → file ditolak format tidak dikenal + pemberitahuan segera; tombol lama tidak berlaku (dijaga database); `/profilmesin` (pembangun) daftar + Hapus |
| Halaman unggah | Memakai profil yang sudah disimpan lewat bot; format baru tanpa profil ditolak dengan arahan "kirim sekali lewat bot" (pemberitahuan segera) |
| Dokumen | `docs/pasang/6-petunjuk-hrd.md`, `docs/pasang/1-pertanyaan-hrd.md` (A5) |

Tambahan kecil di luar teks rencana (tidak mengubah gaji, tidak membatasi akun pembangun): tombol "Pilih ulang" di contoh hasil
bacaan; halaman unggah ikut memakai profil.

## Uji

| Uji | Sebelum | Sesudah |
| --- | --- | --- |
| Pembaca `node --test sistem/urai/uji_urai.ts` | 25 | 35 (uji lama tidak diubah) |
| Database `db/uji/jalankan.sh` | 936 | 984 (`db/uji/360_profil_format.sql`, 48) |
| Pintu `sistem/uji/uji_pintu.sh` | 125 | 134 |
| Simulasi | 153 | 153 |

Semua 0 gagal, lokal dan GitHub (commit 62dba10, uji 45597395468; penyambung 24, pemicu 12, pemulihan 10, cadangan 9, grafik 6).
Pasang run 45599553865. Dicek di Supabase [Pasti]: migrasi 0044 terpasang 25 Nov 18.00 WIB, sidik file `49eb88910dc2` = repo;
sidik gaji periode 1–4 tetap 1:d7a6e443b8c5 2:c642bd4a9b7c 3:45a6ca644ca5 4:c427e5a53c5f.

## Uji nyata 25 Nov 2026 20.25–20.33 WIB — LULUS [Pasti]

File data demo karangan (periode 3 mesin MA2, judul "Nama, No.ID, Waktu, Status" = bentuk F09) dikirim pemilik dari akun pembangun.

1. `A_p3_MA2_formatbaru.xlsx` → bot: judul belum dikenal, file ditahan, konfirmasi no. 1. Supabase: konfirmasi menunggu, langkah id,
   sidik `nama|noid|waktu|status`, 0 kiriman.
2. Tombol No.ID → Supabase pilihan `kolom_id = No.ID`, langkah waktu.
3. Tombol Waktu → tidak ditanya susunan (ada tanggal > 12) → contoh: baris 2 ID 10881 Rabu 25 Mar 2026 07.39, baris 2.601 ID 10942
   Jumat 17 Apr, baris 5.200 ID 11033 Senin 20 Apr; 5.199 tap, 120 ID, 0 baris tidak terbaca (nama hari benar, baris 2 = data asli).
4. Ya, simpan → profil no. 1 aktif (MA2, No.ID, Waktu, dmy, disetujui akun pembangun); kiriman no. 21 diterima 5.199 tap
   (= F1); periode 3–4 dihitung ulang tanpa galat; sidik gaji 1–4 tetap.
5. `A_p3_MA2_formatbaru_kedua.xlsx` → tanpa pertanyaan, "dibaca dengan profil format no. 1"; kiriman no. 22 diterima 2.600 tap;
   tetap 1 konfirmasi; sidik gaji 1–4 tetap.

Catatan: keterangan `MA2` tidak terbawa saat kirim, bot bertanya mesin (perilaku lama, bukan bagian F2). Pesan "PROFIL FORMAT BARU"
tidak dikirim ke pembangun yang menyimpan sendiri (disengaja). `/profilmesin` dan Hapus tidak diuji nyata (pemilik memilih
membiarkan profil no. 1 di demo untuk portofolio); bukti dari uji otomatis (daftar, hapus, file berikutnya ditanya lagi, gaji tetap).

## Sisa

- Tidak ada sisa F2. Profil no. 1 tetap aktif di demo.
- Tetap terbuka di luar F2: uji nyata P1 pada atau sesudah 21 Des 2026; P2–P7 sebelum PT pertama (`docs/pasang/README.md`).
