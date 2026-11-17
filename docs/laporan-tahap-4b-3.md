# Laporan paket 4b-3: PPh masa terakhir, saldo cuti, pecahan uang tunai

17 November 2026 · acuan: `docs/aturan-hitung-gaji.md` versi 3 (commit 9629875, sebelum kode), `docs/cek-aturan-hukum.md` bagian 9

## Hasil singkat

| Uji | Hasil | Bukti |
| --- | --- | --- |
| Kunci K28–K37 (PPh setahun Tuan A, Desember, berhenti dan pengembalian, data tidak lengkap, cuti bersama, saldo cuti, pecahan) | **Lulus** | `db/uji/080_gaji_masa_terakhir_cuti_tunai.sql` (33 uji) |
| Uji 4b-1 dan 4b-2 tetap lulus dengan kode versi 3 | **Lulus** | `060`, `070` |
| Pembanding vs sistem, semua orang-periode | **Lulus**: 4.037 orang-periode, selisih 0 | uji simulasi |
| Naik dari 0010 ke 0011 di salinan lokal (seperti Supabase) | **Lulus**: 4 periode dihitung ulang otomatis sebagai versi 3 | `pasang_supabase.sh` dua kali |

**Bukti pembanding memeriksa: lebih lemah dari 4b-2 [Pasti].** Uji GitHub commit kunci jawaban (9629875) memang gagal, tetapi karena tabel `aturan.tarif_pasal17` belum ada (pembanding berhenti), bukan karena selisih angka. Jadi kali ini tidak ada bukti "pembanding menangkap angka yang salah". Yang tetap berlaku: kunci K28–K37 di `080` ditulis dari hitungan tangan dan ilustrasi PMK 168, bukan dari keluaran kode.

## Yang diubah

| Bagian | Isi |
| --- | --- |
| Migrasi 0011 | Tabel `aturan.tarif_pasal17` (5 lapis UU HPP, sejak 2022) dan `induk.saldo_cuti_awal`; kolom `cuti_terpakai`, `saldo_cuti` di ringkasan gaji; fungsi `pph_pasal17`, `pph21_setahun`, `pecahan_tunai`, `periode_bisa_diajukan`; `hitung_gaji` versi 3 |
| PPh masa terakhir | Desember, atau periode karyawan berhenti: hitung ulang setahun (biaya jabatan 5% maks 500.000 × bulan, iuran JHT+JP, PTKP, PKP dibulatkan ke ribuan, tarif Pasal 17) dikurangi PPh yang sudah dipotong. Lebih bayar → komponen `pengembalian_pph21` (menambah gaji bersih, tidak masuk bruto pajak) |
| Data setahun tidak lengkap | PPh masa itu 0, tanda `pph_masa_terakhir_tertahan`, periode tidak bisa diajukan |
| Cuti | Cuti terpakai per periode; cuti bersama "potong cuti" hanya sebelum 28 Okt 2026, sesudahnya tanda `potong_cuti_tidak_berlaku_uu27`. Saldo dihitung bila ada saldo awal dan periodenya bersambung; tanpa saldo awal saldo kosong |
| Uji 060 | Satu uji lama ("Desember belum dihitung") disesuaikan ke aturan v3 L2 |

## Angka terukur

| Yang diukur | Hasil |
| --- | --- |
| Uji database (komputer kerja) | 311 lulus, 0 gagal |
| Uji simulasi (komputer kerja) | 12 lulus, 0 gagal |
| GitHub "Uji database" 6aa63b8 | lulus |
| Pasang ke Supabase | lulus; 0011 sidik `a87c245ed7d0` sama dengan salinan lokal |
| Hitung gaji di Supabase | 11,6–12,6 detik per periode di database (4b-2: 7,2–12,2) |

## Di Supabase (dicek langsung)

| Periode | Orang | Gaji bersih | PPh tertahan | Bisa diajukan |
| --- | --- | --- | --- | --- |
| 1 (bayar 25 Feb) | 1.011 | 5.183.058.029 | 12 | tidak |
| 2 (bayar 25 Mar) | 1.010 | 8.216.773.882 | 11 | tidak |
| 3 (bayar 25 Apr) | 1.010 | 5.706.405.590 | 15 | tidak |
| 4 (bayar 25 Des) | 1.006 | 4.999.870.485 | 1.006 | tidak |

Angka Supabase sama persis dengan salinan lokal. Pecahan tunai tersedia per periode (misalnya periode 1: 15.423 lembar 100.000, 147 lembar 50.000, …).

**Kenapa gaji bersih periode 2 dan 3 naik:** orang yang berhenti di periode itu kini PPh-nya ditahan (0), bukan TER. Selisihnya diperiksa: TER yang dulu dipotong dari orang tertahan = Rp291.834 (periode 2) dan Rp28.815 (periode 3), tepat sama dengan kenaikan [Pasti]. Periode 1: 12 orang tertahan, TER mereka memang 0.

## Temuan dan batasan

1. **Semua periode demo "tidak bisa diajukan"** [Pasti]. Data simulasi tidak punya periode bayar Januari, jadi orang yang berhenti dan seluruh periode Desember tertahan. Ini sesuai aturan L2, bukan kesalahan.
2. **Masalah nyata untuk perusahaan sungguhan** [Pasti]: perusahaan yang mulai memakai sistem di tengah tahun tidak punya data Januari sampai bulan mulai, sehingga PPh Desember tahun pertama akan selalu tertahan. Perlu isian "data pajak awal tahun" (bruto, iuran, PPh yang sudah dipotong per karyawan dari sistem lama). **Belum dikerjakan** (tidak ada di daftar paket); usul dimasukkan ke paket berikutnya.
3. **Saldo cuti awal belum diisi** untuk data simulasi, jadi saldo di Supabase kosong untuk semua orang. Hanya diuji dengan contoh buatan (K36).
4. **Berhenti di tengah tahun** memakai jumlah bulan yang benar-benar digaji untuk batas biaya jabatan [Menebak, lihat cek-aturan-hukum bagian 9].
5. **Hitung gaji makin lambat** (sekitar 12 detik per periode di Supabase), jauh di atas batas 8 detik fungsi API. Harus diselesaikan di Tahap 5.
6. **Belum dikerjakan dari Tahap 4b:** Pabrik B (U5) dan U10 anomali (paket 4b-4).
