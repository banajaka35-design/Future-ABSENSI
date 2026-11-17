#!/usr/bin/env bash
# Uji pintu Telegram (paket 5b; pemberitahuan dan pengingat paket 5c): database baru berisi struktur, karyawan, dan periode Pabrik A tanpa tap,
# lalu sistem/pintu/uji_pintu.ts mengirim pesan Telegram tiruan. Pemakaian:
#   ADMIN_URL=postgresql://postgres:postgres@localhost:5432/postgres sistem/uji/uji_pintu.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ADMIN_URL="${ADMIN_URL:-postgresql://postgres:postgres@localhost:5432/postgres}"
psql "$ADMIN_URL" -X -q -c "drop database if exists uji_pintu" -c "create database uji_pintu" 2> /dev/null
export DB_URL="${ADMIN_URL%/*}/uji_pintu"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/uji/persiapan_peran.sql
db/pasang.sh > /dev/null
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/data_awal/pabrik_a_struktur.sql
python3 db/data_awal/muat_karyawan.py A | psql "$DB_URL" -X -q -o /dev/null -v ON_ERROR_STOP=1
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/data_awal/pabrik_a_tahap3.sql
node --test --test-concurrency=1 sistem/pintu/uji_pintu.ts
# Uji penyambung Edge Function dengan postgres.js sungguhan (paket 5c, kasus S1). Butuh paket npm postgres@3.4.5
# (workflow Uji database memasangnya). Di GitHub (CI=true) wajib jalan; di komputer lain dilewati bila belum terpasang.
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -c "alter role pintu password 'uji-pintu'"
if node --input-type=module -e "await import('postgres')" 2> /dev/null; then
  PINTU_URL="$(python3 -c 'import sys, urllib.parse as u; p = u.urlsplit(sys.argv[1]); print(p._replace(netloc=f"pintu:uji-pintu@{p.hostname}:{p.port or 5432}").geturl())' "$DB_URL")" \
    node --test --test-concurrency=1 sistem/pintu/uji_sambung.ts
elif [ "${CI:-}" = "true" ]; then
  echo "GAGAL: paket npm postgres belum terpasang; uji penyambung tidak bisa dijalankan." >&2
  exit 1
else
  echo "Uji penyambung dilewati: paket npm postgres belum terpasang (npm install --no-save postgres@3.4.5)."
fi
[ -n "${SIMPAN_DB:-}" ] || psql "$ADMIN_URL" -X -q -c "drop database if exists uji_pintu"
