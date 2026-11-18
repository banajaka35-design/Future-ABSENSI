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
9. Laporan dan serah-terima.

## Yang disiapkan pemilik (dipandu satu per satu)

Membuat token fine-grained di GitHub (Settings → Developer settings), lalu mengisi secret `GITHUB_PICU_TOKEN`. Masa berlaku token paling lama 1 tahun [Kemungkinan Besar, batas GitHub]; tanggal habisnya dicatat di serah-terima.

## Tidak diubah

Mesin hitung, isi Sheets, halaman demo (tidak ikut terbit otomatis; tetap sesudah Pasang/tombol), data simulasi.

## Belum pasti

- [Kemungkinan Besar] File yang semua tapnya sudah ada tetap memicu hitung ulang (antrean diisi untuk periode yang terkena tanpa melihat tap baru; dari kode `pintu_terima_file`). Dibuktikan di uji nyata.
- [Kemungkinan Besar] Edge Function boleh memanggil api.github.com (jalur keluar Supabase terbuka; bot sudah memanggil Telegram dan Brevo).
- Lama file masuk → SELESAI belum diukur; perkiraan tidak ditulis sebelum diukur.
