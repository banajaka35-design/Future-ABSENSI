# Laporan penutup Tahap 7: perintah HRD lewat chat

23 November 2026 · acuan PRD v2 bagian 13: Tahap 7 = "perintah harian HRD: izin, sakit, kasbon, dan persetujuannya"; **gerbang = izin susulan mengubah hasil setelah hitung ulang** · rencana `docs/rencana-tahap-7.md`

## Gerbang

**LULUS 22 November 2026 10.40 WIB** [Pasti]: perintah no. 1604 (`/izin 10067 30-03-2026`, asal chat, akun pembangun) mengubah Vina Pohan 30 Mar 2026 dari `alpha` menjadi `izin` sesudah periode 3 dan 4 dihitung ulang; dicek di `hitung.hasil_harian` dan Sheets (`docs/laporan-7a.md`).

## Yang dibangun (semua terpasang di Supabase dan lulus uji nyata)

| Paket | Isi | Migrasi | Mesin hitung gaji | Laporan |
| --- | --- | --- | --- | --- |
| 7a | `/izin`, `/sakit`, `/cuti` (termasuk susulan), tombol "Perintah HRD", konfirmasi Ya/Batal, hitung ulang lewat antrean, kabar sebelum → sesudah | 0032 | tidak diubah | `docs/laporan-7a.md` |
| 7d | `/batalperintah`, `/perintahku`; konfirmasi menyebut semua periode yang dihitung ulang | 0033 | tidak diubah | `docs/laporan-7d.md` |
| 7b | `/kasbon` (pinjam + cicilan wajib, lihat saldo), `/cicilan`, `/lunas`; pencatat terlacak (PRD C10) | 0034 | v6: kasbon yang perintahnya dibatalkan tidak dihitung | `docs/laporan-7b.md` |
| 7c-1 | `/setujuilembur`, `/batalkanlembur` per orang atau divisi (PRD B4; kasus D04, D05, F12) | 0035 | tidak diubah | `docs/laporan-7c.md` |
| 7c-2 | `/setujuiawal`: jam datang awal yang disetujui digabung dengan lembur sore (PRD B5; permintaan perubahan 06, kasus B05b) | 0036 | v7: aturan D1b | `docs/laporan-7c2.md` |

Semua perintah: hanya akun HRD dan pembangun; tombol Ya berlaku sekali dan 15 menit; periode dirilis/dikunci ditolak; angka orang rahasia tidak ditampilkan; bisa dibatalkan dengan `/batalperintah`.

## Bukti (diukur)

| Hal | Hasil | Label |
| --- | --- | --- |
| Uji otomatis terakhir (GitHub run 45022984479) | Database 748, simulasi 129 (U1 kunci jawaban lulus 3 kali), pintu 116, penyambung 23; semua lulus | [Pasti] |
| Lama dari tombol Ya sampai gaji dihitung ulang (Supabase, 9 perintah nyata) | 21–51 detik (satu periode sekitar 21–26 detik, dua periode 45–51 detik); Sheets selesai sekitar 2 menit sesudah Ya | [Pasti] |
| Mesin hitung v6 dan v7 tidak mengubah angka tanpa perintah baru | Sidik hasil gaji periode 3 versi 5, 6, 7 = `45a6ca644ca5`; periode 4 versi 6 dan 7 = `c427e5a53c5f` | [Pasti] |
| Setiap uji nyata dibandingkan dengan semua orang | Hanya orang yang disasar yang angkanya berubah (izin +Rp84.539; kasbon −Rp250.000; batalkan lembur −Rp80.925; datang awal +Rp22.254), lalu kembali sama persis sesudah dibatalkan | [Pasti] |
| Uji tolak | Periode dikunci (`/izin`, `/setujuiawal`), pelunasan melebihi saldo, divisi tidak ada, pembatalan kedua: semua ditolak, tidak ada yang dicatat | [Pasti] |
| Keadaan demo 23 Nov 2026 13.26 WIB | Semua perintah uji sudah dibatalkan; perintah chat no. 1604–1611 tetap tercatat (fakta hanya bertambah); sidik hasil periode 3 dan 4 sama dengan sebelum Tahap 7 | [Pasti] |

## Temuan selama Tahap 7

| Temuan | Status |
| --- | --- |
| Konfirmasi 7a tidak menyebut periode sesudahnya yang ikut dihitung ulang | Diperbaiki di 7d, terbukti di uji nyata |
| Kabar Sheets menulis "sejak file masuk" untuk perintah chat | Diperbaiki di 7b, terbukti ("sejak perintah dicatat") |
| `/batal` sudah dipakai untuk pengajuan rilis | Perintah pembatalan diberi nama `/batalperintah` |
| Uji bot 7c-1 mengganggu uji pengingat (satu run CI gagal) | Diperbaiki sebelum dipasang; tap uji kini lewat mesin yang sudah mengirim |
| 8 celah rencana 7c-2 (data tap meragukan, persetujuan divisi rentang panjang, jejak, dan lainnya) | Diperbaiki di dalam paket (`docs/rencana-tahap-7.md` bagian 11) |

## Tidak ikut Tahap 7 (tetap terbuka)

- Izin yang dibayar (Pasal 149 ayat 2): ditunda, akan mengubah angka gaji.
- Perintah divisi untuk izin/sakit/cuti, absen manual divisi, tambah libur, tukar shift lewat chat, karyawan baru, berhenti, mutasi, ubah gaji: [Kemungkinan Besar] cocok untuk web Tahap 9.
- Penuntun tombol langkah demi langkah dan perintah kalimat bebas (AI).
- Datang awal di hari libur nasional berjadwal (D3).
