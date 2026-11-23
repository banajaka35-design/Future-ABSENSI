#!/usr/bin/env bash
# Membuktikan cadangan bisa dipulihkan: isi cadangan dimasukkan ke database kosong,
# lalu jumlah baris setiap tabel dibandingkan dengan database sumber. Satu galat = gagal.
# Pemakaian: SUMBER_URL=... TUJUAN_URL=... db/uji_pemulihan.sh <file-cadangan>
#   SUMBER_URL = database yang dicadangkan (hanya dibaca)
#   TUJUAN_URL = database kosong sementara (Postgres 17), bukan Supabase
#   BARIS_SEBELUM, BARIS_SESUDAH (pilihan, paket E2) = file hasil db/hitung_baris.sql dari sumber tepat sebelum dan
#   tepat sesudah cadangan diambil. Bila ada, jumlah baris hasil pemulihan tiap tabel harus berada di antara keduanya
#   (baris yang ditulis bot selama cadangan diambil bukan kegagalan). Bila tidak ada, harus sama persis dengan sumber
#   sekarang (cara lama).
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
TUJUAN="$(mktemp)"
psql "$TUJUAN_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f db/hitung_baris.sql > "$TUJUAN"
if [ -n "${BARIS_SEBELUM:-}" ] || [ -n "${BARIS_SESUDAH:-}" ]; then
  # Paket E2: hitungan sumber diambil tepat sebelum dan sesudah cadangan, bukan saat perbandingan.
  for f in "${BARIS_SEBELUM:-}" "${BARIS_SESUDAH:-}"; do
    if [ -z "$f" ] || [ ! -s "$f" ]; then
      echo "GAGAL: BARIS_SEBELUM dan BARIS_SESUDAH harus sama-sama berisi hitungan baris sumber." >&2
      exit 1
    fi
  done
  if ! awk -F'|' '
      FNR == 1 { berkas++ }
      berkas == 1 { a[$1] = $2; next }
      berkas == 2 { b[$1] = $2; next }
      {
        t[$1] = 1
        if (!($1 in a) || !($1 in b)) { printf "GAGAL: tabel %s tidak ada di hitungan sumber\n", $1; salah = 1; next }
        lo = a[$1] + 0; hi = b[$1] + 0; if (lo > hi) { x = lo; lo = hi; hi = x }
        n = $2 + 0
        if (n < lo || n > hi) { printf "GAGAL: %s hasil pemulihan %d baris, sumber %d (sebelum) dan %d (sesudah)\n", $1, n, a[$1], b[$1]; salah = 1 }
        else if (a[$1] != b[$1]) { printf "Catatan: %s berubah selama cadangan diambil (%d -> %d); pemulihan %d baris, di dalam rentang\n", $1, a[$1], b[$1], n; ubah++ }
        jum += n
      }
      END {
        for (k in a) if (!(k in t)) { printf "GAGAL: tabel %s ada di sumber tetapi tidak ada di hasil pemulihan\n", k; salah = 1 }
        if (salah) exit 1
        printf "Pemulihan berhasil: %d tabel, %d baris, semuanya di dalam rentang sumber sebelum/sesudah cadangan (%d tabel berubah selama cadangan).\n", length(t), jum, ubah
      }' "$BARIS_SEBELUM" "$BARIS_SESUDAH" "$TUJUAN"; then
    echo "GAGAL: jumlah baris hasil pemulihan di luar rentang sumber (lihat di atas)." >&2
    exit 1
  fi
  exit 0
fi
SUMBER="$(mktemp)"
psql "$SUMBER_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f db/hitung_baris.sql > "$SUMBER"
if ! diff -u "$SUMBER" "$TUJUAN"; then
  echo "GAGAL: jumlah baris hasil pemulihan berbeda dengan sumber (lihat selisih di atas)." >&2
  exit 1
fi
echo "Pemulihan berhasil: $(wc -l < "$SUMBER") tabel, $(awk -F'|' '{s+=$2} END {print s}' "$SUMBER") baris, semuanya sama dengan sumber."
