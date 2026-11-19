# Laporan paket 8a: pendaftaran karyawan lewat bot

19 November 2026 · rencana `docs/rencana-8a.md` (di-"buat" pemilik 19 Nov 2026 15.18 WIB) · `docs/rencana-tahap-8.md` · commit c1b5068 · PRD v2 celah K1, K8

## Yang dibuat

1. **Migrasi 0025** (`db/migrasi/0025_daftar_karyawan.sql`)
   - `induk.kode_daftar` lama dihapus (kosong, tidak pernah dipakai, menyimpan kode apa adanya). Diganti `fakta.kode_daftar` yang hanya menyimpan sidik SHA-256 kode, dan `fakta.percobaan_daftar`.
   - `fakta.karyawan_aktif`: status terakhir sampai hari ini bukan `berhenti` sebelum hari ini (tanggal berhenti = hari kerja terakhir, C11), dan sudah `mulai`.
   - `api.pintu_buat_kode`, `api.pintu_daftar`, `api.pintu_daftar_jawab`, `api.pintu_akun` (izin untuk peran `pintu`). Fungsi `fakta.*` tidak bisa dipanggil `pintu`.
2. **Bot** (`sistem/pintu/inti.ts`): `/kode <ID>` dan `/kode <ID> ganti` (HRD/pembangun), `/daftar KODE` (huruf kecil dan tanda hubung dirapikan), tombol "Ya, ini saya" / "Bukan", balasan teks untuk akun karyawan. Kode 10 huruf/angka dari 31 tanda (tanpa O, 0, I, 1, L), acak dengan penolakan supaya setiap tanda sama peluangnya.
3. **Uji**: `db/uji/170_daftar_karyawan.sql` (39 uji) dan 8 uji alur lengkap di `sistem/pintu/uji_pintu.ts`.

## Pengaman yang terbukti oleh uji otomatis [Pasti]

Kode berlaku 60 menit dan sekali pakai; kedaluwarsa, salah, sudah dipakai → ditolak. Kode baru untuk ID yang sama menutup kode lama. 5 kode salah dalam 1 jam → akun Telegram itu terkunci (kode benar pun ditolak), akun lain tidak ikut; sesudah 1 jam boleh mencoba lagi. Satu akun Telegram untuk satu ID (akun HRD atau yang sudah terdaftar tidak bisa `/daftar`); satu ID satu akun aktif; ganti HP hanya dengan `/kode <ID> ganti`, akun lama nonaktif hanya setelah akun baru menekan "Ya". Tombol konfirmasi hanya berlaku untuk akun yang mengetik `/daftar` dengan kode itu. "Bukan" membatalkan kode. Berhenti kemarin → ditolak; berhenti hari ini (hari kerja terakhir) → boleh. Akun karyawan tidak bisa `/unggah`, `/kode`, atau mengirim file. `/daftar` di grup tidak diproses. Pesan tanpa angka gaji. Pendaftaran tercatat di `jejak.perubahan`.

**Uji bisa gagal**: dengan batas dilemahkan (50 kali) dan aturan berhenti dilonggarkan satu hari, 4 uji GAGAL (berhenti kemarin, kunci ke-6, kode benar saat terkunci, akun lain).

## Hasil uji [Pasti]

- Lokal: database 506 lulus 0 gagal (sebelumnya 467); pintu 56 lulus 0 gagal (sebelumnya 48).
- GitHub run 44487624352 lulus: database 506, simulasi 123, pintu 56, penyambung 23, cadangan 9.
- Pasang ke Supabase run 44489333255 lulus: cadangan terenkripsi dulu (1 file `.gpg`, pemasangan pertama sesudah E1), hanya 0025 dipasang, pemeriksaan 31 lulus 0 gagal, Edge Function dipasang ulang.
- Dicek langsung di Supabase: 0025 terpasang 15.41 WIB, sidik `b624ae31a706` sama dengan repo; tabel lama hilang, tabel baru ada; `pintu` boleh memanggil `api.pintu_daftar`, `anon` tidak; `pintu` tidak boleh memanggil `fakta.karyawan_aktif`.

## Uji nyata (19 Nov 2026) [Pasti]

- Pemilik mengirim `/daftar` tanpa kode (15.44 WIB) → bot membalas cara pakai.
- Pemilik mengirim `/kode 10001` (15.46 WIB) → bot membalas "Kode daftar untuk 10001 Eka Susanto (Produksi): …", berlaku sampai 16.46 WIB.
- Di Supabase: 1 baris kode untuk 10001, dibuat oleh akun pembangun, kedaluwarsa 16.46.27 WIB; sidiknya sama dengan SHA-256 kode di pesan bot, dan kodenya sendiri tidak ada di baris itu. Kode tidak dipakai dan batal sendiri pukul 16.46 WIB.

**Belum dibuktikan nyata** (syarat yang menunggu orang lain, aturan 10): `/daftar` dengan kode salah dan pendaftaran berhasil butuh **akun Telegram kedua** yang belum terdaftar; akun pemilik sudah terdaftar sebagai pembangun. Kedua jalur lulus di uji otomatis. Ini separuh gerbang Tahap 8 ("pendaftaran dengan kode salah ditolak"); separuh lainnya ("pesan sampai ke akun uji") ada di paket 8c.

## Temuan dan catatan

- [Pasti] 11 karyawan simulasi mulai bekerja 24 Nov 2026 atau sesudahnya; `/kode` untuk mereka ditolak sampai tanggal mulai (dianggap belum aktif). 38 orang ditolak karena sudah berhenti. Perlu keputusan pemilik: apakah HRD boleh mendaftarkan karyawan sebelum hari pertamanya.
- Kode pada uji nyata sempat tampil di chat Claude lewat tangkapan layar. Untuk data simulasi tidak masalah (kedaluwarsa 16.46 WIB). Untuk perusahaan sungguhan, kode cukup diberikan langsung ke karyawan.
- [Kemungkinan Besar] Tidak ada batas jumlah `/daftar` salah untuk semua akun sekaligus; dengan 31^10 kemungkinan kode, berlaku 60 menit, dan 5 kali per akun per jam, menebak kode tidak masuk akal walau dengan banyak akun. Tidak dikerjakan (tidak ada di daftar paket).

## Tidak diubah

Mesin hitung, Sheets, halaman demo, cadangan.
