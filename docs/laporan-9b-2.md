# Laporan paket 9b-2: karyawan baru dan ubah gaji lewat web (dengan persetujuan)

Rencana: `docs/rencana-9b-2.md`. Di-"buat" pemilik 25 Nov 2026 10.46 WIB dengan K1–K4 sesuai saran Claude.

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Migrasi `0042_ajukan_uang.sql` | `fakta.pengajuan_uang` dan `fakta.keputusan_uang` (hanya bertambah, satu keputusan per pengajuan); pemeriksaan `fakta.web_uang_periksa` (dipakai pratinjau, ajukan, dan sekali lagi saat disetujui); `fakta.web_uang_ajukan`, `fakta.web_uang_terapkan`; bot `api.pintu_uang_minta_pin`, `api.pintu_uang_putuskan`, `api.pintu_uang_daftar`; `fakta.tunggu_pin` bisa menunggu PIN untuk pengajuan; `api.web_hrd` ditambah pengajuan dan penarikan; `fakta.rp` (rupiah bertitik) |
| Edge Function | Pesan pengajuan ke semua akun bos dan pembangun aktif dengan tombol **Setujui (PIN)** / **Tolak (PIN)**; PIN → keputusan → hitung ulang → kabar ke pengaju; perintah `/pengajuan` (menu bos dan pembangun) |
| Halaman web HRD | Jenis "Karyawan baru" dan "Ubah gaji" di tab Perintah; tabel "Pengajuan karyawan baru dan ubah gaji" dengan keadaan dan tombol Tarik; pilihan "Gaji rahasia" hanya tampil untuk akun pembangun |
| Uji | Database `db/uji/340_ajukan_uang.sql` (33); pintu `9b-2` (alur bot lengkap dengan data Pabrik A); simulasi: halaman tanpa isian rekening |

## Keputusan yang diterapkan

- K1: simpan di web hanya membuat pengajuan; data induk berubah sesudah bos/pembangun menyetujui dengan PIN.
- K2: pembangun boleh menyetujui pengajuannya sendiri; tercatat `sendiri = true` di `fakta.keputusan_uang` dan tampil "(sendiri)" di web.
- K3: gaji pokok + tunjangan di bawah UMK ditolak untuk karyawan baru dan untuk ubah gaji pada 12 bulan pertama; sesudahnya peringatan.
- K4: HRD ditolak untuk orang rahasia (ubah gaji, pasang/cabut tanda rahasia, membatalkan perintah gaji rahasia); daftar untuk HRD tanpa angka orang rahasia.

## Hasil uji lokal [Pasti, 25 Nov]

Database **917 lulus** (+33), pintu **123 lulus** (+1), simulasi **133 lulus**; 0 gagal. Halaman dicoba di Chrome dengan jawaban tiruan: isian berganti sesuai jenis, kotak kosong tidak dikirim, tidak ada galat skrip.

## Penyimpangan kecil dari rencana

- "Tolak meminta alasan singkat" (rencana bagian 2) belum dibuat: tolak cukup dengan PIN, pengaju menerima kabar "ditolak oleh bos/pembangun". [Pasti] Alasan bisa ditambah di paket tampilan berikutnya bila perlu.
- Pembatalan ubah gaji sesudah disetujui tidak meminta persetujuan lagi: pembatalan hanya mengembalikan gaji ke nilai yang sebelumnya sudah berlaku (tidak ada angka baru). [Kemungkinan Besar] aman; dicatat supaya bisa diubah bila pemilik ingin.

## Yang belum

- Pemasangan, terbit, dan uji nyata.
