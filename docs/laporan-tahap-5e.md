# Laporan paket 5e: masuk ke halaman unggah lewat kode email

17 November 2026 · acuan: `docs/login-email.md` (commit b9242d0, ditulis sebelum kode) · kode: commit baf4479

## Hasil singkat

| Kasus | Uji otomatis (GitHub) | Uji nyata (Supabase, halaman demo, Brevo) |
| --- | --- | --- |
| E1 email terdaftar mendapat kode | **Lulus** | **Lulus** (percobaan ke-3, lihat temuan 1–2): kode no. 6 dibuat 18.20.14 WIB, email sampai |
| E2 email tidak terdaftar: jawaban sama, tanpa email | **Lulus** | — |
| E3 kode benar → tautan unggah 15 menit; unggah seperti 5d | **Lulus** | **Lulus**: kode no. 6 dipakai 18.20.39, tanpa salah; tautan no. 2 atas nama akun pemilik; kiriman no. 22 (`rusak_excel_MA2.csv`) ditolak, asal `web`, 0 tap, pemberitahuan segera `terkirim` |
| E4 salah 5 kali → terkunci; E5 lewat 10 menit; E6 dipakai dua kali; E7 kode lama | **Lulus** | — |
| E8 permintaan ke-4 dalam 15 menit tidak mengirim | **Lulus** | Terjadi tanpa sengaja (temuan 2) |
| E9 akun dinonaktifkan | **Lulus** | — |
| E10 alamat lain → 403 | **Lulus** | — |
| E11 akun tanpa ID Telegram masuk lewat email dan mengunggah | **Lulus** | — |
| E12 panggilan ke Brevo sesuai dokumen | **Lulus** | **Lulus** (email sampai sesudah izin dan IP dibereskan) |

Jumlah uji otomatis: database 444 lulus; bot 33 lulus; penyambung 19 lulus.

## Penyiapan Brevo oleh pemilik (17 Nov 2026)

- Akun Brevo gratis; alamat pengirim `banajaka35@gmail.com` sudah berstatus Verified.
- Kunci API `future-absensi`: Restricted, **Transactional email: Read/write**, sumber lain None, berlaku sampai 17 Nov 2027. **Kunci mati sendiri bila 90 hari tidak dipakai** (keterangan di layar Brevo).
- **Pemblokiran IP untuk kunci API dimatikan** (Security → Authorised IPs): alamat IP server Supabase berganti-ganti, jadi tidak bisa didaftarkan satu per satu [Kemungkinan Besar]. Kunci tetap hanya ada di secret GitHub dan Supabase.
- Secret GitHub: `BREVO_API_KEY`, `PEMBANGUN_EMAIL`.
- Banner Brevo "akun ditangguhkan untuk email pemasaran" tidak menghalangi email transaksional (terbukti: kode terkirim).

## Temuan

1. **Kunci pertama hanya punya izin Read** [Pasti, log Edge Function]: Brevo menjawab 403 "api key is not authorized for resource transactional.email". Diperbaiki pemilik di Brevo (Read/write). Lalu Brevo menjawab 401 "unrecognised IP address"; diperbaiki dengan mematikan pemblokiran IP.
2. **Email yang gagal terkirim tetap memakai jatah 3 kode per 15 menit** [Pasti, tabel `fakta.kode_email`]: tiga percobaan pukul 17.53 gagal di Brevo, lalu percobaan berikutnya harus menunggu sampai 18.09. Selama tertahan, halaman menjawab "kode sudah dikirim" padahal tidak ada email (sesuai rancangan supaya tidak membocorkan email terdaftar, tetapi membingungkan pemilik akun sendiri). **Usulan perbaikan (belum di-"buat"):** kode yang gagal dikirim tidak dihitung dalam jatah.
3. Kode no. 5 (18.19.59) tidak dipakai: pemilik menekan "Kirim kode" dua kali; hanya kode terbaru yang berlaku (sesuai rancangan E7).

## Batasan

- Email kode uji nyata 17 Nov 2026 masuk **Inbox** Gmail pemilik [Pasti, laporan pemilik]. Ke alamat lain (bukan Gmail yang sama dengan pengirim) belum diuji; bisa masuk Spam [Menebak]. Untuk perusahaan sungguhan tetap disarankan domain sendiri.
- Kunci Brevo mati sesudah 90 hari tanpa pemakaian; tidak ada pemeriksa otomatis untuk ini.
- Pemberitahuan segera dan ringkasan hitungan tetap lewat Telegram.
