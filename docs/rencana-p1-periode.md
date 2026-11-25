# Rencana paket P1: periode gaji bulanan otomatis

Ditulis 25 November 2026. **Belum di-"buat".** Asal: temuan P1 paket 9d (`docs/pasang/README.md`).

## Masalah [Pasti, diperiksa di kode 25 Nov]

- `fakta.periode` hanya diisi dari data awal: `db/data_awal/pabrik_a_tahap3.sql` (demo) dan file susunan PT. Tidak ada migrasi,
  bot, web, atau workflow yang membuat periode baru.
- Demo punya 4 periode; yang terakhir 21 Nov – 20 Des 2026. File mesin berisi tap mulai 21 Des 2026 akan diterima, tetapi tidak
  masuk periode mana pun, sehingga tidak dihitung dan tidak ada gaji.
- Pengaturan yang dibutuhkan sudah ada: `tanggal_tutup_buku` (0 = akhir bulan) dan `tanggal_gajian`, juga fungsi
  `fakta.tutup_buku_sebelum` (migrasi 0018, dipakai pengingat kirim file).

## Isi paket

1. **Migrasi 0043**, fungsi `fakta.buat_periode_sampai(p_tanggal date)`: membuat periode berurutan sesudah periode terakhir
   sampai periode yang memuat `p_tanggal`.
   - Tanggal awal = sehari sesudah akhir periode terakhir. Tanggal akhir = tanggal tutup buku berikutnya menurut pengaturan pada
     tanggal itu (0 atau tanggal yang melewati panjang bulan = akhir bulan). Tanggal bayar = tanggal `tanggal_gajian` pertama
     sesudah tanggal akhir. Contoh: Pabrik A (tutup 20, gajian 25) → 21 Des 2026 – 20 Jan 2027, bayar 25 Jan 2027; Pabrik B
     (akhir bulan, gajian 5) → 1–31 Jan 2027, bayar 5 Feb 2027.
   - Tidak pernah membuat periode sebelum periode pertama dan tidak mengubah periode yang sudah ada.
   - Batas: hanya periode yang tanggal awalnya tidak sesudah **hari ini (WIB)**, dan paling banyak **2** periode baru dalam satu
     panggilan (jam mesin yang salah tahun tidak bisa membuat puluhan periode).
   - Setiap periode baru dicatat di `jejak` seperti perubahan lain (oleh: akun yang mengirim file).
2. **Dipanggil saat file mesin diterima lewat bot dan halaman unggah** (`api.pintu_terima_file` dan jalur unggah web), sebelum
   periode yang terkena dicari. Tidak dipanggil dari `fakta.terima_kiriman` (inti), supaya pemuat data simulasi dan uji tidak
   berubah dan tidak bergantung pada tanggal hari ini.
3. **Balasan bot** menyebut periode baru: "Periode baru no. 5 dibuat: 21 Des 2026 – 20 Jan 2027, gajian 25 Jan 2027."
4. **Uji database:** contoh Pabrik A dan Pabrik B (tanggal pura-pura), batas hari ini, batas 2 periode, tidak menyentuh periode
   lama, pengaturan bertanggal (tutup buku berubah di tengah tahun), periode dirilis tidak terpengaruh. **Uji pintu:** balasan
   bot berisi periode baru. Uji simulasi dan sidik gaji demo tidak boleh berubah.
5. **Pasang ke Supabase** sesudah uji GitHub lulus (migrasi 0043 + Edge Function). Bukti: sidik gaji periode 1–4 tetap.

## Keputusan untuk pemilik

| No | Pertanyaan | Pilihan | Saran Claude dan alasannya |
| --- | --- | --- | --- |
| K1 | Kapan periode baru dibuat? | (a) saat file mesin berisi tap sesudah periode terakhir diterima; (b) terjadwal setiap hari lewat penjadwal Supabase | **(a)**. Periode baru memang hanya berguna bila ada tap untuk dihitung; tidak menambah jadwal baru. Kekurangannya, perintah HRD untuk tanggal di periode yang belum ada tetap ditolak "tanpa periode" sampai file pertama periode itu masuk [Kemungkinan Besar: sama dengan perilaku sekarang] |
| K2 | Batas periode baru | (a) tidak sesudah hari ini dan maksimal 2 per file; (b) tanpa batas | **(a)**. Mencegah jam mesin yang salah membuat periode masa depan |

Tidak ada keputusan yang mengubah angka gaji yang sudah ada atau membatasi akun pembangun.

## Analisa celah

| No | Celah | Penutup | Label |
| --- | --- | --- | --- |
| C1 | Uji dan pemuat simulasi berubah hasil setelah tanggal tertentu (periode 5 tercipta sendiri) | Fungsi hanya dipanggil dari jalur bot/unggah, bukan dari `fakta.terima_kiriman`; uji memakai tanggal pura-pura | [Pasti] |
| C2 | Jam mesin salah membuat periode masa depan | Batas hari ini WIB dan maksimal 2 periode | [Pasti] |
| C3 | Dua file masuk bersamaan membuat periode ganda | Kunci tumpang tindih tanggal di `fakta.periode` sudah ada (0001); fungsi memakai kunci advisory | [Kemungkinan Besar] |
| C4 | Pengaturan tutup buku diubah di tengah jalan menghasilkan periode pendek/panjang yang aneh | Periode baru mengikuti pengaturan yang berlaku pada tanggal awalnya; uji khusus | [Kemungkinan Besar] |
| C5 | Sheets/web tidak menampilkan periode baru | Keduanya membaca semua periode dari database; diperiksa di uji nyata | [Kemungkinan Besar] |

## Uji nyata

[Pasti] Di demo, periode 5 baru bisa dibuat mulai **21 Des 2026** (batas hari ini). Sebelum itu bukti dari uji database dan pintu.
Uji nyata dicatat berjalan di belakang (aturan 10): pada atau sesudah 21 Des 2026 HRD/pembangun mengirim file mesin berisi tap
21 Des, lalu dicek periode 5 di Supabase, Sheets, dan web HRD.

## Yang belum pasti

- [Menebak] Letak tepat jalur unggah web (migrasi 0019/0020) yang ikut diubah; dipastikan saat dibuat.
