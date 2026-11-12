#!/usr/bin/env bash
# Membuktikan "ambil data tanpa login ditolak" (PRD gerbang Tahap 2, uji U7, celah K6) di Supabase sungguhan.
# Dua tingkat:
#   1. Database: katalog izin (db/cek_akses.sql) harus kosong untuk anon dan authenticated.
#   2. Internet: permintaan dengan kunci publik ke jalur API data harus ditolak. Kunci yang sama harus
#      diterima di /auth/v1/settings, supaya penolakan terbukti karena aturan akses, bukan karena kunci salah.
# Hanya membaca; percobaan menulis lewat internet harus ditolak sebelum menyentuh data.
# Pemakaian: DB_URL=... KUNCI=<kunci publik> db/uji_akses_supabase.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?DB_URL belum diisi}"
: "${KUNCI:?KUNCI (kunci publik Supabase) belum diisi}"
GAGAL=0

echo "== 1. Tingkat database"
CELAH="$(psql "$DB_URL" -X -q -t -A -F ' | ' -v ON_ERROR_STOP=1 -f db/cek_akses.sql)"
if [ -n "$CELAH" ]; then
  echo "GAGAL: ada celah akses:" >&2
  echo "$CELAH" >&2
  GAGAL=1
else
  echo "LULUS: anon dan authenticated tidak punya izin apa pun di skema proyek."
fi

echo "== 2. Tingkat internet (kunci publik)"
REF="$(printf '%s' "$DB_URL" | sed -nE 's#^postgres(ql)?://postgres\.([a-z0-9]+):.*#\2#p')"
if [ -z "$REF" ]; then
  echo "GAGAL: kode proyek tidak terbaca dari DB_URL." >&2
  exit 1
fi
BASIS="${BASIS_API:-https://$REF.supabase.co}"  # BASIS_API hanya untuk uji lokal

minta() { # $1 = metode, $2 = alamat, $3 = badan (boleh kosong), sisanya = kepala tambahan; mencetak "kode|isi"
  local metode="$1" alamat="$2" badan="$3"; shift 3
  local isi kode args=()
  for h in "$@"; do args+=(-H "$h"); done
  if [ -n "$badan" ]; then args+=(--data "$badan"); fi
  isi="$(mktemp)"
  kode="$(curl -s -o "$isi" -w '%{http_code}' -m 30 -X "$metode" -H "apikey: $KUNCI" "${args[@]}" "$BASIS$alamat" || true)"
  echo "$kode|$(head -c 200 "$isi" | tr '\n' ' ')"
}

kontrol="$(minta GET /auth/v1/settings "")"
if [ "${kontrol%%|*}" != "200" ]; then
  echo "GAGAL: kunci publik tidak diterima di /auth/v1/settings (HTTP ${kontrol%%|*}); uji tolak tidak bisa dipercaya." >&2
  exit 1
fi
echo "Kontrol: kunci publik diterima (HTTP 200)."

periksa_tolak() { # $1 = nama, $2 = hasil "kode|isi"
  local kode="${2%%|*}" isi="${2#*|}"
  if [ "$kode" = "000" ] || [ "${kode:0:1}" = "5" ]; then
    echo "GAGAL: $1 -> HTTP $kode (tidak tersambung atau Supabase bermasalah; tidak bisa disimpulkan)." >&2
    GAGAL=1
  elif [ "${kode:0:1}" = "2" ]; then
    echo "GAGAL: $1 -> HTTP $kode, TIDAK ditolak. Jawaban: $isi" >&2
    GAGAL=1
  else
    echo "LULUS: $1 -> ditolak (HTTP $kode)."
  fi
}

periksa_tolak "baca data karyawan (induk.karyawan)" \
  "$(minta GET '/rest/v1/karyawan?select=*&limit=1' "" 'Accept-Profile: induk')"
periksa_tolak "baca riwayat gaji (induk.karyawan_riwayat)" \
  "$(minta GET '/rest/v1/karyawan_riwayat?select=*&limit=1' "" 'Accept-Profile: induk')"
periksa_tolak "baca aturan (aturan.pengaturan)" \
  "$(minta GET '/rest/v1/pengaturan?select=*&limit=1' "" 'Accept-Profile: aturan')"
periksa_tolak "tambah kiriman file (fakta.kiriman_file)" \
  "$(minta POST '/rest/v1/kiriman_file' '{}' 'Content-Profile: fakta' 'Content-Type: application/json' 'Prefer: return=minimal')"
periksa_tolak "panggil fungsi karyawan_pada" \
  "$(minta POST '/rest/v1/rpc/karyawan_pada' '{"p_id":"10001","p_tanggal":"2026-01-21"}' 'Content-Profile: induk' 'Content-Type: application/json')"

if [ "$GAGAL" -ne 0 ]; then
  exit 1
fi
echo "Semua permintaan tanpa login ditolak."
