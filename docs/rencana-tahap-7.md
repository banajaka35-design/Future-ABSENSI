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
| **7c** | Persetujuan, isinya tergantung keputusan pemilik (bagian 3 nomor 1) | F11, F12, D05 bila pilihan (a) |
| **7d** | Batalkan perintah (`batalkan_perintah`) dan "daftar perintah terakhir saya", supaya salah ketik bisa dibetulkan tanpa menghapus baris (fakta hanya bertambah) | Perintah dibatalkan → hasil kembali seperti semula |
| di luar PRD Tahap 7 | Absen manual divisi, tambah libur, berhenti/aktif kembali, karyawan baru, mutasi, ubah gaji, penyesuaian, data pajak awal tahun | Tidak dikerjakan di Tahap 7 kecuali pemilik memintanya; [Kemungkinan Besar] cocok untuk templat/web Tahap 9 |

Yang **sama untuk semua paket** (dicatat supaya tidak lupa saat menulis daftar lengkap):

- Migrasi baru untuk fungsi simpan perintah (peran `pintu` tidak menulis tabel langsung, sama seperti paket 8).
- Uji otomatis di GitHub (database + pintu) sebelum Pasang; Pasang lewat cabang `pasang`.
- Balasan bot tidak boleh membuka gaji orang rahasia (F15, F15b). Perintah untuk orang rahasia tetap boleh dicatat HRD; balasannya hanya nama, jenis, tanggal.
- Hitung ulang satu periode di Supabase: baca tap sekitar 12 detik dan gaji 5–6 detik (diukur di Tahap 3 dan 5a), di bawah batas Edge Function 150 detik. Lama total dari "Ya" sampai kabar selesai **belum diukur**.

## 3. Yang perlu diputuskan pemilik sebelum 7a ditulis lengkap

1. **Arti "persetujuannya".** (a) HRD menyetujui usulan sistem: tukar shift (F11) dan lembur tanpa perintah (D04, F12, D05); (b) kasbon perlu disetujui bos sebelum dicatat; (c) keduanya. Saran: **(a)**. Alasan [Kemungkinan Besar]: tabel `fakta.persetujuan` yang dirancang dari PRD sejak 0001 punya pilihan `tukar_shift`, `lembur`, `penyesuaian`, `rilis`, tetapi tidak punya `kasbon`.
2. **Cara menulis perintah.** (a) Perintah tetap, misalnya `/izin 10001 19-02` atau `/cuti 10001 19-02 21-02`, ditambah tombol "Perintah HRD" yang menuntun langkah demi langkah; atau (b) kalimat bebas ("10001 izin tgl 19") yang dibaca AI. Saran: **(a)** dulu. Alasan: tidak ada biaya AI, hasilnya bisa diuji pasti, tombol Ya/Batal menjaga salah ketik. (b) bisa ditambah nanti di atas (a).
3. **Izin dengan alasan Pasal 149 ayat 2** (menikah, keluarga meninggal, dan lain-lain; dibayar). Ikut 7a sebagai pilihan alasan, atau ditunda? Sekarang semua izin tidak dibayar (`izin_dibayar`).

## 4. Yang tidak ikut paket mana pun

Isi Sheets dan halaman demo tidak berubah bentuk. Data simulasi dan kasus jebakan tidak diubah.
