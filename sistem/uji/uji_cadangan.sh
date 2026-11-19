#!/usr/bin/env bash
# Uji paket E1 (docs/rencana-e1.md): db/kunci_cadangan.sh. Memakai kalimat rahasia uji, bukan secret sungguhan.
# Pulih dari cadangan sungguhan terenkripsi dibuktikan setiap malam di workflow "Cadangan malam".
# Pemakaian: sistem/uji/uji_cadangan.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
LULUS=0
GAGAL=0
cek() {  # cek "nama" hasil harapan
  if [ "$2" = "$3" ]; then echo "  LULUS  $1"; LULUS=$((LULUS + 1));
  else echo "  GAGAL  $1 (hasil: $2, harapan: $3)"; GAGAL=$((GAGAL + 1)); fi
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# File tiruan berkepala dump Postgres (PGDMP) dan berisi teks data yang mudah dicari.
{ printf 'PGDMP'; head -c 4096 /dev/urandom; printf 'GAJI-RAHASIA-10998 4999870485\n'; } > "$T/asli.dump"
cp "$T/asli.dump" "$T/salinan.dump"
SIDIK_ASLI="$(sha256sum < "$T/asli.dump")"
KUNCI_UJI="kalimat uji yang panjang untuk paket E1"

echo "== E1: kunci cadangan"
cek "E1: kunci kosong -> GAGAL" "$(CADANGAN_KUNCI='' db/kunci_cadangan.sh kunci "$T/salinan.dump" > /dev/null 2>&1 && echo lulus || echo gagal)" gagal
cek "E1: kunci kosong -> tidak ada file .gpg, file asli tidak disentuh" \
  "$([ ! -e "$T/salinan.dump.gpg" ] && [ "$(sha256sum < "$T/salinan.dump")" = "$SIDIK_ASLI" ] && echo ya || echo tidak)" ya
CADANGAN_KUNCI="$KUNCI_UJI" db/kunci_cadangan.sh kunci "$T/salinan.dump" > /dev/null
cek "E1: kunci -> file .gpg terbentuk dan file asli terhapus" \
  "$([ -s "$T/salinan.dump.gpg" ] && [ ! -e "$T/salinan.dump" ] && echo ya || echo tidak)" ya
cek "E1: file terenkripsi tanpa penanda dump Postgres" "$(grep -c -a 'PGDMP' "$T/salinan.dump.gpg" || true)" 0
cek "E1: file terenkripsi tanpa teks data" "$(grep -c -a 'GAJI-RAHASIA' "$T/salinan.dump.gpg" || true)" 0
cek "E1: file asli memang memuat penanda (pembanding uji)" "$(grep -c -a 'GAJI-RAHASIA' "$T/asli.dump")" 1
cek "E1: kalimat salah -> GAGAL tanpa file keluaran" \
  "$(CADANGAN_KUNCI='kalimat salah' db/kunci_cadangan.sh buka "$T/salinan.dump.gpg" "$T/salah.dump" > /dev/null 2>&1 && echo lulus || echo gagal)/$([ -e "$T/salah.dump" ] && echo ada || echo tidak)" gagal/tidak
CADANGAN_KUNCI="$KUNCI_UJI" db/kunci_cadangan.sh buka "$T/salinan.dump.gpg" "$T/buka.dump" > /dev/null
cek "E1: kunci -> buka menghasilkan file yang sama persis" "$(sha256sum < "$T/buka.dump")" "$SIDIK_ASLI"
cek "E1: kalimat rahasia tidak muncul di keluaran skrip" \
  "$(CADANGAN_KUNCI="$KUNCI_UJI" db/kunci_cadangan.sh buka "$T/salinan.dump.gpg" "$T/buka2.dump" 2>&1 | grep -c "$KUNCI_UJI" || true)" 0

echo "Hasil uji cadangan: $LULUS lulus, $GAGAL gagal."
[ "$GAGAL" -eq 0 ]
