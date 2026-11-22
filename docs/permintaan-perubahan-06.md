# Permintaan perubahan 06: jam datang awal yang disetujui menjadi lembur (PRD v2 B5)

Diajukan 22 November 2026 (paket 7c-2) · status: **disetujui pemilik 22 Nov 2026 ("buat" 19.07 untuk paket 7c-2 yang memuat aturan ini)**

## Latar belakang

PRD v2 B5: "jam sebelum jadwal masuk tidak dihitung kecuali disetujui". Sampai paket 7c-1, menit sebelum jadwal masuk tidak pernah menjadi lembur (kasus B05) dan tidak ada cara menyetujuinya [Pasti, kode 0014/0034]. Keputusan pemilik 22 Nov 2026: menit datang awal yang disetujui **digabung** dengan menit lewat jam pulang di hari yang sama (19.05), dan persetujuannya **terpisah** dari persetujuan lembur biasa (19.05).

## Usulan

Tambah kasus **B05b** (B05 tidak diubah: tanpa persetujuan, jam sebelum jadwal masuk tetap tidak menjadi lembur):

| No | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| B05b | Shift Pagi 07:00–15:00, hari kerja, tap 05:30 dan 15:45; HRD menyetujui datang awal orang itu di tanggal itu | 90 menit datang awal + 45 menit lewat jam pulang = 135 menit → dibayar 120 menit (aturan lembur biasa: minimal 60, kelipatan 30); tanda `lembur_datang_awal_disetujui` | Permintaan perubahan 06 |

## Dampak

Mesin hitung gaji versi kode 7 (aturan D1b di `docs/aturan-hitung-gaji.md`). Tanpa perintah `setujui_datang_awal`, semua angka sama persis dengan versi 6. Data simulasi tidak berisi persetujuan datang awal, jadi kunci jawaban U1 tidak berubah.
