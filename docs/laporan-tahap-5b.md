# Laporan paket 5b: pintu Telegram

17 November 2026 · acuan: `docs/pintu-telegram.md` (ditulis sebelum kode, commit 70ba0e0 sebelum kode bot)

## Hasil singkat

| Kasus | Uji otomatis (GitHub, pesan tiruan) | Uji nyata (bot Abaensi, Supabase) |
| --- | --- | --- |
| T1 file sah diterima, disimpan, periode dihitung, ringkasan terkirim | **Lulus** (14,8 detik di komputer kerja, 2 periode) | Tidak diuji: semua file simulasi sudah ada di demo |
| T2 file sama dikirim lagi → ditolak dobel | **Lulus** | **Lulus**: kiriman no. 17, ditolak "sudah diterima sebelumnya (kiriman no. 3)", 0 tap |
| T3 update_id kembar diabaikan | **Lulus** | — |
| T4 file rusak karena Excel → ditolak dengan alasan | **Lulus** | **Lulus**: kiriman no. 18, ditolak "No.ID rusak (tertulis seperti 1,98E+17)…", 0 tap |
| T5 bukan file mesin → ditolak | **Lulus** | — |
| T6 pengirim tidak terdaftar → ditolak, file tidak diunduh | **Lulus** | Tidak diuji (tidak ada akun kedua) |
| T7 tanpa kode mesin → tombol; tekan dua kali tidak diproses dua kali | **Lulus** | **Lulus** (tombol muncul, pilihan MA2 diproses) |
| T8 kode rahasia salah → 401 | **Lulus** | — |
| T9, T10 hak akses database peran `pintu` | **Lulus** (db/uji/110) | — |
| Hak akses `pembangun` boleh mengirim file (keputusan pemilik) | **Lulus** | **Lulus**: akun pemilik terdaftar sebagai pembangun, bukan HRD |
| Balasan pertama paling lama 5 detik (PRD bagian 15) | — | **Lulus**: sekitar 2 detik (diamati pemilik) |

## Yang dipasang

| Bagian | Isi |
| --- | --- |
| Migrasi 0015 | Pesan Telegram tercatat sekali, file menunggu pilihan mesin, antrean kerja, 5 fungsi `api`, peran database `pintu` (hanya fungsi itu) |
| Migrasi 0016 (tambahan disetujui) | Pembaca tap versi 3: pemeriksaan cakupan file lebih cepat. Satu file mesin saja: 75,6 detik menjadi 4,2 detik (komputer kerja). Sidik hasil keempat periode Supabase sama persis dengan versi 2 |
| Migrasi 0017 (keputusan pemilik) | Hak akses `pembangun` boleh mengirim file |
| Edge Function `pintu-telegram` | `sistem/pintu/inti.ts` (logika, diuji di Node) + `index.ts` (penyambung Deno, postgres.js 3.4.5) |
| Pemasangan | Lewat workflow "Pasang ke Supabase" (`db/pasang_pintu.sh`): kata sandi peran `pintu` dan kode rahasia Telegram dibuat acak setiap pemasangan; ID Telegram pemilik dari secret, tidak di repo |

## Kesalahan yang ditemukan dan diperbaiki

1. **Bot diam pada uji nyata pertama** [Pasti, dari log Edge Function Supabase]: isian ke database terbaca kosong (`update_id` null) karena postgres.js membungkus teks JSON sekali lagi untuk parameter `$1::jsonb`. Diperbaiki menjadi `$1::text::jsonb` (commit 616651f). Uji otomatis tidak menangkapnya karena memakai psql, bukan postgres.js; bagian penyambung (`index.ts`) memang belum punya uji otomatis.
2. **Cadangan malam gagal sekali** sesudah 0015 terpasang: peran `pintu` tidak ikut cadangan pg_dump. Diperbaiki dengan `db/peran_proyek.sql` yang dijalankan sebelum pemulihan.
3. **Pemasangan sempat gagal sekali** karena unduhan alat Postgres terputus (curl 55); diulang dan lulus. Tidak ada yang berubah saat gagal.

## Batasan

- Jalur "file baru diterima lalu dihitung" baru terbukti di uji otomatis, belum di Supabase demo (butuh reset demo atau file baru).
- `index.ts` belum diuji otomatis; kesalahan nomor 1 menunjukkan risikonya.
- Antrean dikerjakan oleh Edge Function yang sama, paling lama sekitar 110 detik per pesan; sisanya menunggu pesan berikutnya.
- Waktu balasan diamati manusia (sekitar 2 detik), belum dicatat sistem.
