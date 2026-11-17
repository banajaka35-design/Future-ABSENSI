#!/usr/bin/env bash
# Uji pintu Telegram (paket 5b): database baru berisi struktur, karyawan, dan periode Pabrik A tanpa tap,
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
[ -n "${SIMPAN_DB:-}" ] || psql "$ADMIN_URL" -X -q -c "drop database if exists uji_pintu"
