#!/usr/bin/env bash
# Paket D1 (docs/rencana-d1.md): pengaman halaman demo publik. Lulus hanya bila SEMUA karyawan di database adalah
# karyawan karangan dari data/simulasi (Pabrik A dan B, cocok ID dan nama), sama dengan pengaman db/reset_supabase.sh.
# Satu saja tidak cocok -> GAGAL, keluar 1. Hanya jumlahnya yang dicetak; ID dan nama orang tidak masuk log.
# Hanya membaca database (daftar karyawan diambil lalu dicocokkan di Python). Pemakaian: DB_URL=... db/cek_hanya_simulasi.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?DB_URL belum diisi}"
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1)

# Galat sambungan menghentikan skrip di sini (set -e) dengan pesan dari psql, bukan pesan yang menyesatkan.
ADA="$("${PSQL[@]}" -t -A -c "select to_regclass('induk.karyawan') is not null")"
if [ "$ADA" != "t" ]; then
  echo "GAGAL: tabel karyawan tidak ada; halaman demo tidak diterbitkan." >&2
  exit 1
fi
DAFTAR="$(mktemp)"
trap 'rm -f "$DAFTAR"' EXIT
"${PSQL[@]}" -c "\\copy (select id, nama from induk.karyawan) to '$DAFTAR' with (format csv)"
python3 - "$DAFTAR" <<'EOF'
import csv, glob, sys
simulasi = set()
for f in sorted(glob.glob("data/simulasi/*/induk/karyawan.csv")):
    for r in csv.DictReader(open(f, encoding="utf-8", newline="")):
        simulasi.add((r["id"], r["nama"]))
if not simulasi:
    print("GAGAL: daftar karyawan simulasi kosong; pemeriksaan tidak bisa dijalankan.", file=sys.stderr)
    sys.exit(1)
db = [tuple(r) for r in csv.reader(open(sys.argv[1], encoding="utf-8", newline=""))]
asing = sum(1 for r in db if r not in simulasi)
if asing:
    print(f"GAGAL: ada {asing} karyawan yang bukan data simulasi; halaman demo publik tidak diterbitkan.", file=sys.stderr)
    sys.exit(1)
print(f"LULUS: {len(db)} karyawan di database, semuanya data simulasi ({len(simulasi)} karyawan karangan di repo).")
EOF
