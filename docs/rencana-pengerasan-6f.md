# Rencana paket 6f: pengerasan keamanan dan perbaikan bug (menunggu "buat")

18 November 2026 · permintaan pemilik: "analisa lagi bug-bug dan potensi bahaya di-hack, tutup semua celahnya" · semua temuan dicek langsung (kode, Supabase, GitHub, riwayat repo), bukan dari ingatan

## Temuan yang merugikan → ditutup di paket ini

| No | Celah / bug | Bukti | Penutup |
| --- | --- | --- | --- |
| S1 | **Kuota email Brevo bisa dihabiskan orang luar.** Halaman masuk-lewat-email membatasi 3 kode per email per 15 menit, tetapi tidak ada batas harian. Orang yang tahu satu email HRD bisa meminta kode terus: sampai 288 email sehari, padahal paket gratis Brevo hanya 300 email sehari untuk semua email. Akibatnya HRD lain tidak menerima kode masuk sampai besok. | [Pasti] aturan E8 di kode (3 per 15 menit, tanpa batas harian); [Pasti] batas Brevo gratis 300 email/hari (halaman bantuan resmi Brevo) | Batas tambahan: **paling banyak 10 kode per email per hari dan 100 email kode per hari untuk semua akun**. Melewati batas: jawaban halaman tetap sama (tidak membuka apakah email terdaftar), email tidak dikirim, dicatat. Migrasi baru (fungsi `api.pintu_minta_kode_email` diganti dengan isi yang sama + dua batas). Uji otomatis: permintaan ke-11 dalam sehari tidak mengirim; batas total 100. |
| S2 | **Fungsi `public.rls_auto_enable()` bisa dipanggil tanpa login** (peringatan keamanan Supabase, tingkat WARN). Fungsi ini bawaan Supabase (bukan buatan proyek), pemicu otomatis untuk menyalakan RLS. | [Pasti] daftar peringatan Supabase 18 Nov 2026; izin `anon=X`, `authenticated=X`; [Kemungkinan Besar] tidak bisa benar-benar dijalankan lewat API karena jenisnya pemicu (`event_trigger`) | Migrasi baru: cabut izin jalankan dari `public`, `anon`, `authenticated` (bila fungsi itu ada; di Postgres uji tidak ada). Uji malam "akses tanpa login ditolak" diperluas: tidak ada fungsi SECURITY DEFINER di skema `public` yang bisa dijalankan `anon`. Dicek ulang dengan daftar peringatan Supabase sesudah dipasang (harus 0). |
| S3 | **Halaman unggah dan demo tanpa header keamanan.** Halaman unggah bisa dimasukkan diam-diam ke halaman orang lain (clickjacking); tidak ada batas sumber skrip bila suatu saat ada celah tampilan. | [Pasti] tidak ada file `_headers` di `web/demo`; [Pasti] tampilan memakai `textContent` (tidak ada celah XSS ditemukan; satu `innerHTML` berisi teks tetap) | File `web/demo/_headers` (Cloudflare Pages): `Content-Security-Policy` (skrip dan gaya hanya dari halaman sendiri, sambungan hanya ke halaman sendiri dan alamat Edge Function, `frame-ancestors 'none'`), `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`. Dicek langsung sesudah terbit: header ada, halaman demo dan unggah tetap berjalan (unggah satu file uji tidak diperlukan; cukup halaman periksa kode tetap terbuka). |
| S4 | Workflow Isi Sheets memasukkan nilai GitHub langsung ke perintah (`run_started_at`). Nilainya dari GitHub (tanggal), tetapi menyalahi aturan pengamanan GitHub Actions. | [Pasti] `.github/workflows/isi-sheets.yml` baris 78 | Dipindah ke `env`. Pemeriksaan otomatis baru: tidak ada `${{ inputs.* }}` atau `${{ github.event.* }}` di dalam baris `run:` semua workflow. |
| B1 | **Pesan "Semua baris data ditolak" tidak menyebut alasannya.** Di uji nyata 6e, file bertanggal 22 Nov–20 Des ditolak karena tanggalnya lebih dari sehari sesudah hari kirim; HRD tidak bisa tahu sebabnya (di lapangan: jam mesin salah). | [Pasti] pesan bot 18 Nov 2026 16.39 dan `sistem/urai/urai.ts` | Pesan ditambah alasan terbanyak dan contohnya, misalnya: "Semua baris data ditolak; tidak ada tap yang bisa dipakai. 39.519 baris: tanggal mustahil (jam mesin kemungkinan tereset atau salah), contoh "22/11/2026 22.52.01"." Awalan pesan tidak berubah (dicocokkan database). Uji pembaca file ditambah. |

## Risiko yang diterima (dicatat, tidak bisa ditutup lebih jauh tanpa biaya)

| No | Risiko | Alasan diterima |
| --- | --- | --- |
| R1 | Pemegang token pemicu (bila bocor dari Supabase) bisa menjalankan workflow bertombol lain (Isi Sheets, Terbitkan demo, Cadangan, Picu pengingat, Pasang) dan menghapus artifact. Reset sudah tertutup (6e). | GitHub tidak menyediakan izin yang lebih sempit; token 90 hari; akibat terparah: pengingat/pesan berlebih, cadangan GitHub terhapus (data di Supabase tetap). |
| R2 | Kunci akun layanan Google tidak punya masa berlaku. | Hanya bisa mengubah satu spreadsheet; diganti bila bocor. Dicatat di serah-terima: ganti tiap 90 hari bersama token GitHub. |
| R3 | Cadangan database (artifact GitHub, 14–30 hari) berisi gaji lengkap dan email akun. | Repo privat [Pasti]; untuk perusahaan sungguhan cadangan harus pindah (sudah dicatat sejak 4b). |

## Diperiksa dan aman (tidak diubah)

- Riwayat repo 113 commit: tidak ada token, kunci pribadi, kunci Brevo, token bot, atau alamat database berkata sandi.
- Tombol pilihan mesin di Telegram: hanya bisa dipakai akun yang mengirim file itu (`pintu_ambil_tunda` memeriksa ID Telegram).
- Halaman demo dan unggah: isi dari server ditampilkan sebagai teks, bukan HTML.
- Webhook Telegram dengan kode rahasia (T8); kode tautan unggah di bagian `#` alamat (tidak terkirim ke server); file > 20 MB (bot) / 50 MB (web) ditolak.
- Kata sandi peran `pintu` dan kode rahasia disamarkan di log workflow (`add-mask`).
- Uji otomatis hanya untuk `pull_request` biasa (bukan `pull_request_target`); repo privat.
- Sheets: tab sistem dikunci, isi ditulis apa adanya (rumus tidak dijalankan), orang rahasia tidak bocor (6a-3, 6a-4).

## Isi paket

1. Dokumen dulu: dokumen ini sudah ditulis; `docs/login-email.md` (batas harian) dan `docs/halaman-demo.md` (header) diperbarui sebelum kode.
2. Migrasi baru untuk S1 dan S2; kode S3, S4, B1; uji masing-masing (lihat tabel).
3. Semua uji GitHub harus lulus.
4. **Supabase**: Pasang ke Supabase (cabang `pasang`) untuk migrasi dan Edge Function. **Terbitkan demo** lewat tombol untuk header.
5. Dicek langsung: peringatan keamanan Supabase = 0; header halaman terbit; bot tetap menjawab `/unggah` (pemilik mengirim satu pesan).
6. Laporan `docs/laporan-tahap-6f.md` dan serah-terima.

## Belum pasti

- [Kemungkinan Besar] Mencabut izin `rls_auto_enable` tidak mengganggu fungsinya sebagai pemicu otomatis Supabase (pemicu tidak memeriksa izin jalankan). Dicek sesudah dipasang: membuat tabel uji sementara di Postgres uji tidak relevan; dicek dengan daftar peringatan Supabase dan pemasangan berikutnya tetap lulus.
- Batas 10 per email dan 100 per hari adalah usulan; bisa diubah pemilik.
