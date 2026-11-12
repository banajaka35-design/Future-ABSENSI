# Data simulasi — isi dan cara pakai

Semua isi `data/simulasi/` adalah karangan, dibuat oleh `generator/buat_data.py` dengan benih acak tetap. Dua kali jalan menghasilkan file yang identik byte demi byte.

## Pabrik

| | Pabrik A | Pabrik B |
| --- | --- | --- |
| Peran | Uji beban | Cermin pasar sasaran |
| Karyawan awal | 1.000 (PRD 600, QC 80, Keamanan 50, Gudang 150, Kantor 120) | 180 (Produksi 110, Gudang 30, Kantor 25, Keamanan 15) |
| Mesin | MA1 (gerbang pabrik), MA2 (kantor) | MB1 |
| Periode | 21 Jan–20 Feb, 21 Feb–20 Mar, 21 Mar–20 Apr, 21 Nov–20 Des 2026 | Feb, Mar, Apr, Des 2026 |
| Pola kerja | Rotasi 4 regu 8 hari (2 pagi, 2 siang, 2 malam, 2 libur) untuk PRD, QC, Keamanan; Gudang 2 shift 6 hari; Kantor 6 hari dengan Sabtu pendek dan jadwal Ramadan | Produksi 2 shift 5 hari; Gudang 2 shift 6 hari; Kantor 5 hari; Keamanan rotasi 4 regu |
| Cuti bersama | Dibayar | Memotong cuti |
| Cara bayar | Mayoritas transfer | Mayoritas tunai |

## Folder per pabrik

| Folder | Isi | Dipakai untuk |
| --- | --- | --- |
| `mesin/` | File ekspor aplikasi mesin per periode dan per mesin, format sama dengan file asli (Nama, No.ID, Tgl/Waktu bertitik, kolom tanpa judul, Status). File `_lanjutan` berisi tap tanggal sesudah tutup buku | Masukan pembaca tap; uji A11 (shift malam di batas periode) dan A1 (tap yang sama terkirim dua kali) |
| `attlog/` | Tap yang sama dalam format attlog.dat ZKTeco | Uji U6 (dua bentuk file, hasil harus sama) |
| `kunci/*_kejadian` | **Kunci jawaban**: per orang per hari, kejadian sebenarnya (hadir, alpha, sakit, libur, lupa tap, tukar shift) dan jam datang dan pulang sebenarnya | Uji U1, U5 |
| `kunci/*_jejak_tap` | Asal setiap tap: dari kejadian mana, apakah statusnya dibalik, dobel, atau digeser jam mesin | Menelusuri kegagalan uji |
| `masukan_hrd/` | Apa yang dilaporkan HRD: sakit, izin, cuti, berhenti, karyawan baru, mutasi regu, tukar shift, absen manual, perintah lembur (Pabrik B) | Uji perintah HRD (Tahap 7) |
| `induk/` | Data karyawan, pemetaan ID mesin, mutasi regu, divisi, jam jadwal, kalender 2026 | Isi awal gudang data (Tahap 2) |

## Kotoran yang ditanam

Takaran dan hasilnya ada di `docs/laporan-kewajaran-data.md`. Selain takaran acak, ada kejadian khusus:

- Mesin MA2 mati 6 Feb 2026 (dilaporkan HRD sebagai absen manual); mesin MB1 mati 11 Mar 2026 (tidak dilaporkan).
- Jam mesin MA2 lebih cepat 4 menit pada 1–10 Mar 2026.
- Satu karyawan Pabrik A terdaftar dua kali di mesin sejak 1 Mar 2026 (ID mesin 90001).
- ID tidak dikenal (tamu) di setiap periode.
- Dua karyawan bernama sama persis di setiap pabrik.
- Sopir Gudang Pabrik A tidak wajib tap; beberapa karyawan baru belum didaftarkan di mesin 3 hari pertama.

## Yang sengaja tidak ada di generator

Generator tidak menghitung telat, lembur, alpha, atau gaji. Semua itu tugas sistem, dan hasil sistem dibandingkan dengan kejadian di kunci jawaban serta dengan kasus jebakan.
