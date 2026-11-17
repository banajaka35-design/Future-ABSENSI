#!/usr/bin/env bash
# Memasukkan file mesin simulasi (Pabrik A bawaan, atau B) lewat pembaca file yang sama dengan sistem (sistem/urai),
# lalu lewat pintu masuk fakta.terima_kiriman. Tidak mengisi tabel langsung.
# Waktu diterima meniru HRD: file utama dikirim tengah malam setelah tutup buku, file lanjutan
# (tap pagi hari berikutnya) dikirim jam 13.30, sesudah batas jam 13.00 (PRD bagian 7, kasus B11).
# Pemakaian: DB_URL=... db/data_awal/muat_tap_simulasi.sh [ekspor|ekspor_utama|attlog] [A|B]
#   ekspor (bawaan): file ekspor aplikasi (mesin/*.csv.gz) beserta file lanjutan
#   ekspor_utama dan attlog: hanya file utama, keduanya diterima tengah malam, untuk uji U6
#   (tap yang sama dalam dua bentuk file harus memberi hasil yang sama persis)
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${DB_URL:?DB_URL belum diisi}"
BENTUK="${1:-ekspor}"
PABRIK="${2:-A}"
AKAR=data/simulasi/$PABRIK
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -t -A)

# periode -> tanggal kirim (sehari setelah tutup buku)
if [ "$PABRIK" = "A" ]; then
  declare -A KIRIM=([1]=2026-02-21 [2]=2026-03-21 [3]=2026-04-21 [4]=2026-12-21)
  MESIN=(MA1 MA2)
else
  declare -A KIRIM=([1]=2026-03-01 [2]=2026-04-01 [3]=2026-05-01 [4]=2027-01-01)
  MESIN=(MB1)
fi

for p in 1 2 3 4; do
  for m in "${MESIN[@]}"; do
    if [ "$BENTUK" = "attlog" ]; then
      node sistem/urai/kirim.ts --mesin "$m" --diterima "${KIRIM[$p]} 00:00:00+07" "$AKAR/attlog/${PABRIK}_p${p}_${m}.dat.gz" | "${PSQL[@]}"
    elif [ "$BENTUK" = "ekspor_utama" ]; then
      node sistem/urai/kirim.ts --mesin "$m" --diterima "${KIRIM[$p]} 00:00:00+07" "$AKAR/mesin/${PABRIK}_p${p}_${m}.csv.gz" | "${PSQL[@]}"
    else
      node sistem/urai/kirim.ts --mesin "$m" --diterima "${KIRIM[$p]} 00:00:00+07" "$AKAR/mesin/${PABRIK}_p${p}_${m}.csv.gz" | "${PSQL[@]}"
      node sistem/urai/kirim.ts --mesin "$m" --diterima "${KIRIM[$p]} 13:30:00+07" "$AKAR/mesin/${PABRIK}_p${p}_${m}_lanjutan.csv.gz" | "${PSQL[@]}"
    fi
  done
done
