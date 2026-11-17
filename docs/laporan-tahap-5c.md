# Laporan paket 5c: pemberitahuan segera dan pengingat kirim file

17 November 2026 · acuan: `docs/pemberitahuan-segera.md` (commit 6a50a0e, ditulis sebelum kode) · kode: commit 6d948b9

## Hasil singkat

| Kasus | Uji otomatis (GitHub) | Uji nyata (bot Abaensi, Supabase) |
| --- | --- | --- |
| N1 ketujuh jenis kejadian segera diambil sekali dan masuk pesan | **Lulus** (db/uji/120, uji_pintu.ts) | — |
| N2 hitung ulang tidak mengirim ulang | **Lulus** | — |
| N3 hanya hrd dan pembangun aktif ber-ID Telegram yang menerima | **Lulus** | — |
| N4 file rusak Excel → balasan ke pengirim + pemberitahuan segera dalam proses yang sama | **Lulus** | **Lulus**: kiriman no. 19 ditolak, 0 tap; catatan `kiriman\|19` `terkirim`, hasil kirim "ok"; dicatat 0,5 detik sesudah kiriman, terkirim 0,4 detik kemudian |
| N5 format tidak dikenal → pemberitahuan segera | **Lulus** | — |
| N6 file sah dengan anomali segera → pemberitahuan dalam proses yang sama | **Lulus** (120 kejadian dari satu file, ke 2 akun) | Tidak diuji (butuh file baru atau reset demo) |
| N7–N9 anomali selesai, tingkat harian, file dobel tidak dikirim | **Lulus** | — |
| P1, P2 pengingat hari ke-1 hanya untuk mesin yang belum mengirim; sekali saja | **Lulus** | — |
| P3 hari ke-2: HRD diingatkan, bos dicatat dilewati | **Lulus** | **Lulus**: tanggal pura-pura 22-12-2026, pesan MA2 terkirim ke akun pemilik; bos `dilewati_tanpa_akun_bos` |
| P4 hari ke-2 dengan akun bos, P5 hari biasa/hari ke-3, P6 tutup buku akhir bulan | **Lulus** | — |
| P7 kode rahasia pengingat salah → 401 | **Lulus** | — |
| S1 penyambung dengan postgres.js sungguhan | **Lulus** (5 uji) | — |

U14 [Pasti, sejauh yang diuji]: setiap kejadian segera yang ada tercatat `terkirim` sesudah proses file yang memunculkannya (diperiksa di uji dengan `fakta.kejadian_segera()`), dan di Supabase untuk file rusak Excel. Gerbang Tahap 5 "pengingat file terkirim": terpenuhi lewat pemicu manual.

## Yang dipasang

| Bagian | Isi |
| --- | --- |
| Migrasi 0018 | `fakta.pemberitahuan` (kunci tetap per kejadian), `fakta.kejadian_segera()`, `fakta.tutup_buku_sebelum()`, 3 fungsi `api` untuk peran `pintu`; 18 kejadian lama dicatat `lama_tidak_dikirim` |
| Edge Function | `sambung.ts` (penyambung, baru diuji otomatis) + `inti.ts` (pemberitahuan dan pengingat); `index.ts` tinggal pembuka |
| Penjadwal | pg_net 0.20.4, pg_cron 1.6.4, jadwal `pengingat-kirim-file` `0 1 * * *`; zona pg_cron GMT, jadi 08.00 WIB [Pasti, dari log pemasangan]; kode rahasia di Vault, baru setiap pemasangan; fungsi `jadwal.picu_pengingat` di skema `jadwal` (di luar cadangan dan reset) |
| Workflow | "Picu pengingat" (tanggal pura-pura) |
| Pengaman | `db/pasang_supabase.sh` mencatat kejadian dari hitungan pemasangan sebagai lama |

## Kejadian di uji nyata

1. **Pemicu pengingat pertama gagal** [Pasti, dari log Edge Function]: "password authentication failed for user pintu", sekitar 1 menit sesudah pemasangan mengganti kata sandi. Diulang sekitar 2 menit kemudian dan berhasil tanpa perubahan apa pun. Penyebab [Kemungkinan Besar]: pooler Supabase belum memakai kata sandi baru. Akibatnya: setiap selesai "Pasang ke Supabase", bot bisa gagal sebentar. **Ralat (paket 5d-2):** bukan soal "1–2 menit"; yang terjadi adalah percobaan masuk pertama sesudah pemasangan selalu gagal, berapa pun jedanya (terulang di 5d, 5 menit sesudah pemasangan). Lihat `docs/laporan-tahap-5d.md` temuan 1. Tidak ada data yang tercatat saat gagal; tetapi pesan Telegram yang masuk pada jeda itu tidak dibalas.
2. **Pemicu kedua (22-10-2026) tidak mengirim apa pun**, dan itu benar: data demo berisi file sampai Desember 2026, jadi semua mesin dianggap sudah mengirim.
3. **Pemicu ketiga (22-12-2026)** mengirim pengingat MA2. Akibatnya pengingat sungguhan hari ke-2 tanggal 22-12-2026 untuk MA2 tidak dikirim lagi (sudah tercatat). Hari ke-1 (21-12-2026) tidak terpengaruh.

## Batasan

- Kejadian dicatat sebelum dikirim. Bila Telegram gagal, kejadian tidak dikirim ulang otomatis; kegagalan terlihat di `status` dan `hasil_kirim`.
- Satu file dari satu mesin bisa menghasilkan banyak kejadian "hari tanpa tap massal" (120 kejadian di uji T1). Dikelompokkan per jenis dan dipecah per 3.800 karakter, tetapi isinya tetap panjang.
- Antrean yang melewati sekitar 110 detik ditunda ke pesan berikutnya, begitu juga pemberitahuannya. Belum terjadi di uji; belum diukur dengan data besar.
- "Belum mengirim" berarti belum ada file dengan tap terakhir pada atau sesudah tanggal tutup buku; file yang terlambat beberapa hari tetap dihitung sudah mengirim.
- Akun bos belum ada; pengingat ke bos baru diuji otomatis (P4).
