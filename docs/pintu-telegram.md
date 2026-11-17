# Pintu Telegram (Tahap 5, paket 5b)

17 November 2026 · ditulis sebelum kode · acuan: PRD v3.1 bagian 6, 9, 12 (A7, A10, D2, L1, M1), 15, 17

## Alur

1. HRD mengirim file mesin (dokumen) ke bot. Telegram meneruskan pesan ke Edge Function `pintu-telegram`.
2. Edge Function memeriksa kode rahasia dari Telegram (`X-Telegram-Bot-Api-Secret-Token`). Salah → ditolak, tidak ada yang tersimpan.
3. Nomor pesan Telegram (`update_id`) dicatat. Sudah pernah tercatat → pesan diabaikan diam-diam (Telegram mengirim ulang, kasus A10).
4. Pengirim harus akun terdaftar dan aktif dengan hak akses `hrd` atau `pembangun` (`induk.pengguna`; `pembangun` ditambah 17 Nov 2026 atas keputusan pemilik, migrasi 0017). Bukan → bot membalas "Akun Anda belum terdaftar sebagai HRD"; file **tidak diunduh dan tidak disimpan**.
5. Mesin asal file:
   - keterangan (caption) pesan berisi kode mesin yang dikenal → mesin itu;
   - perusahaan hanya punya satu mesin → mesin itu;
   - selain itu bot menampilkan tombol pilihan mesin; file menunggu sampai HRD menekan salah satu tombol.
6. Bot membalas **"File diterima, sedang diproses"** sebelum kerja berat (target PRD: paling lama 5 detik).
7. Di belakang (sesudah balasan): unduh file dari Telegram → hitung sidik SHA-256 → urai dengan `sistem/urai` (pembaca yang sama dengan uji Tahap 3) → `fakta.terima_kiriman` dengan pengirim dan nomor pesan.
   - Ditolak → bot membalas alasannya (file sama sudah diterima, rusak karena Excel, format tidak dikenal, dan seterusnya).
   - Diterima → setiap periode yang terkena masuk **antrean kerja**.
8. Antrean dikerjakan satu per satu, berurutan (prinsip F6): baca tap lalu hitung gaji untuk satu periode per langkah. Bila hitung ulang satu periode, periode sesudahnya yang sudah punya gaji ikut masuk antrean (rantai sisa pembulatan dan kasbon, temuan 4b-2).
9. Bot mengirim ringkasan per periode: jumlah hari-orang, gaji bersih total, bisa diajukan atau tidak, dan jumlah tanda baca tap tingkat "segera". Isi pemberitahuan tingkat segera yang lengkap dikerjakan di paket 5c (U14).

## Akses database

- Edge Function tersambung sebagai peran **`pintu`**: hanya boleh menjalankan fungsi di skema `api` yang dibuat untuknya. Tidak bisa membaca atau mengubah tabel langsung.
- Kata sandi peran `pintu` dibuat acak oleh workflow pemasangan setiap kali dipasang, disimpan hanya di rahasia Edge Function. Tidak ada di repo.
- Fungsi `api` memeriksa ulang bahwa pengirim adalah HRD aktif; Edge Function tidak dipercaya begitu saja.

## Kasus uji (wajib benar)

| No | Kejadian | Harapan |
| --- | --- | --- |
| T1 | HRD mengirim file sah satu mesin dengan kode mesin di keterangan | Balasan "diterima, sedang diproses"; kiriman diterima dengan pengirim dan nomor pesan; periode terkena dihitung (baca tap dan gaji); ringkasan terkirim |
| T2 | File yang sama dikirim lagi (pesan lain) | Ditolak: "File yang sama sudah diterima sebelumnya"; tap tidak bertambah (A7, L1) |
| T3 | Telegram mengirim pesan yang sama dua kali (`update_id` sama) | Pesan kedua diabaikan; tidak ada kiriman kedua dan tidak ada balasan kedua (A10) |
| T4 | File pernah dibuka dan disimpan di Excel (No.ID seperti 1,98E+17) | Ditolak dengan alasan "kirim langsung dari mesin" (M1); tidak ada tap tersimpan |
| T5 | File bukan file mesin (misalnya teks biasa) | Ditolak: format tidak dikenal |
| T6 | Pengirim bukan HRD terdaftar | Ditolak; file tidak diunduh; tidak ada kiriman tercatat |
| T7 | Tanpa kode mesin, perusahaan punya dua mesin | Tombol pilihan mesin; setelah tombol ditekan, berlanjut seperti T1 |
| T8 | Kode rahasia Telegram salah | Ditolak (HTTP 401); tidak ada yang tersimpan |
| T9 | Fungsi `api` dipanggil dengan ID Telegram bukan HRD | Ditolak oleh database walau Edge Function salah |
| T10 | Peran `pintu` mencoba membaca tabel langsung | Ditolak |

T1–T7 dan T9–T10 diuji otomatis di GitHub (pesan Telegram tiruan, Postgres sementara, data simulasi Pabrik A). T8 diuji di kode Edge Function. Uji nyata di Supabase: T2, T4 (dan T6 bila ada akun Telegram kedua); T1 tidak bisa diuji nyata di demo tanpa reset karena semua file simulasi sudah ada di sana.

## Pemasangan

Dipasang oleh workflow **"Pasang ke Supabase"** (langkah tambahan `db/pasang_pintu.sh`), bukan workflow baru: aturan 8 di CLAUDE.md hanya mengizinkan perubahan Supabase lewat workflow itu. Langkah ini dilewati (bukan gagal) selama secret `SUPABASE_ACCESS_TOKEN`, `TELEGRAM_BOT_TOKEN`, dan `PEMBANGUN_TELEGRAM_ID` belum diisi. Kata sandi peran `pintu` dan kode rahasia Telegram dibuat acak setiap pemasangan.

## Tambahan yang disetujui di tengah paket (17 Nov 2026)

Uji T1 menemukan baca tap butuh 75 detik bila di periode itu baru ada file satu mesin (pemeriksaan cakupan file F02 memeriksa ulang seluruh tap untuk setiap orang-hari). Pemilik menyetujui perbaikan di paket ini: migrasi 0016, pembaca tap versi 3, aturan tidak berubah. Diukur: 75,6 detik menjadi 4,2 detik; sidik hasil sama persis dengan versi 2 (satu file saja, dan data lengkap 4 periode).

## Batasan yang disadari

- Antrean dikerjakan oleh Edge Function yang sama, paling lama sekitar 120 detik per pesan (batas Edge Function gratis 150 detik). Sisa antrean dikerjakan saat pesan berikutnya datang. Penjadwal terpisah belum ada.
- Ukuran file dari bot Telegram paling besar 20 MB (batas Telegram untuk unduh lewat bot).
- File `.gz` belum diterima; HRD mengirim file asli dari mesin.
