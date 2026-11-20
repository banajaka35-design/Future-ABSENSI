# Laporan paket 8d: jalur bos (terpasang; uji nyata berjalan)

20 November 2026 · rencana `docs/rencana-8d.md` · commit e0650c6

## Yang dibuat

Migrasi `0031_jalur_bos.sql` (constraint `rahasia_wajib_transfer`, `/pin` untuk bos, `api.pintu_total_lengkap`, `api.pintu_periode_gaji`, `fakta.lihat_rahasia`, aksi menunggu PIN `lengkap`, `/hapuspin` ikut akun bos); bot `/lengkap`, tombol Total lengkap, `susunTotalLengkap`.

## Temuan saat membuat [Pasti]

- Kunci `rahasia` di isi periode menimpa daftar orang rahasia → daftar diberi nama `daftar_rahasia`.
- Bukti gagal pertama menunjukkan uji "orang rahasia tidak boleh tunai" lulus karena alasan lain (riwayat bertabrakan); uji diganti memakai karyawan tanpa riwayat, lalu terbukti GAGAL bila constraint dihapus.

## Uji yang diubah karena aturan berubah

- `db/uji/200_rilis_mudah.sql`: daftar `/hapuspin` kini memuat akun bos.
- `sistem/pintu/uji_pintu.ts` (8b, 8b-3): teks penolakan `/pin` kini "PIN hanya untuk akun HRD, bos, dan pembangun".

## Uji [Pasti]

- Lokal: database 643 (sebelumnya 629), pintu 98 (sebelumnya 93), simulasi 128. Bukti gagal: PIN dan constraint dimatikan → 3 uji 230 GAGAL.
- GitHub run 44712487795 lulus (database 643, simulasi 128, pintu 98, penyambung 23).

## Pemasangan [Pasti]

- Pasang run 44714462728 lulus; sidik 0031 `4cf65c3e4b02` = repo; constraint terpasang; `pintu` boleh, `anon` tidak; menu dipasang ulang.

## Belum selesai

- Uji nyata `/lengkap` dengan akun pembangun; jalur bos sungguhan menunggu akun ketiga (`/undang bos`).

## Uji nyata 8d (20 Nov 2026 17.04 WIB) [Pasti]

- Akun pembangun: Total lengkap → No. 2 → PIN. 1.010 orang, bersih Rp8.216.972.265; terlihat HRD 1.007 orang, Rp8.191.433.902; selisih 3 orang rahasia Rp25.538.363 = 9.546.454 + 9.392.875 + 6.599.034 (F15b). Transfer 7.085.503.657 + tunai 1.131.454.000 = dibayar 8.216.957.657; transfer = transfer HRD 7.059.965.294 + 3 orang rahasia (semua transfer). `fakta.lihat_rahasia`: pembangun, periode 2, 17.04, versi yang dirilis.
- Temuan: PIN dua kali diketik sebelum tombol periode ditekan → paket 8d-2 (`docs/rencana-8d-2.md`).
