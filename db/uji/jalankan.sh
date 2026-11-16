#!/usr/bin/env bash
# Menjalankan semua migrasi dari nol lalu semua uji, di database sementara.
# Pemakaian: DB_URL=postgresql://postgres:postgres@localhost:5432/postgres db/uji/jalankan.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/postgres}"
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -f db/uji/persiapan_peran.sql
DB_URL="$DB_URL" db/pasang.sh
echo "Pasang ulang harus melewati semua migrasi:"
DB_URL="$DB_URL" db/pasang.sh | grep -c "Lewati" | xargs -I{} echo "  {} migrasi dilewati"
"${PSQL[@]}" -f db/uji/alat.sql
LOG="$(mktemp)"
for f in db/uji/[0-9]*.sql; do
  echo "Uji: $f"
  "${PSQL[@]}" -t -o /dev/null -f "$f" 2>&1 | sed -E 's/^psql:[^ ]+ (NOTICE|WARNING):  /  /' | tee -a "$LOG"
done

echo "Data awal Pabrik A:"
"${PSQL[@]}" -f db/data_awal/pabrik_a_struktur.sql
python3 db/data_awal/muat_karyawan.py A | "${PSQL[@]}" -o /dev/null
echo "Data aturan resmi (dijalankan dua kali: yang kedua tidak boleh mengubah apa pun):"
"${PSQL[@]}" -o /dev/null -f db/data_awal/aturan_resmi.sql
SEBELUM="$("${PSQL[@]}" -t -A -c "select count(*) from jejak.perubahan")"
"${PSQL[@]}" -o /dev/null -f db/data_awal/aturan_resmi.sql
SESUDAH="$("${PSQL[@]}" -t -A -c "select count(*) from jejak.perubahan")"
if [ "$SEBELUM" = "$SESUDAH" ]; then echo "  LULUS  aturan resmi: jalan kedua tidak mengubah apa pun" | tee -a "$LOG";
else echo "  GAGAL  aturan resmi: jalan kedua mengubah $((SESUDAH - SEBELUM)) baris" | tee -a "$LOG"; fi
"${PSQL[@]}" -t -o /dev/null -f db/data_awal/cek_data_awal.sql 2>&1 | sed -E 's/^psql:[^ ]+ (NOTICE|WARNING):  /  /' | tee -a "$LOG"

LULUS=$(grep -c "LULUS" "$LOG" || true)
GAGAL=$(grep -c "GAGAL" "$LOG" || true)
echo
echo "Hasil: $LULUS lulus, $GAGAL gagal."
if [ "$GAGAL" -ne 0 ] || [ "$LULUS" -eq 0 ]; then
  exit 1
fi
