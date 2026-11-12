# Panduan kerja repo Future-ABSENSI

Sistem absensi fingerprint dan payroll otomatis. Rancangan lengkap ada di PRD v3.1 (dokumen Claude, dikelola pemilik proyek). File ini adalah aturan kerja untuk siapa pun yang melanjutkan repo ini, manusia atau Claude.

## Aturan kerja

1. Tidak ada kode yang ditulis sampai pemilik proyek bilang "buat".
2. Satu tahap dalam satu waktu; tahap berikutnya dimulai setelah gerbangnya lulus (PRD bagian 17).
3. Bahasa Indonesia sederhana di dokumen, pesan commit, dan pesan untuk pengguna.
4. Pisahkan yang terbukti dari yang masih dugaan. Angka kecepatan dan penghematan hanya ditulis setelah diukur.
5. Hasil diperiksa sampai ke gudang data dan Sheets, tidak cukup dari balasan bot.

## Struktur folder

| Folder | Isi |
| --- | --- |
| `docs/` | Kasus jebakan, laporan tiap tahap, catatan keputusan |
| `generator/` | Pembuat data simulasi (Tahap 1). Python, hanya pustaka bawaan |
| `data/simulasi/` | Hasil generator: file mesin, kunci jawaban, data induk, masukan HRD (terkompresi .gz) |
| `percobaan/` | Kode uji kelayakan Tahap 1,5. Boleh dibuang, tidak dipakai sistem |
| `db/migrasi/` | Perubahan database bernomor, hanya maju; file yang sudah dipasang tidak boleh diedit |
| `db/uji/` | Uji otomatis database; dijalankan dari nol di Postgres sementara |

## Larangan penting

- **Generator dan sistem tidak boleh berbagi kode.** Pembaca tap dan mesin hitung tidak boleh mengimpor apa pun dari `generator/`, dan sebaliknya. Generator hanya mencatat kejadian (jam datang, jam pulang, sakit, lupa tap); ia tidak menerapkan aturan jendela tap, telat, atau rumus gaji. Ini yang membuat kunci jawaban tidak berputar.
- **Tidak ada data pribadi di repo.** File mesin asli, rekap manual, dan kunci jawaban U9 hanya disimpan di folder Drive tertutup. Nama dan nomor di `data/simulasi/` sepenuhnya karangan.
- **Kunci rahasia tidak pernah masuk repo** (token bot, kunci Supabase, kunci Sheets). Hanya di brankas rahasia layanan.
- **Kasus jebakan tidak diubah agar kode lulus.** Perubahan hanya lewat permintaan perubahan.

## Menjalankan generator

```
python3 generator/buat_data.py          # menghasilkan data/simulasi/
python3 generator/periksa_kewajaran.py  # menulis docs/laporan-kewajaran-data.md
```

Uji database (butuh Postgres kosong):

```
DB_URL=postgresql://postgres:postgres@localhost:5432/postgres db/uji/jalankan.sh
```

GitHub Actions menjalankan uji ini dan pemeriksaan kewajaran setiap kali ada perubahan (`.github/workflows/uji-database.yml`). Perubahan yang membuat satu uji gagal tidak boleh dipasang.

Generator memakai benih acak tetap, jadi hasilnya selalu sama. Data bisa dibuat ulang kapan saja dari kode ini.
