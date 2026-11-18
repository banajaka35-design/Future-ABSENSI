# Langkah pemilik untuk menyelesaikan paket 6e (ditulis 18 Nov 2026, 13.00 WIB)

Kode paket 6e sudah selesai dan semua uji GitHub lulus (commit e23dedf). Yang tersisa hanya 3 langkah ini.

## Langkah 1 (Anda): buat token GitHub, simpan sebagai secret

1. Buka **github.com/settings/personal-access-tokens/new**
2. Token name: `picu-isi-sheets` · Expiration: **90 days**
3. Repository access: **Only select repositories** → **Future-ABSENSI**
4. Permissions → Repository permissions → **Actions: Read and write** (yang lain biarkan "No access")
5. **Generate token** → salin tokennya
6. Buka **github.com/banajaka35-design/Future-ABSENSI/settings/secrets/actions/new**
   Name: `GITHUB_PICU_TOKEN` · Secret: tempel token → **Add secret**
7. Catat tanggal habis tokennya. Jangan kirim token ke chat.

## Langkah 2 (Claude): pasang ulang

Kirim ke Claude: **"token sudah, habis tanggal …"**. Claude menjalankan "Pasang ke Supabase".
(Di chat baru: "Baca CLAUDE.md, docs/serah-terima.md, dan docs/langkah-pemilik-6e.md di repo banajaka35-design/Future-ABSENSI cabang main. Token sudah, habis tanggal …. Lanjutkan paket 6e langkah 2.")

## Langkah 3 (Anda, sesudah Claude bilang Pasang selesai): kirim file uji

Kirim file **A_p4_MA1_uji6e.csv** (dikirim Claude di chat 18 Nov 2026) ke bot **Abaensi** dengan keterangan `MA1`. Jangan dibuka di Excel.
Bila filenya hilang: Claude bisa membuat ulang (file mesin MA1 periode 21 Nov–20 Des dari data simulasi, baris ke-3 dibuang).

Yang diharapkan di Telegram: "diterima", ringkasan periode, "Sheets sedang diperbarui otomatis", lalu beberapa menit kemudian "Sheets SELESAI … Lama sejak file masuk: … detik". Claude lalu memeriksa Sheets dan Supabase langsung.
