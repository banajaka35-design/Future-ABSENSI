# Rencana Tahap 9: web penuh, coba aturan, paket pasang

Ditulis 23 November 2026. Isi dan gerbang Tahap 9 dari PRD v2 bagian 13 **tidak ada di repo**. Rencana ini adalah **usulan Claude** berdasarkan isi repo, disetujui pemilik pada 23 Nov 2026 15.52 WIB ("oke buat", sesudah usulan di chat). Setiap paket tetap punya daftar lengkap dan "buat" sendiri (aturan 7).

## Dasar dari repo [Pasti]

- Tabel tahap di `docs/serah-terima.md`: Tahap 9 = "Web penuh, coba aturan, paket pasang"; hasil yang bisa dilihat = "Web siap didemokan". Syarat yang berjalan di belakang: U11 waktu operator, dan wawancara 2–3 HRD (hanya untuk angka penghematan).
- `docs/laporan-tahap-7.md`: perintah berikut [Kemungkinan Besar] cocok untuk web Tahap 9: perintah divisi, absen manual divisi, tambah libur, tukar shift, karyawan baru, berhenti, mutasi, dan ubah gaji.
- `docs/serah-terima.md`, tabel "Sebelum dipasang": data asli masuk lewat templat unggah (paket pasang); kuesioner pemasangan berisi 8 pertanyaan (dicatat 16 Nov).
- `docs/laporan-tahap-3.md` butir 8: angka tetap di kode bisa dipindah ke tabel aturan (kuesioner Tahap 9).

## Paket (urutan disetujui)

| Paket | Isi | Status |
| --- | --- | --- |
| 9a | Web HRD lihat saja: masuk dengan kode email, ringkasan periode, daftar gaji per periode, rincian per orang (komponen gaji dan status harian), daftar perlu dicek, dan keberatan | selesai 23 Nov, `docs/laporan-9a.md` |
| 9c | Coba aturan: mengubah aturan secara percobaan, lalu melihat selisih gaji per orang tanpa menyimpan | selesai 25 Nov, `docs/laporan-9c.md` |
| 9b | Perintah lewat web. 9b-1: tambah libur, absen manual divisi, berhenti, aktif kembali, mutasi. 9b-2: karyawan baru, ubah gaji (dengan persetujuan PIN) | selesai 25 Nov, `docs/laporan-9b-1.md`, `docs/laporan-9b-2.md` |
| 9a-2 | Perbaikan tampilan web HRD (T1–T8): kartu di HP, tabel Periode dipecah, urutan komponen, pilihan periode bawaan, kamus nama | selesai 25 Nov (uji nyata lulus 13.13), `docs/laporan-9a-2.md` |
| 9d | Kerangka pasang untuk PT baru: daftar pertanyaan HRD, daftar periksa akun, templat karyawan, cara uji banding, petunjuk HRD, perawatan tahunan, dan cara pasang yang bisa memilih perusahaan (bawaan tetap Pabrik A) | selesai 25 Nov, `docs/laporan-9d.md`; gerbang 3 lulus |

## Gerbang (usulan Claude, disetujui 23 Nov)

1. HRD bisa menjalankan satu bulan penuh lewat web dan bot tanpa bantuan Claude atau pembangun.
2. Coba aturan menunjukkan selisih yang sama dengan hitungan sungguhan bila aturan itu benar-benar dipakai.
3. Perusahaan contoh baru (Pabrik B) bisa dipasang dari nol hanya dengan kuesioner dan templat.

Berjalan di belakang (aturan 10): U11 waktu operator; wawancara 2–3 HRD.
