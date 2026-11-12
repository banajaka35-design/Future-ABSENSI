#!/usr/bin/env bash
# Uji Tahap 3 dengan data simulasi lengkap Pabrik A (4 periode), di database Postgres sementara.
#   U1  hasil per orang per hari vs kunci jawaban (dengan koreksi jam mesin dan tanpa koreksi)
#   U4  file sama dikirim dua kali tidak dobel; kiriman salah dibatalkan tanpa sisa
#   U6  file ekspor aplikasi dan attlog.dat dengan tap yang sama memberi hasil yang sama persis
#   Sidik: dua kali hitung dengan masukan sama menghasilkan sidik yang sama
# Setiap uji memakai database baru. Pemakaian:
#   ADMIN_URL=postgresql://postgres:postgres@localhost:5432/postgres sistem/uji/jalankan_simulasi.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ADMIN_URL="${ADMIN_URL:-postgresql://postgres:postgres@localhost:5432/postgres}"
DASAR="${ADMIN_URL%/*}"
LULUS=0
GAGAL=0
cek() {  # cek "nama" hasil harapan
  if [ "$2" = "$3" ]; then echo "  LULUS  $1"; LULUS=$((LULUS + 1));
  else echo "  GAGAL  $1 (hasil: $2, harapan: $3)"; GAGAL=$((GAGAL + 1)); fi
}

siapkan() {  # siapkan <nama_db> <bentuk_file> <koreksi ya|tidak>
  local db="$1"
  psql "$ADMIN_URL" -X -q -c "drop database if exists $db" -c "create database $db" 2> /dev/null
  export DB_URL="$DASAR/$db"
  psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/uji/persiapan_peran.sql
  db/pasang.sh > /dev/null
  psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/data_awal/pabrik_a_struktur.sql
  python3 db/data_awal/muat_karyawan.py A | psql "$DB_URL" -X -q -o /dev/null -v ON_ERROR_STOP=1
  psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/data_awal/pabrik_a_tahap3.sql
  if [ "$3" = "ya" ]; then psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/data_awal/pabrik_a_koreksi_jam.sql; fi
  python3 db/data_awal/muat_masukan_hrd.py A | psql "$DB_URL" -X -q -o /dev/null -v ON_ERROR_STOP=1
  db/data_awal/muat_tap_simulasi.sh "$2" > /dev/null
  psql "$DB_URL" -X -q -tA -v ON_ERROR_STOP=1 -c "select count(hitung.baca_tap(id)) from fakta.periode" > /dev/null
}
nilai() { psql "$DB_URL" -X -q -tA -v ON_ERROR_STOP=1 -c "$1"; }
SIDIK_HASIL="select md5(string_agg(concat_ws('|', h.id_karyawan, h.tanggal, h.status, h.asal, h.kode_jadwal, h.jenis_hari,
  h.masuk, h.pulang, h.menit_telat, h.menit_pulang_cepat, h.menit_lebih, h.menit_hadir, h.lupa_tap, h.ambigu,
  array_to_string(h.tanda, ',')), E'\n' order by h.id_karyawan, h.tanggal))
  from hitung.hasil_harian h join hitung.versi_terakhir v on v.id = h.versi_id"

echo "== Data lengkap (file ekspor + file lanjutan, koreksi jam mesin tercatat)"
siapkan uji_sim_a ekspor ya
echo "  Jumlah: $(nilai "select count(*) from fakta.tap_mentah") tap mentah, \
$(nilai "select count(*) from hitung.hasil_harian h join hitung.versi_terakhir v on v.id = h.versi_id") hari-orang"
echo "  Lama hitung per periode (ms): $(nilai "select string_agg(lama_ms::text, ' ' order by periode_id) from hitung.versi_hitung")"
if python3 sistem/uji/u1_banding.py A; then cek "U1 dengan koreksi jam mesin" lulus lulus; else cek "U1 dengan koreksi jam mesin" gagal lulus; fi

echo "== Sidik"
P1="$(nilai "select min(id) from fakta.periode")"
nilai "select hitung.baca_tap($P1)" > /dev/null
cek "dua kali hitung menghasilkan sidik hasil yang sama" \
  "$(nilai "select count(distinct sidik_hasil) from hitung.versi_hitung where periode_id = $P1")" 1

echo "== U4: kirim ulang dan pembatalan"
SEBELUM="$(nilai "$SIDIK_HASIL")"
TAP_SEBELUM="$(nilai "select count(*) from fakta.tap_mentah")"
HASIL_ULANG="$(node sistem/urai/kirim.ts --mesin MA1 --diterima "2026-02-21 09:00:00+07" data/simulasi/A/mesin/A_p1_MA1.csv.gz \
  | psql "$DB_URL" -X -q -tA -v ON_ERROR_STOP=1 | grep -o '"hasil": "[a-z]*"')"
cek "file yang sama dikirim dua kali ditolak" "$HASIL_ULANG" '"hasil": "ditolak"'
cek "jumlah tap mentah tidak bertambah" "$(nilai "select count(*) from fakta.tap_mentah")" "$TAP_SEBELUM"
# Kiriman salah: file mesin Pabrik B dikirim sebagai mesin MA1.
node sistem/urai/kirim.ts --mesin MA1 --diterima "2026-02-21 10:00:00+07" data/simulasi/B/mesin/B_p1_MB1.csv.gz \
  | psql "$DB_URL" -X -q -tA -v ON_ERROR_STOP=1 > /dev/null
nilai "select count(hitung.baca_tap(id)) from fakta.periode" > /dev/null
SALAH="$(nilai "$SIDIK_HASIL")"
ANOMALI_SALAH="$(nilai "select count(*) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id")"
nilai "insert into fakta.perintah_hrd (asal, jenis, nilai, alasan)
       select 'chat', 'batalkan_kiriman', id::text, 'file salah' from fakta.kiriman_file where nama_file = 'B_p1_MB1.csv'" > /dev/null
nilai "select count(hitung.baca_tap(id)) from fakta.periode" > /dev/null
SESUDAH="$(nilai "$SIDIK_HASIL")"
ANOMALI_SESUDAH="$(nilai "select count(*) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id")"
ANOMALI_AWAL="$(nilai "select count(*) from hitung.anomali a join hitung.versi_hitung v on v.id = a.versi_id where v.nomor = 1")"
echo "  anomali: awal $ANOMALI_AWAL, dengan kiriman salah $ANOMALI_SALAH, setelah dibatalkan $ANOMALI_SESUDAH"
cek "kiriman salah mengubah hasil (uji ini bermakna)" "$([ "$SALAH" != "$SEBELUM" ] || [ "$ANOMALI_SALAH" != "$ANOMALI_AWAL" ] && echo ya || echo tidak)" ya
cek "setelah dibatalkan, hasil sama persis dengan sebelum kiriman salah" "$SESUDAH" "$SEBELUM"
cek "setelah dibatalkan, anomali kembali seperti semula" "$ANOMALI_SESUDAH" "$ANOMALI_AWAL"

echo "== U1 tanpa koreksi jam mesin"
siapkan uji_sim_tanpa_koreksi ekspor tidak
if python3 sistem/uji/u1_banding.py A --tanpa-koreksi; then cek "U1 tanpa koreksi jam mesin (hasil mengikuti jam mesin)" lulus lulus;
else cek "U1 tanpa koreksi jam mesin (hasil mengikuti jam mesin)" gagal lulus; fi
echo "  Hari Kantor 1-10 Maret yang terbaca telat tanpa koreksi: \
$(nilai "select count(*) from hitung.hasil_harian h join hitung.versi_terakhir v on v.id = h.versi_id
         where h.divisi = 'KTR' and h.tanggal between '2026-03-01' and '2026-03-10' and h.menit_telat > 0")"
echo "  Peringatan jam mesin melenceng untuk MA2 (selisih 4 menit): \
$(nilai "select count(*) from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id
         where a.jenis = 'jam_mesin_melenceng' and a.mesin = 'MA2'")"

echo "== U6: ekspor aplikasi vs attlog.dat (file utama saja, diterima tengah malam)"
siapkan uji_sim_ekspor ekspor_utama ya
EKSPOR="$(nilai "$SIDIK_HASIL")"
siapkan uji_sim_attlog attlog ya
ATTLOG="$(nilai "$SIDIK_HASIL")"
cek "hasil per orang per hari sama persis" "$ATTLOG" "$EKSPOR"

for db in uji_sim_a uji_sim_tanpa_koreksi uji_sim_ekspor uji_sim_attlog; do
  psql "$ADMIN_URL" -X -q -c "drop database if exists $db"
done
echo
echo "Hasil uji simulasi: $LULUS lulus, $GAGAL gagal."
[ "$GAGAL" -eq 0 ]
