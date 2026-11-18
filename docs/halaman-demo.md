# Halaman demo (Tahap 4, paket 4c; versi 2: 6a-3; versi 3: 6a-4; versi 4: 6f; versi 5: G1)

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
10. **Versi 5 (paket G1, `docs/rencana-grafik-demo.md`)**: bagian "Grafik periode" di bawah Ringkasan, untuk periode yang dipilih. Panduan desain grafik (dataviz) dibaca sebelum kode.
    - **Biaya per divisi**: empat grafik kecil berdampingan, satu per nilai, masing-masing dengan skalanya sendiri: gaji pokok (komponen `gaji_pokok`), lembur (komponen `lembur`), potongan hari tidak dibayar (komponen `potongan_tidak_dibayar`, ditampilkan sebagai angka positif), potongan lain (semua komponen kelompok `potongan`: BPJS karyawan, PPh 21, denda, kasbon; positif). Batang mendatar per divisi, angka rupiah di ujung batang. **Koreksi dari rencana** ("batang berkelompok 4 nilai"): skala keempat nilai berbeda jauh (gaji pokok miliaran, potongan hari puluhan juta), sehingga satu grafik berkelompok membuat batang kecil tidak terlihat; panduan grafik juga melarang dua skala dalam satu grafik dan angka di setiap batang dalam grafik padat.
    - **Porsi gaji per divisi**: batang mendatar, persen dan rupiah gaji bersih tiap divisi terhadap gaji bersih periode (tanpa rahasia).
    - **Telat per tanggal**: kolom per tanggal periode (termasuk hari tanpa telat = 0), jumlah orang berstatus hadir dengan menit telat > 0 (semua orang, termasuk rahasia: hitungan hadir bukan angka gaji); hanya angka tertinggi diberi label; label tanggal dijarangkan di layar sempit.
    - Semua angka rupiah grafik **tanpa orang rahasia**; bila divisi memuat orang rahasia, keterangan "tidak termasuk N orang rahasia" di bawah grafik. Divisi = divisi di hari terakhir periode.
    - Tanda "Angka sementara: PPh 21 masa terakhir N orang belum bisa dihitung" (ralat G1: tanda ini muncul di semua periode yang punya orang tertahan, bukan hanya Nov–Des; teks awal "akhir tahun" salah untuk periode 1–3) bila periode punya orang PPh tertahan; keterangan "Termasuk THR Rp…" bila periode memuat THR.
    - Satu warna (biru `#2a78d6`, palet acuan dataviz slot 1) untuk semua batang; teks memakai warna tinta, bukan warna batang. Setiap batang punya keterangan arahkan-kursor (`<title>`), dan setiap grafik punya tabel angka ("lihat angka") untuk pembaca layar dan pemeriksaan.
    - Penghitung ukuran batang di berkas `grafik_inti.js` (fungsi murni, diuji `node --test`), dimuat dari halaman sendiri (`script-src 'self'`).
    - **Daftar karyawan**: pilihan Semua / Transfer / Tunai; rincian orang tunai menampilkan isi amplop (pecahan sama dengan `hitung.pecahan_tunai`, dibayar dipecah dari pecahan terbesar).
    - Pemeriksa: setiap angka grafik = gudang (SQL sendiri); uji kebocoran per divisi: total divisi − jumlah per orang yang tampil di divisi itu = 0 (gaji bersih dari daftar; gaji pokok, lembur, potongan dari rincian); telat per tanggal dari hasil harian; amplop = dibayar dan jumlah amplop = pecahan periode.
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
