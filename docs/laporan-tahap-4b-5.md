# Laporan paket 4b-5: perbaikan temuan 4b-3 dan 4b-4

17 November 2026 · acuan: `docs/aturan-hitung-gaji.md` versi 5, `docs/permintaan-perubahan-02.md`, kasus jebakan v1.3 (commit 2e5ca40, sebelum kode)

## Hasil singkat

| Uji | Hasil | Bukti |
| --- | --- | --- |
| F13b (permintaan perubahan 02): karyawan baru, hari pertama sakit, belum terdaftar di mesin | **Lulus** | `db/uji/040_baca_tap.sql` |
| K47: lembur besar saja tidak memberi tanda gaji berubah | **Lulus** | `db/uji/100_pajak_awal_tahun.sql` |
| K48–K50: isian pajak awal tahun (Desember 800.000; tanpa isian tetap tertahan) | **Lulus** | `100` |
| U5/U1 Pabrik B: kasus 20190 kembali **wajib cocok** (catatan "kelemahan diketahui" dihapus) | **Lulus** | uji simulasi |
| Pembanding A dan B | **Lulus**: 4.037 dan 750 orang-periode, selisih 0 | uji simulasi |
| U10 anomali ditanam | **Lulus** (tiga-tiganya tetap tertangkap) | uji simulasi |

**Bukti kunci jawaban ditulis lebih dulu [Pasti]:** uji GitHub commit 2e5ca40 (kode lama) gagal di **F13b** karena pemberitahuan memang tidak muncul dengan pembaca tap versi 1. Kali ini kegagalannya karena perilaku, bukan hanya karena tabel belum ada. Commit itu tidak dipasang.

## Tanda "gaji berubah" Pabrik A, sebelum dan sesudah [Pasti, diukur]

| Periode | Versi 4 (semua pendapatan kecuali THR) | Versi 5 (upah tetap dan potongan) |
| --- | --- | --- |
| 2 (21 Feb–20 Mar) | 54 | 20 |
| 3 (21 Mar–20 Apr) | 430 | 25 |
| 4 (21 Nov–20 Des) | 504 | 17 |

Yang tersisa berasal dari karyawan baru, karyawan berhenti, dan alpha beberapa hari. Lembur tetap diawasi lewat tanda "lembur divisi naik" (3 dan 1 tanda). Pabrik B: 4, 6, 5 tanda.

## Yang diubah

| Bagian | Isi |
| --- | --- |
| Migrasi 0013 | `hitung.versi_kode_baca()`; pembaca tap versi 2 (hari sakit, izin, cuti, dinas luar dari HRD dilewati saat menilai "belum terdaftar di mesin"); tanda gaji berubah versi 5; tabel `induk.pajak_awal_tahun`; hitung gaji versi 4 (data setahun dinilai per orang, isian ikut dijumlah) |
| Pemasangan | Menghitung ulang baca tap bila versi kode pembaca tap berubah; sesudah itu gaji dihitung ulang karena sumbernya berubah |
| `cek_gaji.sql` | +1: versi baca tap terakhir memakai versi kode terbaru |
| Pembanding | Isian pajak awal tahun, ditulis dari aturan versi 5 sebelum kode |

## Angka terukur

| Yang diukur | Hasil |
| --- | --- |
| Uji database (komputer kerja) | 343 lulus, 0 gagal |
| Uji simulasi A + B (komputer kerja) | 24 lulus, 0 gagal |
| Naik dari 0012 ke 0013 di salinan lokal | 4 periode dibaca ulang dan dihitung ulang; hasil harian dan gaji bersih sama persis; pembanding selisih 0; pemeriksaan 31 lulus |
| GitHub "Uji database" commit kode | lulus |
| Pasang ke Supabase | lulus; 0013 sidik `c1c60afc5221` |

## Di Supabase (dicek langsung)

- Keempat periode Pabrik A memakai baca tap versi 2 dan hitung gaji versi 4.
- Hasil harian versi 1 dan versi 2 dibandingkan: **0 baris berbeda**; anomali baca tap 528 = 528. Data A memang tidak punya kasus seperti 20190.
- Gaji bersih sama dengan 4b-3/4b-4: 5.183.058.029 · 8.216.773.882 · 5.706.405.590 · 4.999.870.485.
- Tanda anomali: periode 2 gaji berubah 20; periode 3 gaji berubah 25 dan lembur divisi naik 3; periode 4 gaji berubah 17 dan lembur divisi naik 1; aktif tanpa tap 4–5 per periode.
- Isian pajak awal tahun kosong (0 baris), sesuai rencana.

## Temuan dan batasan

1. **PPh Desember demo tetap tertahan** [Pasti]: data simulasi hanya punya gajian Feb, Mar, Apr, dan Des; isian awal tahun tidak diisi karena angkanya akan karangan yang tidak bisa dicek. Ini perlu ditulis terus terang di halaman demo 4c.
2. **Isian pajak awal tahun belum punya cara pengisian** selain SQL; formulir atau unggah file untuk HRD masuk Tahap 7 atau 9.
3. **Pegawai pindah kerja di tengah tahun** (bagian PMK 168) masih [Menebak], tidak diubah.
4. **Aktif tanpa tap 4–5 orang per periode di Pabrik A** adalah sopir Gudang yang tidak wajib tap. Tanda ini memang dimaksudkan supaya HRD memeriksanya.
5. **Lama hitung di Supabase** (diukur di log pemasangan): baca tap 11,7–13,6 detik per periode, hitung gaji 11,7–18,8 detik per periode (periode 4 paling lama). Keduanya di atas batas 8 detik fungsi API; harus diselesaikan di Tahap 5.
