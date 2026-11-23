# Rencana paket 8e: keberatan karyawan lewat bot

Ditulis 23 Nov 2026 14.55 WIB atas permintaan pemilik ("ya lanjut"). Acuan: PRD v2 Tahap 8 ("keberatan") dan `docs/kontrak-data.md` tabel `keberatan` (karyawan, tanggal, isi, bukti tap, keputusan HRD). **Belum di-"buat".**

## Keadaan sekarang [Pasti, dicek di kode 23 Nov]

- Pesan rincian gaji ditutup dengan kalimat "Ada yang tidak sesuai? Hubungi HRD." Tidak ada jalur keberatan di bot.
- Karyawan baru menerima rincian gaji **sesudah periode dirilis**.
- Periode yang sudah `dirilis` atau `dikunci` **tidak bisa dihitung ulang**. Perintah HRD di tanggal itu (misalnya `/izin`) ditolak dengan alasan `periode_dirilis` (migrasi 0032). Akibatnya, keberatan yang diterima tidak bisa mengubah gaji periode yang sudah dirilis.

## Alur

1. Karyawan mengetik `/keberatan <tanggal> <alasan>`, misalnya `/keberatan 05-04-2026 saya masuk tapi tercatat alpha`. Bisa juga lewat tombol "Keberatan" di bawah kolom ketik.
2. Bot menampilkan bukti dari gudang untuk tanggal itu: status hari, jadwal, jam masuk dan pulang yang dipakai, menit telat, menit lembur, dan semua tap mentah hari itu beserta perannya. Karyawan lalu menekan **Kirim** atau **Batal**.
3. HRD dan pembangun menerima pesan berisi nomor keberatan, nama, ID, tanggal, alasan, dan bukti, dengan tombol **Terima** dan **Tolak**. Isinya tanpa angka gaji (F15).
   - Tolak: bot meminta alasan (jawab dengan membalas pesan bot). Alasan wajib diisi.
   - Terima: catatan boleh dikosongkan. Bot mengingatkan HRD perintah perbaikannya (`/izin`, `/sakit`, `/setujuilembur`, dan seterusnya) bila periode itu belum dirilis.
4. Karyawan menerima jawaban: diterima atau ditolak, beserta alasannya.
5. `/keberatan` tanpa isi: karyawan melihat keberatannya sendiri, sedangkan HRD dan pembangun melihat keberatan yang belum dijawab.

## Isi paket

1. **Migrasi `0038_keberatan.sql`**
   - `fakta.keberatan` (hanya bertambah): nomor, ID karyawan, akun pengirim, tanggal, alasan (paling banyak 300 huruf), salinan bukti saat dikirim (jsonb), periode, versi hitung, dan waktu.
   - `fakta.keputusan_keberatan` (hanya bertambah, satu per keberatan): diterima atau ditolak, alasan atau catatan, oleh siapa, dan waktu.
   - Draf keberatan berlaku 10 menit, sama seperti draf perintah.
   - Fungsi `api.pintu_keberatan_siapkan`, `api.pintu_keberatan_kirim`, `api.pintu_keberatan_putuskan`, dan `api.pintu_keberatan_daftar`.
   - Aturan:
     - Hanya akun karyawan aktif, dan hanya untuk dirinya sendiri.
     - Tanggal harus berada di periode yang sudah punya hasil hitung, dan tidak lewat batas (keputusan 1).
     - Satu keberatan terbuka per tanggal per orang.
     - Paling banyak 5 keberatan per orang per hari.
     - Hanya HRD dan pembangun yang boleh memutuskan; keputusan kedua ditolak.
2. **Bot**
   - Perintah `/keberatan`, tombol "Keberatan" untuk karyawan, dan tombol Kirim/Batal serta Terima/Tolak.
   - Pesan ke HRD/pembangun dan ke karyawan.
   - Kalimat penutup rincian gaji diganti dengan "Ada yang tidak sesuai? Ketik /keberatan <tanggal> <alasan>."
   - Menu dan teks bantuan untuk karyawan, HRD, dan pembangun diperbarui.
3. **Uji database dan uji bot**
   - Bukan karyawan ditolak.
   - Tanggal di luar periode atau lewat batas ditolak.
   - Dobel tanggal ditolak, dan batas 5 per hari berlaku.
   - Bukti sama dengan `hitung.hasil_harian` dan `hitung.tap_bersih`.
   - Karyawan tidak bisa memutuskan, dan keputusan kedua ditolak.
   - Tolak tanpa alasan ditolak.
   - Pesan HRD tanpa angka gaji, termasuk untuk orang rahasia.
   - Peran `pintu` tidak bisa membaca tabel langsung.
4. **Pasang ke Supabase** lewat cabang `pasang` setelah uji GitHub lulus.
5. **Uji nyata**
   - Akun kedua (karyawan 10735) mengirim keberatan untuk satu tanggal di periode 2, lalu pembangun menolak dengan alasan.
   - Keberatan kedua dikirim, lalu pembangun menerimanya.
   - Diperiksa di Supabase. Gaji dipastikan tidak berubah.
6. **Dokumen:** `docs/laporan-8e.md`, `docs/serah-terima.md`, dan `docs/rencana-tahap-8.md`.

## Keputusan untuk pemilik (menyangkut uang atau hak karyawan)

1. **Batas waktu keberatan.** Saran [Kemungkinan Besar]: sampai **14 hari sesudah tanggal bayar** periode itu. Untuk periode yang belum dirilis, keberatan juga boleh diajukan. Alasannya, karyawan baru tahu rinciannya sesudah gaji dirilis, jadi ia perlu waktu untuk memeriksa.
2. **Keberatan diterima untuk periode yang sudah dirilis.** Gaji periode itu tidak bisa diubah sistem (lihat "Keadaan sekarang"). Pilihan:
   - **(i) Saran:** di paket ini keberatan hanya **dicatat dan diputuskan**. Kekurangan bayar diselesaikan HRD di luar sistem, dan bot menuliskannya dengan jelas ke HRD dan karyawan ("diterima; selisih dibayar HRD di luar gaji periode ini"). Koreksi otomatis yang dibawa ke gaji periode berikutnya dijadikan paket terpisah.
   - (ii) Koreksi otomatis ke periode berikutnya ikut dibangun di 8e. Ini mengubah mesin hitung gaji, sehingga paketnya jauh lebih besar dan perlu kasus jebakan baru lewat permintaan perubahan.
3. **Bos ikut diberi tahu?** Saran: **tidak**. Keberatan adalah urusan harian HRD, dan bos sudah punya jalur rilis dan total lengkap.

## Keputusan Claude

- [Kemungkinan Besar] Keberatan yang diterima **tidak mengubah gaji secara otomatis**. Perbaikan tetap lewat perintah Tahap 7 yang sudah ada (bila periode belum dirilis), supaya hanya ada satu jalan untuk mengubah gaji.
- [Kemungkinan Besar] Bukti disalin saat keberatan dikirim, sehingga yang dilihat HRD tetap sama walaupun gaji dihitung ulang sesudahnya.
- Bukti hanya berisi data hari dan tap, tanpa angka rupiah.

## Belum pasti

- [Menebak] Lama pengerjaan belum diukur.
- Tombol "Keberatan" di HP: jumlah tombol karyawan bertambah dari 2 menjadi 3. Cukup diuji di HP.
