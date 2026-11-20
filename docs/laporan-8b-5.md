# Laporan paket 8b-5: Sheets ikut status rilis; tombol tetap tidak hilang (terpasang; uji nyata berjalan)

20 November 2026 · rencana `docs/rencana-8b-5.md` · commit 974f090

## Yang dibuat

- `sistem/pintu/inti.ts`: `statusBerubah` → `picuSheets(..., karenaStatus=true)` (pemicu "status periode", waktu_file kosong, dicatat di `fakta.picu_sheets` dengan waktu_file null) sesudah ajukan, setujui/tolak, rilis, batal yang berhasil, dalam `finally` sesudah balasan utama. Permintaan PIN tanpa force reply. Jawaban pertanyaan `PIN`/`Kode karyawan` dikirim dengan tombol tetap (`papanAkun`).
- Uji: 3 uji baru, 3 uji lama disesuaikan (jumlah pesan tanpa kabar Sheets; permintaan PIN tanpa force reply).

## Uji [Pasti]

- Lokal: pintu 85 lulus (sebelumnya 82). Uji bisa gagal: pemicu dimatikan → 2 uji GAGAL.
- GitHub run 44675086604 lulus: database 603, simulasi 128, pintu 85, penyambung 23.

## Pemasangan [Pasti]

- Pasang run 44676048297 lulus (tanpa migrasi; pemeriksaan 33 lulus; Edge Function dipasang ulang).
- Isi Sheets sesudah Pasang (11.47 WIB): kolom "Status rilis" = periode 1 Dirilis, 2 Dirilis, 3 Bisa diajukan, 4 "rilis dulu periode no. 3"; sama dengan Supabase; pemeriksa "sama dengan gudang". Terbitkan demo lulus.

## Belum selesai

- Uji nyata pemicu Sheets dari bot (bukan dari Pasang) dan tombol tetap sesudah PIN.
