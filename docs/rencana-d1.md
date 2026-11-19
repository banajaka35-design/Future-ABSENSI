# Rencana paket D1: pengaman halaman demo publik

19 November 2026 · di-"buat" pemilik 19 Nov 2026 14.32 WIB · celah nomor 1 dari evaluasi sesudah G1-3

Ditulis sebelum kode. Yang tidak tertulis di sini tidak ikut dikerjakan.

## Celah [Pasti]

Workflow "Terbitkan demo" berjalan otomatis sesudah setiap "Isi Sheets" (artinya sesudah setiap file masuk lewat bot atau web, sesudah Pasang, dan sesudah Reset). Ia membaca gaji per orang dari Supabase dan menerbitkannya ke https://future-absensi-demo.pages.dev/ , yang bisa dibuka siapa pun. Tidak ada pemeriksaan apakah data di Supabase masih data simulasi. Satu karyawan asli yang masuk ke Supabase ini akan langsung terbit ke publik.

Reset sudah punya pengaman yang sama (`db/reset_supabase.sh`: semua karyawan harus karangan dari `data/simulasi/`, cocok ID dan nama). Terbitkan demo belum.

## Isi paket

1. `db/cek_hanya_simulasi.sh`: semua karyawan di database harus ada di `data/simulasi/*/induk/karyawan.csv` dengan ID **dan** nama yang sama. Satu saja tidak cocok → GAGAL, keluar 1, dengan jumlahnya saja (ID dan nama tidak dicetak ke log).
2. Workflow "Terbitkan demo": langkah pemeriksa ini paling awal sesudah klien Postgres terpasang, sebelum data dibuat. GAGAL → tidak ada yang dibuat dan diunggah; halaman lama tetap.
3. Uji di `sistem/uji/jalankan_simulasi.sh` (database simulasi Pabrik B, sesudah uji lain): data simulasi → LULUS; tambah satu karyawan asing → GAGAL; ubah satu huruf nama karyawan simulasi → GAGAL; keadaan dikembalikan.
4. Bukti nyata: picu "Terbitkan demo" sekali lewat tombol (`gh workflow run`); langkah pengaman harus LULUS dengan data simulasi sekarang; halaman terbit dan dicek langsung.
5. Dokumen: tabel "Sebelum dipasang untuk perusahaan sungguhan" di `docs/serah-terima.md` + 3 baris (halaman demo hanya data simulasi; HRD akses lihat saja ke Sheets, celah T2; pembangun dan sesi Claude tidak membaca gaji perusahaan sungguhan, penyambung Claude hanya untuk proyek demo); `docs/laporan-d1.md`.

Tidak diubah: Supabase (tanpa migrasi dan tanpa Pasang), bot, Isi Sheets (Sheets bukan halaman publik dan nanti memang berisi data asli), Reset (tetap memakai kodenya sendiri; menyatukan keduanya paket terpisah).

## Belum pasti

- Jalur GAGAL hanya dibuktikan di uji otomatis; membuktikannya di Supabase butuh memasukkan karyawan palsu langsung ke Supabase (dilarang aturan 8).
- [Kemungkinan Besar] Kabar bila Terbitkan demo gagal hanya email bawaan GitHub.
- [Kemungkinan Besar] Memeriksa daftar karyawan cukup: data halaman demo (`web/buat_data.py`) hanya terikat ke karyawan; tanda "ID tidak dikenal" dari file asli tidak ikut diterbitkan.
