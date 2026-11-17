# Unggah cadangan lewat web (Tahap 5, paket 5d)

17 November 2026 · ditulis sebelum kode · acuan: keputusan pemilik 17 Nov 2026 (unggah cadangan lewat web dipindah dari Tahap 4 ke Tahap 5; login lewat tautan dari bot; login email menyusul di paket 5e), `docs/halaman-demo.md` (halaman tidak menyentuh database)

## Gunanya

Jalur kedua untuk file mesin: file lebih dari 20 MB (batas unduh bot Telegram), atau HRD lebih mudah mengunggah dari komputer. Login ini masih bergantung pada Telegram untuk mendapatkan tautan; cadangan saat Telegram mati total adalah paket 5e (email).

## Alur

1. HRD mengetik `/unggah` di bot. Hanya akun aktif `hrd` atau `pembangun`; selain itu ditolak.
2. Edge Function membuat kode acak (32 bita), menyimpan **sidik SHA-256** kode itu di database (bukan kodenya), berlaku **15 menit**, lalu bot membalas tautan `https://future-absensi-demo.pages.dev/unggah/#kode=...`. Kode ada di bagian `#`, jadi tidak terkirim ke Cloudflare dan tidak tercatat di log Cloudflare.
3. Halaman membaca kode dari alamat, lalu bertanya ke Edge Function apakah tautan berlaku (sekaligus daftar mesin). Tidak berlaku → pesan "tautan tidak berlaku, ketik /unggah di bot".
4. HRD memilih file dan mesin, lalu menekan Kirim. Selama 15 menit tautan boleh dipakai untuk beberapa file (misalnya MA1 lalu MA2).
5. Edge Function memeriksa ulang tautan, lalu memproses file dengan jalur yang sama dengan bot: sidik file → pembaca file `sistem/urai` → `api.pintu_terima_file` (penolakan dobel, file rusak Excel, format) → antrean → pemberitahuan segera. Kiriman dicatat dengan **asal `web`** dan pengirim pemilik tautan.
6. Hasil terima/tolak, jumlah tap, dan rentang tanggal langsung tampil di halaman.
7. Hitungan per periode berjalan di belakang. Halaman menanyakan status kiriman setiap beberapa detik dan menampilkan hasil per periode. Ringkasan per periode juga dikirim ke Telegram pemilik tautan, seperti file dari bot. Pemberitahuan segera dikirim ke semua penerima (paket 5c).

## Keamanan

- Halaman tidak menyentuh database; hanya memanggil Edge Function.
- Edge Function hanya menerima permintaan web dari alamat halaman demo (`Origin` = `https://future-absensi-demo.pages.dev`); alamat lain ditolak (403).
- Database memeriksa ulang: tautan ada, belum lewat waktu, akunnya masih aktif dengan hak `hrd` atau `pembangun`.
- Status kiriman hanya bisa dibaca dengan tautan pemilik kiriman itu, sampai 60 menit sesudah tautan habis (supaya halaman bisa menunggu hitungan selesai).
- Siapa pun bisa membuka halaman `/unggah`, tetapi tanpa kode yang sah tidak ada yang diproses.

## Kasus uji (wajib benar)

| No | Kejadian | Harapan |
| --- | --- | --- |
| W1 | HRD mengetik `/unggah` | Tautan dibalas; database hanya menyimpan sidik kode, berlaku 15 menit |
| W2 | Akun bukan HRD mengetik `/unggah` | Ditolak; tidak ada tautan dibuat |
| W3 | Kode palsu | Ditolak; file tidak diproses |
| W4 | Tautan lewat 15 menit | Ditolak |
| W5 | Akun pemilik tautan dinonaktifkan sesudah tautan dibuat | Ditolak |
| W6 | File sah lewat web | Diterima, asal `web`, pengirim pemilik tautan, periode masuk antrean dan dihitung; status per periode terbaca halaman |
| W7 | File yang sama lagi | Ditolak dobel |
| W8 | File rusak Excel lewat web | Ditolak dengan alasan; pemberitahuan segera terkirim ke semua penerima (U14) |
| W9 | Dua file dengan satu tautan dalam 15 menit | Keduanya diproses |
| W10 | Permintaan dari alamat lain (`Origin` berbeda) | Ditolak 403 |
| W11 | Status kiriman diminta dengan tautan akun lain | Ditolak |

W1–W11 diuji otomatis di GitHub (Postgres sementara, file simulasi, postgres.js sungguhan untuk penyambung). Uji nyata: pemilik mengetik `/unggah`, lalu mengunggah file rusak Excel (W8) dan file dobel (W7). File sah baru tidak bisa diuji nyata karena semua file simulasi sudah ada di demo.

## Batasan yang disadari

- Batas ukuran file yang diterima Edge Function belum diukur; diukur di uji dan dicatat di laporan.
- Antrean tetap paling lama sekitar 110 detik per permintaan (sama dengan bot); sisanya dikerjakan saat pesan atau unggahan berikutnya.
