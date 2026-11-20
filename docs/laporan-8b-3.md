# Laporan paket 8b-3: urutan rilis, jalan keluar, dan kemudahan bot (terpasang; uji nyata berjalan)

20 November 2026 · rencana `docs/rencana-8b-3.md` · commit 687ce87

## Yang dibuat

- Migrasi `0028_rilis_mudah.sql`: urutan rilis (`fakta.periode_menunggu`), `/batal` (alur `disetujui → dihitung` oleh HRD ditambah), hapus PIN oleh pembangun (`fakta.hapus_pin`, hitungan PIN salah mulai lagi), undangan HRD/bos (`fakta.undangan_akun`, sidik saja, 60 menit, batas 5 salah per jam), menunggu PIN 5 menit (`fakta.tunggu_pin`), kabar rilis/batal, pengingat harian ke bos (`api.pintu_pengingat_rilis`, lewat penjadwal 08.00 WIB yang sudah ada), teks status (`fakta.status_rilis_teks`).
- Bot: perintah tanpa `/` dikenali; pesan 6 angka dihapus dan dipakai sebagai PIN bila ada yang menunggu; tombol Rilis dan tombol Setujui/Tolak pembangun meminta PIN; perintah tanpa PIN meminta PIN; `/batal`, `/hapuspin`, `/undang`, `/gabung`, `/bantuan`; menu perintah per peran (`sistem/pintu/pasang_menu.ts`, dipasang `db/pasang_pintu.sh` dan sesudah `/gabung`).
- Sheets tab Ringkasan: kolom "Status rilis"; halaman demo: baris "Status rilis"; pemeriksa Sheets dan demo membandingkannya dengan gudang.

## Uji yang diubah karena aturan berubah (dicatat jujur)

- `db/uji/180_rilis_gaji.sql`: daftar `/ajukan` awal kini hanya periode 1 (periode 3 menunggu periode 2); periode 2 dihitung ulang tanpa orang tertahan dan dirilis sebelum bagian "HRD lalu bos" (+1 uji).
- `sistem/pintu/uji_pintu.ts` (8b-2): pembangun kini mendapat tombol; `/setujui <nomor>` tanpa PIN kini meminta PIN (sebelumnya "Cara pakai"); teks cara pembangun berubah.

## Uji [Pasti]

- Lokal: database 603 lulus (sebelumnya 567), pintu 77 (sebelumnya 67), simulasi 128 (sebelumnya 127).
- Uji bisa gagal: aturan urutan dan hitungan PIN sesudah hapus dimatikan → 5 uji 200 GAGAL.
- GitHub run 44665815714 lulus: database 603, simulasi 128, pintu 77, penyambung 23.

## Pemasangan [Pasti]

- Pasang run 44667485854 lulus: hanya 0028; pemeriksaan 33 lulus 0 gagal; menu umum ok, menu akun pembangun ok (1).
- Supabase: sidik 0028 `c262e2375693` = repo; 7 fungsi baru boleh dipanggil `pintu`, tidak boleh `anon`. Status: periode 1 "Bisa diajukan", periode 2 "Dirilis", periode 3 dan 4 "Belum bisa diajukan: rilis dulu periode no. 1".
- Isi Sheets sesudahnya: kolom "Status rilis" sama dengan Supabase, status "diperiksa sama dengan gudang". Terbitkan demo: pemeriksa 0 beda (termasuk status rilis).

## Belum selesai

- Uji nyata oleh pemilik (menu, perintah tanpa `/`, tombol yang meminta PIN, `/hapuspin`, `/batal`).
- `/undang` dan `/gabung` butuh akun Telegram kedua (menunggu orang lain, aturan 10).
- [Kemungkinan Besar] kotak balasan PIN dan menu per akun tampil di Telegram Desktop; dibuktikan saat uji nyata.
- Halaman demo belum dilihat langsung dengan mata (hanya pemeriksa angka).
