# Laporan paket G1-2: gaji rahasia per periode, demo terbit sesudah Isi Sheets

18 November 2026 · rencana `docs/rencana-perbaikan-g1.md` · permintaan perubahan 05 (kasus F15c) · commit 24e96c7

## Yang dibuat

1. **Rahasia per periode (C1)**: gaji satu periode disembunyikan bila orang itu rahasia pada hari mana pun di periode itu, atau rahasia sekarang.
   - Diterapkan di `web/buat_data.py`, `web/isi_sheets.py`, `web/periksa_data.py` dan `web/periksa_sheets.py`. Kedua pemeriksa menghitung aturan ini di Python sendiri, bukan dengan SQL yang sama.
   - Halaman demo kini membaca rahasia dari angka periode itu, bukan dari tanda per orang.
2. **Celah turunan yang ditemukan saat mengerjakan C1 (masuk lingkup F15c) [Pasti]**: tanda anomali selalu membandingkan dengan periode lalu.
   - "Gaji berubah dari Rp… ke Rp…" kini tanpa keterangan bila orang itu rahasia di periode ini **atau periode lalu**.
   - "Lembur divisi naik dari Rp…" kini tanpa angka bila divisi itu memuat orang rahasia di periode ini **atau periode lalu**. Sebelumnya, orang rahasia yang pindah divisi bisa membuka lemburnya lewat tanda divisi lamanya. Ini belum terjadi di data.
3. **Demo terbit sesudah Isi Sheets (C2)**: Terbitkan demo kini berjalan sesudah "Isi Sheets" lulus, bukan sesudah Pasang. Isi Sheets sendiri berjalan sesudah Pasang, Reset, dan file Telegram/web, jadi demo tidak terbit dua kali.
4. **Teks (C3, C4)**: "arahkan kursor atau ketuk 'Lihat angka' di HP"; persen porsi bisa berjumlah 99,9% atau 100,1%.
5. **Dokumen**: `docs/permintaan-perubahan-05.md`; kasus F15c ditambah di `docs/kasus-jebakan.md`. F15 dan F15b tidak diubah.

## Uji [Pasti]

- GitHub run 44298819667 lulus: database 453/453, uji pemicu 12/12, simulasi lengkap Pabrik A dan B.
- Uji F15c baru, 9 cek × 2 pabrik, semua lulus. Di database uji, satu orang rahasia dibuat berhenti rahasia mulai periode terakhir. Hasilnya:
  - Sheets dan demo: periode lama tanpa angka, periode terakhir berangka; kedua pemeriksa lulus.
  - Tanda anomali orang itu di periode terakhir tanpa keterangan.
  - Data demo diubah ke aturan lama (gaji periode lama terbuka): pemeriksa GAGAL.
  - Basis data uji dikembalikan seperti semula.
- Isi Sheets lewat tombol (run 44300958658): pemeriksa Sheets 0 beda. Terbitkan demo **jalan sendiri** sesudahnya (run 44301225340, event workflow_run): pemeriksa demo 0 beda.
- Halaman terbit dicek langsung:
  - data dibuat 19:09 WIB;
  - 10998 (rahasia) tampil "rahasia" dan rinciannya berbunyi "rahasia di periode ini";
  - teks keterangan baru tampil;
  - konsol bersih sesudah halaman dimuat ulang.

Di data sekarang angka tidak berubah, karena tidak ada status rahasia yang berubah: 3 orang rahasia, total sama.

## Tidak diubah

Supabase (tanpa migrasi dan tanpa Pasang), mesin hitung, bot.

## Temuan baru saat analisa ulang (belum diperbaiki, butuh paket sendiri)

- **T1 [Pasti]: balasan bot Telegram sesudah file diproses menulis "gaji bersih RpX" yang memasukkan orang rahasia.**
  - Sumbernya `api.pintu_kerjakan` di migrasi 0015 (`sum(g.gaji_bersih)` semua orang) dan pesan di `sistem/pintu/inti.ts` baris 285.
  - Bukti di Supabase: periode 4, bot 4.999.870.485 = jumlah semua orang termasuk rahasia.
  - Akibatnya, HRD yang menerima balasan bot bisa mengurangkan jumlah yang terlihat di Sheets dari total bot dan mendapat gabungan gaji orang rahasia (F15b).
  - Perbaikannya butuh migrasi dan Pasang. Usulan ada di `docs/serah-terima.md`.
