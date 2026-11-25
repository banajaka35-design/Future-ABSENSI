# Uji banding bulan pertama

Dipakai di langkah 7 panduan pasang (`docs/pasang/README.md`). Tujuannya: PT percaya angka sistem karena sudah dibandingkan
sendiri dengan hitungan mereka, bukan karena diberi tahu.

## Aturan pokok

1. Selama uji banding, **gaji tetap dibayar memakai hitungan manual HRD**. Sistem berjalan di samping.
2. Uji banding berjalan **minimal 1 periode, sebaiknya 2**. Periode kedua membuktikan hal yang tidak muncul di periode pertama
   (sisa pembulatan tunai yang dibawa, kasbon yang dicicil, karyawan baru/berhenti).
3. Gaji baru dibayar memakai angka sistem setelah **tidak ada selisih yang belum dijelaskan**.
4. Gaji di periode uji banding **tidak dirilis** lewat bot (periode yang dirilis terkunci dan tidak bisa dihitung ulang).

## Langkah

1. HRD mengirim file mesin periode itu ke bot seperti biasa (atau lewat halaman unggah). Sistem menghitung sendiri.
2. HRD mencatat perintah yang biasa dicatat manual (izin, sakit, cuti, lembur, kasbon) lewat bot atau web HRD.
3. Sesudah tutup buku, ambil dua daftar:
   - **sistem:** tab "Gaji" periode itu di Sheets PT (atau web HRD tab Gaji);
   - **manual:** rekap gaji HRD untuk periode yang sama (file Excel mereka).
4. Bandingkan per orang: **gaji bersih** dulu. Bila berbeda, bandingkan per komponen: gaji pokok, potongan hari tidak dibayar,
   lembur, uang makan, premi, tunjangan shift malam, BPJS, PPh 21, kasbon/denda.
5. Catat setiap selisih di tabel di bawah, satu baris per orang per komponen.
6. Untuk setiap selisih, tentukan sebabnya (lihat "Jenis sebab"), lalu tindak lanjuti.
7. Ulangi untuk periode berikutnya sampai tidak ada selisih yang belum dijelaskan.

Claude bisa membantu langkah 4–5 bila HRD memberikan rekap manualnya: rekap dibandingkan dengan isi Sheets per orang, dan
hasilnya berupa tabel selisih. Rekap manual PT **tidak** disimpan di repo.

## Tabel selisih

| ID | Nama | Komponen | Sistem | Manual | Selisih | Sebab | Tindak lanjut | Selesai |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 10001 | (contoh) | Lembur | Rp111.850 | Rp105.000 | Rp6.850 | Manual memakai pembulatan 60 menit, aturan PT 30 menit | Konfirmasi aturan ke HRD | ya |

## Jenis sebab

| Sebab | Contoh | Tindak lanjut |
| --- | --- | --- |
| Data tap berbeda | Tap pulang terbaca di hari berikutnya; mesin mati sebagian hari | Periksa tab "Perlu dicek"; bila tap memang hilang, HRD mencatat absen manual |
| Perintah belum dicatat | Izin/sakit/cuti/lembur yang hanya ada di catatan HRD | HRD mencatat lewat bot atau web; periode dihitung ulang otomatis |
| Aturan PT salah dicatat di susunan | Toleransi telat, kelipatan lembur, nominal uang makan | Perbaiki aturan di database PT lalu hitung ulang. **Jalurnya belum ada** (temuan 9d, lihat README): Pasang melewati susunan yang sudah terisi, dan aturan hanya boleh diubah lewat workflow |
| Hitungan manual yang salah | Salah rumus BPJS, PPh, atau prorata | Tunjukkan rincian "Dasar hitung" di web HRD (rincian satu orang) |
| Aturan PT belum dikenal sistem | Tunjangan khusus, upah harian | **Temuan**: hentikan uji, laporkan ke pemilik proyek; jangan diakali di data |
| Aturan pemerintah berbeda | UMK/BPJS/TER yang dipakai manual sudah usang atau sebaliknya | Cocokkan ke sumber resmi; ikuti yang resmi, catat di laporan |

## Bukti selesai

Uji banding dianggap lulus bila, untuk satu periode penuh:
- jumlah orang di sistem = jumlah orang di rekap manual;
- setiap selisih punya sebab dan tindak lanjut yang selesai;
- total gaji bersih sistem dan manual sama, atau selisihnya seluruhnya dijelaskan oleh kesalahan manual yang sudah diakui HRD.

Hasilnya ditulis di laporan pemasangan PT (repo PT, `docs/`), dengan angka total dan jumlah selisih per jenis sebab, tanpa nama
dan gaji per orang.
