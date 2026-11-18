# Paket H1: hemat menit GitHub Actions

18 November 2026 · di-"buat" pemilik 18 Nov 2026 · dikerjakan sebelum G1-2 (`docs/rencana-perbaikan-g1.md`)

## Alasan

Repo tetap private (keputusan pemilik 18 Nov 2026). Jatah gratis GitHub untuk repo private adalah 2.000 menit per bulan [Kemungkinan Besar; angka resmi tidak bisa dibaca dari sesi Claude, lihat https://github.com/settings/billing].

Pemakaian 1–18 Nov 2026, dihitung dari 270 run [Pasti]:
- total ±1.086 menit, dengan irama ±1.810 menit per bulan;
- "Uji database" 165 run, 832 menit. Dari jumlah itu:
  - 81 run (440 menit) untuk commit yang hanya mengubah `docs/`;
  - 26 run (±130 menit) di cabang `pasang`, untuk commit yang sudah diuji di main.

## Isi

1. `uji-database.yml`:
   - hanya untuk push ke `main`, dilewati bila yang berubah hanya `docs/**`;
   - pemicu `pull_request` dihapus, karena PR tidak dipakai;
   - cabang `pasang`/`reset` tidak diuji ulang.
2. `db/periksa_pemicu.sh` menelusuri commit main ke belakang (paling jauh 30 commit) sampai menemukan commit yang uji otomatisnya lulus. Commit yang dilewati harus:
   - hanya mengubah `docs/` (satu induk, minimal 1 berkas, kurang dari 300 berkas);
   - tidak punya uji yang gagal, dibatalkan, atau belum selesai.
   Syarat lama "harus commit terbaru main" tetap berlaku.
3. `sistem/uji/uji_pemicu.sh`: 12 kasus. Ia memakai gh tiruan yang menjalankan ekspresi jq asli, sehingga ekspresi jq di skrip ikut teruji. Ekspresi jq yang sama juga dicoba sekali terhadap jawaban API GitHub sungguhan (commit d20f6e4 dan e28ed4d) dan hasilnya sesuai.
4. CLAUDE.md aturan 8: satu kalimat tambahan.

## Tidak diubah

Supabase, mesin hitung, Sheets, bot, Cadangan malam, Isi Sheets, Terbitkan demo.

## Belum pasti

- [Kemungkinan Besar] Hemat ±570 menit per 18 hari dengan pola kerja yang sama.
- [Menebak] Pemakaian akhir ±850–950 menit per bulan. Angka ini baru bisa diukur seminggu sesudah terpasang (target cek: 25 Nov 2026).
