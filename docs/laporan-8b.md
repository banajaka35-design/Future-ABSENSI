# Laporan paket 8b: rilis gaji dengan PIN (terpasang; uji nyata belum)

19 November 2026 · rencana `docs/rencana-8b.md` (di-"buat" pemilik 19 Nov 2026 15.52 WIB; **file rencana ditulis sesudah kode**, lihat catatan di file itu) · commit 2144ad1 · PRD v2 celah K5

## Yang dibuat

1. **Migrasi 0026** (`db/migrasi/0026_rilis_gaji.sql`)
   - Kunci tabel alur status menjadi (dari, ke, peran); langkah baru: `terbuka→dihitung` (sistem), `diajukan/disetujui→dihitung` (sistem, hitung ulang), `diajukan→dihitung` (bos menolak).
   - Pemicu di `hitung.versi_hitung`: periode `dirilis`/`dikunci` tidak boleh mendapat versi hitung baru; sesudah hitung gaji, periode menjadi `dihitung` (pengajuan yang ada batal).
   - `fakta.pengajuan_rilis`, `fakta.rilis_gaji` (hanya bertambah), `fakta.percobaan_pin`; `hitung.ringkasan_rilis` (tanpa orang rahasia, dengan transfer/tunai).
   - `api.pintu_atur_pin`, `api.pintu_daftar_periode`, `api.pintu_ajukan`, `api.pintu_setujui` (hanya akun bos), `api.pintu_rilis`.
   - Antrean melewati periode dirilis (tap tetap tersimpan) dan membuat kejadian segera `periode_dirilis_kena_file`.
   - `fakta.boleh_daftar`: karyawan boleh didaftarkan sebelum tanggal mulai; berhenti sebelum hari ini tetap ditolak.
2. **Isian pajak awal tahun 2026 KARANGAN** (`db/data_awal/pajak_awal_tahun_simulasi.sql`): 38 karyawan simulasi yang berhenti di periode 1–3; bruto Januari = gaji pokok + tunjangan tetap (cocok dengan `karyawan.csv`), iuran 0, PPh 0. Dimuat `db/pasang_supabase.sh`; bila isian bertambah, periode tahun itu dihitung ulang. Pemasangan melewati periode dirilis/dikunci; `cek_gaji.sql` mengecualikan periode itu dari syarat "versi kode terbaru".
3. **Bot**: `/pin`, `/ajukan` (ringkasan + Ajukan/Batal), tombol bos Setujui/Tolak, `/rilis` dan `/rilis <nomor> <PIN>`; pesan berisi PIN dihapus bot.
4. **Uji**: `db/uji/180_rilis_gaji.sql` (45 uji), 6 uji alur lengkap di `uji_pintu.ts`, 4 uji isian di uji simulasi.

## Dugaan yang dibuktikan sebelum kode [Pasti]

Salinan demo lokal (pemasangan sama dengan Supabase): orang tertahan 12/11/15/1.006 (sama dengan Supabase). Aturan L2: masa terakhir butuh setiap bulan sebelum bulan bayar. Dengan isian Januari untuk 38 orang: periode 1–3 bisa diajukan, Desember tetap tertahan.

## Uji [Pasti]

- Lokal: database 551 lulus (sebelumnya 506), pintu 62 (sebelumnya 56), simulasi 127 (sebelumnya 123); pembanding tetap sama sampai rupiah dengan isian Januari.
- Uji bisa gagal: penjaga dirilis, cek versi, dan cek bos dilemahkan → 6 uji GAGAL.
- Pemasangan diuji di atas salinan kode lama: isian 0→38, 4 periode dihitung ulang, status `dihitung`, pemeriksaan 33 lulus; dipasang ulang → tidak ada hitung ulang.
- Kesalahan yang tertangkap uji sebelum dikirim: kunci tabel alur (satu peran per perpindahan); dua kesalahan di data/uji sendiri.
- GitHub run 44495882866 lulus: database 551, simulasi 127, pintu 62, penyambung 23, cadangan 9.

## Pemasangan [Pasti]

Pasang run 44497579196 lulus (cadangan terenkripsi dulu; 0026; isian 0→38; 4 periode dihitung ulang; pemeriksaan 33 lulus 0 gagal; Edge Function dipasang ulang). Isi Sheets sesudahnya 0 beda; Cadangan malam sesudahnya pulih 59 tabel / 1.436.218 baris sama.

Dicek langsung di Supabase: sidik 0026 `43691e2210e7` = repo; isian 38; keempat periode `dihitung` (riwayat `terbuka>dihitung/sistem`); periode 1–3 bisa diajukan, Desember tidak.

**Perubahan angka gaji** (total tanpa orang rahasia): periode 1 tetap 5.167.334.029; periode 2 8.191.235.519 → 8.191.433.902 (+198.383); periode 3 5.690.720.227 → 5.691.968.045 (+1.247.818); periode 4 tetap 4.983.863.768. Sebabnya: PPh masa terakhir 38 orang yang berhenti kini dihitung (sebelumnya tertahan). [Kemungkinan Besar] kenaikan = pengembalian PPh karena isian karangan menulis PPh Januari 0.

## Belum selesai

- **Uji nyata belum dilakukan.** Daftar 8b salah menulis pengaturan demo "HRD saja"; di Supabase ternyata **"HRD lalu bos"** (data awal Pabrik A), dan belum ada akun bos.
- **Keputusan pemilik 19 Nov 2026 16.43 WIB: akun pembangun harus bisa melakukan semua yang bisa dilakukan akun lain**, termasuk menyetujui seperti bos; pembatasan apa pun ditanyakan dulu. Paket **8b-2** diusulkan (pembangun boleh Setujui/Tolak dengan PIN, tercatat "oleh pembangun", `/setujui <nomor> <PIN>`), **menunggu "buat"**. Sesudah itu uji nyata penuh: `/pin` → `/ajukan` 21 Feb–20 Mar → `/setujui` → `/rilis`. Periode itu lalu terkunci permanen di demo (hanya Reset yang mengembalikan).
