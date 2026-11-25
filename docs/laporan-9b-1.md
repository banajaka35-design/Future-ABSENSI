# Laporan paket 9b-1: perintah lewat web (tanpa angka uang)

Rencana: `docs/rencana-9b-1.md`. Di-"buat" pemilik 25 Nov 2026 08.59 WIB. Pekerjaan sempat ditahan 09.00–09.05 karena dua fakta di rencana ternyata salah; pemilik lalu memilih "pengecualian sempit".

## Yang dibuat

| Bagian | Isi |
| --- | --- |
| Migrasi `0041_perintah_web.sql` | `asal` boleh 'web'; draf 15 menit (`fakta.draf_perintah_web`); `fakta.perintah_web` dan `fakta.perintah_web_ubah` (hanya bertambah); pemeriksaan bersama `fakta.web_perintah_periksa`; simpan dan batal; daftar; `api.web_hrd` ditambah aksi `perintah_daftar`, `perintah_pratinjau`, `perintah_simpan`, `perintah_batal`; pengecualian sempit di `jejak.tolak_ubah` dan `jejak.jaga_bertanggal` |
| Edge Function (`sistem/pintu/inti.ts`) | Isian perintah disaring (hanya 10 kunci dikenal). Sesudah simpan/batal, hitung ulang lewat antrean yang sama dengan file dan chat (`kerjakanAntrean`, pemicu Sheets "perintah web"); kabar ke Telegram akun itu |
| Halaman `web/demo/hrd/index.html` | Tab "Perintah": isian per jenis, pratinjau, Simpan, daftar 30 perintah web terakhir dengan keadaan hitung ulang (diperbarui tiap 5 detik selama masih dihitung), tombol Batalkan dua langkah. Teks spanduk demo diganti (halaman tidak lagi "hanya melihat") |
| Uji | Database `db/uji/330_perintah_web.sql` (54 uji); pintu `9b-1` (data Pabrik A lengkap); simulasi: halaman tidak memuat isian gaji/rekening |

## Hasil uji lokal [Pasti, 25 Nov]

- Uji database: **884 lulus, 0 gagal** (sebelumnya 830; +54 uji 330).
- Uji pintu: **122 lulus, 0 gagal**. Uji penyambung dilewati di lokal karena paket npm tidak bisa dipasang (jaringan mati); dijalankan di GitHub.
- Simpan + hitung ulang satu periode lewat web dengan data Pabrik A lengkap (1.044 orang, Postgres lokal): **5,5 detik** (diukur sekali). Angka di Supabase belum diukur.
- Halaman dicoba di Chrome (tanpa server sungguhan, jawaban tiruan): isian berganti sesuai jenis, pratinjau, simpan, keadaan "sedang dihitung…" → "selesai", Batalkan dua langkah, teks `<b>` tampil sebagai teks biasa (bukan HTML), tidak ada galat skrip.

## Yang dibuktikan uji database 330

- Pratinjau tidak mengubah apa pun (perintah, data induk, versi hitung, antrean, jejak).
- Tambah libur: hari itu menjadi libur; orang yang tap menjadi "masuk di hari libur". Batal → hasil kembali persis.
- Absen manual divisi (F08): yang tidak tap menjadi hadir, asal "manual". Batal → kembali persis.
- Berhenti (keputusan 2a): hari X tetap ada; tap sesudah X tidak dihitung. Pratinjau memperingatkan jumlah tap sesudah X dan masa pajak terakhir.
- Aktif kembali: tap sejak tanggal mulai lagi dihitung.
- Berhenti tidak bisa dibatalkan selama ada aktif kembali sesudahnya. Bila dibatalkan berurutan (aktif kembali dulu, lalu berhenti), data induk dan hasil harian kembali **persis** semula.
- Mutasi:
  - riwayat baru menyalin gaji, tunjangan, PTKP, cara bayar, rekening, BPJS, dan tanda rahasia apa adanya;
  - jadwal mengikuti divisi baru mulai tanggal berlaku;
  - ID mesin baru wajib bila mesinnya berbeda; ID yang dipakai orang lain ditolak;
  - regu wajib dan dalam batas untuk divisi rotasi;
  - batal → kembali persis.
- Mutasi bertumpuk (A lalu B): A tidak bisa dibatalkan duluan; B lalu A bisa, dan data kembali persis.
- Perubahan dari luar web (misalnya tangan atau file) sesudah perintah → pembatalan ditolak.
- Penolakan:
  - periode dirilis;
  - lebih dari 31 hari;
  - lebih dari 62 hari ke depan;
  - keterangan kosong;
  - perintah ganda;
  - draf milik akun lain;
  - draf lewat 15 menit;
  - draf dipakai dua kali;
  - sesi palsu;
  - peran `pintu` memanggil fungsi dalam secara langsung.
- Akun pembangun bisa membuat perintah web seperti HRD.
- **Penjaga tetap berlaku di luar pembatalan web:**
  - status kerja dan riwayat tidak bisa dihapus;
  - riwayat tertutup tidak bisa dibuka;
  - menyalakan pengecualian tanpa pembatalan yang tercatat ditolak;
  - pengecualian tidak berlaku untuk baris yang bukan milik perintah itu;
  - tabel fakta lain dan aturan bertanggal tetap terjaga.

## Pemasangan [Pasti, 25 Nov]

- Uji GitHub commit 2f5f012 (dijalankan ulang 09.47 sesudah repo publik): database 884, simulasi 133, pintu 122, penyambung 24, semua lulus (run 45534377141).
- Pasang ke Supabase run 45537499453 sukses (0041 terpasang); Isi Sheets, Cadangan (pertama sejak 23 Nov), dan Terbitkan demo (run 45538531224) sukses.
- Dicek di Supabase: 5 fungsi baru ada, `asal` menerima 'web', 3 tabel baru, belum ada perintah web.
- Lama pemeriksaan pratinjau di Supabase (diukur sekali, tanpa menyimpan): tambah libur semua divisi 1 Des = **181 ms** (996 orang aktif, 789 sudah tap); berhenti 10002 1 Des = **62 ms** (peringatan 31 tap sesudah 1 Des, periode 4 masa pajak terakhir).

## Uji nyata 25 Nov 2026 [Pasti, dicek di Supabase dan Sheets]

Langkah 1–3 dari rencana (tambah libur KTR 1 Des 2026, lalu dibatalkan), oleh pemilik lewat web dengan akun pembangun:

| Langkah | Hasil |
| --- | --- |
| Pratinjau 10.19 | 120 orang aktif, 116 sudah tap, periode 4 (sama dengan gudang); tidak ada yang tersimpan (hanya 1 draf) |
| Sebelum simpan | KTR 1 Des: 117 hadir, 2 alpha, 1 sakit; sidik gaji periode 4 `c427e5a53c5f`; total gaji bersih Sheets/gudang Rp4.983.863.768 |
| Simpan 10.20 (perintah no. 1612) | Asal web, oleh pembangun; hitung ulang periode 4 = 25,5 detik; KTR 1 Des: 117 masuk di hari libur, 3 libur; sidik `eb4edab2a80a`; Sheets diisi ulang 10.22, total gaji bersih Rp5.049.547.543 = gudang (+Rp65.683.775, lembur hari libur); kabar Telegram terkirim |
| Batal 10.27 (pembatalan no. 1613) | Hitung ulang 24,2 detik; KTR 1 Des kembali 117 hadir, 2 alpha, 1 sakit; **sidik gaji periode 4 kembali persis `c427e5a53c5f`**; Sheets diisi ulang 10.29, total Rp4.983.863.768 = gudang |

Mutasi 10.35–10.40 (10881 Rahmat Santoso, KTR → PRD regu 1 mulai 1 Des 2026):

| Langkah | Hasil |
| --- | --- |
| Pratinjau tanpa ID mesin | Ditolak: "Divisi Produksi memakai mesin MA1, sedangkan ID 10881 terdaftar di mesin lain…" (C7); tidak ada yang tersimpan |
| Simpan dengan ID MA1 9001 (no. 1614) | Hitung ulang 22,6 detik. Riwayat KTR ditutup 1 Des, riwayat PRD dibuka 1 Des; regu 0 → 1; MA1:9001 ditambah (MA2 tetap). Isian uang di dua riwayat sama persis. Mulai 1 Des jadwal rotasi PRD regu 1 (P, P, S, S, M, M, libur) — **jalur pindah ke divisi rotasi terbukti**. Sidik gaji periode 4 `76a70658fc37`. Alpha/masuk di hari libur sesudah 1 Des karena tap data simulasi tetap mengikuti jam Kantor [Kemungkinan Besar] |
| Batal (no. 1615) | Hitung ulang 23,6 detik. Riwayat, regu, dan ID mesin 10881 kembali satu baris masing-masing seperti semula; hasil harian 30 Nov–5 Des kembali KTR hadir; **sidik gaji periode 4 kembali `c427e5a53c5f`** |

Temuan kecil (tampilan, masuk 9a-2):
- Selama pembatalan dihitung, baris perintah aslinya ikut tertulis "sedang dihitung…", karena keadaan diambil per periode.
- Di layar sempit, tabel perlu digeser ke samping.
- Aturan lama mesin hitung (Tahap 3) yang terlihat di uji ini: orang yang tercatat sakit pada hari yang kemudian dijadikan libur menjadi "libur". Dicatat untuk pemilik; tidak diubah.

## Yang belum

- [Menebak] Lama pratinjau dan hitung ulang di Supabase: belum diukur.
