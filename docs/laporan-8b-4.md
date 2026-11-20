# Laporan paket 8b-4: tombol tetap di bawah kolom ketik (terpasang; uji nyata berjalan)

20 November 2026 · rencana `docs/rencana-8b-4.md` · commit fdf9a90

## Yang dibuat

- `sistem/pintu/inti.ts`: `TOMBOL_TETAP` per peran, `papanTombol`, `teksTombol` (teks tombol → perintah); `Kode karyawan` dan `PIN` bertanya dengan force reply, jawabannya dikenali dari pesan bot yang dibalas (`TANYA_ID`, `TANYA_PIN`); `Undang` → pilihan HRD/Bos (`u|hrd`, `u|bos`); tombol `Batalkan pengajuan` (`b|y|<periode>`) di daftar Rilis; `/bantuan`, `/start`, `/gabung` memasang tombol.
- Uji: 5 uji baru di `sistem/pintu/uji_pintu.ts`.

## Uji [Pasti]

- Lokal: pintu 82 lulus (sebelumnya 77). Satu kesalahan uji sendiri tertangkap: kode tautan `/unggah` acak, jadi perbandingan teks tanpa kode itu.
- Uji bisa gagal: penerjemah teks tombol dimatikan → 4 uji GAGAL; dikembalikan.
- GitHub run 44670639203 lulus: database 603, simulasi 128, pintu 82, penyambung 23.

## Pemasangan [Pasti]

- Pasang run 44672144413 lulus: tidak ada migrasi baru (0001–0028 dilewati), pemeriksaan 33 lulus 0 gagal, Edge Function pintu-telegram dipasang ulang, alamat bot didaftarkan.
- Supabase sesudahnya: migrasi terakhir tetap 0028; status periode tidak berubah (1 dihitung, 2 dirilis, 3 dihitung, 4 dihitung); rilis 1.

## Belum selesai

- Uji nyata oleh pemilik (tombol tetap, tombol PIN, Kode karyawan, Undang, Rilis lewat tombol).
