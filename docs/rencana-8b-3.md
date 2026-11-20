# Rencana paket 8b-3: urutan rilis, jalan keluar, dan kemudahan bot

20 November 2026 · di-"buat" pemilik 20 Nov 2026 09.42 WIB ("sesuai saran kamu, kerjakan") · sesudah uji nyata 8b/8b-2 (`docs/laporan-8b-2.md`)

## Keputusan pemilik (20 Nov 2026, sesuai saran Claude)

- Semua temuan digabung dalam satu paket.
- Periode 2 demo yang sudah dirilis mendahului periode 1 dibiarkan (bekas uji nyata, data simulasi), tidak di-Reset.
- Setujui dan rilis untuk pembangun tidak digabung (PIN kedua tetap pengaman terakhir).
- Bos tidak wajib PIN (rilis tetap butuh PIN HRD/pembangun).

## Temuan yang diperbaiki

| No | Temuan | Bukti |
| --- | --- | --- |
| 1 | Urutan rilis tidak dijaga | [Pasti] periode 2 dirilis saat periode 1 masih `dihitung`; PPh masa terakhir memakai hasil periode sebelumnya (migrasi 0013 baris 1126) |
| 2 | Lupa PIN tidak ada jalan keluar | [Pasti] `/pin` ganti butuh PIN lama |
| 3 | Akun HRD/bos tidak bisa ditambah lewat bot | [Pasti] hanya akun pembangun yang dibuat (`db/pasang_pintu.sh`) |
| 4 | Rilis tidak diberitahukan | [Pasti] hanya perilis yang dibalas |
| 5 | Pengajuan bisa menggantung | [Pasti] tidak ada pengingat ke bos; tidak ada perintah batal |
| 6 | Perintah tanpa `/` tidak dikenali; PIN di dalamnya tidak dihapus | [Pasti] terjadi saat uji nyata |
| 7 | Perintah tanpa PIN hanya dibalas "Cara pakai" | [Pasti] terjadi saat uji nyata |
| 8 | Tidak ada menu perintah; tidak ada tombol Rilis | [Pasti] |
| 9 | Status rilis tidak terlihat di Sheets dan halaman demo | [Pasti] kode tidak membaca status |

## Isi paket

1. Migrasi `0028_rilis_mudah.sql`:
   - Urutan: periode hanya bisa diajukan dan dirilis bila semua periode sebelumnya `dirilis`/`dikunci` (`fakta.periode_menunggu`).
   - `/batal <nomor>`: HRD/pembangun membatalkan pengajuan (`diajukan` atau `disetujui` → `dihitung`); langkah alur `disetujui → dihitung` oleh HRD ditambah.
   - Hapus PIN oleh pembangun (`fakta.hapus_pin`, tercatat); hitungan PIN salah dimulai lagi sesudah dihapus.
   - Undangan akun HRD/bos sekali pakai 60 menit, hanya sidik disimpan (`fakta.undangan_akun`); batas 5 kode salah per jam sama dengan `/daftar`.
   - Menunggu PIN 5 menit sesudah tombol ditekan (`fakta.tunggu_pin`).
   - Pemberitahuan rilis dan pembatalan ke HRD, bos, pembangun lain.
   - Pengingat harian 08.00 WIB ke bos untuk pengajuan yang belum dijawab sejak kemarin (lewat penjadwal pengingat yang sudah ada); tanpa akun bos → ke pembangun.
   - `fakta.status_rilis_teks`: satu sumber teks status untuk Sheets dan halaman demo.
2. Bot: menu perintah per peran (dipasang saat Pasang dan sesudah `/gabung`); perintah tanpa `/` dikenali; pesan 6 angka dihapus; tombol Rilis dan tombol Setujui/Tolak untuk pembangun yang meminta PIN; perintah tanpa PIN meminta PIN; `/batal`, `/hapuspin`, `/undang hrd|bos`, `/gabung <kode>`. Perintah lama tetap jalan.
3. Sheets tab Ringkasan: kolom baru "Status rilis" (kolom terakhir); halaman demo: baris status; pemeriksa Sheets dan demo ikut.
4. Uji database, uji bot, uji Sheets/demo; bukti uji bisa gagal.
5. Pasang lewat cabang `pasang` sesudah uji GitHub lulus; Isi Sheets dan Terbitkan demo dipicu sesudahnya.
6. Laporan `docs/laporan-8b-3.md`, serah-terima.

## Belum pasti

- [Kemungkinan Besar] Kotak balasan PIN (force reply) muncul juga di Telegram Desktop; dibuktikan saat uji nyata.
- [Kemungkinan Besar] Menu per akun (`setMyCommands` lingkup chat) tampil sesudah aplikasi Telegram dibuka ulang.
- Periode tanpa data (tidak pernah ada file) ikut menahan rilis periode sesudahnya; untuk demo tidak ada periode seperti itu [Pasti].
