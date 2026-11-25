# Laporan paket 9a-2: perbaikan tampilan web HRD

Di-"buat" 25 November 2026 11.52 WIB, persis menurut `docs/rencana-9a-2.md` (T1–T8, isi 1–8, celah V1–V4).
Commit kode: `a7974e2`. Yang diubah hanya `web/demo/hrd/index.html` dan bagian "Web HRD" di `sistem/uji/jalankan_simulasi.sh`.
Tidak ada migrasi, tidak ada perubahan Edge Function, tidak ada pemasangan ke Supabase. Sidik gaji periode 4 tidak tersentuh
(halaman hanya membaca).

## Yang dibuat

| Temuan | Perubahan |
| --- | --- |
| T1 | Tabel Periode hanya: No., Tanggal, Status rilis, Orang, Gaji bersih, Dibayar, Rahasia. Klik baris → rincian: tanggal bayar, pendapatan, potongan, gaji bersih, dibayar, transfer, tunai, bersih − dibayar (sisa pembulatan), versi hitung, tombol "Lihat gaji periode no. X". Semua angka dari `web_ringkasan` (V4) |
| T2 | Di bawah 760 px setiap baris tabel jadi kartu; setiap isian berjudul ("Gaji bersih: Rp…"). Satu pembuat sel `sel()` memberi `data-judul`; CSS menampilkannya. Isian kosong disembunyikan. Di tab Gaji judul kolom tetap tampil sebagai pengurut |
| T3 | Komponen urut pendapatan → potongan karyawan → iuran perusahaan, lalu nominal terbesar (nilai mutlak); judul kelompok tebal |
| T4 | Pilihan periode menyebut status, mis. "No. 3 · 21 Mar – 20 Apr 2026 · bisa diajukan". Judul tab "Gaji periode no. 3 (…)" dan "Perlu dicek · periode no. 3 (…)". Bawaan Gaji dan Perlu dicek = periode tertua yang belum dirilis; pilihan terakhir disimpan di sessionStorage selama sesi |
| T5 | Perintah yang sudah dibatalkan menulis "dibatalkan (no. X)" di kolom Hitung ulang; tombol Batalkan tidak ada |
| T6 | Kamus nama: 22 komponen (termasuk BPJS 5 program × 2 bagian), 19 peringatan, 19 jenis perintah. Kode asli di `title`. Kode tanpa nama tampil dengan garis bawah diganti spasi (juga untuk jenis di Perlu dicek). Nama aturan di hasil Coba aturan |
| T7 | Rupiah minus "-Rp183.458.000" |
| T8 | Teks tab Perintah: perintah uang menjadi pengajuan dan berlaku setelah disetujui bos/pembangun lewat bot dengan PIN; rekening belum bisa diisi |

Tambahan kecil yang dibutuhkan agar syarat "tidak lebih lebar dari layar" lulus di laptop: kolom Keterangan (Perlu dicek) dan
Keadaan (Keberatan) boleh pindah baris; `select` tidak melebihi lebar layar.

## Hasil uji [Pasti, diukur 25 Nov]

| Uji | Hasil |
| --- | --- |
| Database lokal (`db/uji/jalankan.sh`, database baru) | 917 lulus, 0 gagal (sama dengan sebelum) |
| Simulasi lokal (`jalankan_simulasi.sh`) | 139 lulus, 0 gagal (133 + 6 baru) |
| Sintaks skrip halaman (`node --check`) | lulus |
| Uji kamus dibuktikan bisa gagal | `thr` dan `wajib_makan` dihapus sementara dari kamus → GAGAL "thr,wajib_makan" |
| GitHub "Uji database" commit a7974e2 (run 45554089636) | success: database 917, simulasi 139, pemicu 12, pemulihan cadangan 10, semua 0 gagal |

Pemeriksaan baru di uji simulasi: semua `<table>` berkelas `kartu`; sel tabel hanya dibuat `sel()` yang memberi `data-judul`;
CSS layar sempit ada; daftar komponen/peringatan terbaca dari definisi `hitung.hitung_gaji` terbaru di `db/migrasi`
(≥ 20 komponen, ≥ 15 peringatan, supaya pola yang rusak tidak lolos diam-diam); semua punya nama di kamus; kode asli di `title`.

### Uji tampilan di Chrome (server tiruan, data berbentuk sama dengan Supabase)

Data tiruan diambil dari Supabase (hanya baca): `web_ringkasan`, `web_gaji(4)` 15 baris, `web_orang(4,'10002')`,
`web_keberatan`, `web_perlu_dicek(4)`, `web_perintah_daftar`, `web_pengajuan_daftar(true)`. Ditambah: satu orang rahasia,
teks berisi `<b>` di nama, alasan, keterangan, dan ringkas perintah, satu peringatan tanpa nama kamus, dan pasangan
perintah + pembatalan yang sedang dihitung.

Lebar tabel terlebar (px) — sebelum → sesudah:

| Tab | 1.366 px | 390 px |
| --- | --- | --- |
| Periode | 1.679 → 1.026 | 1.679 → 344 |
| Gaji | 1.026 → 1.026 | 996 → 344 |
| Rincian orang | 1.026 → 1.026 | 979 → 344 |
| Perlu dicek | 1.524 → 1.026 | 1.524 → 344 |
| Keberatan | 1.190 → 1.026 | 1.190 → 344 |
| Coba aturan | 1.026 → 1.026 | 948 → 344 |
| Perintah | 1.026 → 1.026 | 911 → 344 |

(1.026 = lebar kotak isi di laptop; 344 = lebar kotak isi di HP.) Tombol Tarik/Batalkan di HP: sebelum di x = 807–935
(di luar layar 390), sesudah x = 34–129. Galat skrip (pageerror): 0. Teks `<b>` tampil sebagai teks (0 elemen `<b>` di halaman).
Pilihan bawaan tab Gaji: sebelum "No. 4", sesudah "No. 3 · 21 Mar – 20 Apr 2026 · bisa diajukan". Tangkapan layar
sebelum/sesudah sudah dilihat Claude (tidak disimpan di repo).

## Terbit

"Terbitkan demo" run 45556204579 success 25 Nov 12.52 WIB: pemeriksa angka demo 0 beda (4 periode, 1.044 karyawan,
3 rahasia), 2 file baru diunggah ke Cloudflare Pages. Supabase tidak diubah.

## Yang belum

- Uji nyata pemilik di https://future-absensi-demo.pages.dev/hrd/ (laptop lalu HP).
- [Menebak] Batas 760 px tetap tebakan; belum dicoba di tablet.
- Ringkasan rincian orang adalah satu baris teks, sehingga di HP "-" dan "Rp172.000" bisa terpisah baris (kosmetik).
- "Bersih − dibayar" di rincian Periode termasuk sisa pembulatan periode lalu; `web_ringkasan` tidak memisahkannya.
