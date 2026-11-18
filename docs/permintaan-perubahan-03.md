# Permintaan perubahan 03: cara bayar mengikuti bagian, bukan acak

Diajukan 18 November 2026 (paket 6a-2) · status: **menunggu "buat" pemilik proyek** untuk daftar paket 6a-2 di `docs/rencana-tahap-6.md`.

## Latar belakang

Pemilik proyek, saat melihat rekap Sheets hasil paket 6a (18 Nov 2026): pembagian transfer/tunai "kelihatan banget karangannya". Penyebabnya [Pasti]: generator memilih cara bayar **acak per orang** (`generator/buat_data.py` baris 113; peluang tunai 0,3 di Pabrik A dan 0,75 di Pabrik B). Akibatnya di Supabase 43 dari 124 orang Kantor dibayar tunai, sama acaknya dengan bagian lain.

Keputusan pemilik 18 Nov 2026 (diskusi untuk portofolio): tidak acak; daftar transfer dan daftar tunai ditampilkan terpisah; di Pabrik A hanya Gudang yang tunai.

## Usulan

| Pabrik | Tunai | Transfer | Alasan |
| --- | --- | --- | --- |
| A (1.000 karyawan) | Gudang (GDG) | PRD, QC, Keamanan, Kantor | Sekitar 15% tunai: cukup untuk menunjukkan fitur amplop, tetap wajar untuk pabrik besar |
| B (180 karyawan) | Produksi dan Gudang (PRD, GDG) | Kantor, Keamanan | Menjaga rancangan awal "Pabrik B mayoritas tunai" (`docs/data-simulasi.md`), sekarang berpola |

Cara di generator: isian baru `divisi_tunai` per pabrik di `generator/konfigurasi.py` menggantikan `cara_bayar_tunai`. Pemanggilan `self.r.random()` di baris 113 **tetap dijalankan** (hasilnya tidak dipakai) supaya urutan angka acak tidak bergeser dan semua data lain tetap sama.

## Dampak

- Data simulasi: hanya kolom `cara_bayar` di `A/induk/karyawan.csv` dan `B/induk/karyawan.csv` yang berubah. **Semua file lain di `data/simulasi/` harus sama persis** (dibuktikan dengan `sidik_isi.txt`: hanya dua baris itu yang berubah). Bila ada file lain yang ikut berubah, paket berhenti.
- Kunci jawaban absen (U1, U5) tidak berubah; hasil baca tap tidak berubah.
- Gaji: gaji bersih tidak berubah; yang berubah hanya "dibayar" dan "sisa pembulatan" (pembulatan Rp1.000 hanya untuk tunai, kasus E09) dan angka transfer/tunai/pecahan di Ringkasan. Kalkulator pembanding U2 ikut membaca data baru.
- Kasus jebakan tidak diubah.
- Supabase: karyawan sudah termuat, dan pemasangan hanya memuat bila kosong, jadi perlu **Reset Supabase** (hanya untuk demo; skripnya menolak bila ada karyawan bukan simulasi).
