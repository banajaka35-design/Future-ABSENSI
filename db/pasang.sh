#!/usr/bin/env bash
# Memasang migrasi yang belum terpasang, berurutan, masing-masing dalam satu transaksi.
# File yang sudah terpasang tetapi isinya berubah ditolak (aturan F13).
# Dipakai oleh uji otomatis dan oleh alur pemasangan ke Supabase.
# Pemakaian: DB_URL=... db/pasang.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?DB_URL belum diisi}"
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -t -A)

catat_terpasang() {
  # Catat semua file yang sudah dipasang di jalan ini, kalau tabel catatannya sudah ada.
  if [ "$("${PSQL[@]}" -c "select to_regclass('jejak.migrasi') is not null")" = "t" ]; then
    for item in "${TERPASANG[@]}"; do
      "${PSQL[@]}" -c "insert into jejak.migrasi (nama, sidik) values ('${item%%:*}', '${item##*:}') on conflict (nama) do nothing"
    done
  fi
}

TERPASANG=()
for f in db/migrasi/*.sql; do
  nama="$(basename "$f")"
  sidik="$(sha256sum "$f" | cut -d' ' -f1)"
  lama=""
  if [ "$("${PSQL[@]}" -c "select to_regclass('jejak.migrasi') is not null")" = "t" ]; then
    lama="$("${PSQL[@]}" -c "select sidik from jejak.migrasi where nama = '$nama'")"
  fi
  if [ -n "$lama" ]; then
    if [ "$lama" != "$sidik" ]; then
      echo "GAGAL: $nama sudah terpasang tetapi isinya berubah. Buat migrasi baru, jangan edit yang lama." >&2
      exit 1
    fi
    echo "Lewati (sudah terpasang): $nama"
    continue
  fi
  echo "Pasang: $nama"
  "${PSQL[@]}" -1 -f "$f"
  TERPASANG+=("$nama:$sidik")
  catat_terpasang
done
echo "Migrasi selesai."
