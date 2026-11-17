#!/usr/bin/env bash
# Membuktikan cadangan bisa dipulihkan: isi cadangan dimasukkan ke database kosong,
# lalu jumlah baris setiap tabel dibandingkan dengan database sumber. Satu galat = gagal.
# Pemakaian: SUMBER_URL=... TUJUAN_URL=... db/uji_pemulihan.sh <file-cadangan>
#   SUMBER_URL = database yang dicadangkan (hanya dibaca)
#   TUJUAN_URL = database kosong sementara (Postgres 17), bukan Supabase
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SUMBER_URL:?SUMBER_URL belum diisi}"
: "${TUJUAN_URL:?TUJUAN_URL belum diisi}"
FILE="${1:?file cadangan belum diisi}"

if [ "$(psql "$TUJUAN_URL" -X -t -A -c "select count(*) from pg_namespace where nspname in ('induk','aturan','fakta','hitung','jejak','api')")" != "0" ]; then
  echo "GAGAL: database tujuan tidak kosong. Uji pemulihan hanya boleh ke database sementara." >&2
  exit 1
fi

echo "== Siapkan database kosong seperti Supabase"
# Peran Supabase dan ekstensi btree_gist di skema extensions tidak ikut dicadangkan (lihat docs/serah-terima.md).
psql "$TUJUAN_URL" -X -q -v ON_ERROR_STOP=1 -f db/uji/persiapan_peran.sql
psql "$TUJUAN_URL" -X -q -v ON_ERROR_STOP=1 -f db/peran_proyek.sql
psql "$TUJUAN_URL" -X -q -v ON_ERROR_STOP=1 \
  -c "create schema if not exists extensions" \
  -c "create extension if not exists btree_gist with schema extensions"

echo "== Pulihkan cadangan (berhenti pada galat pertama)"
pg_restore -d "$TUJUAN_URL" --exit-on-error --single-transaction "$FILE"

echo "== Bandingkan jumlah baris"
SUMBER="$(mktemp)"; TUJUAN="$(mktemp)"
psql "$SUMBER_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f db/hitung_baris.sql > "$SUMBER"
psql "$TUJUAN_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f db/hitung_baris.sql > "$TUJUAN"
if ! diff -u "$SUMBER" "$TUJUAN"; then
  echo "GAGAL: jumlah baris hasil pemulihan berbeda dengan sumber (lihat selisih di atas)." >&2
  exit 1
fi
echo "Pemulihan berhasil: $(wc -l < "$SUMBER") tabel, $(awk -F'|' '{s+=$2} END {print s}' "$SUMBER") baris, semuanya sama dengan sumber."
