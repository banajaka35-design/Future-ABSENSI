# Rencana paket G1-3: total gaji di bot dan halaman unggah tanpa orang rahasia

19 November 2026 · di-"buat" pemilik 19 Nov 2026 13.48 WIB · temuan T1 di `docs/laporan-g1-2.md` · kasus F15b, F15c

Ditulis sebelum kode. Yang tidak tertulis di sini tidak ikut dikerjakan.

## Celah yang ditutup

| No | Celah | Bukti |
| --- | --- | --- |
| T1 | Balasan bot sesudah file diproses menulis total gaji bersih **termasuk** orang rahasia. HRD bisa mengurangkan jumlah yang terlihat di Sheets dan mendapat gaji gabungan orang rahasia (F15b) | [Pasti] `api.pintu_kerjakan` migrasi 0015 (`sum(g.gaji_bersih)` semua orang); Supabase periode 4: bot 4.999.870.485 |
| C1 | Halaman unggah membaca total yang **disimpan** di `fakta.antrean_kerja.hasil`. Total yang disimpan bisa basi: orang yang dijadikan rahasia sesudah file diproses tetap terhitung (melanggar "rahasia sekarang", F15c) | [Pasti] `api.pintu_status_kiriman` migrasi 0019, `web/demo/unggah/index.html` |
| C1b | 3 baris antrean lama (kiriman 18, periode 2–4) sudah menyimpan total termasuk orang rahasia | [Pasti] Supabase 19 Nov 2026 |
| C2 | Bot memeriksa izin dari pengirim, tetapi membalas ke chat asal pesan tanpa memeriksa jenis chat. Di grup, `/unggah` menaruh tautan unggah (berlaku 15 menit) di depan semua anggota grup | [Pasti] `sistem/pintu/inti.ts` (`pesan.chat.id`) |
| C3 | Fungsi daftar rahasia per periode tidak boleh bisa dipanggil peran `pintu` | syarat rancangan |

Sudah aman, cukup dibuktikan dengan uji: tombol pilihan mesin hanya berlaku untuk pengirim file [Pasti] (`api.pintu_ambil_tunda` mencocokkan `telegram_id`).

## Isi paket

1. **Migrasi 0024**
   - `hitung.ringkasan_terlihat(versi)`: jumlah orang terlihat, gaji bersih terlihat, dan jumlah orang rahasia untuk satu versi gaji, dengan aturan F15c (rahasia pada hari mana pun di periode itu, atau rahasia sekarang). Di skema `hitung`, tanpa izin untuk `pintu`; hanya mengembalikan jumlah, bukan nomor orang.
   - `api.pintu_kerjakan`: kolom `hasil` antrean hanya menyimpan nomor versi gaji (tanpa rupiah dan tanpa jumlah orang). Jawaban untuk bot dihitung saat itu juga dengan `hitung.ringkasan_terlihat`.
   - `api.pintu_status_kiriman`: total dihitung saat dibaca. Baris tanpa nomor versi tampil tanpa angka.
   - Baris lama yang berisi `bersih`: `orang` dan `bersih` dihapus, diberi tanda `angka_dihapus`.
2. **Bot** (`inti.ts`): pesan "X orang, gaji bersih RpY (tidak termasuk N orang rahasia)"; hanya melayani chat pribadi (chat asal harus sama dengan pengirim dan bukan grup), pesan dari grup dijawab satu kalimat tanpa tautan, angka, atau pemrosesan file. Teks hasil untuk halaman unggah disusun di `inti.ts` juga, supaya bot dan halaman memakai kalimat yang sama.
3. **Halaman unggah**: menampilkan kalimat dari server; baris tanpa angka ditulis "angka gaji tidak ditampilkan".
4. **Uji**: `db/uji/160_total_tanpa_rahasia.sql` dan `sistem/pintu/uji_pintu.ts`:
   - total bot − jumlah yang terlihat = 0 (gaji dan orang);
   - F15c: orang yang dicabut status rahasianya di tengah riwayat tetap disembunyikan di periode lama;
   - C1: orang yang dijadikan rahasia sesudah file diproses ikut disembunyikan di halaman unggah;
   - kolom antrean tidak berisi rupiah; baris lama tanpa angka;
   - C2: pesan dari grup tidak dijawab dengan tautan atau angka dan file tidak diproses;
   - C3: `pintu` ditolak memanggil `hitung.ringkasan_terlihat`;
   - tombol pilihan mesin oleh orang lain ditolak;
   - uji harus GAGAL dengan aturan lama (semua orang, atau hanya status terakhir).
5. **Pasang** lewat `git push --force origin main:pasang`, sesudah uji GitHub lulus.
6. **Uji nyata**: file salinan simulasi (satu baris dibuang) dikirim pemilik lewat chat pribadi bot; balasan dicocokkan dengan Sheets dan Supabase; gaji keempat periode tidak berubah.
7. **Penelusuran** semua pesan dan halaman yang menulis angka gaji, ditulis di laporan.
8. **Dokumen**: `docs/laporan-g1-3.md`, serah-terima, catatan di kasus F15b/F15c, temuan T2 (riwayat versi Sheets) untuk paket berikutnya.

Tidak ikut: mesin hitung, isi Sheets, halaman demo utama, pemeriksa Python, riwayat versi Sheets.
