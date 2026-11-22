# Laporan paket 7c-2: jam datang awal yang disetujui (PRD v2 B5)

22 November 2026 · rencana `docs/rencana-tahap-7.md` bagian 10–11 (keputusan pemilik: digabung, terpisah; "buat" 19.07 bersama pemeriksaan celah) · permintaan perubahan 06 (kasus B05b) · migrasi 0036 · commit 053f13b

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Aturan | D1b di `docs/aturan-hitung-gaji.md`; kasus B05b di `docs/kasus-jebakan.md` (versi 1.4); `docs/permintaan-perubahan-06.md` |
| Migrasi 0036 | Jenis perintah `setujui_datang_awal`; `hitung.menit_datang_awal` (satu sumber untuk mesin hitung dan bot; hanya data tap lengkap dan tidak meragukan); `hitung.hitung_gaji` versi kode 7 = versi 6 + D1b; fungsi bot lembur menerima jenis baru, `fakta.hari_lembur` menyebut menit datang awal (orang) dan orang/menit datang awal (divisi). Pembaca tap tidak diubah |
| Bot | `/setujuiawal <ID atau kode divisi> <tanggal> [tanggal selesai]`; konfirmasi per hari + jumlah seluruh rentang untuk divisi; "Hasil" lembur sebelum → sesudah; `/batalperintah` |
| Perbaikan celah (diminta pemilik) | 8 butir di rencana bagian 11: data tap meragukan tidak dihitung, jumlah rentang di konfirmasi divisi, tanda `lembur_datang_awal_disetujui`, bukti tanpa perubahan angka, wajib perintah, shift malam, persetujuan ganda, uji pengingat tidak terganggu |

## Uji (diukur)

| Uji | Hasil |
| --- | --- |
| Lokal Postgres 16 | Database 748 lulus (15 uji baru di `db/uji/280_datang_awal.sql`: B05, B05b 135 → 120, divisi, lupa tap, shift malam 22:20–07:30 → 60, wajib perintah pagi saja → 60 lalu + sore → 150, ganda dihitung sekali, pembatalan); simulasi 129 lulus (U1 lulus); pintu 116 lulus; MA1 tetap "belum mengirim" sesudah uji pintu |
| Bukti uji gagal dengan kode lama | Tanpa 0036: "versi kode gaji terbaru" GAGAL dan `hitung.menit_datang_awal(...) does not exist`, keluar kode 3 |
| GitHub "Uji database" run 45022984479 | Lulus: database 748, simulasi 129 (U1 lulus 3 kali), pintu 116, penyambung 23 |
| GitHub "Pasang ke Supabase" run 45024488103 | Lulus: hanya 0036, pemeriksaan 33 lulus, Edge Function terpasang ulang |
| **Bukti angka tidak berubah tanpa persetujuan** (Supabase) | Sesudah dipasang, periode 3 dan 4 dihitung ulang dengan versi 7: sidik hasil periode 3 versi 45 (v7) = versi 35 (v6) = versi 32 (v5) = `45a6ca644ca5`; periode 4 versi 46 (v7) = versi 44 (v6) = `c427e5a53c5f` [Pasti] |
| Dicek di Supabase | 0036 sidik `80c7c7342d68` = repo; versi kode `hitung_gaji 7 (paket 7c-2)`; 10060 21 Nov 2026: hadir, datang awal 29 menit, lewat jam pulang 94 menit; lembur periode 4 690 menit Rp445.088; dibayar Rp4.472.088 |

## Uji nyata

Belum. Langkah: `/setujuiawal 10060 21-11-2026` → Ya (lembur 690 → 720 menit); `/batalperintah <nomor>` → kembali; uji tolak `/setujuiawal 10060 25-02-2026`.
