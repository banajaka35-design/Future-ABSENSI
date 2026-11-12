#!/usr/bin/env bash
# Mengosongkan skema proyek di database, supaya bisa dipasang ulang dari nol dengan db/pasang_supabase.sh.
# HANYA untuk pemasangan demo (data simulasi). Jejak perubahan ikut terhapus, jadi tidak boleh dipakai
# untuk perusahaan sungguhan. Pengaman: ditolak kalau ada satu saja karyawan di database yang bukan
# karyawan karangan dari data/simulasi (Pabrik A dan B, cocok ID dan nama).
# Cadangan wajib diambil lebih dulu oleh pemanggil (workflow "Reset Supabase").
# Pemakaian: DB_URL=... db/reset_supabase.sh kosongkan
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?DB_URL belum diisi}"
if [ "${1:-}" != "kosongkan" ]; then
  echo "Pemakaian: db/reset_supabase.sh kosongkan" >&2
  exit 2
fi
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1)
SKEMA="induk, aturan, fakta, hitung, jejak, api"

echo "== Pengaman: semua karyawan harus karangan"
if [ "$("${PSQL[@]}" -t -A -c "select to_regclass('induk.karyawan') is not null")" = "t" ]; then
  ASING="$({
    echo "create temp table simulasi (id text, nama text);"
    echo "copy simulasi from stdin;"
    python3 - <<'EOF'
import csv, glob
for f in sorted(glob.glob("data/simulasi/*/induk/karyawan.csv")):
    for r in csv.DictReader(open(f, encoding="utf-8", newline="")):
        print(f"{r['id']}\t{r['nama']}")
EOF
    echo "\\."
    echo "select count(*) from induk.karyawan k where not exists (select 1 from simulasi s where s.id = k.id and s.nama = k.nama);"
  } | "${PSQL[@]}" -t -A)"
  if [ "$ASING" != "0" ]; then
    echo "GAGAL: ada $ASING karyawan yang bukan data simulasi. Reset ditolak; database ini bukan demo." >&2
    exit 1
  fi
  echo "Semua karyawan di database adalah data simulasi."
else
  echo "Tabel karyawan belum ada."
fi

echo "== Kosongkan skema proyek ($SKEMA)"
"${PSQL[@]}" -1 -c "set local client_min_messages = warning" -c "drop schema if exists $SKEMA cascade"
SISA="$("${PSQL[@]}" -t -A -c "select count(*) from pg_namespace where nspname in ('induk','aturan','fakta','hitung','jejak','api')")"
if [ "$SISA" != "0" ]; then
  echo "GAGAL: masih ada $SISA skema proyek setelah dikosongkan." >&2
  exit 1
fi
echo "Skema proyek kosong."
