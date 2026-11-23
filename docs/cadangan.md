# Cadangan database: tempat, kunci, dan cara membuka

Paket E1 (19 Nov 2026, `docs/rencana-e1.md`). Untuk demo dengan data simulasi. Untuk perusahaan sungguhan, cadangan **tidak** disimpan di GitHub (lihat "Sebelum dipasang untuk perusahaan sungguhan" di `docs/serah-terima.md`).

## Di mana cadangan disimpan

| Workflow | Kapan | Nama artifact | Disimpan |
| --- | --- | --- | --- |
| Cadangan malam | setiap 02.20 WIB, sesudah Pasang/Reset berhasil, atau lewat tombol | `cadangan-malam-<nomor>` | 14 hari |
| Pasang ke Supabase | sebelum mengubah Supabase | `cadangan-sebelum-pasang-<nomor>` | 30 hari |
| Reset Supabase | sebelum mengosongkan Supabase | `cadangan-sebelum-reset-<nomor>` | 30 hari |

Sejak E1 isinya satu file `….dump.gpg`: cadangan `pg_dump` yang dikunci gpg (AES-256). Artifact lama tanpa enkripsi (`.dump`) dibiarkan sampai habis masa simpannya (keputusan 19 Nov 2026).

## Kunci

- Secret GitHub `CADANGAN_KUNCI` berisi kalimat rahasia buatan pemilik. Kalimat yang sama disimpan pemilik di tempat pribadinya (pengelola kata sandi atau catatan tertutup). Kalimat ini tidak pernah ditulis di repo, chat, atau log.
- Secret kosong → Cadangan malam GAGAL; Pasang dan Reset berhenti sebelum menyentuh Supabase. Tidak ada cadangan yang diunggah tanpa enkripsi.
- **Kalimat hilang = cadangan terenkripsi tidak bisa dibuka siapa pun.** Mengganti kalimat: ubah secret; cadangan lama tetap memakai kalimat lama.
- Cara mengisi secret: GitHub repo → Settings → Secrets and variables → Actions → New repository secret → nama `CADANGAN_KUNCI`, isi kalimatnya → Add secret.

## Cara membuka satu cadangan secara manual

1. Unduh artifact dari halaman run workflow di GitHub (bagian "Artifacts"), lalu ekstrak zip-nya; isinya satu file `….dump.gpg`.
2. Di komputer yang punya `gpg` dan klien Postgres 17, buka file itu (gpg menanyakan kalimat rahasia):

   ```
   gpg --decrypt --output cadangan.dump nama-file.dump.gpg
   ```

   Atau dari folder repo: `CADANGAN_KUNCI='kalimat' db/kunci_cadangan.sh buka nama-file.dump.gpg cadangan.dump` (kalimat di baris perintah bisa tersimpan di riwayat terminal; cara pertama lebih aman).
3. Pulihkan ke database **kosong** (bukan Supabase utama), dengan cara yang sama seperti uji pemulihan malam: `SUMBER_URL=... TUJUAN_URL=... db/uji_pemulihan.sh cadangan.dump`. Memulihkan ke Supabase utama hanya lewat paket tersendiri yang di-"buat" pemilik.
4. Hapus `cadangan.dump` sesudah selesai; file itu tidak terenkripsi.

Setiap malam workflow Cadangan malam membuktikan langkah 2–3 otomatis: file terenkripsi yang diunggah dibuka lalu dipulihkan ke Postgres 17 kosong, dan jumlah baris setiap tabel harus sama dengan Supabase pada saat cadangan diambil. Sejak paket E2 (`docs/laporan-e2.md`), Supabase dihitung tepat sebelum dan tepat sesudah cadangan; hasil pemulihan tiap tabel harus berada di antara dua hitungan itu. Tabel yang bertambah selama cadangan diambil (bot sedang menulis) dicatat sebagai "Catatan", bukan kegagalan. Baris yang hilang tetap GAGAL.
