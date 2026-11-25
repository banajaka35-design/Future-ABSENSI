# Laporan Tahap 9: web penuh, coba aturan, paket pasang

Ditutup 25 November 2026 atas persetujuan pemilik ("oke lanjut", 14.27 WIB), dengan satu gerbang yang berjalan di belakang.
Isi dan gerbang memakai usulan Claude yang disetujui 23 Nov 2026 (`docs/rencana-tahap-9.md`; PRD v2 tidak memuat isi Tahap 9).

## Paket

| Paket | Isi | Laporan | Uji nyata |
| --- | --- | --- | --- |
| 9a | Web HRD lihat saja: periode, gaji per orang, rincian, perlu dicek, keberatan | `docs/laporan-9a.md` | Lulus 23 Nov |
| 9c | Coba aturan tanpa menyimpan | `docs/laporan-9c.md` | Lulus 25 Nov |
| 9b-1 | Perintah lewat web: tambah libur, absen manual divisi, berhenti, aktif kembali, mutasi | `docs/laporan-9b-1.md` | Lulus 25 Nov |
| 9b-2 | Karyawan baru dan ubah gaji lewat web, dengan persetujuan PIN | `docs/laporan-9b-2.md` | Lulus 25 Nov |
| 9a-2 | Tampilan web HRD menyesuaikan laptop dan HP, kamus nama | `docs/laporan-9a-2.md` | Lulus 25 Nov |
| 9d | Kerangka pasang untuk PT baru (`docs/pasang/`) | `docs/laporan-9d.md` | Uji coba panduan oleh Claude |

## Gerbang

| No | Gerbang | Hasil |
| --- | --- | --- |
| 1 | HRD bisa menjalankan satu bulan penuh lewat web dan bot tanpa bantuan Claude atau pembangun | **Belum bisa diuji**: belum ada HRD sungguhan. Berjalan di belakang (aturan 10), dimulai saat PT pertama |
| 2 | Coba aturan menunjukkan selisih yang sama dengan hitungan sungguhan | **Lulus** [Pasti]: uji database 320 (paket 9c) |
| 3 | Pabrik B bisa dipasang dari nol hanya dengan kuesioner dan templat | **Lulus** [Pasti]: U5 Pabrik B lewat jalur PT, dan uji coba panduan menghasilkan 23 tabel sama persis (paket 9d) |

## Angka terakhir [Pasti, 25 Nov 2026]

- Uji: database 917, simulasi 153, pintu 123, semua 0 gagal (GitHub run 45566189081 untuk database dan simulasi).
- Supabase demo: migrasi terakhir 0042; sidik gaji periode 4 `c427e5a53c5f`; periode 1–2 dikunci, 3–4 dihitung.

## Yang dibawa ke tahap berikutnya

Temuan P1–P7 dari paket 9d (`docs/pasang/README.md` bagian "Belum ada"), harus selesai sebelum PT pertama. Yang terpenting:
**P1, tidak ada pembuatan periode bulanan otomatis**. Tanpa P1, sistem berhenti sesudah periode terakhir yang dimasukkan saat
pemasangan, termasuk di demo (periode 4 berakhir 20 Des 2026). Rencana P1: `docs/rencana-p1-periode.md`.
