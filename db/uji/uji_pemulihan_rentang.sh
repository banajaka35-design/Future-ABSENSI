#!/usr/bin/env bash
# Uji paket E2 (docs/rencana-e2.md): db/uji_pemulihan.sh dengan hitungan sumber sebelum/sesudah cadangan.
# Memakai database sumber tiruan kecil (satu tabel di skema fakta), bukan Supabase.
# Pemakaian: ADMIN_URL=postgresql://postgres:postgres@localhost:5432/postgres db/uji/uji_pemulihan_rentang.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${ADMIN_URL:?ADMIN_URL belum diisi}"
LULUS=0
GAGAL=0
cek() {  # cek "nama" hasil harapan
  if [ "$2" = "$3" ]; then echo "  LULUS  $1"; LULUS=$((LULUS + 1));
  else echo "  GAGAL  $1 (hasil: $2, harapan: $3)"; GAGAL=$((GAGAL + 1)); fi
}
T="$(mktemp -d)"
DASAR="${ADMIN_URL%/*}"
SUMBER_URL="$DASAR/e2_sumber"
TUJUAN_URL="$DASAR/e2_tujuan"
export SUMBER_URL TUJUAN_URL
bersih() { psql "$ADMIN_URL" -X -q -c "drop database if exists e2_sumber" -c "drop database if exists e2_tujuan" > /dev/null 2>&1 || true; rm -rf "$T"; }
trap bersih EXIT
q() { psql "$1" -X -q -t -A -v ON_ERROR_STOP=1 -c "$2"; }
hitung() { psql "$SUMBER_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f db/hitung_baris.sql > "$1"; }
tujuan_baru() {
  psql "$ADMIN_URL" -X -q -c "drop database if exists e2_tujuan" -c "create database e2_tujuan" > /dev/null
}
pulihkan() {  # pulihkan <berkas-log>; mencetak lulus/gagal
  tujuan_baru
  if db/uji_pemulihan.sh "$T/cadangan.dump" > "$1" 2>&1; then echo lulus; else echo gagal; fi
}

psql "$ADMIN_URL" -X -q -c "drop database if exists e2_sumber" -c "create database e2_sumber" > /dev/null
q "$SUMBER_URL" "create schema fakta; create table fakta.minta_gaji (id int primary key); create table fakta.tetap (id int primary key);
  insert into fakta.minta_gaji select generate_series(1, 3); insert into fakta.tetap select generate_series(1, 4)"

echo "== E2: uji pemulihan dengan rentang sebelum/sesudah cadangan"
hitung "$T/sebelum.txt"
pg_dump "$SUMBER_URL" -Fc -n fakta --no-owner --no-privileges -f "$T/cadangan.dump"
q "$SUMBER_URL" "insert into fakta.minta_gaji values (4), (5)"   # bot menulis selama cadangan diambil
hitung "$T/sesudah.txt"

# (a) cadangan utuh, baris baru masuk sesudahnya -> lulus dengan catatan
H="$(BARIS_SEBELUM="$T/sebelum.txt" BARIS_SESUDAH="$T/sesudah.txt" pulihkan "$T/a.log")"
cek "E2a: baris baru selama cadangan -> LULUS" "$H" lulus
cek "E2a: tabel yang berubah dicatat" "$(grep -c '^Catatan: fakta.minta_gaji berubah selama cadangan diambil (3 -> 5)' "$T/a.log" || true)" 1
cek "E2a: tabel yang tidak berubah tidak dicatat" "$(grep -c 'Catatan: fakta.tetap' "$T/a.log" || true)" 0

# (b) cadangan kehilangan baris: sumber 5 sebelum dan sesudah, hasil pemulihan 3 -> gagal
H="$(BARIS_SEBELUM="$T/sesudah.txt" BARIS_SESUDAH="$T/sesudah.txt" pulihkan "$T/b.log")"
cek "E2b: baris hilang dari cadangan -> GAGAL" "$H" gagal
cek "E2b: pesan menyebut tabelnya" "$(grep -c 'GAGAL: fakta.minta_gaji hasil pemulihan 3 baris, sumber 5 (sebelum) dan 5 (sesudah)' "$T/b.log" || true)" 1

# (c) cara lama (tanpa file hitungan), sumber berubah sesudah cadangan -> gagal seperti dulu
H="$(pulihkan "$T/c.log")"
cek "E2c: cara lama, sumber berubah -> GAGAL" "$H" gagal

# (d) hanya satu file hitungan -> gagal, tidak diam-diam memakai cara lain
H="$(BARIS_SEBELUM="$T/sebelum.txt" pulihkan "$T/d.log")"
cek "E2d: hanya BARIS_SEBELUM -> GAGAL" "$H" gagal

# (e) tabel ada di sumber tetapi tidak ada di cadangan -> gagal
cp "$T/sebelum.txt" "$T/sebelum_lebih.txt"; echo "fakta.hilang|7" >> "$T/sebelum_lebih.txt"
cp "$T/sesudah.txt" "$T/sesudah_lebih.txt"; echo "fakta.hilang|7" >> "$T/sesudah_lebih.txt"
H="$(BARIS_SEBELUM="$T/sebelum_lebih.txt" BARIS_SESUDAH="$T/sesudah_lebih.txt" pulihkan "$T/e.log")"
cek "E2e: tabel hilang dari cadangan -> GAGAL" "$H" gagal
cek "E2e: pesan menyebut tabelnya" "$(grep -c 'GAGAL: tabel fakta.hilang ada di sumber' "$T/e.log" || true)" 1

# (f) sumber tidak berubah, cara lama -> lulus (cara lama tetap jalan)
q "$SUMBER_URL" "delete from fakta.minta_gaji where id > 3"
H="$(pulihkan "$T/f.log")"
cek "E2f: cara lama, sumber sama -> LULUS" "$H" lulus

echo "== Hasil: $LULUS lulus, $GAGAL gagal"
[ "$GAGAL" -eq 0 ]
