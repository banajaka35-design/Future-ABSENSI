# Laporan kewajaran data simulasi

Dibuat otomatis oleh `generator/periksa_kewajaran.py` (PRD v3.1 aturan F12).

**Hasil: 130 dari 130 pemeriksaan lulus.**

Kemandirian generator: tidak ada impor di luar pustaka bawaan.

## Ukuran file mesin

| Pabrik | Periode | Mesin | Baris | Baris lanjutan (tanggal 21 / tanggal 1) |
| --- | --- | --- | --- | --- |
| A | 1 | MA1 | 40.566 | 203 |
| A | 1 | MA2 | 5.671 | 0 |
| A | 2 | MA1 | 36.179 | 207 |
| A | 2 | MA2 | 4.937 | 0 |
| A | 3 | MA1 | 39.608 | 199 |
| A | 3 | MA2 | 5.199 | 0 |
| A | 4 | MA1 | 39.519 | 206 |
| A | 4 | MA2 | 5.931 | 0 |
| B | 1 | MB1 | 6.830 | 6 |
| B | 2 | MB1 | 6.244 | 11 |
| B | 3 | MB1 | 7.994 | 12 |
| B | 4 | MB1 | 8.081 | 10 |

## Pemeriksaan

| Pabrik | Periode | Pemeriksaan | Nilai | Target | Hasil |
| --- | --- | --- | --- | --- | --- |
| A | 1 | Alpha + sakit + izin + cuti (% hari kerja) | 2.33% | 1–3% | lulus |
| A | 1 | Lupa tap (% hari hadir) | 1.41% | 1–2% | lulus |
| A | 1 | Tap ulang (% hari hadir) | 3.03% | ±3% | lulus |
| A | 1 | Status terbalik (% tap) | 5.24% | ±5% | lulus |
| A | 1 | Baris dobel persis | 98 | ada, sedikit | lulus |
| A | 1 | Tap tunggal di tengah shift | 51 | ada | lulus |
| A | 1 | Tap ID tidak dikenal | 6 | ada | lulus |
| A | 1 | Tukar shift (tidak dilaporkan) | 40 (16) | ada, sebagian tidak dilaporkan | lulus |
| A | 1 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| A | 1 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| A | 1 | Shift malam melewati tengah malam | 6258 dari 5532 | semua malam | lulus |
| A | 1 | Format ekspor MA1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 1 | Baris file MA1 vs batas .xls 65.536 | 40566 | di bawah batas | lulus |
| A | 1 | attlog MA1 sama jumlah baris dengan ekspor | 40566 vs 40566 | sama | lulus |
| A | 1 | Format ekspor MA2 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 1 | Baris file MA2 vs batas .xls 65.536 | 5671 | di bawah batas | lulus |
| A | 1 | attlog MA2 sama jumlah baris dengan ekspor | 5671 vs 5671 | sama | lulus |
| A | 1 | Mesin MA2 mati 2026-02-06 (dilaporkan) | 0 tap | 0 tap | lulus |
| A | 2 | Alpha + sakit + izin + cuti (% hari kerja) | 2.23% | 1–3% | lulus |
| A | 2 | Lupa tap (% hari hadir) | 1.45% | 1–2% | lulus |
| A | 2 | Tap ulang (% hari hadir) | 2.94% | ±3% | lulus |
| A | 2 | Status terbalik (% tap) | 4.96% | ±5% | lulus |
| A | 2 | Baris dobel persis | 96 | ada, sedikit | lulus |
| A | 2 | Tap tunggal di tengah shift | 31 | ada | lulus |
| A | 2 | Tap ID tidak dikenal | 6 | ada | lulus |
| A | 2 | Tukar shift (tidak dilaporkan) | 46 (11) | ada, sebagian tidak dilaporkan | lulus |
| A | 2 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| A | 2 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| A | 2 | Shift malam melewati tengah malam | 5658 dari 4999 | semua malam | lulus |
| A | 2 | Format ekspor MA1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 2 | Baris file MA1 vs batas .xls 65.536 | 36179 | di bawah batas | lulus |
| A | 2 | attlog MA1 sama jumlah baris dengan ekspor | 36179 vs 36179 | sama | lulus |
| A | 2 | Format ekspor MA2 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 2 | Baris file MA2 vs batas .xls 65.536 | 4937 | di bawah batas | lulus |
| A | 2 | attlog MA2 sama jumlah baris dengan ekspor | 4937 vs 4937 | sama | lulus |
| A | 2 | Selisih jam MA2 +4 menit 2026-03-01..2026-03-10 | 1872 tap | semua bergeser | lulus |
| A | 2 | Tap dengan ID mesin kedua (90001) | 15 | ada sejak 1 Mar | lulus |
| A | 3 | Alpha + sakit + izin + cuti (% hari kerja) | 2.25% | 1–3% | lulus |
| A | 3 | Lupa tap (% hari hadir) | 1.45% | 1–2% | lulus |
| A | 3 | Tap ulang (% hari hadir) | 3.00% | ±3% | lulus |
| A | 3 | Status terbalik (% tap) | 5.11% | ±5% | lulus |
| A | 3 | Baris dobel persis | 74 | ada, sedikit | lulus |
| A | 3 | Tap tunggal di tengah shift | 45 | ada | lulus |
| A | 3 | Tap ID tidak dikenal | 6 | ada | lulus |
| A | 3 | Tukar shift (tidak dilaporkan) | 52 (22) | ada, sebagian tidak dilaporkan | lulus |
| A | 3 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| A | 3 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| A | 3 | Shift malam melewati tengah malam | 6230 dari 5507 | semua malam | lulus |
| A | 3 | Format ekspor MA1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 3 | Baris file MA1 vs batas .xls 65.536 | 39608 | di bawah batas | lulus |
| A | 3 | attlog MA1 sama jumlah baris dengan ekspor | 39608 vs 39608 | sama | lulus |
| A | 3 | Format ekspor MA2 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 3 | Baris file MA2 vs batas .xls 65.536 | 5199 | di bawah batas | lulus |
| A | 3 | attlog MA2 sama jumlah baris dengan ekspor | 5199 vs 5199 | sama | lulus |
| A | 3 | Tap dengan ID mesin kedua (90001) | 24 | ada sejak 1 Mar | lulus |
| A | 4 | Alpha + sakit + izin + cuti (% hari kerja) | 1.99% | 1–3% | lulus |
| A | 4 | Lupa tap (% hari hadir) | 1.53% | 1–2% | lulus |
| A | 4 | Tap ulang (% hari hadir) | 3.12% | ±3% | lulus |
| A | 4 | Status terbalik (% tap) | 4.89% | ±5% | lulus |
| A | 4 | Baris dobel persis | 109 | ada, sedikit | lulus |
| A | 4 | Tap tunggal di tengah shift | 45 | ada | lulus |
| A | 4 | Tap ID tidak dikenal | 6 | ada | lulus |
| A | 4 | Tukar shift (tidak dilaporkan) | 52 (12) | ada, sebagian tidak dilaporkan | lulus |
| A | 4 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| A | 4 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| A | 4 | Shift malam melewati tengah malam | 6085 dari 5343 | semua malam | lulus |
| A | 4 | Format ekspor MA1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 4 | Baris file MA1 vs batas .xls 65.536 | 39519 | di bawah batas | lulus |
| A | 4 | attlog MA1 sama jumlah baris dengan ekspor | 39519 vs 39519 | sama | lulus |
| A | 4 | Format ekspor MA2 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| A | 4 | Baris file MA2 vs batas .xls 65.536 | 5931 | di bawah batas | lulus |
| A | 4 | attlog MA2 sama jumlah baris dengan ekspor | 5931 vs 5931 | sama | lulus |
| A | 4 | Tap dengan ID mesin kedua (90001) | 21 | ada sejak 1 Mar | lulus |
| B | 1 | Alpha + sakit + izin + cuti (% hari kerja) | 2.42% | 1–3% | lulus |
| B | 1 | Lupa tap (% hari hadir) | 1.45% | 1–2% | lulus |
| B | 1 | Tap ulang (% hari hadir) | 3.16% | ±3% | lulus |
| B | 1 | Status terbalik (% tap) | 5.22% | ±5% | lulus |
| B | 1 | Baris dobel persis | 12 | ada, sedikit | lulus |
| B | 1 | Tap tunggal di tengah shift | 5 | ada | lulus |
| B | 1 | Tap ID tidak dikenal | 3 | ada | lulus |
| B | 1 | Tukar shift (tidak dilaporkan) | 4 (1) | ada, sebagian tidak dilaporkan | lulus |
| B | 1 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| B | 1 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| B | 1 | Shift malam melewati tengah malam | 260 dari 109 | semua malam | lulus |
| B | 1 | Format ekspor MB1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| B | 1 | Baris file MB1 vs batas .xls 65.536 | 6830 | di bawah batas | lulus |
| B | 1 | attlog MB1 sama jumlah baris dengan ekspor | 6830 vs 6830 | sama | lulus |
| B | 2 | Alpha + sakit + izin + cuti (% hari kerja) | 2.06% | 1–3% | lulus |
| B | 2 | Lupa tap (% hari hadir) | 1.68% | 1–2% | lulus |
| B | 2 | Tap ulang (% hari hadir) | 3.55% | ±3% | lulus |
| B | 2 | Status terbalik (% tap) | 4.54% | ±5% | lulus |
| B | 2 | Baris dobel persis | 10 | ada, sedikit | lulus |
| B | 2 | Tap tunggal di tengah shift | 6 | ada | lulus |
| B | 2 | Tap ID tidak dikenal | 3 | ada | lulus |
| B | 2 | Tukar shift (tidak dilaporkan) | 13 (2) | ada, sebagian tidak dilaporkan | lulus |
| B | 2 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| B | 2 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| B | 2 | Shift malam melewati tengah malam | 279 dari 133 | semua malam | lulus |
| B | 2 | Format ekspor MB1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| B | 2 | Baris file MB1 vs batas .xls 65.536 | 6244 | di bawah batas | lulus |
| B | 2 | attlog MB1 sama jumlah baris dengan ekspor | 6244 vs 6244 | sama | lulus |
| B | 2 | Mesin MB1 mati 2026-03-11 (tidak_dilaporkan) | 0 tap | 0 tap | lulus |
| B | 3 | Alpha + sakit + izin + cuti (% hari kerja) | 2.27% | 1–3% | lulus |
| B | 3 | Lupa tap (% hari hadir) | 1.16% | 1–2% | lulus |
| B | 3 | Tap ulang (% hari hadir) | 3.16% | ±3% | lulus |
| B | 3 | Status terbalik (% tap) | 5.06% | ±5% | lulus |
| B | 3 | Baris dobel persis | 10 | ada, sedikit | lulus |
| B | 3 | Tap tunggal di tengah shift | 8 | ada | lulus |
| B | 3 | Tap ID tidak dikenal | 3 | ada | lulus |
| B | 3 | Tukar shift (tidak dilaporkan) | 6 (1) | ada, sebagian tidak dilaporkan | lulus |
| B | 3 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| B | 3 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| B | 3 | Shift malam melewati tengah malam | 314 dari 132 | semua malam | lulus |
| B | 3 | Format ekspor MB1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| B | 3 | Baris file MB1 vs batas .xls 65.536 | 7994 | di bawah batas | lulus |
| B | 3 | attlog MB1 sama jumlah baris dengan ekspor | 7994 vs 7994 | sama | lulus |
| B | 4 | Alpha + sakit + izin + cuti (% hari kerja) | 2.21% | 1–3% | lulus |
| B | 4 | Lupa tap (% hari hadir) | 1.47% | 1–2% | lulus |
| B | 4 | Tap ulang (% hari hadir) | 2.61% | ±3% | lulus |
| B | 4 | Status terbalik (% tap) | 5.09% | ±5% | lulus |
| B | 4 | Baris dobel persis | 11 | ada, sedikit | lulus |
| B | 4 | Tap tunggal di tengah shift | 9 | ada | lulus |
| B | 4 | Tap ID tidak dikenal | 3 | ada | lulus |
| B | 4 | Tukar shift (tidak dilaporkan) | 6 (2) | ada, sebagian tidak dilaporkan | lulus |
| B | 4 | Tap tanpa kejadian hadir | 0 | 0 | lulus |
| B | 4 | Hari hadir bertap tanpa tap sama sekali | 0 | 0 | lulus |
| B | 4 | Shift malam melewati tengah malam | 326 dari 144 | semua malam | lulus |
| B | 4 | Format ekspor MB1 (judul, waktu bertitik) | sesuai | sama dengan file asli | lulus |
| B | 4 | Baris file MB1 vs batas .xls 65.536 | 8081 | di bawah batas | lulus |
| B | 4 | attlog MB1 sama jumlah baris dengan ekspor | 8081 vs 8081 | sama | lulus |
