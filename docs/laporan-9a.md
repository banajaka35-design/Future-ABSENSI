# Laporan paket 9a: web HRD (lihat saja)

Rencana: `docs/rencana-9a.md`, termasuk analisa celah C1–C14. "Buat" dari pemilik: 23 Nov 2026 15.54 WIB, dengan permintaan menganalisa kelemahan dan celah lalu memperbaikinya.

## Yang dibuat

- **Migrasi `0039_web_hrd.sql`**
  - `fakta.sesi_web` hanya menyimpan sidik sesi. Sesi berlaku 2 jam dan berakhir bila 30 menit tidak dipakai. Batasnya 300 permintaan per jam, dan semua sesi berakhir otomatis saat akun dinonaktifkan atau dicabut.
  - `fakta.pakai_kode_email` dipakai bersama oleh halaman unggah dan web HRD (C5).
  - Satu pintu baca, `api.web_hrd`, dengan aksi: ringkasan, gaji, orang, perlu_dicek, keberatan, dan keluar.
- **Edge Function:** jalur `hrd_minta_kode` (judul email "Kode masuk web HRD"), `hrd_masuk`, dan `hrd`. Semua jawaban web memakai `cache-control: no-store`.
- **Halaman `web/demo/hrd/`:**
  - Isi dari server hanya ditulis lewat `textContent`.
  - Sesi disimpan di `sessionStorage`, dan kodenya hanya dikirim di isi POST.
  - Skrip diizinkan CSP lewat sidik.
  - Bagian halaman: Periode, Gaji (bisa dicari, diurutkan, 200 baris per tampilan), rincian orang, Perlu dicek, dan Keberatan.

## Uji [Pasti]

| Uji | Hasil |
| --- | --- |
| CI run 45145254501, commit a98fef8 | Database 813 (23 uji baru 9a), simulasi 132 (4 uji halaman baru), pintu 120 (1 baru), penyambung 24 (1 baru): semua lulus |
| Pasang ke Supabase, run 45147433315 | 0039 terpasang, pemeriksaan 33 lulus, Edge Function terpasang ulang |
| Terbitkan demo, run 45148480194 | Terbit dengan 3 sidik skrip; `/hrd/` tampil dengan judul "Web HRD" |

## Uji nyata

Uji nyata dilakukan pada 23 Nov 2026 oleh pemilik, masuk dengan email pembangun. Semua langkah dicek di Supabase [Pasti]:

| Jam WIB | Langkah | Bukti |
| --- | --- | --- |
| 16.55 | Masuk dengan kode email (judul "Kode masuk web HRD") | Sesi no. 1 tercatat untuk pengguna 1, berlaku sampai 18.55; yang tersimpan hanya sidik (64 huruf) |
| 16.55 | Tab Periode | Periode 1–4 cocok dengan Ringkasan Sheets: orang, pendapatan, potongan, dan gaji bersih |
| 16.59 | Rincian 10735, periode 4 | Pendapatan 4.189.527, potongan -154.000, bersih 4.035.527, sisa lalu 135, dibayar 4.035.000, sisa 662; peringatan dan komponen sama dengan gudang |
| 17.00 | Rincian 10998 (rahasia) | Pesan "Gaji orang ini rahasia", komponen "Rahasia", status harian tetap tampil |
| 17.01 | Tab Keberatan | No. 2 diterima (15.47); no. 1 ditolak (15.46) dengan catatan |
| 17.01 | Keluar | Sesi no. 1 berakhir 17.01.17 dengan alasan `keluar`; tercatat 6 permintaan |

**Uji nyata 9a lulus.**

Temuan tampilan (belum diperbaiki; usulan paket kecil 9a-2):
1. Tabel lebar (Periode, Keberatan) harus digeser ke samping; kolom kanan terpotong di layar laptop.
2. Komponen gaji diurutkan menurut abjad kelompok, sehingga potongan karyawan muncul sesudah komponen perusahaan. Urutan seharusnya pendapatan, potongan, lalu perusahaan.
3. Pilihan periode di tab Gaji otomatis memilih periode terbaru; pemilik membuka periode 4 padahal yang dimaksud periode 3. Saran: tampilkan nomor periode lebih jelas di judul tab.
