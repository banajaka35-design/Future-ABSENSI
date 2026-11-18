# Rencana paket 6b-baru: Sheets terisi otomatis sesudah file masuk (menunggu "buat")

18 November 2026 · dimajukan sebelum G1 (keputusan pemilik 18 Nov 2026) · acuan: PRD v2 bagian 1 dan 4 ("hasilnya muncul di Google Sheets"), temuan analisa ulang 6a-4 (Sheets tetap "SELESAI <waktu lama>" sesudah file baru masuk, HRD bisa memakai angka lama)

Nama paket: **6e** (6b dan 6c sudah dipakai untuk lembar cetak dan file bank yang ditunda).

## Jalur sekarang (dicek di kode, 18 Nov 2026)

File masuk lewat bot atau halaman unggah → `api.pintu_terima_file` menaruh periode yang terkena (dan periode sesudahnya yang sudah punya gaji) di antrean → `kerjakanAntrean` di Edge Function menghitung tiap periode dan mengirim ringkasan ke HRD. **Tidak ada yang memicu "Isi Sheets"**; workflow itu hanya jalan sesudah Pasang/Reset atau lewat tombol.

## Isi paket

1. **Dokumen dulu**: `docs/rekap-sheets.md` versi 4 (bagian "kapan diisi") dan `docs/pintu-telegram.md` (pemicu Sheets), sebelum kode.
2. **Pemicu**: sesudah antrean selesai dikerjakan dan **paling sedikit satu periode berhasil dihitung**, Edge Function meminta GitHub menjalankan workflow "Isi Sheets" (GitHub API `workflow_dispatch`, satu panggilan, coba ulang sekali). Berlaku untuk file dari bot dan dari halaman unggah. File ditolak atau periode gagal dihitung → tidak memicu.
3. **Pesan ke HRD**: sesudah pemicu berhasil: "Sheets sedang diperbarui; tunggu status SELESAI di tab Ringkasan (biasanya beberapa menit)". Pemicu gagal: "Sheets BELUM diperbarui (…alasan…); angka di Sheets masih yang lama" dan dicatat sebagai pemberitahuan segera untuk pembangun.
4. **Kunci GitHub**: token fine-grained milik pemilik, **hanya repo Future-ABSENSI, hanya izin Actions: Read and write** (bisa menjalankan workflow, tidak bisa membaca kode atau secret). Disimpan sebagai secret GitHub `GITHUB_PICU_TOKEN`, lalu diteruskan `db/pasang_pintu.sh` ke rahasia Edge Function. Tanpa secret → pemicu dilewati dan HRD diberi tahu "Sheets belum diperbarui otomatis". Token tidak pernah masuk repo atau log.
5. **Workflow "Isi Sheets"**: pemicu tetap satu antrean; GitHub hanya menyimpan satu run menunggu per antrean, jadi banyak file beruntun tidak menumpuk [Kemungkinan Besar, aturan concurrency GitHub]. Waktu "file masuk" dicatat di Riwayat isi supaya lama file masuk → SELESAI bisa diukur.
6. **Uji otomatis** (`sistem/uji/uji_pintu.sh`, GitHub tiruan): file diterima dan dihitung → satu panggilan pemicu dengan alamat dan isi yang benar; file ditolak → tidak ada panggilan; GitHub menjawab galat → pesan "Sheets BELUM diperbarui" dan pemberitahuan segera; token kosong → dilewati dengan pesan; token tidak pernah muncul di pesan atau log uji.
7. **Supabase**: Edge Function dan rahasianya dipasang ulang lewat **Pasang ke Supabase** (cabang `pasang`). Tidak ada migrasi baru [Kemungkinan Besar; bila ternyata perlu fungsi baru untuk mencatat waktu file masuk, ditulis di migrasi baru dan disebut di laporan].
8. **Uji nyata** (pemilik mengirim satu file lewat bot): file uji dibuat Claude dari file simulasi periode 21 Nov–20 Des **dengan satu baris dibuang** (sidik berbeda sehingga diterima, semua tap sudah ada di gudang sehingga angka gaji tidak berubah). Dicek: bot membalas pesan Sheets; run "Isi Sheets" terpicu dari Edge Function; pemeriksa 0 beda; total gaji bersih periode itu sama dengan sebelum; lama file masuk → SELESAI diukur.
9. Penutup C1–C5 dan M1–M2 di atas (tombol Reset dihapus; pesan Telegram di akhir Isi Sheets; waktu file masuk di Riwayat isi), dengan uji otomatis masing-masing (pesan akhir terkirim ke daftar penerima tiruan; Reset tidak lagi punya tombol).
10. Laporan dan serah-terima.

## Analisa ulang celah (18 Nov 2026, sebelum "buat")

**Merugikan → ditutup di paket ini**

| No | Celah | Penutup (masuk isi paket) |
| --- | --- | --- |
| C1 | [Pasti] Izin "Actions: Read and write" bukan hanya untuk "Isi Sheets": siapa pun yang memegang token bisa menjalankan **semua** workflow yang punya tombol, termasuk **Reset Supabase** (kata konfirmasi `RESET` bisa dikirim lewat API, dicek di file workflow) dan Pasang. Bila token bocor dari Supabase, gudang bisa dikosongkan. | Tombol (`workflow_dispatch`) **dihapus dari Reset Supabase**; Reset hanya lewat dorongan ke cabang `reset` (butuh izin isi repo, yang tidak dimiliki token ini). Pasang tetap bertombol (selalu mencadangkan dulu dan tidak menghapus data). |
| C2 | [Kemungkinan Besar] Izin yang sama bisa menghapus artifact dan log workflow, termasuk cadangan database. | Tidak bisa dibatasi lebih sempit di token GitHub. Dikurangi: token berlaku **90 hari** (bukan 1 tahun), hanya repo ini, dan hanya disimpan di rahasia Edge Function. Dicatat terus terang di laporan. |
| C3 | HRD diberi tahu "Sheets sedang diperbarui", tetapi bila workflow Isi Sheets gagal sesudahnya, HRD tidak tahu (hanya lampu merah di GitHub). | Workflow Isi Sheets **mengirim pesan Telegram ke semua akun HRD/pembangun** di akhir: "Sheets SELESAI, diperiksa sama dengan gudang" atau "Sheets GAGAL diperbarui, jangan dipakai" (bot token sudah ada di secret GitHub; daftar penerima dibaca dari gudang). |
| C4 | Dua file beruntun: pemeriksa bisa membaca gudang yang sudah berubah lagi di tengah pemeriksaan → GAGAL palsu. | Dibiarkan aman: GAGAL berarti "jangan dipakai", dan run berikutnya (sudah antre) mengisi ulang. Pesan C3 menyebut "akan diisi ulang otomatis" bila masih ada run menunggu. |
| C5 | Token habis masa berlaku tanpa kabar → Sheets diam-diam tidak diperbarui. | Pemicu gagal → HRD diberi tahu "Sheets BELUM diperbarui" dan pemberitahuan segera untuk pembangun (sudah di isi paket); tanggal habis token dicatat di serah-terima. |

**Menguntungkan → dimanfaatkan**

| No | Peluang | Dipakai |
| --- | --- | --- |
| M1 | Pesan penutup C3 sekaligus menutup alur "zero-touch": HRD kirim file → bot menghitung → **bot sendiri mengabarkan Sheets sudah siap**. Bahan video portofolio yang lengkap tanpa membuka GitHub. | Ya (C3) |
| M2 | Waktu file masuk ikut dikirim ke workflow → lama "file masuk → Sheets SELESAI" terukur otomatis setiap kali dan tertulis di Riwayat isi. | Ya |
| M3 | Halaman demo juga bisa ikut terbit otomatis sesudah file masuk. | **Tidak**: untuk perusahaan sungguhan halaman demo tidak boleh memuat data asli; tetap hanya sesudah Pasang/tombol. |

## Yang disiapkan pemilik (dipandu satu per satu)

Membuat token fine-grained di GitHub (Settings → Developer settings): hanya repo Future-ABSENSI, izin Actions: Read and write, **masa berlaku 90 hari** (C2). Lalu mengisi secret `GITHUB_PICU_TOKEN`. Tanggal habisnya dicatat di serah-terima.

## Tidak diubah

Mesin hitung, isi Sheets, halaman demo (tidak ikut terbit otomatis; tetap sesudah Pasang/tombol), data simulasi.

## Belum pasti

- [Kemungkinan Besar] File yang semua tapnya sudah ada tetap memicu hitung ulang (antrean diisi untuk periode yang terkena tanpa melihat tap baru; dari kode `pintu_terima_file`). Dibuktikan di uji nyata.
- [Kemungkinan Besar] Edge Function boleh memanggil api.github.com (jalur keluar Supabase terbuka; bot sudah memanggil Telegram dan Brevo).
- Lama file masuk → SELESAI belum diukur; perkiraan tidak ditulis sebelum diukur.
