#!/usr/bin/env bash
# Menjalankan semua migrasi dari nol lalu semua uji, di database sementara.
# Pemakaian: DB_URL=postgresql://postgres:postgres@localhost:5432/postgres db/uji/jalankan.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/postgres}"
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -f db/uji/persiapan_peran.sql
for f in db/migrasi/*.sql; do
  echo "Migrasi: $f"
  "${PSQL[@]}" -f "$f"
done
"${PSQL[@]}" -f db/uji/alat.sql
LOG="$(mktemp)"
for f in db/uji/[0-9]*.sql; do
  echo "Uji: $f"
  "${PSQL[@]}" -t -o /dev/null -f "$f" 2>&1 | sed -E 's/^psql:[^ ]+ (NOTICE|WARNING):  /  /' | tee -a "$LOG"
done

LULUS=$(grep -c "LULUS" "$LOG" || true)
GAGAL=$(grep -c "GAGAL" "$LOG" || true)
echo
echo "Hasil: $LULUS lulus, $GAGAL gagal."
if [ "$GAGAL" -ne 0 ] || [ "$LULUS" -eq 0 ]; then
  exit 1
fi
