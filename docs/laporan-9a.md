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

(diisi setelah dilakukan)
