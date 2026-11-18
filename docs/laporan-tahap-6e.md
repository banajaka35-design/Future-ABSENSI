# Laporan paket 6e: Sheets terisi otomatis sesudah file masuk

18 November 2026 · "buat" pemilik 18 Nov 2026 · rancangan dan analisa celah: `docs/rencana-sheets-otomatis.md` · dokumen sebelum kode: commit 7d3d8c3 · kode: commit e23dedf, nama secret: ec135d6

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Edge Function (`sistem/pintu/inti.ts`, `sambung.ts`) | Sesudah antrean, bila ≥ 1 periode berhasil dihitung: GitHub `workflow_dispatch` ke `isi-sheets.yml` (coba ulang sekali untuk 5xx/jaringan), pesan ke pengirim, catatan `api.pintu_catat_picu`; gagal atau belum disiapkan → kejadian segera `sheets_tidak_terpicu` ke HRD dan pembangun |
| Migrasi 0022 | Tabel `fakta.picu_sheets`, `api.pintu_catat_picu`, `fakta.kejadian_segera` diperluas |
| Workflow Isi Sheets | Masukan `pemicu`, `waktu_file`; kabar Telegram akhir (`web/kabar_telegram.py`) ke akun aktif hrd/pembangun bila dipicu file; Riwayat isi + kolom "Waktu file masuk" |
| Celah C1 | Tombol Reset dihapus; `db/periksa_pemicu.sh` menolak Reset yang dijalankan ulang dari riwayat (ditemukan saat membangun) |
| Token | Fine-grained, hanya repo ini, Actions: Read and write (+ Metadata: Read-only, wajib dari GitHub); secret GitHub `GTHUB_PICU_TOKEN` (GitHub melarang awalan `GITHUB_`), rahasia Edge Function `PICU_SHEETS_TOKEN`; **habis 16 Februari 2027** |

## Uji otomatis (GitHub, commit e23dedf dan ec135d6)

Pembaca file 16, database 453, simulasi 92 (termasuk 47 uji Sheets: kabar Telegram ke hrd/pembangun aktif saja, token tidak tercetak, kabar GAGAL), pintu 38 (T1 memicu sekali, ditolak/dobel tidak memicu, GitHub menolak → pesan + pemberitahuan segera, token kosong → belum disiapkan, galat → dicatat gagal), penyambung 23 (alamat/kepala/isi permintaan GitHub, 401 tanpa coba ulang dan tanpa token di alasan, 502 lalu 204, jaringan putus). 0 gagal.

## Pemasangan

Pasang ke Supabase (run 44276940012): migrasi 0022 terpasang, pemeriksaan 31 lulus 0 gagal, "Pemicu Isi Sheets: diisi".

## Uji nyata (18 Nov 2026, pemilik mengirim file lewat bot)

1. File pertama `A_p4_MA1_uji6e.csv` (periode 21 Nov–20 Des) **ditolak**: semua tap bertanggal lebih dari sehari sesudah tanggal kirim (pengaman `urai`; kesalahan Claude memilih periode yang tanggalnya belum lewat). Bukti tambahan: **file ditolak tidak memicu** (`fakta.picu_sheets` tetap 0) dan gaji tidak berubah.
2. File pengganti `A_p3_MA1_uji6e.csv` (periode 21 Mar–20 Apr, satu baris dibuang) diterima: 39.607 tap; antrean periode 2, 3, 4 selesai; versi gaji baru 10, 12, 14; **total gaji bersih keempat periode sama persis** dengan sebelum (5.183.058.029 · 8.216.773.882 · 5.706.405.590 · 4.999.870.485).
3. `fakta.picu_sheets` id 1: telegram, **terkirim** 16.41.41 WIB; file mulai diproses 16.40.21 WIB.
4. Isi Sheets (run 44278319017, `workflow_dispatch`, pemicu "file Telegram"): lama isi 16.588 ms; pemeriksa 0 beda; status `SELESAI 2026-11-18 16:43:12 WIB`; kabar Telegram 1 dari 1 penerima: "Sheets SELESAI diperbarui 2026-11-18 16:43 WIB, diperiksa sama dengan gudang. Lama sejak file masuk: 172 detik."
5. Dicek langsung di Sheets: Riwayat isi baris terakhir pemicu "file Telegram", versi "1:5; 2:10; 3:12; 4:14", waktu file masuk `2026-11-18T09:40:21.896Z`; Ringkasan sama dengan sebelum (contoh periode 4: 1.003 orang, gaji bersih 4.983.863.768, 3 rahasia tidak termasuk).

**Diukur sekali: file masuk → Sheets SELESAI dan dikabarkan = 172 detik** (hitung ulang 3 periode sekitar 80 detik; workflow Isi Sheets 96 detik termasuk memasang klien Postgres).

## Belum terbukti

- Jalur file lewat halaman unggah web memicu dengan pemicu "file web" (diuji otomatis, belum diuji nyata).
- Kabar GAGAL di Telegram (diuji otomatis, belum terjadi sungguhan).
