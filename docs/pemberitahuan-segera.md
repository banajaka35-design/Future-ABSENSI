# Pemberitahuan segera dan pengingat kirim file (Tahap 5, paket 5c)

17 November 2026 · ditulis sebelum kode · acuan: PRD v3.1 bagian 9 (tingkat pemberitahuan), 12 (celah A13), 16 (U14), 17 (gerbang Tahap 5); keputusan pemilik 17 Nov 2026

## Syarat dari PRD

- **U14:** "Setiap kejadian tingkat 'segera' di bagian 9 memicu pesan ke HRD dalam satu kali proses file."
- **Gerbang Tahap 5:** "U14 lulus; pengingat file terkirim."
- **A13:** pengingat otomatis di hari pertama dan kedua setelah tutup buku. **Bagian 9:** kalau file belum masuk dua hari setelah tutup buku, pemberitahuan juga dikirim ke bos.
- Tingkat "rekap harian" dan "sebelum rilis" bukan bagian paket ini.

## Kejadian tingkat "segera"

| Kejadian (PRD bagian 9) | Sumber di sistem | Kasus |
| --- | --- | --- |
| File dibuka lalu disimpan di Excel (ID rusak) | Kiriman ditolak, alasan diawali "No.ID rusak" | F01 |
| Format file berubah | Kiriman ditolak, alasan diawali "Format file tidak dikenal" | F09 |
| File kemungkinan terpotong | Anomali `file_terpotong` | F02 |
| Memori mesin bermasalah | Anomali `tap_terakhir_lama` | F03 |
| Jam mesin bermasalah | Anomali `jam_mesin_melenceng` | F05 |
| Hari tanpa tap massal | Anomali `tanpa_tap_massal` | C06 |
| Karyawan baru belum terdaftar di mesin | Anomali `belum_terdaftar_mesin` | F13 |
| Libur mendadak | Tidak ada pendeteksi sendiri: muncul sebagai hari tanpa tap massal, lalu HRD menetapkannya (kontrak data: libur mendadak masuk kalender) | C06 |

Anomali diambil dari hasil **versi terakhir** setiap periode, tingkat `segera`, yang belum selesai (`selesai = false`; misalnya hari tanpa tap massal yang sudah ditetapkan lewat absen manual tidak dikirim).

## Penerima

Semua akun aktif berhak akses `hrd` dan `pembangun` yang punya ID Telegram (keputusan pemilik). Pengirim file tetap mendapat balasan penolakan seperti di 5b; bila ia juga penerima, ia mendapat dua pesan (balasan dan pemberitahuan).

## Tidak dikirim dua kali

Setiap kejadian punya **kunci tetap** yang dicatat di tabel `fakta.pemberitahuan`:

- kiriman ditolak: nomor kiriman;
- anomali: jenis + mesin + divisi + karyawan + nomor kiriman + tanggal + tanggal akhir (tanpa nomor versi dan tanpa angka `nilai`).

Hitung ulang membuat baris anomali baru dengan versi baru, tetapi kuncinya sama, jadi tidak dikirim lagi. Kejadian dicatat **lebih dulu**, baru dikirim; hasil kirim per penerima dicatat sesudahnya. Bila pengiriman ke Telegram gagal, kejadian itu tidak dikirim ulang otomatis; kegagalannya tercatat (`status` dan `hasil_kirim`).

## Kapan dikirim (U14)

Dalam proses file yang sama:

1. File ditolak karena Excel atau format → sesudah balasan penolakan ke pengirim, pemberitahuan dikirim.
2. File diterima → sesudah **setiap periode** selesai dihitung di antrean (bukan menunggu seluruh antrean), pemberitahuan kejadian baru dikirim.

Satu pesan per penerima berisi semua kejadian baru saat itu, dikelompokkan per jenis, masing-masing dengan langkah yang perlu dilakukan HRD. Pesan lebih dari batas panjang Telegram dipecah.

## Pengingat kirim file (A13)

- Tanggal tutup buku dari pengaturan `tanggal_tutup_buku` (sekarang 20; 0 berarti akhir bulan), bukan dari daftar periode yang sudah dibuat.
- Penjadwal: pg_cron di Supabase, setiap hari 01.00 UTC = 08.00 WIB, memanggil Edge Function lewat pg_net dengan kode rahasia pengingat (disimpan di Vault Supabase, dibuat acak setiap pemasangan).
- Edge Function memeriksa: hari ini hari ke-1 atau ke-2 sesudah tutup buku? Bila tidak, tidak ada apa-apa.
- **Mesin belum mengirim** = belum ada kiriman diterima dari mesin itu yang tap terakhirnya pada atau sesudah tanggal tutup buku.
- Hari ke-1 dan ke-2: satu pesan ke semua akun `hrd` dan `pembangun` berisi daftar mesin yang belum mengirim.
- Hari ke-2: juga ke akun `bos` aktif. Belum ada akun bos → dicatat `dilewati_tanpa_akun_bos`.
- Satu pengingat per mesin per hari ke-1/ke-2 per periode (kunci tetap); dipicu dua kali di hari yang sama tidak mengirim dua kali.
- Pemicu manual untuk uji: workflow **"Picu pengingat"** dengan tanggal pura-pura (misalnya 2026-11-21).

## Pengaman pemasangan

Kejadian yang sudah ada saat paket ini dipasang (dan yang dibuat oleh skrip pemasangan sendiri, bukan oleh file dari HRD) dicatat `lama_tidak_dikirim` dan tidak dikirim.

## Akses

Edge Function tetap memakai peran `pintu`, hanya lewat fungsi `api` baru: `pintu_pemberitahuan_ambil`, `pintu_pengingat`, `pintu_pemberitahuan_hasil`.

## Kasus uji (wajib benar)

| No | Kejadian | Harapan |
| --- | --- | --- |
| N1 | Ketujuh jenis kejadian ada | Masing-masing tercatat sekali dan masuk pesan ke semua penerima (U14) |
| N2 | Hitung ulang periode yang sama | Tidak ada pesan ulang; tidak ada baris catatan baru |
| N3 | Akun `karyawan`, akun `hrd` nonaktif, akun tanpa ID Telegram | Tidak menerima |
| N4 | File rusak Excel dikirim lewat bot | Pengirim dapat balasan penolakan; semua penerima dapat pemberitahuan dalam proses yang sama |
| N5 | File format tidak dikenal lewat bot | Sama dengan N4 |
| N6 | File sah yang menimbulkan anomali segera | Pemberitahuan terkirim dalam proses file yang sama |
| N7 | Anomali yang sudah selesai | Tidak dikirim |
| N8 | Anomali tingkat `harian` | Tidak dikirim |
| N9 | Kiriman ditolak karena file dobel | Tidak dikirim (bukan tingkat segera) |
| P1 | Hari ke-1 sesudah tutup buku, satu mesin belum mengirim | Pengingat untuk mesin itu saja ke semua penerima |
| P2 | Dipicu lagi di hari yang sama | Tidak ada pesan kedua |
| P3 | Hari ke-2 tanpa akun bos | Pengingat HRD terkirim; bos dicatat dilewati |
| P4 | Hari ke-2 dengan akun bos | Bos juga menerima |
| P5 | Hari ke-3 atau hari biasa | Tidak ada pengingat |
| P6 | Tutup buku 0 (akhir bulan) | Hari ke-1 = tanggal 1 bulan berikutnya |
| P7 | Kode rahasia pengingat salah | Ditolak (HTTP 401), tidak ada catatan |
| S1 | Penyambung `index.ts` dengan postgres.js sungguhan | Isian jsonb terbaca benar (kesalahan 616651f tertangkap), fungsi tanpa isian dan hasil null berjalan |

N1–N9 dan P1–P6 diuji di GitHub (Postgres sementara). N4–N6 dan S1 lewat pesan Telegram tiruan. Uji nyata di Supabase: N4 (pemilik mengirim lagi file rusak Excel) dan P1/P3 (pengingat dipicu manual sekali dengan tanggal pura-pura).
