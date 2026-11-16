# Laporan paket 4b-1: inti hitung gaji Pabrik A

16 November 2026 · acuan: `docs/aturan-hitung-gaji.md` (ditulis sebelum kode), `docs/cek-aturan-hukum.md`, kasus jebakan v1.2

## Hasil singkat

Mesin hitung gaji sudah menghitung 4 periode Pabrik A di Supabase: 4.037 orang-periode, 57.189 baris rincian. Semua uji lulus di komputer kerja, di GitHub Actions, dan pemeriksaan sesudah pemasangan di Supabase.

| Uji | Hasil | Bukti |
| --- | --- | --- |
| Kunci K1–K18 dan kasus C, D, E yang masuk paket ini | **Lulus** | `db/uji/060_hitung_gaji.sql` (64 uji) |
| K1 contoh resmi PMK 168 (bruto 30.160.000 → Rp3.920.800) | **Lulus** | sumber di luar Claude |
| U2 versi mesin: kalkulator pembanding vs sistem | **Lulus**: 4.037 orang-periode, selisih 0 rupiah | `sistem/uji/u2_pembanding.py`, uji simulasi |
| U3: gaji bersih = jumlah rincian (tiap orang dan total) | **Lulus** | `060`, `cek_gaji.sql` (juga di Supabase) |
| Dua kali hitung, sidik sama | **Lulus** | `060`, uji simulasi |
| Tabel dan fungsi gaji tertutup untuk akses tanpa login | **Lulus** | `060`, dicek langsung di Supabase |
| U2 dengan pembanding manusia | Belum (dipindah ke berjalan berdampingan, keputusan 13 Nov) | — |

**Batasan pembanding [Pasti]:** kalkulator pembanding dan kode SQL sama-sama ditulis Claude dari dokumen aturan yang sama. Selisih 0 membuktikan kode mengikuti dokumen, **bukan** bahwa dokumen benar menurut hukum. Satu-satunya angka dari luar Claude adalah K1 (contoh PMK 168) dan angka kasus jebakan dari PRD.

## Angka terukur

| Yang diukur | Hasil |
| --- | --- |
| Uji database (Postgres 16, komputer kerja) | 248 lulus, 0 gagal |
| Uji simulasi lengkap (komputer kerja) | 12 lulus, 0 gagal, 3 menit 29 detik |
| GitHub Actions "Uji database" commit 4e96d97 | lulus, sekitar 5 menit |
| Hitung gaji satu periode Pabrik A | Supabase **7,4–12,2 detik** · komputer kerja 3,8–6,1 detik |
| Pasang ke Supabase (cadangan, 0009, hitung 4 periode, pemeriksaan) | sekitar 4 menit, pemeriksaan 26 lulus 0 gagal |

Total gaji bersih per periode di Supabase sama persis dengan hitungan di komputer kerja (periode 1 Rp5.183.058.029; 2 Rp5.121.184.148; 3 Rp5.706.376.775; 4 Rp4.999.870.485), dan sama dengan jumlah rinciannya.

## Tiga contoh orang (Supabase)

**10003, Produksi, periode 21 Feb–20 Mar (bayar 25 Mar), satu alpha, shift malam, lembur**

| Komponen | Rupiah | Bukti |
| --- | --- | --- |
| Gaji pokok | 3.850.000 | sebulan penuh |
| Tunjangan tetap | 350.000 | 24 dari 24 hari kerja |
| Potongan hari tidak dibayar | −175.000 | 1 alpha × 4.200.000 ÷ 24 hari |
| Uang makan | 285.000 | 19 hari hadir × 15.000 |
| Tunjangan shift malam | 50.000 | 5 hari |
| Premi hadir | 0 | hangus karena alpha (E13) |
| Lembur | 582.658 | 750 menit dibayar, dasar 4.200.000 ÷ 173 |
| BPJS karyawan (Kes, JHT, JP) | −168.000 | 1% + 2% + 1% × 4.200.000; JP memakai batas sejak 1 Mar |
| PPh 21 | 0 | TER A, bruto 5.133.338 (di bawah 5.400.000 = 0%) |
| **Gaji bersih** | **4.774.658** | bruto pajak 5.133.338 = pendapatan + JKK 10.080 + JKM 12.600 + Kes perusahaan 168.000 |

**10004, Produksi, periode 21 Mar–20 Apr (Idul Fitri, operasi 7 hari), PTKP K/3**

Gaji pokok 3.650.000 + tunjangan tetap 500.000 + uang makan 345.000 + shift malam 70.000 + premi hadir 100.000 + lembur 1.211.416 (1.470 menit, termasuk shift di hari libur nasional dengan tarif hari libur) − BPJS 166.000 − PPh 0 (TER C, bruto 6.064.826 di bawah 6.600.000) = **5.710.416**.

**10881, Kantor, periode 21 Jan–20 Feb, PTKP K/2**

Gaji pokok 5.100.000 + tunjangan tetap 600.000 + uang makan 375.000 + lembur 49.422 − BPJS 228.000 − PPh 15.958 (TER B 0,25% × bruto 6.383.202, dibulatkan ke bawah) = **5.880.464**.

## Temuan

1. **Hitung gaji di Supabase 7,4–12,2 detik per periode**, di atas batas 8 detik jalur API (sama seperti baca tap, temuan Tahap 3). Di Tahap 5, hitung gaji juga harus lewat koneksi database langsung atau dipecah. Penyebab utama [Kemungkinan Besar]: pengaturan dibaca per orang per hari (sekitar 30 ribu panggilan per periode); belum dioptimalkan karena belum perlu.
2. **Peringatan "lewat batas 4 jam" muncul 1.859 kali**, kebanyakan dari shift 7 jam di hari libur nasional (operasi 7 hari). Ini akibat Penjelasan Pasal 116 UU 27/2026 yang memasukkan kerja di hari libur ke "waktu kerja lembur". Kalau dibiarkan, peringatan ini terlalu ramai untuk HRD. Perlu diputuskan sebelum Tahap 5: tetap seperti teks UU, atau dipisah menjadi "lembur hari libur" dan "lembur hari kerja" [Menebak: aturan pelaksana nanti mungkin mengatur pengecualian sektor 7 hari, Pasal 116 ayat 4].
3. **Izin tidak dibayar secara bawaan** (Pasal 149 ayat 1). Pengaturan baru `izin_dibayar` bisa diubah per perusahaan atau divisi. Data simulasi tidak membedakan izin karena alasan Pasal 149 ayat 2 (menikah, keluarga meninggal, dan lain-lain); perintah HRD belum punya isian alasan itu (Tahap 7).
4. **Pembulatan PPh 21 ke bawah** adalah tebakan; aturan resminya belum ditemukan. Bisa diganti lewat pengaturan `pembulatan_pph21`.
5. **Aturan "dasar lembur yang lebih besar" (permintaan perubahan 01) sama angkanya dengan aturan 75% lama.** Bedanya hanya tanda "perlu dikonfirmasi HRD" untuk lembur sejak 28 Okt 2026. Di data simulasi tidak ada karyawan yang terkena aturan 75%, jadi tanda ini hanya muncul di uji.
6. **Uji lama `cek_tahap3.sql` harus disesuaikan**: satu pemeriksaannya menganggap setiap versi hitung punya hasil harian; versi gaji tidak punya. Sekarang hanya versi baca tap yang diperiksa. Tidak ada hasil Tahap 3 yang berubah.
7. **Angka tetap baru di kode** (belum ada tabel aturannya): uang makan hilang bila telat lebih dari 60 menit; istirahat 60 menit untuk lembur hari libur tanpa jadwal bila hadir lebih dari 4 jam; batas 240 menit/hari dan 1.080 menit/minggu.
8. **Belum dihitung (paket 4b-2):** THR, kasbon, denda, batas potongan 50%, pembulatan tunai, saldo cuti (termasuk kasus C02b), PPh Desember. Periode 4 (bayar 25 Des) karena itu punya PPh 0 dengan tanda "PPh Desember belum dihitung", sehingga total periode 4 belum final.
