# Permintaan perubahan 01: cuti bersama dan dasar lembur setelah UU 27/2026

Diajukan 16 November 2026 (paket 4a) · status: **usulan 1 dan 2 disetujui pemilik proyek 16 Nov 2026, 19.27 WIB** · kasus, kode, dan data dikerjakan di paket 4b (belum ada yang diubah).

Kasus jebakan dikunci (v1.1, 12 Nov 2026) dan hanya boleh diubah lewat permintaan perubahan. Dasar hukum dan labelnya ada di `docs/cek-aturan-hukum.md`.

## Latar belakang

UU 27/2026 berlaku sejak 28 Oktober 2026. Kasus jebakan dan data simulasi ditulis memakai aturan lama. Semua kejadian di data simulasi bertanggal 2026, dan sebagian periodenya jatuh **sesudah** 28 Oktober 2026: Pabrik A 21 Nov–20 Des 2026, Pabrik B Desember 2026.

Prinsip yang diusulkan: **aturan dipakai menurut tanggal kejadian.** Kejadian sebelum 28 Okt 2026 dihitung dengan aturan lama, kejadian sesudahnya dengan aturan baru. Ini sama dengan pola bertanggal yang sudah dipakai semua tabel aturan (kontrak data bagian 1 ayat 4).

## Usulan 1: cuti bersama tidak memotong cuti tahunan sejak 28 Okt 2026

Pasal 118 ayat 6 [Kemungkinan Besar]: cuti bersama yang ditetapkan Pemerintah Pusat tidak mengurangi hak cuti tahunan.

| Yang terdampak | Sekarang | Usulan |
| --- | --- | --- |
| Kasus C02 (16 Feb 2026, pilihan "dibayar" / "potong cuti") | Tetap | **Tidak diubah**: tanggalnya sebelum UU baru, jadi pilihan "potong cuti" masih sah untuk tanggal itu |
| Kasus baru C02b | — | Tidak ada tap 24 Des 2026 (cuti bersama Natal), pengaturan "potong cuti" yang berlaku sejak sebelum 28 Okt 2026 → libur dibayar, **saldo cuti tidak berkurang**, dan muncul peringatan "pengaturan potong cuti tidak berlaku lagi sejak 28 Okt 2026" |
| Pengaturan Pabrik B di `docs/data-simulasi.md` ("Memotong cuti") | Satu nilai untuk seluruh 2026 | Bertanggal: `potong_cuti` sampai 27 Okt 2026, `dibayar` sejak 28 Okt 2026 (diisi saat data struktur Pabrik B dibuat di 4b) |
| Daftar pilihan `cuti_bersama` (migrasi 0002) | `dibayar`, `potong_cuti` | Tetap. Mesin hitung menolak memakai `potong_cuti` untuk tanggal sejak 28 Okt 2026 (batas bawah hukum ada di kode hitung, bukan pilihan HRD) |
| Kunci jawaban generator | Tidak terdampak | Generator hanya mencatat kejadian (tidak ada tap di hari cuti bersama), tidak menghitung saldo cuti |

## Usulan 2: dasar upah lembur — pertanyaan terbuka, belum ada usulan perubahan

Kasus D11 memakai aturan lama: bila upah pokok + tunjangan tetap di bawah 75% dari seluruh upah (termasuk tunjangan tidak tetap), dasar lembur = 75% × seluruh upah.

UU 27/2026 Pasal 116 ayat 3 dan Pasal 125 ayat 5 [Kemungkinan Besar] menulis upah sejam = (upah pokok + tunjangan tetap) ÷ 173, tanpa menyebut aturan 75%. Pasal 310 [Kemungkinan Besar] membiarkan aturan pelaksana lama tetap berlaku selama tidak bertentangan.

Yang belum diketahui [Menebak]: apakah aturan 75% (di aturan pelaksana lama) dianggap bertentangan dengan Pasal 116 ayat 3, atau tetap berlaku sampai PP baru terbit (paling lambat 28 Okt 2027).

Usulan cara memutuskan:
1. Cek naskah resmi Pasal 116 ayat 3 dan Pasal 125 ayat 5 dari PDF JDIH.
2. Bila tetap tidak jelas, kasus D11 dibiarkan untuk tanggal sebelum 28 Okt 2026, dan **untuk tanggal sesudahnya sistem memakai yang lebih menguntungkan pekerja** (dasar terbesar dari kedua cara), ditandai sebagai hitungan yang perlu dikonfirmasi HRD. Ini tebakan cara aman, bukan tafsir hukum.
3. Tambah kasus D11b (tanggal sesudah 28 Okt 2026) setelah cara di atas diputuskan.

## Usulan 3: pengaturan "lembur otomatis" — dicatat, tidak diubah

Pasal 116 ayat 1 [Kemungkinan Besar]: lembur butuh perintah tertulis atau digital dan persetujuan pekerja. Pengaturan `lembur = otomatis` membayar lembur yang terjadi walau tanpa perintah. Membayar lembur yang benar-benar dikerjakan tetap wajib, jadi hitungannya tidak diubah. Yang perlu dipikirkan nanti (kuesioner pemasangan, Tahap 7): apakah sistem mencatat perintah dan persetujuan lembur sebagai bukti untuk perusahaan.

## Keputusan pemilik proyek (16 Nov 2026)

- **Usulan 1 disetujui:** kasus C02 tetap; tambah kasus C02b; pengaturan cuti bersama Pabrik B bertanggal (`potong_cuti` sampai 27 Okt 2026, `dibayar` sejak 28 Okt 2026).
- **Usulan 2 disetujui, cara sementara:** untuk tanggal sejak 28 Okt 2026 dasar lembur = yang terbesar dari (a) pokok + tunjangan tetap dan (b) 75% seluruh upah bila aturan lama berlaku; hasilnya ditandai "perlu dikonfirmasi HRD". Kasus D11 tetap untuk tanggal sebelumnya; kasus D11b ditulis di paket 4b. Dicek ulang setelah PDF resmi UU 27/2026 ada di Drive, dan lagi saat PP pelaksana terbit (paling lambat 28 Okt 2027).
- Usulan 3 tetap catatan untuk kuesioner pemasangan.
