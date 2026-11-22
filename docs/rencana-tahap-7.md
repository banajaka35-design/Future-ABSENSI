# Rencana Tahap 7: perintah HRD lewat chat

21 November 2026 · ditulis sebelum kode · **belum di-"buat"** · acuan: tabel "Rencana Tahap 3 sampai 9" di `docs/serah-terima.md` (Tahap 7 = "Perintah HRD lewat chat", hasil "Koreksi lewat chat"), kasus jebakan C12, D05, F08, F12, F16, temuan Tahap 3 nomor 7.

## 0. Acuan PRD v2 bagian 13 (ditempel pemilik 21 Nov 2026 10.08 WIB)

- **Yang dibangun:** perintah harian HRD: izin, sakit, kasbon, dan persetujuannya.
- **Gerbang (selesai kalau):** izin susulan mengubah hasil setelah hitung ulang.

## 1. Hasil pemeriksaan (21 Nov 2026 09.3x WIB)

| Hal | Hasil | Label |
| --- | --- | --- |
| Rencana atau laporan Tahap 7 di repo | Tidak ada | [Pasti] |
| Bot (`sistem/pintu/inti.ts`, `sambung.ts`) menulis ke `fakta.perintah_hrd` | Tidak ada satu baris kode pun | [Pasti] |
| Migrasi 0015–0031 (semua migrasi bot) menulis ke `fakta.perintah_hrd` | Tidak ada; hanya dibaca oleh baca tap dan hitung gaji | [Pasti] |
| Isi `fakta.perintah_hrd` di Supabase | 1.603 baris, **semua `asal = file`** (sakit 674, cuti 443, izin 356, tukar shift 129, absen manual 1), dari `db/data_awal/muat_masukan_hrd.py`; **0 baris `asal = chat`** | [Pasti] |
| Berhenti dan karyawan baru di Supabase | Masuk lewat data induk (`induk.status_kerja`: mulai 1.044, berhenti 44), dimuat `muat_karyawan.py`, bukan perintah | [Pasti] |
| Tabel penampung perintah | Sudah ada sejak 0001 (`fakta.perintah_hrd`, kolom `asal` sudah punya pilihan `chat`, kolom `oleh` ke `induk.pengguna`, `membatalkan` untuk koreksi) | [Pasti] |
| Efek perintah pada hitungan | Sudah dibangun dan diuji sejak Tahap 3/4: sakit, izin, cuti, dinas luar, absen manual, tukar shift, tambah libur, setujui/batalkan lembur, batalkan perintah, kasbon | [Pasti] |
| Jenis yang ada di daftar tabel tetapi belum punya efek | penyesuaian, ubah gaji, mutasi, karyawan baru (sebagai perintah) | [Pasti] (hanya muncul di 0001) |

**Kesimpulan [Pasti]:** Tahap 7 belum dibangun. Yang kurang hanya "pintu"-nya: membaca perintah dari chat, menyimpannya, lalu menghitung ulang. Mesin hitungnya sudah ada.

## 2. Usulan pecahan paket (versi 2, sesudah acuan PRD)

Setiap paket punya daftar lengkap dan "buat" sendiri (aturan 7). Urutan di bawah adalah saran.

| Paket | Isi | Kasus uji |
| --- | --- | --- |
| **7a** | Izin, sakit, cuti untuk satu orang (satu tanggal atau rentang), termasuk **susulan** (tanggal yang sudah lewat). Bot membalas ringkasan ("Izin · 10001 Eka Susanto · 19 Feb"), lalu tombol **Ya / Batal**; baru disimpan sesudah Ya (`asal = chat`, `oleh` = akun pengirim). Sesudah disimpan, periode yang kena dihitung ulang (baca tap + gaji) lewat antrean yang sama dengan file, bot mengabarkan selesai, Sheets ikut diisi ulang. Hanya akun `hrd` dan `pembangun`. Ditolak bila periode sudah dirilis/dikunci | **Gerbang:** izin susulan untuk hari yang tercatat alpha → sesudah hitung ulang menjadi izin, dicek di Supabase dan Sheets (pola C12); perintah ke periode dirilis ditolak; akun karyawan ditolak |
| **7b** | Kasbon lewat chat: pinjam dan pelunasan (menulis `fakta.buku_kasbon`, aturan potong I2–I4 sudah ada sejak 4b-2) | Pinjam → potongan muncul di gaji sesudah hitung ulang, tidak melewati batas 50% (K22, K23) |
| **7c** | Persetujuan (keputusan pemilik (a), 21 Nov 2026): HRD menyetujui atau membatalkan lembur lewat chat, per orang atau per divisi (`setujui_lembur`, `batalkan_lembur`; efeknya sudah ada sejak 4b-1); persetujuan jam sebelum jadwal masuk (B5, **efek belum ada**, butuh aturan hitung baru + permintaan perubahan untuk kasus uji); tukar shift lewat chat cukup dicatat HRD (lihat bagian 3a) | D04, D05, F12; kasus baru B5 lewat permintaan perubahan |
| **7d** | Batalkan perintah (`batalkan_perintah`) dan "daftar perintah terakhir saya", supaya salah ketik bisa dibetulkan tanpa menghapus baris (fakta hanya bertambah) | Perintah dibatalkan → hasil kembali seperti semula |
| di luar PRD Tahap 7 | Absen manual divisi, tambah libur, berhenti/aktif kembali, karyawan baru, mutasi, ubah gaji, penyesuaian, data pajak awal tahun | Tidak dikerjakan di Tahap 7 kecuali pemilik memintanya; [Kemungkinan Besar] cocok untuk templat/web Tahap 9 |

Yang **sama untuk semua paket** (dicatat supaya tidak lupa saat menulis daftar lengkap):

- Migrasi baru untuk fungsi simpan perintah (peran `pintu` tidak menulis tabel langsung, sama seperti paket 8).
- Uji otomatis di GitHub (database + pintu) sebelum Pasang; Pasang lewat cabang `pasang`.
- Balasan bot tidak boleh membuka gaji orang rahasia (F15, F15b). Perintah untuk orang rahasia tetap boleh dicatat HRD; balasannya hanya nama, jenis, tanggal.
- Hitung ulang satu periode di Supabase: baca tap sekitar 12 detik dan gaji 5–6 detik (diukur di Tahap 3 dan 5a), di bawah batas Edge Function 150 detik. Lama total dari "Ya" sampai kabar selesai **belum diukur**.

## 3a. Persetujuan: dasar PRD v2 dan hasil cek kode (21 Nov 2026)

Keputusan pemilik: **(a)**. Dasar PRD v2 yang ditempel pemilik: B4 "lembur wajib disetujui; tanpa persetujuan hanya tercatat sebagai kelebihan jam"; B5 "jam sebelum jadwal masuk tidak dihitung kecuali disetujui"; C10 kasbon cukup "saldo dan cicilan tercatat, beserta siapa yang memasukkan" (tanpa persetujuan bos); tukar shift = "pengecualian per orang".

| Hal | Hasil cek kode | Label |
| --- | --- | --- |
| B4 persetujuan lembur | Sudah bekerja: pengaturan `wajib_perintah` membayar lembur hanya bila ada `setujui_lembur` (per orang atau divisi); tanpa itu tanda `lembur_tidak_dibayar_tanpa_izin`. Pengaturan `otomatis` membayar kecuali ada `batalkan_lembur` (migrasi 0013/0014). Pabrik A demo memakai `otomatis`, Pabrik B `wajib_perintah` | [Pasti] |
| B5 jam sebelum jadwal | Jam sebelum masuk tidak pernah menjadi lembur (kasus B05). **Belum ada cara menyetujuinya**: `setujui_lembur` hanya membuka menit sesudah jam pulang | [Kemungkinan Besar]; dipastikan saat menulis daftar 7c |
| C10 kasbon | Sesuai rencana 7b: dicatat HRD, `oleh` = akun pengirim, tanpa persetujuan bos | [Pasti] (bunyi PRD) |
| Tukar shift | Perintah `tukar_shift` dari HRD langsung berlaku di baca tap; tidak memakai tabel `fakta.persetujuan`. Usulan sistem (F11) hanya tanda; "disetujui" di F11 dijalankan dengan HRD mengirim perintah tukar shift. **Jadi cukup dicatat HRD**, cocok dengan "pengecualian per orang" | [Pasti] (kode 0016 baris 149, uji U1 F11) |

## 3. Yang perlu diputuskan pemilik sebelum 7a ditulis lengkap

1. ~~Arti "persetujuannya"~~: diputuskan **(a)** 21 Nov 2026 10.11 WIB (bagian 3a).
2. ~~Cara menulis perintah~~: diputuskan **(a) perintah tetap** 21 Nov 2026 10.13 WIB.
3. **Izin dengan alasan Pasal 149 ayat 2**: diputuskan Claude (kewenangan dari pemilik 10.13 WIB): **ditunda, tidak ikut 7a**. Izin lewat chat tetap tidak dibayar seperti sekarang (`izin_dibayar = tidak`). Mengubahnya akan mengubah angka gaji, jadi nanti ditanyakan ke pemilik.

**Cara memutuskan mulai 21 Nov 2026 10.13 WIB (pesan pemilik):** untuk keputusan di Tahap 7, Claude memakai sarannya sendiri, mencatatnya di sini dengan label, lalu lanjut. Pemilik hanya ditanya bila keputusannya (1) tidak bisa dibatalkan, (2) mengubah angka gaji atau uang, atau (3) membatasi hak akun pemilik.

## 5. Daftar paket 7a (di-"buat" 21 Nov 2026 10.39 WIB; terpasang, `docs/laporan-7a.md`)

**Tujuan:** HRD mencatat izin, sakit, atau cuti lewat chat, termasuk susulan; hasil berubah sesudah hitung ulang (gerbang Tahap 7).

### Keputusan Claude untuk 7a (dicatat sesuai kewenangan 10.13 WIB)

| Keputusan | Alasan | Label |
| --- | --- | --- |
| Bentuk perintah: `/izin <ID> <tanggal> [tanggal selesai] [catatan]`, sama untuk `/sakit` dan `/cuti`. Tanggal `dd-mm-yyyy` atau `dd-mm` (tahun = tahun ini menurut WIB). Juga bisa diketik tanpa garis miring sesudah menekan tombol | Konfirmasi Ya/Batal menampilkan tanggal lengkap, jadi salah tahun terlihat sebelum disimpan | [Pasti] keputusan |
| Tombol tetap HRD/pembangun ditambah **"Perintah HRD"**: bot membalas contoh dan kolom balas (force reply). Penuntun langkah demi langkah dengan tombol pilihan **tidak** ikut 7a | Paket tetap kecil; bisa ditambah kemudian | [Pasti] keputusan |
| Draf disimpan di tabel baru; tombol Ya hanya berlaku sekali dan 15 menit | Mencegah dobel bila Ya ditekan dua kali; tidak membuat perintah tanpa konfirmasi | [Pasti] keputusan |
| Yang boleh: akun `hrd` dan `pembangun` (fungsi `api.pintu_hrd` yang sudah ada sejak 0017). Bos dan karyawan ditolak | PRD: perintah harian HRD. Tidak membatasi akun pemilik | [Pasti] |
| Semua tanggal harus ada di periode yang tercatat dan periode itu belum `dirilis`/`dikunci`; rentang paling panjang 31 hari; karyawan harus aktif di setiap tanggalnya | Periode dirilis tidak boleh dihitung ulang (8b); 31 hari = paling panjang satu periode | [Pasti] keputusan |
| Periode `diajukan`/`disetujui`: perintah tetap diterima, pengajuan batal sesudah hitung ulang, dan ini ditulis di konfirmasi | Sama dengan file yang masuk (perilaku 8b yang sudah ada) | [Pasti] |
| Perintah baru di hari yang sudah punya perintah: diterima; yang baru berlaku (aturan baca tap yang sudah ada: perintah terbaru menang). Konfirmasi menulis perintah lama yang tertimpa | Tidak mengubah aturan hitung | [Pasti] (0016 baris 348) |
| Periode yang dihitung ulang: periode yang kena dan periode sesudahnya yang sudah punya gaji | Sama dengan file (0015); sisa pembulatan dan saldo kasbon berantai (aturan J4) | [Pasti] |
| Balasan bot hanya nama, divisi, jenis, tanggal, status hari sebelum → sesudah; tanpa angka gaji perorangan. Kabar selesai memakai pesan yang sudah ada (total tanpa orang rahasia) | F15, F15b | [Pasti] |
| Saldo cuti tidak dicek saat perintah dibuat | Sama dengan file; aturan saldo 4b-3 tetap berlaku di hitung gaji | [Kemungkinan Besar] cukup untuk demo |

### Isi paket

1. **Migrasi 0032** (`db/migrasi/0032_perintah_chat.sql`):
   - tabel `fakta.draf_perintah` (pengguna, jenis, karyawan, tanggal, catatan, dibuat, kedaluwarsa, perintah yang dibuat);
   - kolom `fakta.antrean_kerja.perintah_id` (boleh kosong), supaya kabar tahu asal hitung ulang;
   - `api.pintu_perintah_siapkan`: periksa semua aturan di atas, buat draf, kembalikan ringkasan untuk konfirmasi;
   - `api.pintu_perintah_simpan`: periksa ulang, tulis `fakta.perintah_hrd` (`asal = chat`, `oleh` = akun), masukkan periode ke antrean, tandai draf terpakai;
   - `api.pintu_perintah_hasil`: status hari-hari itu sesudah hitung ulang;
   - izin untuk peran `pintu` hanya pada fungsi `api` itu (peran `pintu` tidak menulis tabel langsung).
2. **Bot** (`sistem/pintu/inti.ts`): perintah `/izin`, `/sakit`, `/cuti`; tombol "Perintah HRD"; tombol Ya/Batal; sesudah Ya: "Tercatat no. N", lalu antrean dikerjakan (fungsi yang sudah ada), Sheets diisi ulang (pemicu yang sudah ada), lalu "Hasil 10067 30 Mar: alpha → izin". `/bantuan` dan daftar fungsi yang boleh (`apiBoleh`) diperbarui.
3. **Uji otomatis** (wajib lulus di GitHub sebelum Pasang):
   - `db/uji/` file baru: draf sekali pakai, kedaluwarsa, periode dikunci ditolak, karyawan tidak aktif ditolak, rentang terlalu panjang ditolak, akun karyawan/bos ditolak, antrean terisi periode yang benar, alpha → izin sesudah antrean dikerjakan, perintah lama tertimpa yang baru;
   - `sistem/pintu/uji_pintu.ts`: membaca perintah dan tanggal, alur Ya/Batal, balasan tanpa angka gaji;
   - bukti uji gagal dengan kode lama.
4. **Pasang ke Supabase** lewat cabang `pasang` sesudah uji lulus.
5. **Uji nyata gerbang** (pemilik mengetik di bot, Claude memeriksa Supabase dan Sheets):
   - `/izin 10067 30-03-2026` (Vina Pohan, periode 3). Dicek 21 Nov 2026: hari itu `alpha`, satu-satunya alpha periode 3, tanpa telat, bukan orang rahasia [Pasti];
   - lulus bila: hari itu menjadi `izin` di Supabase; perintah tercatat `asal = chat` oleh akun pembangun; Sheets periode 3 orang itu Alpha −1, Izin +1;
   - uji tolak: `/izin 10067 25-02-2026` (periode 2 dikunci) ditolak, tidak ada baris baru.
6. **Dokumen**: `docs/laporan-7a.md`, `docs/serah-terima.md`.

### Perlu diketahui pemilik sebelum "buat"

- **Uji nyata mengubah angka gaji demo** (pemicu aturan nomor 2 di atas). Izin tetap tidak dibayar, jadi potongan hari itu tetap. Tetapi premi hadir hanya hilang karena alpha atau telat (aturan C3 yang sudah ada sejak 4b-1), jadi [Kemungkinan Besar] 10067 mendapat premi hadir Rp100.000 di periode 3 dan PPh-nya ikut berubah. Total gaji periode 3 berubah, periode 4 dihitung ulang. Ini akibat aturan lama, bukan aturan baru.
- **Perintah tidak bisa dihapus** (fakta hanya bertambah). Membatalkan perintah lewat chat baru ada di 7d. Sebelum itu, yang bisa mengembalikan demo hanya Reset Supabase.
- **Belum pasti:** lama dari Ya sampai kabar selesai (belum diukur; hitung ulang dua periode diperkirakan sekitar 35 detik [Menebak], dari 12 detik baca tap + 6 detik gaji per periode yang diukur di Tahap 3 dan 5a).
- **Tidak ikut 7a:** kasbon (7b), persetujuan lembur (7c), batalkan perintah (7d), perintah divisi, alasan izin dibayar, penuntun tombol langkah demi langkah.

## 7. Daftar paket 7d (di-"buat" 22 Nov 2026 10.47 WIB)

**Tujuan:** perintah HRD yang salah bisa dibatalkan lewat chat tanpa Reset Supabase. Fakta tetap hanya bertambah: pembatalan dicatat sebagai perintah `batalkan_perintah` (kolom `membatalkan`), yang sudah dihormati baca tap dan hitung gaji sejak Tahap 3 [Pasti: 0013, 0014, 0016].

### Keputusan Claude untuk 7d (kewenangan 21 Nov 2026 10.13 WIB)

| Keputusan | Alasan | Label |
| --- | --- | --- |
| Bentuk: `/batal <nomor perintah>`, lalu konfirmasi dengan tombol Ya/Batal seperti 7a | Nomor perintah sudah tertulis di pesan "Tercatat: perintah no. ..." | [Pasti] keputusan |
| **Diubah saat membuat (22 Nov 2026):** perintahnya `/batalperintah <nomor>`, bukan `/batal` | `/batal <nomor>` sudah dipakai untuk membatalkan pengajuan rilis (paket 8b); nama yang sama akan bentrok. Pesan "Tercatat" 7a kini menulis petunjuk `/batalperintah <nomor>` | [Pasti] keputusan |
| Yang bisa dibatalkan: perintah sakit, izin, cuti, **dari chat maupun dari file** | Salah catat bisa datang dari keduanya; efeknya sama | [Pasti] keputusan |
| Ditolak bila: nomor tidak ada, jenis lain, sudah dibatalkan, atau tanggalnya di periode `dirilis`/`dikunci` | Periode dirilis tidak dihitung ulang (8b) | [Pasti] keputusan |
| `/perintahku`: 10 perintah chat terakhir dari semua akun HRD/pembangun (nomor, jenis, ID, nama, tanggal, pencatat, sudah dibatalkan atau belum) | Tim HRD berbagi pekerjaan; tanpa angka gaji | [Pasti] keputusan |
| Hanya akun `hrd` dan `pembangun` | Sama dengan 7a | [Pasti] |

### Isi paket

1. **Migrasi 0033**:
   - `fakta.draf_perintah` boleh berisi draf `batalkan_perintah` (kolom baru `membatalkan`);
   - `fakta.periksa_perintah` diganti: ikut mengembalikan **semua** periode yang akan dihitung ulang, termasuk periode sesudahnya yang sudah punya gaji (perbaikan temuan uji nyata 7a: teks hanya menyebut periode 3);
   - fungsi baru `api.pintu_batal_siapkan`, `api.pintu_perintah_terakhir`; `api.pintu_perintah_simpan` diganti supaya bisa menyimpan draf pembatalan.
2. **Bot**: `/batal`, `/perintahku`, tombol Ya/Batal, kabar "Hasil ... sebelum → sesudah"; konfirmasi dan "Tercatat" 7a menyebut semua periode yang dihitung ulang; menu dan `/bantuan`.
3. **Uji otomatis** (database dan pintu), termasuk: pembatalan mengembalikan status dari tap, batal dua kali ditolak, periode dikunci ditolak, perintah file bisa dibatalkan, daftar perintahku; bukti uji gagal dengan kode lama.
4. **Pasang ke Supabase** lewat cabang `pasang` sesudah uji lulus.
5. **Uji nyata**: `/batal 1604` (izin Vina Pohan 30 Mar 2026 dari uji 7a) → hari itu kembali `alpha`; dicek di Supabase dan Sheets. Uji tolak: `/batal 1604` kedua kali.
6. **Dokumen**: `docs/laporan-7d.md`, `docs/serah-terima.md`.

### Perlu diketahui pemilik

- **Uji nyata mengubah angka gaji demo kembali**: [Kemungkinan Besar] dibayar Vina Pohan periode 3 kembali dari Rp5.597.917 ke Rp5.513.378 (premi hadir hilang), seperti sebelum uji 7a. Bisa diulang dengan `/izin` lagi.
- **Pembatalan tidak bisa dibatalkan.** Kalau salah membatalkan, perintahnya diketik ulang (nomor baru).
- **Tidak ikut 7d:** kasbon (7b), persetujuan lembur (7c), pembatalan jenis lain (tukar shift, lembur, absen manual).

## 8. Daftar paket 7b (di-"buat" 22 Nov 2026 16.13 WIB dengan pilihan (a); terpasang, `docs/laporan-7b.md`)

**Tujuan:** HRD mencatat kasbon lewat chat: pinjam dengan cicilan, ubah cicilan, pelunasan tunai, dan melihat saldo (PRD v2 C10: "saldo dan cicilan tercatat, beserta siapa yang memasukkan"; tanpa persetujuan bos, keputusan 21 Nov).

### Cara kasbon dihitung sekarang (dicek 22 Nov 2026)

- [Pasti] Aturan I2–I4 (`docs/aturan-hitung-gaji.md`, migrasi 0014): saldo = pinjam − pelunasan − potongan kasbon di periode sebelumnya; dipotong = cicilan terakhir yang dicatat (kalau tidak ada: seluruh saldo), dibatasi 50% pendapatan sesudah denda; sisa dibawa ke periode berikut.
- [Pasti] Kasbon **tidak punya tanggal sendiri**: yang dipakai tanggal dicatat (`dibuat`, WIB). Kasbon yang dicatat hari ini mulai dipotong di periode yang memuat hari ini (demo: periode no. 4, 21 Nov–20 Des 2026). Jadi tidak ada "kasbon susulan".
- [Pasti] `fakta.buku_kasbon` tidak punya kolom pencatat; pencatat diambil dari `perintah_id` → `fakta.perintah_hrd.oleh`.
- [Pasti] Demo Supabase belum punya baris kasbon sama sekali.

### Keputusan Claude untuk 7b

| Keputusan | Alasan | Label |
| --- | --- | --- |
| `/kasbon <ID> <jumlah> <cicilan per periode> [catatan]` = pinjam + cicilan. **Cicilan wajib diisi** | Tanpa cicilan, aturan I2 memotong seluruh saldo sekaligus; HRD harus menyebutnya sendiri supaya tidak kaget. Tidak mengubah aturan hitung | [Pasti] keputusan |
| `/cicilan <ID> <jumlah>` = ganti cicilan; `/lunas <ID> <jumlah> [catatan]` = pelunasan tunai di luar gaji, ditolak bila melebihi saldo | Tiga jenis yang sudah ada di `buku_kasbon` | [Pasti] keputusan |
| `/kasbon <ID>` tanpa jumlah = lihat saldo, cicilan, 5 catatan terakhir (tanpa angka gaji lain) | Pengecekan sebelum mencatat | [Pasti] keputusan |
| Jumlah boleh ditulis `1500000`, `1.500.000`, `1,5jt`, `500rb` | Cara orang menulis uang | [Pasti] keputusan |
| Setiap catatan lewat konfirmasi Ya/Batal; tercatat sebagai perintah `kasbon` (asal chat, `oleh` = akun, nilai = jenis dan jumlah) + baris `buku_kasbon` dengan `perintah_id` | Siapa yang memasukkan terlacak (C10) | [Pasti] keputusan |
| Ditolak bila hari ini tidak masuk periode mana pun, atau periode yang memuat hari ini sudah dirilis/dikunci; karyawan harus aktif hari ini | Sama dengan 7a | [Pasti] keputusan |
| Yang dihitung ulang: periode yang memuat hari ini dan periode sesudahnya yang sudah punya gaji (fungsi 0033) | Saldo berantai (J4) | [Pasti] |
| Hanya `hrd` dan `pembangun` | Sama dengan 7a | [Pasti] |

### Pertanyaan untuk pemilik (keputusan yang tidak bisa dibatalkan)

**Bagaimana kasbon yang salah catat dibetulkan?**

- **(a) Lewat `/batalperintah <nomor>` seperti izin** (saran). Butuh satu perubahan di mesin hitung gaji: baris kasbon yang perintahnya dibatalkan tidak dihitung. Aturan I2–I4 tidak berubah. Fungsi `hitung.hitung_gaji` (0014, sekitar 480 baris) disalin ke migrasi baru dengan satu syarat tambahan; semua uji gaji lama harus tetap lulus.
- **(b) Tanpa pembatalan**: salah catat dibetulkan dengan `/lunas` (tercatat seperti pelunasan tunai, padahal bukan). Mesin hitung tidak disentuh, tetapi riwayat kasbon jadi tidak jujur, dan kasbon yang salah tidak bisa dihapus dari catatan.

### Isi paket (dengan pilihan (a))

1. **Migrasi 0034**: `api.pintu_kasbon_siapkan`, `api.pintu_kasbon_saldo`; `api.pintu_perintah_simpan` diganti (draf kasbon → perintah + `buku_kasbon`); `api.pintu_batal_siapkan` diganti (kasbon bisa dibatalkan); `hitung.hitung_gaji` diganti dengan satu syarat: baris `buku_kasbon` yang perintahnya dibatalkan tidak dihitung; tabel draf menampung jenis kasbon dan jumlah.
2. **Bot**: `/kasbon`, `/cicilan`, `/lunas`; konfirmasi (saldo sekarang → sesudah, cicilan, periode mulai dipotong, batas 50%); "Hasil": potongan kasbon orang itu di periode berjalan dan sisa saldo. **Hanya HRD/pembangun yang melihat angka ini**, dan orang rahasia (F15) tidak ditampilkan angkanya.
3. **Perbaikan temuan 7d**: kabar Sheets sesudah perintah chat menulis "Lama sejak perintah dicatat", bukan "sejak file masuk" (`web/kabar_telegram.py`).
4. **Uji otomatis**: database (pinjam/cicilan/lunas, lunas melebihi saldo ditolak, kasbon dibatalkan → potongan hilang, K22/K23 tetap lulus, semua uji gaji lama lulus), pintu, Sheets; bukti uji gagal dengan kode lama.
5. **Pasang ke Supabase** lewat cabang `pasang`.
6. **Uji nyata**: `/kasbon 10067 1.000.000 250.000` → Ya → potongan kasbon Rp250.000 muncul di gaji periode 4 Vina Pohan (Supabase dan Sheets); lalu `/batalperintah <nomor>` → potongan hilang. Uji tolak: `/lunas 10067 5.000.000` (melebihi saldo).
7. **Dokumen**: `docs/laporan-7b.md`, `docs/serah-terima.md`.

### Perlu diketahui pemilik

- **Uji nyata mengubah angka gaji demo periode 4** (potongan Rp250.000 untuk satu orang), lalu dikembalikan oleh pembatalan.
- Pilihan (a) **menyentuh mesin hitung gaji** untuk pertama kali sejak Tahap 4. Risikonya [Kemungkinan Besar] kecil karena hanya satu syarat dan semua uji gaji (K01–K25, U1 kunci jawaban) harus tetap lulus sebelum dipasang.
- **Tidak ikut 7b:** persetujuan lembur (7c), kasbon yang dipotong dari THR, batas jumlah pinjaman.

## 9. Daftar paket 7c-1 (di-"buat" 22 Nov 2026 17.12 WIB; terpasang, `docs/laporan-7c.md`)

**Tujuan:** HRD menyetujui atau membatalkan lembur lewat chat, per orang atau per divisi (PRD v2 B4; kasus D04, D05, F12). Paket ini **tidak mengubah aturan hitung**: efek `setujui_lembur` dan `batalkan_lembur` sudah ada di mesin hitung gaji sejak 4b-1 (aturan D5).

Persetujuan **jam sebelum jadwal masuk (B5)** dipisah menjadi **paket 7c-2**, karena butuh aturan hitung baru (mengubah angka gaji) dan kasus uji baru lewat permintaan perubahan. Daftarnya ditulis sesudah 7c-1 selesai, dengan pertanyaan ke pemilik.

### Yang dicek (22 Nov 2026)

- [Pasti] Demo Supabase (Pabrik A): pengaturan `lembur = otomatis` untuk seluruh perusahaan. Jadi di demo, **`/setujuilembur` tidak mengubah angka** (lembur sudah dibayar otomatis); yang terlihat efeknya hanya `/batalkanlembur` (D05). Pengaturan `wajib_perintah` (D04, F12) diuji di uji otomatis.
- [Pasti] Mesin hitung: `wajib_perintah` membayar hanya bila ada `setujui_lembur` untuk orang itu atau divisinya pada tanggal itu; `otomatis` membayar kecuali ada `batalkan_lembur`. Perintah yang dibatalkan dengan `batalkan_perintah` tidak berlaku.
- [Pasti] Belum ada perintah lembur di demo. Kode divisi: GDG, KAM, KTR, PRD, QC.
- [Pasti] Calon uji nyata: 10067 Vina Pohan, 26 Nov 2026 (periode 4), pulang 127 menit sesudah jadwal; lembur periode 4 orang itu Rp80.925, hanya dari hari itu.

### Keputusan Claude untuk 7c-1

| Keputusan | Alasan | Label |
| --- | --- | --- |
| `/setujuilembur <ID atau kode divisi> <tanggal> [tanggal selesai] [catatan]` dan `/batalkanlembur ...` (bentuk tanggal sama dengan `/izin`) | Satu bentuk untuk orang dan divisi; kode divisi huruf, ID karyawan angka | [Pasti] keputusan |
| Konfirmasi Ya/Batal berisi: pengaturan lembur di tanggal itu (otomatis / wajib perintah), dan untuk orang: menit lebih per hari; untuk divisi: jumlah orang yang pulang lewat jadwal 60 menit atau lebih. Bila perintah tidak akan mengubah apa pun (misalnya setujui di pengaturan otomatis), konfirmasi menulisnya | HRD tahu akibatnya sebelum Ya | [Pasti] keputusan |
| "Hasil" sesudah hitung ulang: orang → lembur periode itu sebelum → sesudah (rupiah; orang rahasia tidak ditampilkan); divisi → jumlah orang yang lemburnya berubah dan total perubahannya tanpa orang rahasia (F15b) | Sama dengan kabar kasbon | [Pasti] keputusan |
| Aturan tanggal sama dengan 7a: periode harus ada dan belum dirilis/dikunci; rentang paling panjang 31 hari; untuk orang: aktif di tanggal itu | Konsisten | [Pasti] |
| Bisa dibatalkan dengan `/batalperintah`; muncul di `/perintahku` | Sama dengan 7a/7b | [Pasti] |
| Hanya `hrd` dan `pembangun` | Sama | [Pasti] |

### Isi paket

1. **Migrasi 0035**: `api.pintu_lembur_siapkan`; `api.pintu_perintah_simpan`, `api.pintu_batal_siapkan`, `api.pintu_perintah_hasil` diganti (perintah lembur, per orang atau per divisi); draf menampung divisi. **Mesin hitung tidak diubah.**
2. **Bot**: `/setujuilembur`, `/batalkanlembur`; konfirmasi; "Hasil"; menu dan `/bantuan`.
3. **Uji otomatis**: database (D04 tanpa perintah tidak dibayar; F12 setujui divisi → dibayar; D05 batalkan orang → Rp0; batalkan perintah lembur → kembali; periode dikunci ditolak; divisi tidak ada ditolak), pintu; bukti uji gagal dengan kode lama.
4. **Pasang ke Supabase** lewat cabang `pasang`.
5. **Uji nyata**: `/batalkanlembur 10067 26-11-2026` → lembur Vina Pohan periode 4 Rp80.925 → Rp0 (Supabase dan Sheets); lalu `/batalperintah <nomor>` → kembali Rp80.925. Uji tolak: `/setujuilembur XYZ 26-11-2026` (divisi tidak ada).
6. **Dokumen**: `docs/laporan-7c.md`, `docs/serah-terima.md`.

### Perlu diketahui pemilik

- **Uji nyata mengubah gaji demo periode 4** untuk satu orang (lembur −Rp80.925, PPh ikut), lalu dikembalikan oleh pembatalan.
- **Tidak ikut 7c-1:** jam sebelum jadwal masuk (7c-2), tukar shift lewat chat, perintah divisi untuk izin/sakit/cuti.

## 10. Paket 7c-2: jam sebelum jadwal masuk (PRD v2 B5) — sedang ditanyakan ke pemilik

PRD v2 B5: "jam sebelum jadwal masuk tidak dihitung kecuali disetujui". Sekarang [Pasti]: menit sebelum jadwal masuk tidak pernah menjadi lembur (baca tap 0016, kasus B05); `setujui_lembur` hanya membuka menit sesudah jam pulang (D1). Mengubahnya **mengubah angka gaji**, jadi setiap keputusan aturan ditanyakan ke pemilik, satu per satu.

### Pertanyaan 1: cara menghitung menit datang awal yang disetujui

Contoh: jadwal 07.00–15.00, datang 05.30 (90 menit lebih awal), pulang 15.45 (45 menit lewat). Aturan lembur sekarang: minimal 60 menit, kelipatan 30 menit, pengali per jam ke-1, ke-2, ... per hari.

| Pilihan | Menit dibayar contoh | Catatan |
| --- | --- | --- |
| **(a) Digabung** dengan menit lewat jam pulang di hari yang sama, lalu aturan lembur biasa (saran) | 90 + 45 = 135 → 120 menit | Satu hari satu hitungan lembur, sama dengan cara tabel pengali sekarang (jam ke-1, ke-2 per hari) [Kemungkinan Besar paling sesuai] |
| (b) Dihitung terpisah, masing-masing harus 60 menit atau lebih | pagi 90 → 90; sore 45 → 0; jumlah 90 menit | Dua potong lembur di satu hari; pengali jam ke-1 bisa terpakai dua kali |
| Sekarang (tanpa persetujuan) | 45 → 0 | Tetap berlaku untuk hari yang tidak disetujui |

Jawaban pemilik: **(a) digabung** (22 Nov 2026 19.05 WIB, sesudah penjelasan bahwa (a) tidak pernah membayar lebih kecil daripada (b): batas 60 menit, pembulatan sekali, dan jam pertama 1,5× tidak terpakai dua kali [Pasti, hitungan]).

### Pertanyaan 2: apakah persetujuan lembur biasa ikut membuka jam datang awal?

| Pilihan | Akibat |
| --- | --- |
| **(a) Terpisah** (saran): jam datang awal hanya dibayar bila ada persetujuan khusus "datang awal" (misalnya `/setujuiawal <ID atau divisi> <tanggal>`), di pengaturan otomatis maupun wajib perintah | Sesuai bunyi B5 ("kecuali disetujui"); persetujuan lembur sore untuk satu divisi tidak ikut membayar semua yang datang awal |
| (b) Sekali setujui untuk keduanya: `/setujuilembur` membuka menit sesudah pulang dan sebelum masuk; di pengaturan otomatis, datang awal tetap perlu `/setujuilembur` | Satu perintah lebih ringkas, tetapi lebih mudah membayar datang awal tanpa sengaja |

Catatan [Pasti]: tap yang lebih awal dari jendela tap (sekarang 120 menit sebelum masuk) tidak dibaca sebagai tap masuk, jadi datang awal yang bisa dibayar paling banyak 120 menit.

Jawaban pemilik: **(a) terpisah** (22 Nov 2026 19.05 WIB).

### Temuan data demo (22 Nov 2026) [Pasti]

- Di data simulasi, hampir semua hari hadir punya datang awal 1–30 menit (periode 4: 21.423 hari; paling awal 30 menit). Jadi persetujuan datang awal untuk satu divisi bisa menambah lembur banyak orang sekaligus; karena itu konfirmasi wajib menyebut jumlah orang dan menitnya.
- Calon uji nyata: **10060 Maya Sitorus, Sabtu 21 Nov 2026**: datang 29 menit lebih awal, pulang 94 menit lewat jadwal. Sekarang dibayar 90 menit; dengan persetujuan datang awal (digabung): 123 menit → **120 menit**.

## 11. Daftar paket 7c-2 (di-"buat" 22 Nov 2026 19.07 WIB bersama perbaikan celah di bawah)

**Tujuan:** PRD v2 B5: jam sebelum jadwal masuk dibayar sebagai lembur hanya bila disetujui (keputusan pemilik: digabung dengan menit lewat jam pulang; persetujuan terpisah dari persetujuan lembur biasa).

### Aturan baru (masuk `docs/aturan-hitung-gaji.md` sebagai D1b, versi kode gaji 7)

- **D1b** Hari kerja (status `hadir`, asal mesin, jenis hari `kerja` atau `cuti_bersama`): menit lembur = (menit lewat jam pulang, bila boleh menurut D5) + (menit datang awal, bila ada perintah `setujui_datang_awal` untuk orang itu atau divisinya di tanggal itu). Menit datang awal = jadwal masuk − tap masuk, dibulatkan ke bawah per menit; paling banyak sejauh jendela tap. Jumlahnya lalu memakai D4 (minimal 60, kelipatan 30), D6–D9 seperti biasa.
- Persetujuan datang awal berlaku di pengaturan **otomatis maupun wajib perintah**; persetujuan lembur biasa (`setujui_lembur`) dan pembatalannya (`batalkan_lembur`) hanya untuk menit lewat jam pulang, seperti sekarang.
- Tanda `lembur_tidak_dibayar_tanpa_izin` tetap untuk menit lewat jam pulang yang tidak boleh. Datang awal tanpa persetujuan tidak diberi tanda (sama dengan sekarang, kasus B05).
- **Tidak ikut** (tetap seperti sekarang): hari libur tanpa jadwal (D2, seluruh jam hadir sudah dihitung) dan hari libur nasional dengan jadwal (D3).

### Keputusan Claude (bukan soal uang)

| Keputusan | Label |
| --- | --- |
| Perintah bot `/setujuiawal <ID atau kode divisi> <tanggal> [tanggal selesai] [catatan]`; konfirmasi Ya/Batal berisi, per hari: orang → menit datang awal dan menit lewat jam pulang; divisi → jumlah orang yang datang awal dan jumlah menitnya. "Hasil": lembur sebelum → sesudah (sama dengan 7c-1) | [Pasti] keputusan |
| Jenis perintah baru `setujui_datang_awal` di `fakta.perintah_hrd` (daftar jenis ditambah lewat migrasi), supaya tidak tercampur dengan `setujui_lembur` | [Pasti] keputusan |
| Bisa dibatalkan dengan `/batalperintah`; muncul di `/perintahku` | [Pasti] |

### Isi paket

1. **Permintaan perubahan 06** (`docs/permintaan-perubahan-06.md`): tambah kasus **B05b** "Shift Pagi: tap 05:30 dan 15:45; HRD menyetujui datang awal → 90 + 45 = 135 menit → dibayar 120 menit"; B05 tidak diubah (tanpa persetujuan tetap tidak menjadi lembur). Kasus jebakan jadi versi 1.4.
2. **Migrasi 0036**:
   - daftar jenis `fakta.perintah_hrd` dan draf ditambah `setujui_datang_awal`;
   - `hitung.hitung_gaji` versi kode 7: salinan versi 6 (0034) dengan D1b; menit datang awal dihitung dari `hitung.hasil_harian` (tap masuk dan jadwal masuk yang sudah tersimpan), **pembaca tap tidak diubah**;
   - fungsi bot: `api.pintu_lembur_siapkan` dan teman-temannya menerima jenis baru; `fakta.hari_lembur` ikut menyebut menit datang awal.
3. **Bot**: `/setujuiawal`, konfirmasi, hasil, menu, `/bantuan`.
4. **Dokumen aturan**: `docs/aturan-hitung-gaji.md` D1b dan contoh K (angka uji).
5. **Uji otomatis**: B05 tetap (tanpa persetujuan 0), B05b (135 → 120 menit), persetujuan divisi, wajib perintah (datang awal disetujui tetapi sore tidak → hanya pagi yang dihitung), batalkan perintah → kembali; **semua uji gaji lama dan U1 kunci jawaban harus tetap lulus** (data simulasi tidak punya persetujuan datang awal, jadi angkanya tidak boleh berubah); bukti uji gagal dengan kode lama.
6. **Pasang ke Supabase** lewat cabang `pasang`.
7. **Uji nyata**: `/setujuiawal 10060 21-11-2026` → lembur Maya Sitorus periode 4 naik (90 → 120 menit dibayar; rupiah dicek di Supabase dan Sheets); lalu `/batalperintah <nomor>` → kembali; uji tolak `/setujuiawal 10060 25-02-2026` (periode dikunci).
8. **Dokumen**: `docs/laporan-7c2.md`, `docs/serah-terima.md`.

### Pemeriksaan kelemahan dan celah (diminta pemilik 22 Nov 2026 19.07: "cek kelemahan dan celah baru, perbaiki dan buat")

| No | Kelemahan / celah | Perbaikan yang masuk paket | Label |
| --- | --- | --- | --- |
| 1 | Datang awal bisa terbaca dari data tap yang tidak bisa dipercaya: lupa tap, tap tunggal yang ragu (B08), jendela tap bertumpuk (B10, tap pulang shift malam bisa terbaca sebagai tap masuk pagi), absen manual dari HRD | Menit datang awal **hanya** dihitung untuk hari `hadir`, asal `mesin`, tap masuk dan pulang ada, tanpa lupa tap, tidak ambigu, tanpa tanda `jendela_bertumpuk`. Hari lain: datang awal tidak dihitung walau disetujui | [Kemungkinan Besar] lebih aman; mengurangi pembayaran hanya untuk data yang meragukan |
| 2 | Persetujuan divisi untuk rentang panjang bisa menaikkan lembur banyak orang tanpa disadari (data demo: hampir semua hari ada datang awal) | Konfirmasi divisi menyebut **jumlah hari-orang yang datang awal dan total menitnya untuk seluruh rentang**, bukan hanya per hari; hari yang datanya tidak dihitung (nomor 1) tidak ikut dijumlah | [Pasti] keputusan |
| 3 | Lembur naik tanpa jejak yang terlihat di Sheets/halaman demo | Hari yang datang awalnya dibayar diberi tanda gaji `lembur_datang_awal_disetujui` (muncul di kolom Peringatan) | [Pasti] keputusan |
| 4 | Versi kode 7 bisa tanpa sengaja mengubah angka orang yang tidak punya persetujuan | Perubahan kode hanya menyentuh baris hari yang punya persetujuan datang awal; dibuktikan dengan semua uji gaji lama, U1, dan perbandingan semua orang di Supabase sesudah uji nyata (hanya orang yang disetujui boleh berbeda) | [Pasti] keputusan |
| 5 | Pengaturan wajib perintah: datang awal disetujui tetapi lembur sore tidak | Hanya menit pagi yang dihitung; tanda `lembur_tidak_dibayar_tanpa_izin` tetap untuk bagian sore | [Pasti] (sesuai jawaban pertanyaan 2) |
| 6 | Shift malam lintas tengah malam dan tukar shift | Menit dihitung dari jadwal masuk dan tap masuk yang sudah tersimpan (sudah memperhitungkan tukar shift dan tanggal); diuji dengan shift malam | [Pasti] |
| 7 | Persetujuan ganda (orang + divisinya, atau dua kali) | Dihitung sekali | [Pasti] |
| 8 | Uji bot bisa mengganggu uji pengingat (pelajaran 7c-1) | Tap uji dikirim lewat mesin yang sudah mengirim | [Pasti] |

### Perlu diketahui pemilik

- **Ini mengubah mesin hitung gaji** (versi kode 7). Tanpa perintah `setujui_datang_awal`, semua angka harus sama persis dengan sekarang; itu dibuktikan dengan uji U1 dan perbandingan semua orang di Supabase sesudah dipasang.
- **Uji nyata mengubah gaji demo periode 4** untuk satu orang, lalu dikembalikan oleh pembatalan.
- **Tidak ikut:** datang awal di hari libur nasional berjadwal (D3), batas menit datang awal selain jendela tap.

## 6. Yang tidak ikut paket mana pun

Isi Sheets dan halaman demo tidak berubah bentuk. Data simulasi dan kasus jebakan tidak diubah.
