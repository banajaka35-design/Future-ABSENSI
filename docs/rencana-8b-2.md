# Rencana paket 8b-2: pembangun menyetujui atau menolak rilis dengan PIN

20 November 2026 · daftar ditulis di chat dan di-"buat" pemilik 20 Nov 2026 08.56 WIB (jawaban "iya" atas pertanyaan "lanjut = buat?") · dasar: keputusan pemilik 19 Nov 2026 16.43 WIB "akun pembangun bisa melakukan semua yang bisa dilakukan akun lain" · `docs/laporan-8b.md`

## Keadaan sebelum paket [Pasti, dicek di Supabase 20 Nov 2026]

- Satu-satunya akun bukan karyawan: pembangun (aktif, Telegram tersambung, PIN belum ada).
- Pengaturan `persetujuan_rilis` = `hrd_lalu_bos`; keempat periode `dihitung`; pengajuan, persetujuan, rilis = 0.
- `api.pintu_setujui` hanya menerima peran `bos`; pesan pengajuan hanya dikirim ke akun bos.

## Keputusan pemilik (20 Nov 2026)

- A: menolak juga lewat `/tolak <nomor> <PIN>`.
- B: pesan pengajuan untuk pembangun berupa teks perintah, tanpa tombol (tombol tidak bisa membawa PIN).

## Isi paket

1. Migrasi `0027_setujui_pembangun.sql`:
   - `api.pintu_setujui` menerima bos atau pembangun. Pembangun wajib PIN (PIN yang sama dengan `/rilis`, batas 5 salah per jam dipakai bersama); tanpa nomor pengajuan dipakai pengajuan terakhir periode itu. Bos tetap lewat tombol tanpa PIN; bos lewat perintah dibalas "pakai tombol".
   - Tercatat: `fakta.persetujuan.catatan = 'oleh pembangun'`; riwayat status oleh `pengguna <id>` dengan alasan "disetujui pembangun"/"ditolak pembangun". Peran di tabel alur tetap `bos` (susunan tabel tidak diubah).
   - `api.pintu_ajukan` ikut mengembalikan daftar akun pembangun; `api.pintu_daftar_periode` menandai apakah akun ini pembangun.
2. Bot: `/setujui <nomor> <PIN>` dan `/tolak <nomor> <PIN>` (pesan berisi PIN dihapus); pembangun menerima teks pengajuan berisi cara menyetujui (pengaju yang juga pembangun cukup satu pesan); pesan ke pengaju menyebut "Pembangun menyetujui/menolak"; `/rilis` menampilkan cara `/setujui` untuk pembangun.
3. Uji: `db/uji/190_setujui_pembangun.sql` (16) dan 5 uji di `sistem/pintu/uji_pintu.ts`; bukti uji bisa gagal.
4. Pasang lewat cabang `pasang` sesudah uji GitHub lulus.
5. Uji nyata oleh pemilik: `/pin` → `/ajukan` periode 2 (21 Feb–20 Mar 2026) → `/setujui 2 <PIN>` → `/rilis 2 <PIN>`; dicek langsung di Supabase dan Sheets. Periode itu lalu terkunci permanen (hanya Reset yang membuka).
6. Laporan `docs/laporan-8b-2.md` dan `docs/serah-terima.md` diperbarui.

## Belum pasti

- [Menebak] Isi Sheets dan halaman demo tidak berubah karena status `dirilis`; dicek sesudah uji nyata.
- Aturan "dua orang" (HRD mengajukan, bos menyetujui) tidak berlaku bila pembangun mengajukan dan menyetujui sendiri; sudah dicatat di tabel "Sebelum dipasang" (`docs/serah-terima.md`).
