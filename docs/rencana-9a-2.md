# Rencana paket 9a-2: perbaikan tampilan web HRD

Ditulis 25 November 2026. Sumber temuan:
- 3 butir dari uji nyata 9a (`docs/laporan-9a.md`);
- 2 butir dari uji nyata 9b-1;
- pemeriksaan halaman di Chrome dengan data berbentuk sama dengan Supabase, pada lebar laptop 1366 px dan HP 390 px.

**Belum di-"buat".** Paket ini hanya mengubah halaman `web/demo/hrd/index.html`. Tidak ada perubahan database, Edge Function, atau angka gaji.

## Temuan [Pasti, diukur 25 Nov]

| No | Temuan | Bukti |
| --- | --- | --- |
| T1 | Tabel Periode lebih lebar dari layar laptop. Kolom gaji bersih, dibayar, transfer, tunai, dan seterusnya terpotong di kanan | Lebar tabel 1.665 px pada layar 1.366 px (temuan 9a no. 1) |
| T2 | Di HP semua tabel harus digeser ke samping. Tombol Batalkan/Tarik tersembunyi di ujung kanan | Tabel 911–1.665 px pada layar 390 px (temuan uji nyata 9b-1) |
| T3 | Komponen gaji berurutan pendapatan → perusahaan → potongan. Potongan karyawan terselip di bawah iuran perusahaan | Temuan 9a no. 2 |
| T4 | Tab Gaji otomatis memilih periode terbaru tanpa penanda jelas. Pemilik membuka periode 4 padahal maksudnya periode 3 | Temuan 9a no. 3 |
| T5 | Selama pembatalan dihitung, baris perintah aslinya ikut bertulisan "sedang dihitung…" | Temuan uji nyata 9b-1 |
| T6 | Kode teknis tampil apa adanya: `ubah_gaji`, `gaji_pokok`, `bpjs_jht_perusahaan`, `pph_masa_terakhir_tertahan`, `pembulatan_lembur_ke_bawah` | Tangkapan layar tab orang dan Gaji |
| T7 | Angka minus tertulis "Rp-183.458.000"; yang lazim "-Rp183.458.000" | Tab Periode dan komponen |
| T8 | Teks tab Perintah masih "Gaji tidak bisa diubah dari sini", padahal sejak 9b-2 bisa lewat pengajuan | Halaman sekarang |

## Isi paket

1. **T1 + T2: tabel menyesuaikan layar.**
   - Di layar sempit (di bawah 760 px), setiap baris tabel menjadi kartu bertumpuk. Setiap isian diberi judul kolomnya, misalnya "Gaji bersih: Rp…". Tombol ikut terlihat tanpa digeser.
   - Di laptop, tabel Periode dipecah. Tabel utama hanya berisi No., Tanggal, Status rilis, Orang, Gaji bersih, Dibayar, dan Rahasia. Rincian lain (pendapatan, potongan, transfer, tunai, sisa pembulatan, versi) muncul saat baris diklik.
   - Caranya: fungsi `baris()` yang dipakai semua tabel menambahkan `data-judul` di setiap sel, lalu CSS menampilkannya di layar sempit. Isi sel tetap memakai `textContent` (C2 9a).
2. **T3:** komponen diurutkan pendapatan → potongan → perusahaan, lalu menurut nominal terbesar. Judul kelompok ditebalkan.
3. **T4:** pilihan periode di tab Gaji dan Perlu dicek menyebut status, misalnya "No. 3 · 21 Mar – 20 Apr 2026 · bisa diajukan". Judul tab memakai huruf tebal: "Gaji periode no. 3". Pilihan bawaan diganti menjadi **periode tertua yang belum dirilis**, yaitu periode yang harus diurus HRD berikutnya (sekarang no. 3, karena urutan rilis wajib berurutan sejak 8b-3). Pilihan terakhir disimpan selama sesi.
4. **T5:** baris perintah yang sudah dibatalkan menulis "dibatalkan (no. X)" di kolom Hitung ulang, bukan keadaan periodenya.
5. **T6:** kamus nama:
   - jenis perintah, misalnya ubah gaji, tambah libur;
   - komponen, misalnya Gaji pokok, BPJS JHT (perusahaan), PPh 21;
   - peringatan, dalam kalimat pendek, misalnya "PPh akhir tahun belum bisa dihitung (data gaji setahun belum lengkap)".
   Kode yang belum ada di kamus tetap tampil, dengan garis bawah diganti spasi.
6. **T7:** rupiah minus ditulis "-Rp…".
7. **T8:** teks tab Perintah diperbarui: perintah uang perlu persetujuan bos/pembangun; rekening belum bisa diisi.
8. **Uji:**
   - Pemeriksaan otomatis di uji simulasi:
     - tidak ada `innerHTML`;
     - setiap tabel diberi `data-judul`;
     - kamus mencakup semua komponen dan peringatan yang ada di mesin hitung, diambil dari daftar komponen di migrasi. Bila ada komponen baru tanpa nama, uji gagal.
   - Uji tampilan di Chrome pada 1.366 px dan 390 px. Syaratnya: tidak ada tabel yang lebih lebar dari layar, dan tombol Batalkan/Tarik terlihat. Ini dijalankan Claude dengan jawaban tiruan; tidak masuk CI karena CI tidak punya Chrome.

## Analisa celah

| No | Celah | Penutup | Label |
| --- | --- | --- | --- |
| V1 | Kartu di HP membuat halaman panjang untuk 1.000 orang di tab Gaji | Batas tampil 200 baris yang sudah ada tetap dipakai, dengan tombol "tampilkan lagi"; pencarian ID/nama tetap | [Kemungkinan Besar] |
| V2 | Kamus nama salah menerjemahkan dan menyesatkan HRD | Nama hanya untuk tampilan; kode asli tetap ada di keterangan saat diarahkan (title); uji kamus memastikan semua kode tercakup | [Kemungkinan Besar] |
| V3 | Mengubah `baris()` merusak tabel lain (Coba aturan, Keberatan) | Uji tampilan memeriksa setiap tab; isi data tidak berubah, hanya atribut dan CSS | [Pasti] |
| V4 | Angka orang rahasia terbuka lewat rincian Periode yang baru | Rincian memakai data yang sama dengan tabel sekarang (`web_ringkasan`, sudah tanpa rahasia) | [Pasti] |

## Yang dipasang

Tidak ada pemasangan Supabase. Halaman diterbitkan lewat "Terbitkan demo" sesudah uji GitHub lulus.

## Yang belum pasti

- [Menebak] Batas 760 px untuk ganti ke tampilan kartu; angka umum untuk HP dan tablet kecil.
