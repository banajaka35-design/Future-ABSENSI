# Rencana paket 8b: rilis gaji dengan PIN

19 November 2026 · di-"buat" pemilik 19 Nov 2026 15.52 WIB · `docs/rencana-tahap-8.md` · PRD v2 celah K5; kontrak data bagian 6

**Catatan jujur:** file ini seharusnya ditulis sebelum kode (kebiasaan repo). Isinya sama dengan daftar yang di-"buat" pemilik di chat, tetapi file ini baru ditulis sesudah kode selesai. Dicatat juga di `docs/laporan-8b.md`.

## Temuan sebelum paket [Pasti]

- Semua periode berstatus `terbuka`: langkah sistem yang memindahkan periode ke `dihitung` belum pernah dibuat.
- File baru yang menyentuh periode selalu memicu hitung ulang, termasuk periode yang nanti dirilis.
- Semua periode demo "belum bisa diajukan" karena PPh masa terakhir tertahan (data pajak Januari 2026 tidak ada).

## Alur (chat pribadi; HRD atau pembangun)

1. `/pin <6 angka>` (ganti: `/pin <lama> <baru>`). Pesan berisi PIN dihapus bot. bcrypt di `induk.pengguna.pin_tersamar`. PIN tidak boleh angka sama semua atau berurutan. 5 PIN salah per jam → terkunci 1 jam.
2. `/ajukan` → ringkasan per periode yang bisa diajukan (periode, tanggal bayar, orang, gaji bersih tanpa orang rahasia, transfer, tunai) + tombol Ajukan/Batal. Versi gaji yang diajukan dicatat.
3. Pengaturan `persetujuan_rilis = hrd_lalu_bos`: ringkasan ke akun bos dengan tombol Setujui/Tolak. Tolak → `dihitung`.
4. `/rilis` → daftar; `/rilis <nomor> <PIN>` → `dirilis` (konfirmasi kedua, K5). Pesan gaji ke karyawan = paket 8c.

## Pengaman

- Hanya periode tanpa orang tertahan yang bisa diajukan. Rilis ditolak bila versi gaji berlaku berbeda dengan yang diajukan (termasuk baca tap baru tanpa hitung gaji).
- Periode `dirilis`/`dikunci` tidak pernah mendapat versi hitung baru (pemicu di database); file baru tetap disimpan, antrean melewatinya, HRD menerima pemberitahuan segera.
- Periode `diajukan`/`disetujui` yang dihitung ulang kembali ke `dihitung` (pengajuan batal).
- Sesudah hitung gaji, sistem memindahkan `terbuka`/`menunggu_data` ke `dihitung`.
- Akun karyawan tidak bisa memakai perintah ini; grup ditolak (G1-3). Akun pembangun tidak bisa menyetujui sebagai bos.

## Juga dalam paket

- Daftar sebelum tanggal mulai: boleh (`fakta.boleh_daftar`); berhenti sebelum hari ini tetap ditolak.
- Isian pajak awal tahun 2026 **karangan** (`db/data_awal/pajak_awal_tahun_simulasi.sql`, bukan dari generator) untuk 38 karyawan yang tertahan di periode 1–3; dimuat saat Pasang, periode tahun itu dihitung ulang. Periode Desember tetap tertahan.

## Isi paket

Migrasi 0026; data awal di atas dan langkahnya di `db/pasang_supabase.sh`; bot; uji `db/uji/180_rilis_gaji.sql`, `uji_pintu.ts`, uji simulasi; Pasang; uji nyata; `docs/laporan-8b.md`, serah-terima.

## Belum pasti saat daftar ditulis

- [Kemungkinan Besar] Isian Januari cukup membebaskan periode 1–3 → **terbukti** di salinan lokal sebelum kode.
- [Kemungkinan Besar] Bot boleh menghapus pesan masuk di chat pribadi.
- [Salah di daftar] Daftar menulis pengaturan demo "HRD saja"; ternyata **"HRD lalu bos"** (data awal Pabrik A). Uji nyata sampai "dirilis" butuh akun bos atau perubahan pengaturan; keputusan pemilik diminta 19 Nov 2026.
