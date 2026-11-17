# Masuk ke halaman unggah lewat kode email (Tahap 5, paket 5e)

17 November 2026 · ditulis sebelum kode · acuan: keputusan pemilik 17 Nov 2026 (cara B: kode dari Edge Function sendiri, bukan Supabase Auth; layanan email Brevo), `docs/unggah-web.md` (paket 5d)

## Gunanya

HRD bisa mengunggah file mesin walau Telegram mati total: tautan unggah tidak lagi harus didapat dari bot.

## Alasan cara B dan Brevo

- Supabase Auth tidak dipakai: halaman tetap hanya berbicara dengan Edge Function (prinsip `docs/halaman-demo.md`), dan hasil masuk adalah **tautan unggah yang sama dengan 5d**, jadi seluruh jalur unggah yang sudah teruji dipakai ulang.
- Pengirim email bawaan Supabase hanya mengirim ke anggota tim proyek (dokumen resmi Supabase, "Send emails with custom SMTP"). Resend tanpa domain hanya mengirim ke email pemilik akun Resend (dokumen resmi Resend). Brevo tidak mewajibkan domain; alamat pengirim diverifikasi satu per satu (sumber pihak ketiga; dicek lagi saat pemilik membuat akun). Paket gratis 300 email/hari.
- API Brevo (dokumen resmi): `POST https://api.brevo.com/v3/smtp/email`, kepala `api-key`, isi `sender`, `to`, `subject`, `textContent`.

## Alur

1. HRD membuka `https://future-absensi-demo.pages.dev/unggah/` tanpa tautan dari bot. Halaman menampilkan isian email.
2. HRD mengetik email → Edge Function → database:
   - email milik akun aktif `hrd` atau `pembangun` → kode 6 angka dibuat, **sidiknya** (SHA-256 dari email + kode) disimpan, berlaku **10 menit**, lalu kode dikirim lewat Brevo;
   - selain itu tidak ada yang dibuat dan tidak ada email terkirim.
   - Halaman **selalu** menampilkan pesan yang sama: "Bila email terdaftar, kode sudah dikirim." Orang luar tidak bisa menebak email mana yang terdaftar.
3. HRD mengetik kode → Edge Function membuat kode tautan acak (seperti `/unggah` di 5d) → database memeriksa kode email dan membuat tautan unggah 15 menit atas nama akun itu. Halaman lalu memakai tautan itu persis seperti tautan dari bot.
4. Unggah, status, pemberitahuan segera: sama dengan 5d. Ringkasan hitungan dikirim ke Telegram akun itu bila ada ID Telegram; bila tidak ada atau Telegram mati, hasil tetap terlihat di halaman.

## Pengaman

| Hal | Aturan |
| --- | --- |
| Kode salah | Paling banyak 5 kali per kode; sesudah itu kode dikunci, harus minta kode baru |
| Kode lama | Hanya kode terbaru untuk email itu yang berlaku; kode dipakai sekali |
| Permintaan kode | Paling banyak 3 kode per email per 15 menit, dan 50 kode per jam untuk seluruh pemasangan (menjaga kuota 300 email/hari) |
| Akun | Dicek ulang saat tukar kode: masih aktif, masih `hrd` atau `pembangun` |
| Alamat asal | Hanya dari alamat halaman demo, sama dengan 5d |
| Penyimpanan | Kode email dan kode tautan tidak pernah disimpan; hanya sidiknya |
| Email gagal terkirim | Halaman diberi tahu "pengiriman email sedang gangguan" (hanya terjadi untuk email terdaftar; risiko kecil membocorkan bahwa email terdaftar, dicatat) |

## Mengisi email akun

- Kolom baru `induk.pengguna.email` (satu alamat untuk satu akun, huruf besar-kecil tidak dibedakan).
- Email akun pembangun diisi oleh pemasangan dari secret `PEMBANGUN_EMAIL`.
- Email HRD sungguhan diisi lewat pendaftaran (Tahap 7 atau 9), bukan paket ini.
- Selama secret `BREVO_API_KEY` belum diisi, jalur email menjawab "masuk lewat email belum disiapkan" dan pemasangan tidak gagal.

## Kasus uji (wajib benar)

| No | Kejadian | Harapan |
| --- | --- | --- |
| E1 | Email terdaftar meminta kode | Satu kode tercatat (sidik saja), satu email terkirim berisi 6 angka |
| E2 | Email tidak terdaftar | Jawaban halaman sama dengan E1; tidak ada kode tercatat, tidak ada email |
| E3 | Kode benar | Tautan unggah 15 menit atas nama akun itu; unggah file berhasil seperti 5d |
| E4 | Kode salah 5 kali | Kode dikunci; kode benar sesudahnya ditolak |
| E5 | Kode lewat 10 menit | Ditolak |
| E6 | Kode dipakai dua kali | Kedua kali ditolak |
| E7 | Kode lama sesudah minta kode baru | Ditolak; kode baru berlaku |
| E8 | Lebih dari 3 permintaan dalam 15 menit | Permintaan ke-4 tidak membuat kode dan tidak mengirim email; jawaban halaman tetap sama |
| E9 | Akun dinonaktifkan sesudah kode dikirim | Kode ditolak |
| E10 | Permintaan dari alamat lain | 403 |
| E11 | Akun tanpa ID Telegram masuk lewat email dan mengunggah | File diterima atas nama akun itu; tidak ada pesan Telegram |
| E12 | Panggilan ke Brevo | Alamat, kepala `api-key`, pengirim, penerima, dan isi sesuai dokumen Brevo |

E1–E12 diuji otomatis di GitHub (pengirim email tiruan). Uji nyata: pemilik masuk lewat email (tanpa bot) lalu mengunggah file rusak Excel.
