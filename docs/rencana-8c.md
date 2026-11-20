# Rencana paket 8c: pesan rincian gaji ke tiap karyawan

20 November 2026 · daftar ditulis di chat 13.59 WIB, di-"buat" pemilik 14.00 WIB (dua pertanyaan tidak dijawab → saran Claude dipakai, seperti keputusan pemilik sebelumnya "sesuai saran kamu") · acuan `docs/rencana-tahap-8.md` baris 8c, `docs/kontrak-data.md` (dirilis → dikunci "pesan gaji terkirim"), kasus E09

## Keputusan (saran Claude, 20 Nov 2026)

1. Bagian BPJS yang dibayar perusahaan ditampilkan sebagai informasi terpisah "tidak memotong gaji".
2. Periode menjadi `dikunci` bila tidak ada lagi yang menunggu; yang belum punya akun atau gagal 3 kali dianggap selesai (bisa minta sendiri).

## Isi paket

1. Migrasi `0029_pesan_gaji.sql`: `fakta.kirim_gaji` (diisi pemicu saat rilis; periode 1 dan 2 yang sudah dirilis diisi saat pasang), `fakta.isi_gaji`, `api.pintu_kirim_gaji_ambil` / `_hasil` (3 percobaan; kiriman terputus > 10 menit diulang), `fakta.kunci_bila_selesai` + ringkasan, `api.pintu_gaji_saya` (5 kali per jam), `api.pintu_contoh_gaji` (pembangun siapa saja; HRD bukan orang rahasia menurut F15c), `fakta.ada_kirim_gaji`, teks status "Dirilis, pesan gaji sedang/selesai dikirim".
2. `db/pasang_pintu.sh`: penjadwal `kirim-pesan-gaji` tiap menit; Edge Function hanya dipanggil bila ada pekerjaan.
3. Bot: `susunPesanGaji` (dipecah di antara baris), rute penjadwal `{"tugas": "kirim_gaji"}` (≤ 20 detik per panggilan, jeda 50 ms per pesan), tombol karyawan `Gaji saya` · `Bantuan`, `/gaji [nomor]`, `/contohgaji <ID> <nomor>`, rincian terakhir langsung sesudah daftar, ringkasan ke HRD/pembangun, `menu` → `/bantuan`.
4. Uji, Pasang, uji nyata dengan `/contohgaji`.

## Belum pasti

- [Menebak] Kecepatan kirim (sekitar 20 pesan per detik); diukur saat ada antrean nyata.
- Gerbang Tahap 8 "pesan sampai ke akun uji" butuh akun Telegram kedua sebagai karyawan (berjalan di belakang, aturan 10).
- Saat pasang, periode 1 dan 2 langsung `dikunci` tanpa ringkasan bot (semua belum punya akun; kunci dilakukan migrasi).
