# Permintaan perubahan 02: karyawan baru yang hari kerja pertamanya sakit, izin, atau cuti

Diajukan 17 November 2026 (paket 4b-5) · status: **disetujui pemilik proyek 17 Nov 2026** (perintah "buat" untuk daftar paket 4b-5 yang memuat kasus ini kata per kata).

## Latar belakang

Uji U5 Pabrik B (paket 4b-4) menemukan karyawan baru 20190: mulai 6 Apr 2026, hari itu sakit (dilaporkan HRD), lalu 7 dan 8 Apr masuk tetapi belum didaftar di mesin. Kasus F13 hanya menyebut "tanpa tap di hari-hari kerja pertamanya". Pembaca tap versi 1 melihat 2 hari kerja pertama sejak mulai, termasuk hari sakit, sehingga pemberitahuan "belum didaftar di mesin?" tidak muncul.

## Usulan

Tambah kasus **F13b** (kasus F13 tidak diubah):

| No | Kejadian | Hasil yang diharapkan | Sumber |
| --- | --- | --- | --- |
| F13b | Karyawan baru, hari kerja pertamanya sakit (perintah HRD), lalu 2 hari masuk tetapi belum didaftar di mesin | 2 hari itu alpha, dan ada pemberitahuan "belum didaftar di mesin?" | Permintaan perubahan 02 (temuan U5 Pabrik B) |

Cara pembaca tap: saat menilai "belum terdaftar di mesin", hari kerja yang statusnya dari perintah HRD (sakit, izin, cuti, dinas luar) dilewati; yang dinilai adalah 2 hari kerja pertama sesudahnya.

## Dampak

- Pembaca tap naik ke versi 2; hasil baca tap semua periode di Supabase dibaca ulang, lalu gaji dihitung ulang.
- Data simulasi dan generator tidak berubah.
