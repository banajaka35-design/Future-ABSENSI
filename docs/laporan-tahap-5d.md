# Laporan paket 5d: unggah cadangan lewat web

17 November 2026 · acuan: `docs/unggah-web.md` (commit 91500bf, ditulis sebelum kode) · kode: commit 43a9692

## Hasil singkat

| Kasus | Uji otomatis (GitHub) | Uji nyata (Supabase, halaman demo) |
| --- | --- | --- |
| W1 `/unggah` dari HRD → tautan 15 menit, database hanya menyimpan sidik kode | **Lulus** | **Lulus**: tautan no. 1 dibuat 16.26 WIB, berlaku sampai 16.41 (percobaan kedua; lihat temuan 1) |
| W2 akun bukan HRD → tanpa tautan | **Lulus** | — |
| W3 kode palsu, W4 tautan lewat 15 menit, W5 akun dinonaktifkan | **Lulus** | — |
| W6 file sah lewat web → diterima, asal `web`, dihitung, status terbaca, ringkasan ke Telegram | **Lulus** | Tidak diuji (semua file simulasi sudah ada di demo) |
| W7 file dobel lewat web → ditolak | **Lulus** | **Lulus**: kiriman no. 21 (`A_p1_MA2.csv`) ditolak "sudah diterima sebelumnya (kiriman no. 3)", 0 tap, tidak masuk antrean, tidak ada pemberitahuan segera |
| W8 file rusak Excel lewat web → ditolak + pemberitahuan segera (U14) | **Lulus** | **Lulus**: kiriman no. 20 ditolak, asal `web`, pengirim pemilik tautan, 0 tap; pemberitahuan `terkirim` 0,2 detik sesudah kiriman tercatat, sampai ke Telegram 1,2 detik kemudian |
| W9 beberapa file dengan satu tautan | **Lulus** | **Lulus**: tautan no. 1 dipakai 2 kali |
| W10 permintaan dari alamat lain → 403 | **Lulus** | — |
| W11 status kiriman dengan tautan akun lain → ditolak | **Lulus** | — |
| Telegram gagal total → file web tetap diterima dan dihitung | **Lulus** | — |

Jumlah uji otomatis: database 420 lulus; bot 25 lulus; penyambung (postgres.js sungguhan, unggah multipart) 11 lulus.

## Yang dipasang

| Bagian | Isi |
| --- | --- |
| Migrasi 0019 | `fakta.tautan_unggah`, kolom `fakta.kiriman_file.asal` (diisi saat baris dibuat; baris lama dibiarkan kosong karena tabel hanya boleh ditambah), `api.pintu_terima_file` diperbarui (mencatat asal), 4 fungsi `api` baru |
| Bot | Perintah `/unggah` |
| Edge Function | Jalur `?jalur=periksa`, `unggah`, `status`; hanya dari `https://future-absensi-demo.pages.dev`; pesan Telegram yang gagal tidak menghentikan hitungan |
| Halaman | `web/demo/unggah/` di Cloudflare Pages; alamat fungsi ditulis saat terbit |

## Temuan

1. **Bot diam setelah setiap "Pasang ke Supabase"** [Pasti, dari log Supabase]: pesan pertama sesudah pemasangan gagal dengan "password authentication failed for user pintu" (5c pukul 15.47 WIB; 5d pukul 16.24 WIB, 5 menit sesudah pemasangan). Pesan berikutnya berhasil. Laporan 5c menyebut "1–2 menit"; itu keliru: yang terjadi adalah **percobaan pertama selalu gagal**, berapa pun jedanya. Penyebab [Kemungkinan Besar]: pooler Supabase (Supavisor) menyimpan kata sandi lama peran `pintu` dan baru memperbaruinya setelah satu kali gagal. Akibat: pesan pertama HRD sesudah pemasangan hilang tanpa balasan (tidak tercatat, Telegram tidak mengirim ulang karena dijawab 200). **Usulan perbaikan (paket terpisah):** skrip pemasangan mencoba masuk sebagai `pintu` sampai berhasil sesudah mengganti kata sandi; bot membalas "ada gangguan, coba lagi" bila database gagal.

## Batasan

- Batas ukuran file yang diterima Edge Function sungguhan **belum diukur** (uji memakai file kecil). Batas di kode: 50 MB.
- Login masih lewat Telegram; cadangan saat Telegram mati total untuk mendapatkan tautan adalah paket 5e (email).
- Siapa pun bisa membuka halaman `/unggah`; tanpa kode yang sah tidak ada yang diproses.

## Paket 5d-2 (17 Nov 2026): bot tidak diam bila database menolak masuk

Kode: commit 61c79ff. Edge Function mencoba ulang galat sambungan/masuk (3 percobaan); bila tetap gagal, pengirim diberi pesan gangguan dan Telegram dijawab 503 supaya pesan dikirim ulang (dokumen setWebhook: permintaan yang tidak dijawab 2xx diulang, lalu Telegram menyerah sesudah beberapa kali). `db/pasang_pintu.sh` masuk sebagai `pintu` lewat pooler sampai berhasil sesudah mengganti kata sandi.

| Uji | Hasil |
| --- | --- |
| Otomatis (penyambung, postgres.js sungguhan): ditolak sekali lalu berhasil; ditolak terus → 503 + pesan gangguan, tidak tercatat, kiriman ulang diproses sekali; tombol; teks galat pooler dengan kode lain; galat lain tetap 200; kode rahasia salah tidak menyentuh database | **Lulus** (17 uji penyambung) |
| Pemasangan: skrip masuk sebagai `pintu` | Berhasil pada percobaan ke-1 |
| Nyata: pesan "halo" pukul 16.52 WIB, sekitar 3 menit sesudah pemasangan | **Lulus**: dibalas pada kiriman pertama; log Edge Function tanpa percobaan ulang |

Catatan [Pasti, log Supavisor]: satu penolakan kata sandi `pintu` tercatat pukul 16.45.59 WIB, saat pemasangan; sumbernya tidak terbaca dari log [Menebak: kolam sambungan lama di pooler]. Kolam `pintu` lama ditutup pooler pukul 16.48. Jalur coba ulang di Edge Function belum pernah terpakai di Supabase sungguhan; baru terbukti di uji otomatis.
