# Laporan paket 6f: pengerasan keamanan dan perbaikan bug

18 November 2026 · "buat" pemilik 18 Nov 2026 · rancangan: `docs/rencana-pengerasan-6f.md` · dokumen sebelum kode: commit b6d1150 · kode: 7fcd6cc, perbaikan B2: a2dab26

## Yang ditutup

| No | Masalah | Perbaikan | Bukti |
| --- | --- | --- | --- |
| S1 | Kuota email Brevo (300/hari) bisa dihabiskan lewat permintaan kode berulang untuk satu email HRD (sampai 288/hari) | Migrasi 0023: paling banyak 10 kode per email per 24 jam dan 100 total per 24 jam; jawaban halaman tetap sama | Uji pintu 2 baru lulus (kode ke-11 tidak dikirim; batas 100 berlaku untuk email lain; jawaban sama dengan email tak terdaftar). Supabase: fungsi terpasang memuat batas 24 jam (dicek langsung) |
| S2 | `public.rls_auto_enable()` (bawaan Supabase) bisa dijalankan `anon`/`authenticated` | Migrasi 0023: izin dicabut; `db/cek_akses.sql` kini menganggap fungsi SECURITY DEFINER di `public` yang bisa dijalankan tanpa login sebagai celah (uji malam dan uji database) | Supabase: izin tinggal `postgres`, `service_role`; pemicu `ensure_rls` tetap aktif; **peringatan keamanan Supabase: 0** (dicek langsung sesudah Pasang) |
| S3 | Halaman unggah dan demo tanpa header keamanan | `web/buat_headers.py`, dijalankan saat terbit: CSP (skrip hanya bersidik, sambungan hanya ke halaman sendiri dan Edge Function, `frame-ancestors 'none'`), nosniff, no-referrer, X-Frame-Options DENY. Koreksi saat membangun: gaya `'unsafe-inline'` (atribut `style=` tidak bisa diberi sidik) | Terbitkan demo run 44284807601: "_headers ditulis: 2 sidik skrip"; uji simulasi: penangan `onclick` dan asal Edge Function palsu ditolak pembuat header |
| S4 | Nilai GitHub dimasukkan langsung ke perintah `run:` | Lewat `env`; `sistem/uji/periksa_workflow.py` memeriksa semua workflow (menangkap baris lama saat diuji) | Uji simulasi: 8 workflow, 0 temuan |
| B1 | Pesan "Semua baris data ditolak" tanpa alasan | Pesan menyebut alasan terbanyak, jumlah, contoh; awalan tetap | Uji pembaca file baru lulus (1.500 baris tanggal mustahil + 1 lain) |
| **B2** (ditemukan saat Pasang) | Pemeriksaan data awal mengharuskan **tepat 12** kiriman diterima, menghitung juga kiriman Telegram/web sungguhan → **setiap Pasang gagal begitu HRD pernah mengirim file** (Pasang run 44281846498 gagal 30/31 karena kiriman uji nyata 6e) | Hanya kiriman data awal (`asal = 'lain'`) yang dihitung | Pasang run 44284088746: 31 lulus, 0 gagal |

Catatan Pasang pertama (run 44281846498): migrasi 0023 sudah terpasang sebelum pemeriksaan gagal; langkah pintu tidak jalan. Pasang kedua memasang semuanya (Edge Function dengan perbaikan B1, "Pemicu Isi Sheets: diisi").

## Uji otomatis (GitHub)

Commit 7fcd6cc dan a2dab26: pembaca file 17, database 453, simulasi 96, pintu 40, penyambung 23; 0 gagal.

## Sesudah dipasang

- Pasang (44284088746) lulus; Terbitkan demo (44284807601) lulus, pemeriksa demo 0 beda; Isi Sheets (44284807750) lulus.

## Belum dicek langsung

- Header di halaman yang sudah terbit: browser aplikasi Claude tidak terjangkau saat dicek (komputer pemilik tidak terhubung) dan jaringan kerja Claude menolak alamat halaman. [Kemungkinan Besar] header aktif, karena `_headers` ditulis di folder yang diunggah (log terbit). Dicek begitu browser terjangkau.
- Bot sesudah Pasang: pemilik mengirim `/unggah`.

## Risiko yang diterima

R1–R3 di `docs/rencana-pengerasan-6f.md` (token pemicu bisa menjalankan workflow bertombol lain dan menghapus artifact; kunci akun layanan Google tanpa masa berlaku, diusulkan diganti tiap 90 hari; cadangan berisi gaji lengkap di repo privat).
