# Halaman demo (Tahap 4, paket 4c; versi 2: paket 6a-3; versi 3: paket 6a-4; versi 4: paket 6f)

17 November 2026 · ditulis sebelum kode · acuan: PRD v3.1 bagian 14 ("halaman demo sederhana di Tahap 4, hanya membaca hasil yang lulus uji, bertanda data simulasi") dan gerbang Tahap 4 ("angka demo sama dengan gudang").

## Keputusan pemilik (17 Nov 2026)

| Hal | Keputusan |
| --- | --- |
| Cara membaca data | **Salinan tetap.** GitHub Actions membaca gudang (Supabase) dan menulis file data ke halaman. Halaman tidak pernah menyentuh Supabase; tidak ada bagian database yang dibuka ke internet (PRD K6, K11) |
| Tempat | Cloudflare Pages, proyek `future-absensi-demo` |
| Unggah cadangan lewat web | **Dipindah ke Tahap 5** (butuh login HRD dan pembaca file di Edge Function, yang dibangun bersama pintu Telegram). Syarat gerbang Tahap 4 di PRD berubah karena keputusan ini |

## Isi halaman

1. Tanda **DATA SIMULASI** di bagian atas setiap tampilan, dengan penjelasan: nama dan angka karangan, dibuat oleh generator.
2. **Ringkasan per periode** (hanya versi gaji terakhir): tanggal periode dan bayar, jumlah orang, total pendapatan, total potongan, total gaji bersih, total dibayar, dibayar lewat transfer, dibayar tunai, sisa pembulatan dibawa, pecahan uang tunai (lembar per pecahan), versi kode baca tap dan gaji.
3. **Status pengajuan** per periode dari `hitung.periode_bisa_diajukan`. Bila tidak bisa: jumlah orang yang PPh masa terakhirnya tertahan, dan penjelasan bahwa data simulasi hanya punya 4 periode gajian (bulan lain kosong), jadi PPh masa terakhir tidak bisa dihitung.
4. **Tanda anomali** per periode dari `hitung.anomali_gaji`: jumlah per jenis dan daftar isinya.
5. **Daftar karyawan** dengan pencarian ID atau nama: divisi dan gaji bersih per periode. Klik satu orang: rincian per komponen, dibayar, sisa, peringatan, saldo cuti. Karyawan dengan `gaji_rahasia` di riwayat terakhirnya: angka tidak ditampilkan ("rahasia").
6. Tidak ada tombol aksi, tidak ada formulir yang mengirim data.
7. **Versi 2 (paket 6a-3, F15b)**: Ringkasan per periode (orang, total pendapatan, potongan, gaji bersih, dibayar, sisa, transfer, tunai, PPh tertahan) dan pecahan uang tunai dihitung **tanpa orang rahasia**, dengan keterangan "tidak termasuk N orang rahasia; amplop orang rahasia disiapkan terpisah". Total = jumlah gaji per orang yang tampil di daftar (selisih 0). Tanda anomali atas nama orang rahasia ditampilkan tanpa keterangan (keterangannya bisa berisi angka).
9. **Versi 4 (paket 6f, celah S3)**: file `web/demo/_headers` (Cloudflare Pages) memberi header keamanan untuk semua halaman (demo dan unggah): `Content-Security-Policy` (skrip, gaya, gambar hanya dari halaman sendiri; sambungan hanya ke halaman sendiri dan alamat Edge Function `https://orfkxznhfsalhznbummc.supabase.co`; `frame-ancestors 'none'`; `form-action 'self'`; `base-uri 'none'`), `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`. Skrip yang tertulis langsung di halaman diizinkan dengan sidik SHA-256 masing-masing, bukan `unsafe-inline`; skrip dari luar dan penangan kejadian langsung (`on...=`) ditolak oleh pembuat header. **Koreksi saat membangun:** gaya diizinkan `'unsafe-inline'` karena kedua halaman memakai atribut `style="..."` yang tidak bisa diberi sidik; risikonya rendah (CSS tidak menjalankan kode). File `_headers` dibuat `web/buat_headers.py` saat terbit (alamat Edge Function dari proyek yang dipasang) dan sidik dihitung ulang setiap terbit; uji otomatis memeriksa pembuatnya.
8. **Versi 3 (paket 6a-4, F15b)**: tanda anomali tingkat divisi (tanpa ID karyawan) untuk divisi yang memuat orang rahasia di periode itu (divisi = divisi di hari terakhir periode, sama dengan daftar karyawan) ditampilkan **tanpa angka**: keterangan diganti "Divisi <kode>: angka tidak ditampilkan karena divisi ini memuat gaji rahasia". Alasan: angka divisi memuat orang rahasia, sedangkan angka orang lain di divisi itu tampil per orang, sehingga selisihnya membuka angka orang rahasia (contoh nyata 18 Nov 2026: lembur KTR 20.159.394 − 19.921.677 = 237.717).

## Pemeriksaan "angka demo sama dengan gudang"

Skrip pemeriksa membaca file data halaman dan menghitung ulang langsung dari gudang dengan perintah SQL sendiri (bukan dari skrip pembuat data). Harus sama persis per periode:

| Angka | Dari gudang |
| --- | --- |
| Jumlah orang | baris `hitung.ringkasan_gaji` versi gaji terakhir |
| Total pendapatan, potongan, gaji bersih, dibayar, sisa pembulatan | jumlah kolom ringkasan |
| Dibayar transfer dan tunai | dibayar menurut cara bayar riwayat karyawan pada tanggal akhir periode |
| Pecahan tunai | ~~`hitung.pecahan_tunai(versi)`~~ (versi 1; lihat versi 2) |
| Bisa diajukan, jumlah tertahan | `hitung.periode_bisa_diajukan`, peringatan `pph_masa_terakhir_tertahan` |
| Tanda anomali per jenis | `hitung.anomali_gaji` |
| Per orang (bukan rahasia) | gaji bersih dan setiap komponen rincian |
| Orang rahasia | tidak ada angka di file data |
| Ringkasan tanpa orang rahasia (versi 2) | jumlah kolom ringkasan untuk orang bukan rahasia; dan total dikurangi jumlah per orang di file data = 0 untuk orang, gaji bersih, dibayar, transfer, tunai |
| Pecahan tunai (versi 2) | amplop orang tunai bukan rahasia; ditambah amplop orang rahasia = `hitung.pecahan_tunai(versi)` |
| Anomali orang rahasia (versi 2) | tanpa keterangan |
| Anomali berangka (versi 3) | keterangan yang memuat "Rp" tidak boleh menyangkut orang rahasia atau divisi yang memuat orang rahasia (divisi orang rahasia dihitung dari hasil harian dengan perintah SQL sendiri); jumlah tanda per jenis tetap = gudang |

Pemeriksaan dijalankan (1) di uji GitHub dengan data simulasi Pabrik A, dan (2) di workflow terbit, terhadap Supabase, sebelum mengunggah. Gagal → tidak diunggah.
