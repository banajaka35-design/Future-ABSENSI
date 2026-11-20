# Rencana paket 8b-4: tombol tetap di bawah kolom ketik

20 November 2026 · di-"buat" pemilik 20 Nov 2026 10.40 WIB · usulan pemilik sesudah melihat menu perintah 8b-3

## Isi paket

1. Tombol tetap (reply keyboard) per peran: HRD `Kirim file` · `Ajukan` · `Rilis` · `Kode karyawan` · `PIN` · `Bantuan`; pembangun ditambah `Undang` · `Hapus PIN`; bos `Bantuan`; karyawan tanpa tombol (menunggu 8c).
2. `Kode karyawan` bertanya ID (balas pesan); `PIN` bertanya PIN baru atau "PIN lama spasi PIN baru" (pesan dihapus); `Undang` memberi pilihan HRD/Bos.
3. Tombol `Batalkan pengajuan` di daftar Rilis.
4. Tombol muncul sesudah `/bantuan`, `/start`, atau `/gabung`. Perintah ketik dan menu `/` tetap jalan.
5. Hanya bot dan uji bot; tanpa migrasi database (jawaban pertanyaan dikenali dari pesan yang dibalas, bukan dari catatan di database).
6. Uji, Pasang lewat cabang `pasang`, uji nyata pemilik.

## Belum pasti

- [Kemungkinan Besar] Tombol tetap dan kotak balasan tampil di Telegram Desktop dan HP.
- [Kemungkinan Besar] Jawaban untuk `Kode karyawan` dan `PIN` dikenali bila pengguna membalas pertanyaan bot (Telegram mengisi balasan otomatis lewat force reply). Bila pengguna mengetik tanpa membalas, ID tidak dikenali dan 6 angka dibaca sebagai PIN tanpa perintah (pesan tetap dihapus, bot memberi petunjuk).
