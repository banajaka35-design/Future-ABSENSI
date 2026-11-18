# Laporan paket 6a-2: cara bayar berpola, daftar transfer/tunai dipisah

18 November 2026 · "buat" pemilik 18 Nov 2026 · permintaan perubahan 03 · rancangan `docs/rekap-sheets.md` versi 2 (commit c5edd92, sebelum kode)

## Yang diubah

| Bagian | Isi | Commit |
| --- | --- | --- |
| Generator | `divisi_tunai` (A: GDG; B: PRD, GDG) menggantikan peluang acak; angka acak tetap diambil supaya data lain tidak bergeser | 99a9edc |
| Data simulasi | Hanya kolom `cara_bayar` di `A/induk/karyawan.csv` (380 orang berubah) dan `B/induk/karyawan.csv` (80 orang berubah). Semua file lain identik byte demi byte (sidik sama). Kewajaran data 130/130 lulus | 99a9edc |
| Sheets | Dua tab per periode (`... transfer`, `... tunai`); tab tunai + 7 kolom isi amplop per orang | fdb1916 |
| Pemeriksa | Orang di tab sesuai cara bayar; amplop = dibayar; lembar semua amplop = `hitung.pecahan_tunai` | fdb1916 |
| Uji Sheets tiruan | 40 uji (sebelumnya 30) | fdb1916 |

Tidak diubah: kasus jebakan, migrasi, mesin hitung, halaman demo (angka ikut gudang).

## Hasil (diukur)

- Uji GitHub commit fdb1916 (run 44234826586): uji database 453 lulus; uji simulasi 65 lulus (U1, U2, U5, U10, halaman demo = gudang, 40 uji Sheets); 0 gagal.
- Reset Supabase (run 44235942621): lulus; 04.14.30–04.29.04 UTC (sekitar 14,5 menit; Reset 13 Nov sekitar 3 menit; penyebab belum diperiksa). Akun pengguna kosong sesudah Reset, sesuai dugaan.
- Pasang ke Supabase (run 44237654024): lulus, sekitar 4 menit; pemeriksaan 31 lulus 0 gagal; peran `pintu` masuk pada percobaan ke-1; akun pengirim file terdaftar 1; webhook Telegram terpasang; jadwal pengingat aktif.
- Sesudah Pasang otomatis: Isi Sheets lulus (lama isi 15.300 ms, 26 permintaan; pemeriksa 0 beda; **lama dari awal Pasang sampai Sheets SELESAI: 331 detik**), Terbitkan demo lulus, Cadangan malam lulus.

## Dicek langsung di Supabase (18 Nov 2026)

- Karyawan 1.044; cara bayar: GDG tunai 158, KAM/KTR/PRD/QC transfer (54/124/624/84).
- **Total gaji bersih per periode sama persis dengan sebelum paket**: 5.183.058.029 · 8.216.773.882 · 5.706.405.590 · 4.999.870.485. Orang per periode 1.011 · 1.010 · 1.010 · 1.006. Hasil harian 119.853 (sama).
- Tunai per periode (jumlah pecahan): 696.157.000 · 1.131.454.000 (periode THR) · 697.009.000 · 703.801.000.
- Akun pembangun aktif 1; skema `uji` tidak tertinggal.

## Dicek langsung di Sheets

- Tab: Sheet1 (tidak disentuh), Ringkasan, Riwayat isi, 8 tab Gaji (transfer 854–861 baris, tunai 154–157 baris). Tab versi 1 terhapus.
- Ringkasan periode 4: transfer 4.296.067.659, tunai 703.801.000 = Supabase; status `SELESAI 2026-11-18 11:34:48 WIB`.
- Contoh tunai: 10731 Nurul Pohan, GDG, dibayar 4.267.000 → amplop 42×100.000 + 1×50.000 + 1×10.000 + 1×5.000 + 1×2.000 = 4.267.000 (sisa pembulatan 586 dibawa). 10732 Citra Rangkuti, dibayar 4.315.000 → 43×100.000 + 1×10.000 + 1×5.000.

## Akibat Reset

Riwayat kiriman Telegram, pemberitahuan, kode email, catatan pengingat, dan jejak perubahan lama terhapus (data demo).

## Uji nyata bot (langkah 10)

Pemilik mengirim `/unggah` ke bot "Abaensi" 18 Nov 2026 11.39 WIB; bot membalas tautan unggah. Dicek di Supabase: `fakta.tautan_unggah` baris 1, dibuat 04.39.48 UTC oleh pengguna 1 (akun pembangun yang didaftarkan ulang oleh Pasang), berlaku 15 menit, belum dipakai. **Bot pulih sesudah Reset + Pasang: terbukti.**
