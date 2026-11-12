#!/usr/bin/env bash
# Pemasangan ke database utama (Supabase), dipakai oleh workflow pasang-supabase.
# Dua bagian, dijalankan terpisah supaya cadangan sudah tersimpan sebelum apa pun diubah (aturan F13):
#   DB_URL=... db/pasang_supabase.sh cadangan <file>   -> salin skema milik proyek ke <file>
#   DB_URL=... db/pasang_supabase.sh pasang            -> migrasi, data awal bila kosong, pemeriksaan
# Pengaman ada di skrip ini sendiri, bukan di pengaturan koneksi: lewat Session pooler,
# pengaturan seperti default_transaction_read_only diabaikan (lihat docs/serah-terima.md).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?DB_URL belum diisi}"

SKEMA=(induk aturan fakta hitung jejak api)
PSQL=(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1)
nilai() { "${PSQL[@]}" -t -A -c "$1"; }
SKEMA_SQL="array['$(IFS=,; echo "${SKEMA[*]}" | sed "s/,/','/g")']"

cadangan() {
  local file="${1:?nama file cadangan belum diisi}"
  local ada
  ada="$(nilai "select string_agg(nspname, ' ' order by nspname) from pg_namespace where nspname = any($SKEMA_SQL)")"
  if [ -z "$ada" ]; then
    echo "Database belum berisi skema proyek; tidak ada yang perlu dicadangkan."
    echo "database kosong saat dicadangkan" > "$file.kosong.txt"
    return
  fi
  local args=()
  for s in $ada; do args+=(-n "$s"); done
  echo "Mencadangkan skema: $ada"
  pg_dump "$DB_URL" -Fc "${args[@]}" -f "$file"
  local isi
  isi="$(pg_restore -l "$file" | grep -c "TABLE DATA" || true)"
  if [ "$isi" -eq 0 ]; then
    echo "GAGAL: file cadangan tidak berisi data tabel." >&2
    exit 1
  fi
  echo "Cadangan selesai: $(du -h "$file" | cut -f1), $isi tabel berisi data."
}

# Hitung berapa tabel dalam daftar yang kosong dan yang berisi. Hasil: "kosong berisi".
periksa_isi() {
  local kosong=0 berisi=0 n t
  for t in "$@"; do
    n="$(nilai "select count(*) from $t")"
    if [ "$n" -eq 0 ]; then kosong=$((kosong + 1)); else berisi=$((berisi + 1)); fi
    echo "  $t: $n baris" >&2
  done
  echo "$kosong $berisi"
}

muat_bila_kosong() {
  # $1 = nama bagian, $2 = perintah pemuat, sisanya = tabel yang diisi bagian itu
  local nama="$1" pemuat="$2"; shift 2
  local hasil kosong berisi
  hasil="$(periksa_isi "$@")"
  kosong="${hasil% *}"; berisi="${hasil#* }"
  if [ "$berisi" -eq 0 ]; then
    echo "Muat $nama (semua tabelnya kosong)."
    eval "$pemuat"
  elif [ "$kosong" -eq 0 ]; then
    echo "Lewati $nama (semua tabelnya sudah berisi; kelengkapannya diperiksa di langkah pemeriksaan)."
  else
    echo "GAGAL: $nama setengah ada ($berisi tabel berisi, $kosong kosong). Tidak dilanjutkan; periksa manual." >&2
    exit 1
  fi
}

pasang() {
  echo "== Migrasi"
  db/pasang.sh

  echo "== Data awal Pabrik A"
  muat_bila_kosong "struktur Pabrik A" \
    '"${PSQL[@]}" -o /dev/null -f db/data_awal/pabrik_a_struktur.sql' \
    induk.mesin induk.divisi induk.kalender aturan.pengali_lembur aturan.pengaturan
  muat_bila_kosong "karyawan Pabrik A" \
    'python3 db/data_awal/muat_karyawan.py A | "${PSQL[@]}" -o /dev/null' \
    induk.karyawan induk.karyawan_riwayat induk.status_kerja induk.penugasan_regu induk.pemetaan_id_mesin

  echo "== Pemeriksaan data awal"
  # Alat uji tidak boleh tertinggal di database utama: dipasang dan dijalankan dalam satu transaksi
  # yang dibatalkan di akhir.
  local log
  log="$(mktemp)"
  { echo "begin;"; cat db/uji/alat.sql db/data_awal/cek_data_awal.sql; echo "rollback;"; } \
    | "${PSQL[@]}" -t -o /dev/null 2>&1 | sed -E 's/^psql:[^ ]+ (NOTICE|WARNING):  /  /' | tee "$log"
  local lulus gagal
  lulus="$(grep -c "LULUS" "$log" || true)"
  gagal="$(grep -c "GAGAL" "$log" || true)"
  if [ "$(nilai "select to_regnamespace('uji') is null")" != "t" ]; then
    echo "GAGAL: skema uji tertinggal di database utama." >&2
    exit 1
  fi
  echo "Pemeriksaan: $lulus lulus, $gagal gagal."

  echo "== Jumlah baris per tabel"
  "${PSQL[@]}" -c "
    select n.nspname || '.' || c.relname as tabel,
           (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname),
                                                false, true, '')))[1]::text::bigint as baris
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p') and not c.relispartition and n.nspname = any($SKEMA_SQL)
    order by 1"

  if [ "$gagal" -ne 0 ] || [ "$lulus" -eq 0 ]; then
    exit 1
  fi
}

case "${1:-}" in
  cadangan) cadangan "${2:-}" ;;
  pasang) pasang ;;
  *) echo "Pemakaian: db/pasang_supabase.sh cadangan <file> | pasang" >&2; exit 2 ;;
esac
