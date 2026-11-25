# Cara mengisi templat data karyawan

Dipakai di langkah 5 panduan pasang (`docs/pasang/README.md`). Templat ada di `docs/pasang/templat/`: tiga file CSV yang baru
berisi baris judul. Kolomnya sama persis dengan data simulasi Pabrik A/B, sehingga dimuat oleh pemuat yang sama
(`db/data_awal/muat_karyawan.py`). Pemeriksa otomatis gagal bila judul kolom templat berbeda dengan data simulasi.

**Data karyawan asli tidak pernah dimasukkan ke repo**, walaupun repo PT privat. File yang sudah diisi HRD disimpan di tempat
tertutup milik PT; cara memuatnya ke Supabase PT diputuskan saat PT pertama (lihat README bagian "Belum ada").

## 1. `karyawan.csv`: satu baris per karyawan

| Kolom | Isi | Contoh | Catatan |
| --- | --- | --- | --- |
| `id` | ID karyawan (NIK perusahaan) | `10001` | Unik. Simpan sebagai teks supaya nol di depan tidak hilang |
| `nama` | Nama lengkap | `Eka Susanto` | |
| `divisi` | Kode divisi dari jawaban pertanyaan B1 | `PRD` | Harus sama persis dengan kode di susunan PT |
| `regu` | Nomor regu untuk divisi bergilir, `0` untuk divisi jam tetap | `0` | Nomor regu mulai dari 0 |
| `mulai` | Tanggal mulai bekerja | `2025-08-20` | Bentuk tahun-bulan-tanggal |
| `berhenti` | Hari kerja terakhir, kosong bila masih bekerja | | Keputusan 25 Nov 2026: "berhenti tanggal X" = hari kerja terakhir |
| `tipe_upah` | `bulanan` | `bulanan` | Hanya `bulanan` yang dihitung mesin gaji sekarang; upah harian/borongan adalah temuan, tanyakan ke pemilik proyek |
| `gaji_pokok` | Gaji pokok per bulan, rupiah tanpa titik | `4100000` | |
| `tunjangan_tetap` | Tunjangan tetap per bulan, `0` bila tidak ada | `300000` | |
| `ptkp` | Status PTKP | `K/3` | Salah satu: `TK/0` `TK/1` `TK/2` `TK/3` `K/0` `K/1` `K/2` `K/3` |
| `cara_bayar` | `transfer` atau `tunai` | `transfer` | Orang bergaji rahasia wajib `transfer` |
| `wajib_tap` | `ya` atau `tidak` (tidak perlu absen fingerprint) | `ya` | Karyawan wajib tap harus punya baris di `pemetaan_id_mesin.csv` |
| `gaji_rahasia` | `ya` bila gajinya tidak boleh dilihat HRD, kosong bila tidak | | Pertanyaan H1 |
| `catatan` | Catatan bebas, tidak dipakai hitungan | | |

Belum bisa diisi lewat templat (temuan 9d, diubah lewat web HRD "Ubah gaji" sesudah pasang, atau perlu paket kecil):
ikut/tidak ikut BPJS (bawaan: ikut keduanya), jabatan, nomor rekening (belum dienkripsi), saldo cuti awal.

## 2. `pemetaan_id_mesin.csv`: ID karyawan di mesin absen

Satu baris per karyawan per mesin. Satu orang boleh punya dua ID di mesin yang sama (misalnya terdaftar ulang); keduanya ditulis.

| Kolom | Isi | Contoh |
| --- | --- | --- |
| `mesin` | Kode mesin dari pertanyaan A3 | `MA1` |
| `id_mesin` | Nomor yang tercatat di mesin fingerprint | `10001` |
| `id_karyawan` | ID karyawan di `karyawan.csv` | `10001` |
| `berlaku_dari` | Sejak kapan nomor ini dipakai | `2025-08-20` |
| `berlaku_sampai` | Kosong bila masih dipakai | |

## 3. `mutasi_regu.csv`: pindah regu (boleh kosong)

Hanya untuk karyawan yang pindah regu sesudah tanggal mulai. File boleh dibiarkan hanya berisi judul.

| Kolom | Isi | Contoh |
| --- | --- | --- |
| `id_karyawan` | ID karyawan | `10095` |
| `berlaku_dari` | Tanggal mulai di regu baru | `2026-01-26` |
| `regu_baru` | Nomor regu baru | `3` |

## Kesalahan yang sering terjadi saat memakai Excel

- **Nol di depan ID hilang** (`00123` menjadi `123`). Sebelum mengetik, blok kolom `id`, `id_mesin`, `id_karyawan` → Format Cells →
  Text.
- **Tanggal berubah bentuk** (`20/08/2025` atau `Aug-20`). Format kolom tanggal sebagai Text, lalu ketik `2025-08-20`.
- **Pemisah titik koma.** Excel berbahasa Indonesia kadang menyimpan CSV dengan `;`. Simpan lewat File → Save As → **CSV UTF-8
  (Comma delimited)**. Dari Google Sheets: File → Download → **Comma Separated Values (.csv)**.
- **Angka dengan titik ribuan** (`4.100.000`). Tulis tanpa titik: `4100000`.
- Tanda BOM yang ditambahkan Excel di awal file tidak masalah; pemuat sudah membacanya.

## Pemeriksaan saat dimuat

Database menolak seluruh isi file (tidak ada yang dimuat setengah) bila: ID ganda, divisi tidak ada di susunan PT, PTKP atau cara
bayar di luar pilihan, gaji minus, tanggal salah. Sesudah dimuat, pemeriksaan pemasangan perusahaan (`db/pasang_supabase.sh`)
memastikan setiap karyawan punya riwayat gaji, punya regu sejak mulai kerja, karyawan wajib tap punya ID mesin, dan orang bergaji
rahasia dibayar transfer. Pemasangan berhenti bila satu saja gagal.
