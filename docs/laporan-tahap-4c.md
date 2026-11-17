# Laporan paket 4c: halaman demo

17 November 2026 · acuan: `docs/halaman-demo.md` (ditulis sebelum kode)

Alamat: **https://future-absensi-demo.pages.dev/** (Cloudflare Pages, proyek `future-absensi-demo`, akun pemilik).

## Hasil singkat

| Syarat | Hasil | Bukti |
| --- | --- | --- |
| Hanya membaca hasil, bertanda "data simulasi", tanpa tombol aksi (PRD bagian 14, K11) | **Lulus** | halaman; tidak ada formulir atau tombol yang mengirim data |
| Halaman tidak menyentuh Supabase; tidak ada bagian database yang dibuka ke internet | **Lulus** | salinan tetap dibuat GitHub Actions |
| Angka demo sama dengan gudang (gerbang Tahap 4) | **Lulus**: 4 periode, 1.044 karyawan, 0 beda | `web/periksa_data.py` di uji GitHub (data simulasi) dan di workflow terbit (Supabase) |
| Pemeriksa benar-benar memeriksa | **Lulus**: dua angka yang sengaja diubah di salinan ikut tertangkap | percobaan lokal |
| Karyawan gaji rahasia tanpa angka | **Lulus**: 3 orang, tidak ada angkanya di file data | pemeriksa |

## Dicek langsung di halaman yang sudah terbit

Dibuka di browser 17 Nov 2026 12.47 WIB, data dibaca dari halaman, lalu dibandingkan dengan perintah SQL langsung ke Supabase:

| Periode | Orang | Gaji bersih | Dibayar | Tunai | Transfer | PPh tertahan | Tanda anomali |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1.011 | 5.183.058.029 | 5.182.913.834 | 1.557.200.000 | 3.625.713.834 | 12 | 4 |
| 2 | 1.010 | 8.216.773.882 | 8.216.770.362 | 2.454.507.000 | 5.762.263.362 | 11 | 24 |
| 3 | 1.010 | 5.706.405.590 | 5.706.401.189 | 1.722.580.000 | 3.983.821.189 | 15 | 33 |
| 4 | 1.006 | 4.999.870.485 | 4.999.877.277 | 1.529.688.000 | 3.470.189.277 | 1.006 | 22 |

Halaman dan Supabase sama persis. Klik satu karyawan (10001) memuat rincian per komponen beserta bukti hitungnya.

## Angka terukur

| Yang diukur | Hasil |
| --- | --- |
| Membuat data dari Supabase (GitHub Actions) | 7,8 dan 4,8 detik |
| Unggah ke Cloudflare Pages | 8,1 detik (pertama, termasuk membuat proyek); 6,8 detik (kedua) |
| Ukuran | 5,8 MB total; halaman awal `data.json` 158 KB; rincian 1,4–1,5 MB per periode, dimuat saat karyawan diklik |
| Uji simulasi lokal | 25 lulus |

## Keputusan dan batasan

1. **Unggah cadangan lewat web dipindah ke Tahap 5** (keputusan pemilik 17 Nov 2026). Syarat gerbang Tahap 4 di PRD perlu disesuaikan oleh pemilik (PRD dikelola pemilik).
2. **Angka di halaman diperbarui hanya saat workflow terbit berjalan**: otomatis sesudah "Pasang ke Supabase" lulus, atau lewat tombol.
3. Workflow sempat dijalankan dua kali oleh pemilik (tidak sengaja); keduanya lulus dan berjalan berurutan, tidak ada akibat.
4. **Alamat halaman bersifat umum**: siapa pun yang tahu alamatnya bisa membuka. Isinya hanya data karangan. Halaman diberi tanda agar tidak diindeks mesin pencari (`noindex`) [Kemungkinan Besar dipatuhi mesin pencari besar].
5. Tampilan ponsel belum diperiksa satu per satu; tata letaknya menyesuaikan lebar layar.
