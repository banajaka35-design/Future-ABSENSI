# Catatan serah terima

File ini ditulis supaya siapa pun yang melanjutkan proyek (manusia, Claude di chat lain, atau Claude di sesi baru) tahu posisi terakhir tanpa harus membaca riwayat chat. **Perbarui file ini setiap kali satu langkah selesai.**

Terakhir diperbarui: 12 November 2026, 23.10 WIB, cabang `tahap-2b`.

## Aturan sebelum mengubah apa pun

1. Tarik isi GitHub terbaru, lalu baca `CLAUDE.md` dan file ini.
2. **GitHub adalah satu-satunya sumber kebenaran.** Apa pun yang dipasang ke Supabase harus sudah ada di GitHub lebih dulu, dan dipasang lewat workflow, bukan langsung dari chat.
3. **Satu proyek dikerjakan di satu chat dalam satu waktu.** Kalau berpindah chat, mulai dari file ini.
4. Setiap perubahan dijelaskan ke pemilik proyek dalam satu paragraf bahasa sederhana: apa yang diubah, kenapa, dan cara mengeceknya.

Alasan aturan 2–4: pada 12 Nov 2026 pukul 21.14–21.16 WIB, migrasi 0001–0004 dipasang ke Supabase oleh sesi Claude lain, dan file 0004 tidak dikirim ke GitHub. Pemilik proyek tidak tahu perubahan itu terjadi. File asli ditemukan kembali dan sidiknya cocok (lihat di bawah).

## Posisi sekarang: Tahap 2 (gudang data), gerbang belum lulus

### Sudah terbukti

| Hal | Bukti |
| --- | --- |
| Migrasi 0001–0004 ada di GitHub dan di Supabase, sidiknya sama | `jejak.migrasi` di Supabase; sidik 0004 = `08ff638a00a1…d091dd` |
| Uji otomatis memasang 0001–0004 dari nol | GitHub Actions "Uji database": 63 lulus, 0 gagal |
| Struktur Pabrik A di Supabase | mesin 2, divisi 5, kalender 22, pengali lembur 44 |
| Karyawan di Supabase masih kosong | `induk.karyawan` = 0 (CSV berisi 1.044) |
| Secret `SUPABASE_DB_URL` (Session pooler) dibuat dan berfungsi | Workflow "Cek koneksi Supabase" tersambung, server Postgres 17.11 |
| Klien Postgres 17 bisa dipasang dari PGDG di GitHub Actions | psql 17.12 terpasang di workflow cek-koneksi |

### Temuan yang perlu diingat

- **Pengaturan koneksi diabaikan lewat Session pooler.** `PGOPTIONS=-c default_transaction_read_only=on` tidak berlaku (hasil `show` = off). Pengaman tidak boleh bergantung pada pengaturan koneksi; harus ada di dalam perintah atau skripnya (Kemungkinan Besar: pooler membuang opsi itu).
- **Data awal tidak bisa dijalankan dua kali.** `pabrik_a_struktur.sql` dan `muat_karyawan.py` memakai `insert` biasa. Pemasangan harus memeriksa dulu apakah datanya sudah ada.
- **Tombol "Run workflow" hanya muncul untuk workflow yang ada di cabang main** (Kemungkinan Besar, aturan GitHub). Karena itu penggabungan tahap-2b ke main dikerjakan sebelum workflow pasang-supabase dipakai.
- **Uji pemulihan ke postgres:17 polos** kemungkinan gagal kalau seluruh database dicadangkan, karena ada peran dan skema khusus Supabase. Cadangkan hanya skema milik proyek, dan siapkan peran dengan `db/uji/persiapan_peran.sql`.
- **Cadangan skema proyek belum bisa dipulihkan utuh begitu saja** (Terbukti di Postgres 16 lokal): 18 galat "no default operator class for access method gist", karena ekstensi `btree_gist` ada di skema `extensions` yang tidak ikut dicadangkan. Uji pemulihan (langkah 4) harus membuat ekstensi itu lebih dulu, lalu memastikan galatnya nol.
- **Sentuhan harian lewat koneksi database belum tentu dihitung aktif oleh Supabase** (Menebak). Baru terbukti setelah gerbang "demo hidup setelah 8 hari".
- GitHub mematikan jadwal otomatis di repo yang 60 hari tanpa commit (Kemungkinan Besar).

### Keputusan pemilik proyek (12 Nov 2026)

| Keputusan | Isi |
| --- | --- |
| Muat karyawan | Dilebur ke workflow pasang-supabase, tidak dibuat workflow terpisah, supaya cadangan diambil lebih dulu (F13) |
| Pengaman tombol | Workflow pasang-supabase hanya jalan kalau pemilik mengetik `PASANG` |
| Umur simpan cadangan | 30 hari (artifact GitHub; hanya untuk data simulasi, tidak untuk perusahaan sungguhan) |
| Urutan | Gabung tahap-2b ke main dikerjakan sebelum workflow pasang-supabase dijalankan |

## Langkah berikutnya (satu per satu, masing-masing menunggu "buat")

1. ~~Workflow `pasang-supabase`~~ **Selesai dibuat (12 Nov 2026, belum pernah dijalankan ke Supabase).** File: `.github/workflows/pasang-supabase.yml` dan `db/pasang_supabase.sh`. Diuji di Postgres 16 lokal (bukan 17, bukan Supabase) dengan empat keadaan: seperti Supabase sekarang (karyawan dimuat, 9 pemeriksaan lulus), pasang ulang (semua dilewati), database kosong (semua dimuat), dan struktur setengah ada (berhenti dengan GAGAL). Skema `uji` tidak tertinggal.
2. Gabung tahap-2b ke main setelah uji otomatis lulus.
3. Pemilik menjalankan pasang-supabase; hasilnya diperiksa langsung di Supabase (karyawan 1.044).
4. Cadangan malam + uji pemulihan ke postgres:17 (bandingkan hitung baris), sekaligus sentuhan harian.

## Sisa gerbang Tahap 2 setelah langkah di atas

- Tempat uji terpisah dari utama (saat ini hanya ada satu proyek Supabase).
- "Ambil data tanpa login ditolak" dibuktikan di Supabase sungguhan, bukan hanya di Postgres sementara.
- Demo masih hidup setelah 8 hari tanpa dipakai.

## Belum dikerjakan, ditunda

- Tabel TER dan PTKP: Tahap 4.
- Batas upah Jaminan Pensiun 2026: perlu dicek.
- Peringatan advisor `public.rls_auto_enable()` adalah bawaan Supabase, dibiarkan.

## Sisa tes sambungan (boleh dihapus, menunggu izin pemilik)

- Cabang `tes-claude` di repo ini (berisi `TES-CLAUDE.md`).
- Sel A1 di Google Sheets "PROJECT ABSENSI" berisi "TES CLAUDE - boleh dihapus".
- File "TES CLAUDE - boleh dihapus.txt" di folder Drive "PROJECT ABSENSI".
