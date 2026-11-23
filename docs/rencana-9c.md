# Rencana paket 9c: coba aturan

Ditulis 23 November 2026. Acuan: `docs/rencana-tahap-9.md`, gerbang 2 ("coba aturan menunjukkan selisih yang sama dengan hitungan sungguhan bila aturan itu benar-benar dipakai"). **Di-"buat" pemilik 23 Nov 2026 17.15 WIB.** Catatan saat membuat: aturan bertanggal tidak boleh diubah isinya (`jejak.jaga_bertanggal`), jadi percobaan menutup baris terbuka di tanggal awal periode dan menambah baris percobaan, sama dengan cara resmi mengganti aturan; bila aturan sudah berganti di tengah periode, percobaan ditolak dengan alasan jelas.

## Gunanya

HRD atau pemilik ingin tahu akibat sebuah perubahan aturan sebelum aturan itu dipakai, misalnya: "kalau toleransi telat jadi 10 menit, berapa orang yang gajinya berubah, dan berapa totalnya?" Hitungan dijalankan sungguhan oleh mesin hitung yang sama, lalu **dibatalkan**, sehingga tidak ada yang tersimpan.

## Keadaan sekarang [Pasti, dicek 23 Nov]

- Aturan disimpan sebagai isian bertanggal di `aturan.*`, misalnya `toleransi` (telat_menit), `lembur` (menit_minimal, kelipatan_menit, cara_bulat), dan `komponen_lain` (uang makan, premi hadir, tunjangan shift malam, berupa nominal). Tidak boleh ada dua baris yang tanggalnya bertumpuk untuk cakupan yang sama.
- Hitung ulang satu periode (baca tap + gaji) di Supabase memakan **21–26 detik** (diukur 9 kali di Tahap 7). Peran `pintu` dibatasi 120 detik per perintah.
- Web HRD (9a) sudah punya sesi untuk HRD dan pembangun, serta satu pintu baca `api.web_hrd`.

## Isi paket

1. **Migrasi `0040_coba_aturan.sql`**
   - `api.web_coba_aturan` lewat sesi web yang sama. Masukan: periode dan perubahan aturan. Yang bisa dicoba di versi ini:
     - toleransi telat (menit);
     - lembur: menit minimal, kelipatan, cara pembulatan;
     - uang makan per hari, premi hadir per periode, tunjangan shift malam per hari (nominal).
   - Cara kerja: di dalam satu sub-transaksi, aturan untuk rentang periode itu diganti, `hitung.baca_tap` lalu `hitung.hitung_gaji` dijalankan, hasilnya dibandingkan dengan versi gaji yang berlaku sekarang, lalu **semuanya dibatalkan** (rollback). Yang dibawa keluar hanya hasil perbandingan.
   - Hasilnya:
     - per orang: ID, nama, divisi, gaji bersih sekarang, gaji bersih percobaan, dan selisih, ditambah komponen yang berubah;
     - ringkasan: jumlah orang yang naik dan turun, serta total selisih;
     - semuanya **tanpa angka orang rahasia** (F15b/F15c), memakai `fakta.rahasia_di_periode`.
   - `fakta.coba_aturan`, hanya bertambah: siapa, kapan, periode, aturan yang dicoba, ringkasan hasil (tanpa rahasia), dan lama hitung.
2. **Edge Function:** aksi `coba_aturan` di jalur `hrd` yang sudah ada.
3. **Halaman web HRD:** tab baru "Coba aturan".
   - Pilih periode, lalu isian aturan yang sudah terisi nilai sekarang.
   - Tombol "Hitung percobaan", dengan tulisan "sedang menghitung, sekitar 30 detik".
   - Hasil: ringkasan dan tabel per orang yang bisa diurutkan menurut selisih.
   - Tulisan tetap: "Percobaan, tidak disimpan; gaji sungguhan tidak berubah".
4. **Uji**
   - **Gerbang 2:** aturan X dicoba, lalu aturan X dipasang sungguhan dan dihitung ulang (di database uji). Selisih per orang harus sama persis dengan hasil percobaan.
   - Sesudah percobaan, gudang data tidak berubah: tidak ada versi hitung baru, aturan sama, status periode sama, dan sidik hasil sama.
   - Akun bukan HRD atau pembangun, dan sesi tidak berlaku, ditolak.
   - Isian di luar batas ditolak: negatif, kelipatan bukan 1–60, nominal terlalu besar.
   - Orang rahasia tanpa angka, juga di total.
   - Batas pemakaian berlaku.
5. **Pasang ke Supabase dan Terbitkan demo**, setelah uji GitHub lulus.
6. **Uji nyata:** pemilik mencoba toleransi telat 10 menit pada periode 4. Hasilnya dicocokkan dengan hitungan manual saya untuk 3 orang. Lalu dicek di Supabase bahwa gaji dan versi tidak berubah dan percobaan tercatat.
7. **Dokumen:** `docs/laporan-9c.md` dan `docs/serah-terima.md`.

## Analisa celah sejak awal

| No | Celah | Perbaikan dalam paket | Label |
| --- | --- | --- | --- |
| K1 | Percobaan tidak sengaja tersimpan (aturan atau versi gaji berubah sungguhan) | Semua perubahan di sub-transaksi yang **selalu** dibatalkan, juga saat ada galat. Uji: jumlah baris di `aturan.*`, `hitung.versi_hitung`, dan status periode sama persis sebelum dan sesudah | [Pasti] |
| K2 | Pembanding basi: versi gaji sekarang belum memuat data terbaru (masih ada antrean hitung ulang) | Percobaan ditolak bila periode itu masih punya antrean `menunggu`/`sedang` ("tunggu hitung ulang selesai"). Dengan begitu selisih murni akibat aturan | [Pasti] |
| K3 | Gaji orang rahasia terbuka lewat selisih total (total sekarang − total percobaan) | Total dan daftar dihitung tanpa orang rahasia; orang rahasia hanya dihitung jumlahnya ("N orang rahasia tidak ditampilkan") | [Pasti] |
| K4 | Percobaan berat (sekitar 25 detik) dipakai berulang-ulang dan memperlambat hitungan sungguhan | Satu percobaan dalam satu waktu untuk seluruh pemasangan (kunci tanpa menunggu: "ada percobaan lain, coba sebentar lagi"); paling banyak 20 percobaan per hari | [Kemungkinan Besar] |
| K5 | Selama percobaan, hitung ulang sungguhan dari bot ikut menunggu kunci periode | Satu percobaan paling lama sekitar 30 detik (dari hitungan 21–26 detik), dan antrean bot mencoba lagi sendiri. Dicatat sebagai keterbatasan | [Kemungkinan Besar] |
| K6 | Percobaan di periode yang sudah dirilis memberi kesan gajinya bisa diubah | Hanya periode yang belum dirilis | [Pasti] |
| K7 | Nilai yang tidak masuk akal atau di bawah batas hukum (misalnya lembur kelipatan 60) dianggap "boleh" | Isian dibatasi sesuai batas tabel aturan. Halaman menulis: "percobaan bukan izin memakai aturan; batas bawah hukum tetap dijaga mesin hitung saat aturan dipasang". Memasang aturan sungguhan tidak termasuk 9c | [Kemungkinan Besar] |
| K8 | Waktu tunggu di halaman terlalu lama dan peramban menyerah | Batas `fetch` di halaman 110 detik; batas perintah database 120 detik; bila habis, pesan yang jelas, dan tidak ada yang tersimpan karena dibatalkan | [Kemungkinan Besar] |

## Keputusan Claude

- [Kemungkinan Besar] Tujuh isian aturan di atas dulu, karena paling sering dibicarakan HRD (telat, lembur, uang makan, premi). Aturan lain (BPJS, PPh, UMK) adalah aturan hukum, bukan pilihan perusahaan, jadi tidak dicoba.
- [Kemungkinan Besar] **Memasang** aturan sungguhan dari web tidak termasuk 9c, karena mengubah gaji (perlu keputusan pemilik dan alur persetujuan sendiri). Percobaan hanya untuk melihat.

## Belum pasti

- [Menebak] Lama satu percobaan sekitar 25–30 detik, berdasarkan hitung ulang yang diukur di Tahap 7. Akan diukur di uji nyata.
- [Menebak] Lama pengerjaan belum diukur.
- Perubahan toleransi telat memengaruhi baca tap (status telat) dan gaji (uang makan, premi, denda bila ada). Hasilnya dibuktikan uji gerbang, bukan dugaan.
