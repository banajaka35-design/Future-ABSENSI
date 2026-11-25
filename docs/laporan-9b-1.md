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

## Yang belum

- Pemasangan ke Supabase dan terbit demo (sesudah uji GitHub lulus).
- Uji nyata oleh pemilik (rencana bagian "Uji nyata").
- [Menebak] Lama pratinjau dan hitung ulang di Supabase: belum diukur.
