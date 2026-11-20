# Laporan paket 8b-2: pembangun menyetujui atau menolak rilis dengan PIN (terpasang; uji nyata berjalan)

20 November 2026 · rencana `docs/rencana-8b-2.md` · commit 49492f8

## Yang dibuat

- Migrasi `0027_setujui_pembangun.sql`: `api.pintu_setujui` menerima bos (tombol, tanpa PIN) atau pembangun (wajib PIN); tercatat `fakta.persetujuan.catatan = 'oleh pembangun'` dan alasan riwayat "disetujui pembangun"/"ditolak pembangun". `api.pintu_ajukan` mengembalikan akun pembangun; `api.pintu_daftar_periode` menandai akun pembangun.
- Bot: `/setujui <nomor> <PIN>`, `/tolak <nomor> <PIN>` (pesan berisi PIN dihapus); pembangun menerima teks pengajuan tanpa tombol; pesan ke pengaju menyebut "Pembangun menyetujui/menolak".
- Uji: `db/uji/190_setujui_pembangun.sql` (16), 5 uji baru di `sistem/pintu/uji_pintu.ts`.

## Uji [Pasti]

- Lokal (Postgres 16): database 567 lulus (sebelumnya 551), pintu 67 (sebelumnya 62). Uji simulasi tidak dijalankan lokal (kode hitung tidak berubah); jalan di GitHub.
- Uji bisa gagal: pemeriksaan PIN pembangun dimatikan → 6 uji 190 GAGAL; dikembalikan.
- GitHub run 44658186046 lulus: database 567, pintu 67.

## Pemasangan [Pasti]

- Pasang run 44660004407 lulus: cadangan terenkripsi `cadangan-sebelum-pasang-32`; hanya 0027 dipasang; pemeriksaan 33 lulus 0 gagal; Pintu Telegram dipasang ulang.
- Dicek langsung di Supabase: sidik 0027 `dfeb1fd7075d` = repo; fungsi baru aktif; peran `pintu` boleh memanggil, `anon` tidak; keempat periode tetap `dihitung`; pengajuan dan persetujuan 0.

## Belum selesai

- Uji nyata oleh pemilik: `/pin` → `/ajukan` periode 2 (21 Feb–20 Mar 2026) → `/setujui 2 <PIN>` → `/rilis 2 <PIN>`.
- [Menebak] Sheets dan halaman demo tidak berubah karena status `dirilis`; dicek sesudah uji nyata.
