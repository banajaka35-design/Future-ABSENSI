# Rencana paket 8c-2: sisa pembulatan lalu di pesan gaji

20 November 2026 · di-"buat" pemilik 20 Nov 2026 14.59 WIB · temuan uji nyata `/contohgaji` 8c

## Temuan [Pasti]

Sheets punya kolom "Sisa pembulatan lalu"; pesan gaji tidak. Di periode yang dirilis 132 baris punya sisa lalu bukan nol; untuk mereka angka pesan tidak bisa dicocokkan. Rumus bersih + sisa lalu = dibayar + sisa baru berlaku untuk semua 2.021 baris yang dirilis (dicek di Supabase).

## Isi paket

1. Migrasi `0030_sisa_lalu_pesan_gaji.sql`: `fakta.isi_gaji` ditambah `sisa_lalu`.
2. Bot: baris "Sisa pembulatan periode lalu (ditambahkan)" bila bukan nol, sebelum "Dibayar".
3. Uji `db/uji/220_sisa_lalu.sql` dan 1 uji bot; bukti uji bisa gagal.
4. Pasang; uji nyata `/contohgaji 10735 2` (punya sisa lalu, bukan rahasia).
