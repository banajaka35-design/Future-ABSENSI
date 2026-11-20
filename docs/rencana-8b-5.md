# Rencana paket 8b-5: Sheets ikut status rilis; tombol tetap tidak hilang

20 November 2026 · di-"buat" pemilik 20 Nov 2026 11.17 WIB · temuan uji nyata 8b-3/8b-4 (rilis periode 1, 11.16 WIB)

## Temuan [Pasti]

1. Sheets masih menulis periode 1 "Bisa diajukan" sesudah dirilis: Isi Sheets hanya dipicu file baru atau Pasang.
2. Sesudah PIN diketik, tombol tetap tidak terlihat dan kolom ketik masih "Reply to" (gambar pemilik). [Menebak] force reply pada permintaan PIN menutup tombol tetap.

## Isi paket

1. Ajukan, setujui/tolak, rilis, batal yang berhasil memicu Isi Sheets (pemicu "status periode", tanpa waktu file; jalur yang sama dengan sesudah file, token `GTHUB_PICU_TOKEN`); halaman demo terbit sesudahnya. Kabar "Sheets sedang diperbarui" dikirim sesudah balasan utama.
2. Permintaan PIN dari tombol Rilis/Setujui/Tolak tanpa force reply (6 angka dikenali dari catatan menunggu PIN). Jawaban pertanyaan `Kode karyawan` dan `PIN` (tetap force reply) dibalas dengan tombol tetap.
3. Tanpa migrasi; uji bot; Pasang; uji nyata.

## Belum pasti

- [Kemungkinan Besar] Tanpa force reply, tombol tetap tidak tertutup saat diminta PIN; dibuktikan saat uji nyata.
