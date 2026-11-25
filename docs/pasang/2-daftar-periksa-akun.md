# Daftar periksa akun dan layanan untuk PT baru

Dipakai di langkah 2 dan 3 panduan pasang (`docs/pasang/README.md`). Centang satu per satu. Semua akun dibuat **atas nama PT**;
pembangun diundang sebagai pengelola. Alasannya: data gaji karyawan PT tidak boleh tersimpan di akun pribadi pembangun, dan PT
bisa mencabut akses bila kerja sama selesai.

## Sebelum mulai: sepakati biaya dengan PT

- [ ] **GitHub Actions.** Repo PT privat, sehingga memakai jatah menit GitHub. Satu uji lengkap ±20 menit (diukur run 45554089636,
  25 Nov 2026). Proyek demo pernah kehabisan jatah gratis (25 Nov 2026). Sepakati: PT memakai paket GitHub berbayar, atau uji
  lengkap hanya dijalankan sebelum Pasang.
- [ ] **Supabase.** Paket gratis tidak punya cadangan harian otomatis dan proyek bisa dihentikan bila lama tidak dipakai. Untuk
  data gaji sungguhan disarankan paket berbayar.
- [ ] **Email pengirim** (Brevo) dengan domain PT: perlu domain milik PT.

## Langkah 2: repo privat PT

- [ ] PT (atau pemilik proyek) membuat akun/organisasi GitHub atas nama PT.
- [ ] Di akun PT: tombol **New** → nama misalnya `absensi-pt-abc` → pilih **Private** → **Create repository**. Biarkan kosong (jangan
  centang README, .gitignore, atau license).
- [ ] Settings → Collaborators → **Add people** → `banajaka35` (hak admin).
- [ ] **Jangan memakai tombol Fork.** Fork dari repo publik tidak bisa dijadikan privat.
- [ ] Minta Claude menyalin, dengan kalimat:

  > Salin repo banajaka35-design/Future-ABSENSI cabang main ke repo <akun-PT>/absensi-pt-abc (privat, saya sudah jadi kolaborator).
  > Salin semua isi dan riwayat, lalu periksa jumlah commit dan file sama dengan aslinya.

- [ ] Di repo PT, **matikan** workflow yang khusus demo (Actions → pilih workflow → ··· → Disable workflow):
  - [ ] **Terbitkan demo** (menerbitkan halaman publik demo; penjaga D1 memang menolak data sungguhan, tetapi workflow ini tidak
    dipakai PT);
  - [ ] **Cadangan malam** selama cadangan masih berupa file di GitHub (data gaji sungguhan tidak boleh disimpan sebagai
    artifact GitHub). Ganti dengan cadangan Supabase berbayar sebelum PT memakai sistem;
  - [ ] **Reset Supabase** (hanya untuk demo; skripnya juga menolak bila ada karyawan bukan simulasi).
- [ ] **Yang boleh dihapus** dari repo PT (tidak wajib): laporan dan rencana demo di `docs/` (kecuali `docs/pasang/`,
  `docs/kontrak-data.md`, `docs/aturan-hitung-gaji.md`, `docs/kasus-jebakan.md`), folder `percobaan/`, halaman demo
  `web/demo/` selain `hrd/` dan `unggah/`.
- [ ] **Yang tidak boleh dihapus:** `data/simulasi/` dan `db/data_awal/pabrik_*`. Isinya karangan, tetapi dipakai uji otomatis
  yang membuktikan mesin hitung benar setiap kali kode berubah.
- [ ] **Data karyawan asli tidak pernah dimasukkan ke repo**, walaupun repo-nya privat.

## Langkah 3: akun layanan atas nama PT

### Supabase (database)
- [ ] Buat proyek baru di akun Supabase milik PT. Wilayah: pilih yang terdekat (Singapura kemungkinan lebih dekat dari Mumbai
  untuk Indonesia [Kemungkinan Besar]).
- [ ] Undang pembangun sebagai anggota proyek.
- [ ] Catat untuk secret: alamat database (Session pooler), access token, publishable key.

### Telegram (bot)
- [ ] Buat bot baru lewat @BotFather atas nama PT (jangan memakai bot demo). Catat token.
- [ ] Catat ID Telegram pembangun.

### Google Sheets (rekap)
- [ ] Buat spreadsheet baru di Google Drive milik PT.
- [ ] Buat akun layanan Google Cloud di proyek milik PT, beri hak edit ke spreadsheet itu. Catat kunci JSON dan ID spreadsheet.
- [ ] HRD diberi akses **lihat saja** (riwayat versi Sheets bisa memuat angka gaji yang belakangan dijadikan rahasia; hanya akun
  dengan hak edit yang bisa membuka riwayat versi [Kemungkinan Besar]).

### Email kode masuk web HRD (Brevo)
- [ ] Akun Brevo milik PT, domain PT diverifikasi (supaya email kode tidak masuk Spam). Catat kunci API dan alamat pengirim.

### Web HRD
- [ ] **Belum ada jalur terbit web HRD untuk PT** (temuan 9d): sekarang web HRD hanya terbit lewat workflow Terbitkan demo ke situs
  demo. Sebelum PT memakai web HRD, perlu paket kecil untuk menerbitkannya ke alamat milik PT, dan isian `ASAL_WEB` di
  `db/pasang_pintu.sh` diarahkan ke alamat itu (sekarang bawaannya situs demo). Bot Telegram tetap bisa dipakai tanpa web HRD.

## Secret yang diisi di repo PT (Settings → Secrets and variables → Actions)

| Secret | Isinya | Dipakai oleh |
| --- | --- | --- |
| `SUPABASE_DB_URL` | Alamat database Supabase PT (Session pooler) | Pasang, Isi Sheets, Cadangan |
| `SUPABASE_ACCESS_TOKEN` | Token akses Supabase untuk memasang Edge Function | Pasang (pintu) |
| `SUPABASE_PUBLISHABLE_KEY` | Kunci publik Supabase PT | Cadangan malam |
| `TELEGRAM_BOT_TOKEN` | Token bot PT | Pasang (pintu), Isi Sheets (kabar) |
| `PEMBANGUN_TELEGRAM_ID` | ID Telegram pembangun | Pasang |
| `PEMBANGUN_EMAIL` | Email pembangun (akun web) | Pasang, Isi Sheets |
| `BREVO_API_KEY` | Kunci Brevo PT | Pasang (email kode) |
| `GOOGLE_SA_KEY` | Kunci JSON akun layanan PT | Isi Sheets |
| `SHEETS_ID` | ID spreadsheet PT | Isi Sheets |
| `CADANGAN_KUNCI` | Kunci enkripsi cadangan (buat baru, simpan di tempat aman milik PT) | Pasang, Cadangan |
| `GTHUB_PICU_TOKEN` | Token GitHub untuk bot memicu Isi Sheets | Pasang (pintu) |
| `CLOUDFLARE_*` | Tidak diisi: hanya untuk Terbitkan demo | – |

Nama secret harus persis sama dengan tabel di atas (workflow membacanya dengan nama itu).

## Keputusan yang diambil ulang saat PT pertama

Dari tabel "Sebelum dipasang untuk perusahaan sungguhan" di `docs/serah-terima.md`:

- [ ] **Hak akun pembangun.** Di demo, akun pembangun bisa semua, termasuk mengajukan dan menyetujui gaji sendiri (keputusan pemilik
  19 Nov 2026). Untuk PT, putuskan bersama PT apakah aturan "dua orang" (HRD mengajukan, bos menyetujui) berlaku juga untuk pembangun.
- [ ] **Akses pembangun dan Claude ke angka gaji.** Di demo, pembangun dan sesi Claude bisa membaca semua gaji. Untuk PT: pembangun
  tidak membaca gaji kecuali diizinkan PT; penyambung Supabase/Sheets di Claude hanya dipakai untuk proyek demo.
- [ ] **Sesi web HRD** (2 jam, berhenti bila 30 menit tidak dipakai): tinjau ulang bersama PT.
