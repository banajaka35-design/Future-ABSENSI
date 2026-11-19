# Rencana paket 8a: pendaftaran karyawan lewat bot

19 November 2026 · di-"buat" pemilik 19 Nov 2026 15.18 WIB · `docs/rencana-tahap-8.md` · PRD v2 celah K1, K8

Ditulis sebelum kode. Yang tidak tertulis di sini tidak ikut dikerjakan.

## Alur

1. HRD (atau pembangun) di chat pribadi bot: `/kode 10001`. Bot membalas kode sekali pakai 10 huruf/angka (tanpa huruf yang mirip: O, 0, I, 1, L), berlaku **60 menit**, beserta nama dan divisi orang itu.
2. HRD memberikan kode langsung ke karyawan.
3. Karyawan, di chat pribadi bot: `/daftar KODE`. Bot menampilkan nama dan divisi dengan tombol "Ya, ini saya" / "Bukan" (K8).
4. "Ya" → akun Telegram itu tersambung sebagai `karyawan` untuk ID tersebut. "Bukan" → kode dibatalkan; minta kode baru ke HRD.

## Pengaman

- Kode sekali pakai; kedaluwarsa, salah, atau sudah dipakai → ditolak. Database hanya menyimpan sidik SHA-256 kode.
- **5 kode salah dalam 1 jam** dari satu akun Telegram → akun itu tidak bisa `/daftar` sampai 1 jam sejak salah pertama di jendela itu.
- Satu akun Telegram untuk satu ID (akun yang sudah terdaftar dengan peran apa pun tidak bisa `/daftar`); satu ID hanya punya satu akun aktif.
- Ganti HP hanya lewat HRD: `/kode 10001 ganti`. Akun lama baru dinonaktifkan setelah akun baru menekan "Ya". Tanpa `ganti`, kode untuk ID yang sudah punya akun aktif ditolak.
- Kode baru untuk ID yang sama membatalkan kode lama yang belum dipakai.
- Karyawan yang sudah berhenti (status terakhir `berhenti` dengan tanggal sebelum hari ini; tanggal berhenti = hari kerja terakhir, C11) tidak bisa dibuatkan kode atau mendaftar.
- Tombol konfirmasi hanya berlaku untuk akun Telegram yang mengetik `/daftar` dengan kode itu.
- Akun karyawan tidak bisa mengirim file, `/unggah`, atau `/kode`. Semua hanya di chat pribadi (G1-3).
- Pesan pendaftaran hanya memuat nama dan divisi, tanpa angka gaji. Orang rahasia mendaftar dengan cara yang sama.

## Isi paket

1. Migrasi 0025: `induk.kode_daftar` lama (kosong, tidak pernah dipakai, menyimpan kode apa adanya) dihapus; diganti `fakta.kode_daftar` (sidik) dan `fakta.percobaan_daftar`; fungsi `fakta.karyawan_aktif`, `api.pintu_buat_kode`, `api.pintu_daftar`, `api.pintu_daftar_jawab`, `api.pintu_akun`.
2. Bot (`sistem/pintu/inti.ts`): `/kode`, `/daftar`, tombol konfirmasi; balasan teks untuk akun karyawan.
3. Uji `db/uji/170_daftar_karyawan.sql` dan `sistem/pintu/uji_pintu.ts`.
4. Pasang ke Supabase sesudah uji GitHub lulus.
5. Uji nyata sebagian: pemilik `/kode 10001` → bot membalas kode; pemilik `/daftar SALAH12345` → ditolak (separuh gerbang Tahap 8). Pendaftaran berhasil butuh akun Telegram kedua (menunggu orang lain, aturan 10); jalur berhasil diuji otomatis.
6. `docs/laporan-8a.md`, serah-terima.

Nilai 60 menit dan 5 kali salah adalah nilai bawaan Claude (PRD hanya "berlaku singkat").
