# Rencana paket G1: grafik di halaman demo — versi 2 (menunggu "buat")

18 November 2026 · versi 1 (pagi) ditulis ulang sesudah analisa kelemahan dan paket 6a-3, 6a-4, 6e, 6f · dimajukan dari Tahap 9 untuk portofolio (keputusan pemilik 18 Nov 2026; syarat PRD v2 "web dibangun setelah hitungan terbukti benar" sudah terpenuhi: U2, U3, U5 lulus, angka demo = gudang) · acuan: PRD v2 bagian 10 (tiga grafik web), `docs/halaman-demo.md` versi 4

## Perubahan dari versi 1 (hasil analisa)

| No | Kelemahan versi 1 | Di versi 2 |
| --- | --- | --- |
| K1 | Total per divisi memasukkan orang rahasia → total Kantor dikurangi gaji orang Kantor yang tampil = gaji orang rahasia (jenis kebocoran yang sama dengan F15b dan 6a-4) | Semua angka rupiah grafik **tanpa orang rahasia**, dengan keterangan "tidak termasuk N orang rahasia"; uji kebocoran per divisi |
| K2 | "Potongan" hanya BPJS/PPh; potongan alpha/izin (Rp39,9 juta di periode 1) tidak tampil sebagai potongan | Biaya per divisi memakai 4 nilai: gaji pokok, lembur, **potongan hari tidak dibayar**, **potongan lain** (BPJS karyawan, PPh 21, denda, kasbon) |
| K3 | Periode Nov–Des: PPh akhir tahun tertahan untuk semua orang; angka sementara tampil tanpa tanda | Grafik periode yang punya orang PPh tertahan diberi tanda "angka sementara: PPh akhir tahun belum dihitung (N orang)" |
| K4 | Periode Feb–Mar berisi THR; grafik porsi melonjak tanpa penjelasan | Keterangan "termasuk THR Rp…" bila periode memuat THR |
| K5 | Pemeriksa hanya memeriksa data, bukan gambar | Penghitung ukuran batang dipisah jadi fungsi murni yang diuji otomatis di Node; setiap batang diberi angka tertulis; tangkapan layar diperiksa |
| K6 | Janji "terang/gelap" berarti mengubah gaya seluruh halaman | **Dikeluarkan dari G1** (halaman tetap terang) |
| K7 | Header keamanan baru (6f) | Grafik digambar sebagai SVG lewat DOM oleh skrip halaman sendiri; tidak ada skrip/gaya dari luar; sidik skrip dihitung ulang otomatis saat terbit |

## Isi paket

1. **Dokumen dulu**: `docs/halaman-demo.md` versi 5 (bagian grafik, arti setiap angka, aturan rahasia, tanda sementara/THR), sebelum kode.
2. **Tiga grafik** (PRD v2 bagian 10) untuk periode yang dipilih:
   - **Biaya per divisi**: batang berkelompok per divisi, 4 nilai (K2); angka tertulis di tiap batang.
   - **Telat per tanggal**: jumlah orang telat per tanggal (status hadir dengan menit telat > 0; arti sama dengan kolom "Telat (kali)" di Sheets). Hitungan hadir bukan angka gaji, jadi orang rahasia ikut dihitung (sama dengan Sheets, yang menampilkan hadir/telat orang rahasia).
   - **Porsi gaji per divisi**: batang mendatar berisi persen dan rupiah gaji bersih tiap divisi, tanpa orang rahasia.
   - Divisi = divisi di hari terakhir periode (sama dengan daftar karyawan, Sheets, dan tanda anomali).
3. **Daftar karyawan**: pilihan Semua / Transfer / Tunai; rincian orang tunai menampilkan isi amplop (aturan pecahan sama dengan Sheets 6a-2); orang rahasia tetap tanpa angka.
4. **Data** (`web/buat_data.py`): per periode per divisi: orang tampil, gaji pokok, lembur, potongan hari tidak dibayar, potongan lain, gaji bersih (semua tanpa rahasia), jumlah orang rahasia; telat per tanggal; THR per periode (tanpa rahasia); jumlah PPh tertahan (sudah ada). Per orang: cara bayar dan isi amplop (bukan rahasia).
5. **Pemeriksa** (`web/periksa_data.py`, SQL sendiri): setiap angka grafik = gudang; **uji kebocoran per divisi: total divisi − jumlah per orang yang tampil di divisi itu = 0** untuk setiap nilai rupiah; amplop = dibayar; telat per tanggal dari hasil harian.
6. **Uji otomatis**: fungsi murni penghitung ukuran batang ditaruh di berkas `web/demo/grafik_inti.js` (dimuat halaman dari asal sendiri) dan diuji `node --test`: skala, batang nol, angka minus, satu divisi saja, 31 tanggal, label dijarangkan di layar sempit. `web/buat_headers.py` diubah: skrip dari halaman sendiri (`<script src="grafik_inti.js">`) boleh dengan `script-src 'self'`; skrip dari situs lain tetap ditolak. Uji simulasi: satu angka grafik di data diubah → pemeriksa GAGAL; total divisi dimasukkan orang rahasia → pemeriksa GAGAL (Pabrik A dan B).
7. **Terbit** lewat tombol "Terbitkan demo" sesudah semua uji GitHub lulus.
8. **Dicek langsung** di browser aplikasi Claude: tangkapan layar tiga grafik di lebar komputer dan HP (375 px); angka satu divisi dan satu tanggal dicocokkan dengan Supabase; tanda sementara (Nov–Des) dan keterangan THR (Feb–Mar) tampil; tidak ada galat CSP di konsol.
9. Laporan `docs/laporan-grafik-demo.md` dan serah-terima.

## Tidak diubah

Supabase (tanpa migrasi, tanpa Pasang), mesin hitung, Sheets, bot. Login, akun HRD/bos, total lengkap untuk bos, dan "daftar perlu dicek" tetap di Tahap 9.

## Belum pasti

- [Kemungkinan Besar] Ukuran `data.json` hanya bertambah sedikit (5 divisi × 4 periode dan sekitar 120 tanggal); diukur saat dibuat.
- [Menebak] Di layar HP grafik telat 30-31 batang rapat; bila begitu label tanggal dijarangkan (angka tidak berubah).
- `script-src 'self'` (untuk berkas grafik) menambah satu sumber yang diizinkan CSP; tetap hanya berkas di halaman sendiri.
