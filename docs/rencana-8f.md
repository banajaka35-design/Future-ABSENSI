# Rencana paket 8f: pembangun bisa mencabut akun

Diminta pemilik 23 Nov 2026 14.05 WIB: akun pembangun harus bisa menghapus posisi akun lain (HRD, bos, karyawan), karena sistem masih percobaan. Ditulis sebelum uji `/gabung` akun ketiga.

## Keadaan sekarang [Pasti, dicek di kode dan Supabase 23 Nov]

- Bot tidak punya perintah untuk mencabut akun. Satu-satunya cara sekarang adalah Reset Supabase, yang ikut menghapus semua data.
- `induk.pengguna.telegram_id` unik. Akun yang hanya dinonaktifkan tidak bisa `/gabung` atau `/daftar` lagi dari HP yang sama karena bot menjawab "sudah terdaftar".

## Isi paket

1. **Migrasi `0037_cabut_akun.sql`**
   - Tabel baru `fakta.cabut_akun`: nomor akun, Telegram lama, peran, ID karyawan, dicabut oleh siapa, dan kapan. Hanya bisa ditambah.
   - `api.pintu_cabut_daftar`: khusus pembangun. Mendaftar akun aktif HRD, bos, dan karyawan. Akun pembangun tidak ikut didaftar.
   - `api.pintu_cabut_akun`: khusus pembangun. Target harus akun aktif dan bukan pembangun. Yang dilakukan: akun dinonaktifkan, PIN dihapus, Telegram dilepas (dikosongkan) agar HP yang sama bisa `/gabung` atau `/daftar` lagi, tunggu PIN dan draf perintah milik akun itu dihapus, lalu dicatat di `fakta.cabut_akun`.
   - Riwayat lama (perintah, pengajuan, kiriman file, persetujuan) tetap menunjuk ke nomor akun lama. Tidak ada yang dihapus.
2. **Bot**
   - Perintah baru `/cabutakun`, khusus pembangun. Bot menampilkan tombol daftar akun, lalu meminta konfirmasi Ya/Tidak, lalu menampilkan hasilnya.
   - Akun yang dicabut diberi tahu, dan menu Telegram-nya dikembalikan ke menu umum.
   - Kata "cabut akun" tanpa `/` dikenali. Perintah ditambahkan ke menu dan teks bantuan pembangun.
3. **Uji database dan uji bot**
   - Bukan pembangun ditolak.
   - Pembangun tidak bisa dicabut.
   - Akun bos yang dicabut tidak bisa menyetujui dan `/lengkap`-nya ditolak.
   - Akun HRD yang dicabut tidak bisa menyimpan draf perintah lamanya.
   - Akun karyawan yang dicabut: kiriman rincian gaji berikutnya menjadi `tanpa_akun`.
   - HP yang sama bisa `/gabung` lagi dengan undangan baru.
   - Mencabut dua kali ditolak.
4. **Pasang ke Supabase** lewat cabang `pasang` setelah uji GitHub lulus.
5. **Uji nyata**
   - Akun ketiga `/gabung` sebagai bos, lalu uji bos menyetujui dan `/lengkap`.
   - Pembangun `/cabutakun` akun ketiga.
   - Akun ketiga kembali berstatus belum terdaftar. Dicek di bot dan di Supabase.
6. **Dokumen:** `docs/laporan-8f.md` dan `docs/serah-terima.md`.

## Keputusan Claude (aturan delegasi)

- [Kemungkinan Besar] **Tanpa PIN**, sama seperti `/hapuspin` dan `/undang`. Pencabutan bisa dipulihkan dengan undangan atau kode daftar baru. Konfirmasi Ya/Tidak mencegah salah tekan.
- [Kemungkinan Besar] **Karyawan ikut bisa dicabut.** Akun karyawan 10735 di akun kedua juga bisa dilepas saat percobaan. Ia bisa mendaftar lagi dengan `/kode` dari HRD atau pembangun.
- **Pembangun tidak bisa dicabut lewat bot,** termasuk akun pembangun sendiri. Ini supaya tidak terkunci dari sistem sendiri.

## Belum pasti

- [Menebak] Jumlah uji tambahan dan lamanya pekerjaan belum diukur.
- Pemeriksaan "HRD yang dicabut tidak bisa menyimpan draf lama" akan dibuktikan lewat uji; belum dicek di kode.
