# Laporan kecepatan paket 5a, langkah 0: pengukuran (belum ada kode yang diubah)

17 November 2026 · data simulasi Pabrik A, periode 3 (21 Mar–20 Apr 2026, 1.010 orang, sekitar 31 ribu hari-orang)

## Angka keseluruhan [Pasti, diukur]

| Hitungan | Komputer kerja | Supabase gratis (log pemasangan 4b-5) |
| --- | --- | --- |
| Baca tap satu periode | 5,9 detik | 11,7–13,6 detik |
| Hitung gaji satu periode | 7,4–7,7 detik | 11,7–18,8 detik |
| Tahap 1,5 (baca tap versi percobaan, aturan jauh lebih sedikit) | — | 0,19 detik |

Supabase gratis 1,6–2,5 kali lebih lambat dari komputer kerja untuk hitungan yang sama.

## Di mana waktunya habis (komputer kerja, perintah di atas 100 ms, diukur dengan `auto_explain`)

**Hitung gaji (7,4 detik):**

| Bagian | Waktu | Penyebab |
| --- | --- | --- |
| Menyiapkan tabel hari (`_hari`) | 2,6 detik | Setiap hari-orang (sekitar 31 ribu) memanggil `aturan.pengaturan_pada` 6 kali, padahal nilainya hanya berbeda per divisi per tanggal (sekitar 150 pasangan) |
| Menyiapkan tabel pajak (`_pajak`) | 2,1 detik | Untuk setiap orang, bruto dan iuran dicari dengan menyisir seluruh rincian (sekitar 10 ribu baris) tanpa indeks |
| Sebelas perintah lain | 0,1–0,35 detik masing-masing, total sekitar 2,2 detik | Fungsi kecil dipanggil per baris (menit lembur, satuan lembur, iuran BPJS) |

Dua bagian pertama = 4,7 dari 7,4 detik (63%).

**Baca tap (5,9 detik):** tersebar. Terbesar: membakukan tap mentah 0,95 detik, menyiapkan jadwal 0,44 detik, menulis tap bersih 0,42 detik, menentukan peran tap 0,39 detik, sisanya 0,1–0,34 detik per perintah. Tidak ada satu bagian yang dominan.

## Batas waktu yang berlaku [Pasti, dokumen resmi Supabase dibaca 17 Nov 2026]

| Jalur | Batas |
| --- | --- |
| Panggilan lewat API umum (PostgREST) | 8 detik bawaan, untuk peran `authenticated` dan `service_role`; bisa dinaikkan per fungsi dengan `set statement_timeout` |
| Edge Function, sambungan langsung ke database | Tidak ada batas 8 detik; perintah dibatasi batas global 2 menit; satu Edge Function hidup paling lama 150 detik (gratis), dan waktu menunggu database tidak dihitung sebagai jatah CPU 2 detik |

Sumber: supabase.com/docs/guides/database/postgres/timeouts, supabase.com/docs/guides/functions/limits.

Ralat: laporan 4b-1 sampai 4b-5 menyebut "di atas batas 8 detik API" seolah-olah pasti menghalangi. Batas itu hanya berlaku untuk jalur API umum. Kalau bot memakai Edge Function dengan sambungan langsung, hitungan sekarang tetap muat [Kemungkinan Besar; belum dicoba sampai Tahap 5b].

## Dibanding target PRD bagian 15

Target: satu periode Pabrik A selesai dihitung **dan masuk Sheets** paling lama 60 detik. Sekarang di Supabase: baca tap sekitar 13 detik + hitung gaji sekitar 19 detik ≈ 32 detik, sebelum Sheets (Tahap 6, belum diukur). Muat, tetapi sisanya hanya sekitar 28 detik, dan setiap kiriman file atau perintah HRD memicu hitung ulang.

## Kesimpulan

Hitungan sekarang **sudah muat** untuk jalur bot lewat Edge Function, tetapi sisa waktunya tipis. Dua bagian hitung gaji (63% waktunya) bisa dipercepat tanpa mengubah aturan. Keputusan langkah 1 ada di pemilik proyek.

---

# Langkah 1: hitung gaji dipercepat (migrasi 0014) — keputusan pemilik: pilihan A

17 November 2026. Aturan tidak berubah; hanya cara membaca pengaturan (sekali per divisi per tanggal) dan cara menjumlah bruto dan iuran untuk PPh (sekali per orang).

## Bukti hasil tidak berubah [Pasti]

Sidik hasil (gabungan seluruh rincian dan ringkasan gaji semua orang) versi 5 **sama persis** dengan versi 4, di komputer kerja dan di Supabase:

| Periode | Sidik versi 4 | Sidik versi 5 |
| --- | --- | --- |
| 1 | 2cfe4e216766 | 2cfe4e216766 |
| 2 | e7e24ab3a2ff | e7e24ab3a2ff |
| 3 | 071ae0629d51 | 071ae0629d51 |
| 4 | db9bf21fa79b | db9bf21fa79b |

Selain itu: uji database 343 lulus; uji simulasi 25 lulus; pembanding Pabrik A (4.037) dan B (750) orang-periode selisih 0; pemeriksaan pemasangan 31 lulus; angka halaman demo = gudang (terbit ulang otomatis).

## Kecepatan hitung gaji per periode [Pasti, diukur]

| Tempat | Versi 4 | Versi 5 |
| --- | --- | --- |
| Komputer kerja | 7,1–8,1 detik | 2,4–2,8 detik |
| Supabase (dicatat di database) | 11,7–18,8 detik | 5,0–6,2 detik |

Satu periode di Supabase sekarang sekitar 13 detik (baca tap) + 5–6 detik (gaji) ≈ 19 detik, dari target 60 detik termasuk Sheets.

Baca tap tidak diubah (waktunya tersebar, tidak ada bagian yang dominan).
