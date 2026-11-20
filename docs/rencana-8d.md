# Rencana paket 8d: jalur bos (total lengkap termasuk orang rahasia)

20 November 2026 · keputusan pemilik 16.10 WIB "(a)" dan 16.11 WIB "(i) … soalnya di TF dan bos wajib bisa liat, buat" · acuan `docs/rencana-tahap-8.md` baris 8d, kasus F15, F15b

## Keadaan sebelum paket [Pasti, Supabase 20 Nov 2026]

3 orang rahasia, tidak ada yang tunai. Periode 2: total lengkap gaji bersih Rp8.216.972.265, terlihat HRD Rp8.191.433.902, selisih Rp25.538.363. Belum ada akun bos; bos belum bisa membuat PIN.

## Isi paket

1. Migrasi `0031_jalur_bos.sql`:
   - (i) `induk.karyawan_riwayat` constraint `rahasia_wajib_transfer`.
   - `/pin` untuk HRD, bos, pembangun; `/hapuspin` ikut menampilkan akun bos.
   - `api.pintu_total_lengkap` (bos/pembangun, PIN): total lengkap, total terlihat HRD, daftar orang rahasia; versi yang dirilis atau versi berlaku. Setiap lihat dicatat di `fakta.lihat_rahasia` (hanya bertambah).
   - `api.pintu_periode_gaji` (pilihan periode); menunggu PIN aksi `lengkap`.
2. Bot: `/lengkap [nomor] [PIN]`, tombol tetap **Total lengkap** (bos: Total lengkap, PIN, Bantuan; pembangun ditambah Total lengkap), pilihan periode dengan tombol lalu PIN.
3. Uji database `230_jalur_bos.sql`, 5 uji bot; bukti uji bisa gagal. Pasang. Uji nyata dengan akun pembangun; jalur bos sungguhan menunggu akun ketiga (`/undang bos`).

## Tidak termasuk

- Pesan total lengkap tidak terhapus otomatis (butuh penjadwal); bos belum memakai `/contohgaji`.
