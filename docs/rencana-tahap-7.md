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

## 6. Yang tidak ikut paket mana pun

Isi Sheets dan halaman demo tidak berubah bentuk. Data simulasi dan kasus jebakan tidak diubah.
