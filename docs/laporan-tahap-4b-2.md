# Laporan paket 4b-2: THR, denda, kasbon, batas potongan, gaji tunai, peringatan lembur

17 November 2026 · acuan: `docs/aturan-hitung-gaji.md` versi 2 (commit 91d1a7f, sebelum kode), `docs/cek-aturan-hukum.md` bagian 8

## Hasil singkat

| Uji | Hasil | Bukti |
| --- | --- | --- |
| Kunci K19–K27 (THR, denda, kasbon, batas 50%, tunai dan sisa, peringatan lembur) | **Lulus** | `db/uji/070_gaji_thr_kasbon_tunai.sql` (31 uji) |
| Uji 4b-1 (K1–K18) tetap lulus dengan kode versi 2 | **Lulus** | `060` |
| Pembanding vs sistem, semua orang-periode | **Lulus**: 4.037 orang-periode, selisih 0 | uji simulasi |
| U3 dan "dibayar + sisa = gaji bersih + sisa lalu" | **Lulus** | `070`, `cek_gaji.sql` di Supabase |

**Bukti pembanding benar-benar memeriksa [Pasti]:** commit kunci jawaban (91d1a7f) di-push sebelum kode. Uji GitHub untuk commit itu **gagal** karena pembanding (aturan baru) berbeda dengan kode lama di 3.824 orang-periode (THR dan sisa tunai belum ada di kode). Setelah kode versi 2 masuk (ae6a09d), selisihnya 0. Commit yang gagal itu tidak pernah dipasang.

## Angka terukur

| Yang diukur | Hasil |
| --- | --- |
| Uji database (komputer kerja) | 278 lulus, 0 gagal |
| Uji simulasi (komputer kerja) | 12 lulus, 0 gagal |
| GitHub "Uji database" ae6a09d | lulus, sekitar 5 menit |
| Naik dari 0009 ke 0010 di salinan lokal (seperti Supabase) | 4 periode dihitung ulang otomatis, pemeriksaan 28 lulus, pembanding selisih 0 |
| Pasang ke Supabase | lulus, sekitar 3,5 menit; 0010 sidik `257d665d9cf9` sama dengan repo |
| Hitung gaji di Supabase | 7,2–12,2 detik per periode (sama seperti 4b-1) |

## Di Supabase (dicek langsung)

| Periode | Orang | Gaji bersih | Dibayar | Sisa pembulatan | THR |
| --- | --- | --- | --- | --- | --- |
| 1 (bayar 25 Feb) | 1.011 | 5.183.058.029 | 5.182.913.834 | 144.195 | — |
| 2 (bayar 25 Mar) | 1.010 | 8.216.482.048 | 8.216.478.528 | 146.837 | 3.247.308.342 (990 orang) |
| 3 (bayar 25 Apr) | 1.010 | 5.706.376.775 | 5.706.372.374 | 149.392 | — |
| 4 (bayar 25 Des) | 1.006 | 4.999.870.485 | 4.999.877.277 | 140.411 | — |

Gaji bersih periode 1, 3, 4 sama persis dengan versi 4b-1 (yang berubah hanya cara bayar tunai). Versi gaji lama tetap tersimpan (8 versi gaji). Peringatan "lewat batas 4 jam" turun dari 1.859 menjadi 0, "wajib makan" 42 (hanya lembur hari kerja).

**Contoh THR, 10003 (TK/0, masa kerja 67 bulan), periode 2:** THR Rp4.200.000 (1 bulan upah 4.200.000) ikut bruto pajak 9.333.338 → PPh TER A 1,75% = Rp163.333. Gaji bersih Rp8.811.325, transfer, dibayar penuh.

**Contoh tunai, 10002 (K/3, mulai 4 Nov 2025), periode 2:** THR 4/12 × 4.300.000 = Rp1.433.333. Gaji bersih 6.142.605 + sisa periode lalu 538 = 6.143.143 → dibayar **Rp6.143.000**, sisa **Rp143** dibawa ke periode berikutnya. PPh 0 (TER C, bruto 6.509.825 di bawah 6.600.000).

## Temuan dan batasan

1. **Data simulasi tidak punya kasbon dan denda** (tabel kosong, Pabrik A tidak punya tingkat denda). Bagian ini hanya diuji dengan contoh buatan (K22–K25), belum dengan data lengkap [Pasti].
2. **Rantai antarperiode**: sisa pembulatan dan saldo kasbon diambil dari versi gaji terakhir periode sebelumnya. Bila periode lama dihitung ulang, periode sesudahnya juga perlu dihitung ulang; pemasangan baru menangani ini untuk pergantian versi kode, belum untuk hitung ulang biasa (Tahap 5).
3. **THR untuk pekerja yang berhenti dalam 30 hari sebelum hari raya** belum dihitung (Permenaker 6/2016 memberi hak itu untuk PKWTT) [Kemungkinan Besar ada di aturan; belum dicek naskahnya].
4. **Ganti rugi** belum ada tempat datanya; batas potongan sudah menyebutnya, tetapi nilainya selalu 0.
5. **Naskah Permenaker 6/2016 dan PP 36/2021 belum dibaca langsung**; isi diambil dari Hukumonline dan berita (label Kemungkinan Besar). Sebelum dipakai perusahaan sungguhan, keduanya perlu dicek ke naskah resmi seperti UU 27/2026.
6. **Perbaikan bug 4b-1**: hitung gaji gagal bila perusahaan tidak punya isian uang makan atau tunjangan shift malam. Ditemukan oleh uji 070, diperbaiki di 0010.
7. **Periode 4 (Desember) belum final**: PPh Desember masih 0 (paket 4b-3).
