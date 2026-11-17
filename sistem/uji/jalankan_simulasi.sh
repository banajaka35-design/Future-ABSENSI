#!/usr/bin/env bash
# Uji dengan data simulasi lengkap Pabrik A dan Pabrik B (4 periode masing-masing), di database Postgres sementara.
#   U1  hasil per orang per hari vs kunci jawaban (dengan koreksi jam mesin dan tanpa koreksi)
#   U4  file sama dikirim dua kali tidak dobel; kiriman salah dibatalkan tanpa sisa
#   U6  file ekspor aplikasi dan attlog.dat dengan tap yang sama memberi hasil yang sama persis
#   Sidik: dua kali hitung dengan masukan sama menghasilkan sidik yang sama
#   U5  Pabrik B dengan kode yang sama: U1, U2 (pembanding), U3
#   U10 anomali gaji yang ditanam di salinan data uji tertangkap
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
echo "  Lama hitung per periode (ms): $(nilai "select string_agg(lama_ms::text, ' ' order by periode_id) from hitung.versi_hitung where jenis = 'baca_tap'")"
if python3 sistem/uji/u1_banding.py A; then cek "U1 dengan koreksi jam mesin" lulus lulus; else cek "U1 dengan koreksi jam mesin" gagal lulus; fi

echo "== Hitung gaji (paket 4b-1)"
nilai "select count(hitung.hitung_gaji(id)) from fakta.periode" > /dev/null
echo "  Lama hitung gaji per periode (ms): $(nilai "select string_agg(lama_ms::text, ' ' order by periode_id) from hitung.versi_hitung where jenis = 'hitung_gaji'")"
if python3 sistem/uji/u2_pembanding.py; then cek "U2 versi mesin: kalkulator pembanding sama dengan sistem sampai rupiah" lulus lulus;
else cek "U2 versi mesin: kalkulator pembanding sama dengan sistem sampai rupiah" gagal lulus; fi
CEK_GAJI="$({ echo "begin;"; cat db/uji/alat.sql db/data_awal/cek_gaji.sql db/data_awal/cek_tahap3.sql; echo "rollback;"; } \
  | psql "$DB_URL" -X -q -t -o /dev/null 2>&1 || true)"
echo "$CEK_GAJI" | sed -E 's/^psql:[^ ]+ (NOTICE|WARNING):  /  /' | grep -E "LULUS|GAGAL|hasil:" || true
cek "pemeriksaan gaji dan tahap 3 sesudah hitung gaji tanpa GAGAL" "$(echo "$CEK_GAJI" | grep -c GAGAL || true)" 0
P1G="$(nilai "select min(id) from fakta.periode")"
nilai "select hitung.hitung_gaji($P1G)" > /dev/null
cek "dua kali hitung gaji menghasilkan sidik yang sama" \
  "$(nilai "select count(distinct sidik_hasil) from hitung.versi_hitung where periode_id = $P1G and jenis = 'hitung_gaji'")" 1

echo "== Sidik"
P1="$(nilai "select min(id) from fakta.periode")"
nilai "select hitung.baca_tap($P1)" > /dev/null
cek "dua kali hitung menghasilkan sidik hasil yang sama" \
  "$(nilai "select count(distinct sidik_hasil) from hitung.versi_hitung where periode_id = $P1 and jenis = 'baca_tap'")" 1

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

echo "== U5: Pabrik B dengan kode yang sama (180 karyawan, 4 periode bulan kalender)"
psql "$ADMIN_URL" -X -q -c "drop database if exists uji_sim_b" -c "create database uji_sim_b" 2> /dev/null
export DB_URL="$DASAR/uji_sim_b"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/uji/persiapan_peran.sql
db/pasang.sh > /dev/null
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f db/data_awal/pabrik_b_struktur.sql
python3 db/data_awal/muat_karyawan.py B | psql "$DB_URL" -X -q -o /dev/null -v ON_ERROR_STOP=1
python3 db/data_awal/muat_masukan_hrd.py B | psql "$DB_URL" -X -q -o /dev/null -v ON_ERROR_STOP=1
db/data_awal/muat_tap_simulasi.sh ekspor B > /dev/null
nilai "select count(hitung.baca_tap(id)) from fakta.periode" > /dev/null
echo "  Jumlah: $(nilai "select count(*) from fakta.tap_mentah") tap mentah, \
$(nilai "select count(*) from hitung.hasil_harian h join hitung.versi_terakhir v on v.id = h.versi_id") hari-orang, \
$(nilai "select count(*) from fakta.perintah_hrd where jenis = 'setujui_lembur'") persetujuan lembur"
if python3 sistem/uji/u1_banding.py B; then cek "U5/U1 Pabrik B: hasil per orang per hari vs kunci jawaban" lulus lulus;
else cek "U5/U1 Pabrik B: hasil per orang per hari vs kunci jawaban" gagal lulus; fi
nilai "select count(hitung.hitung_gaji(id)) from fakta.periode" > /dev/null
if python3 sistem/uji/u2_pembanding.py; then cek "U5/U2 Pabrik B: kalkulator pembanding sama dengan sistem sampai rupiah" lulus lulus;
else cek "U5/U2 Pabrik B: kalkulator pembanding sama dengan sistem sampai rupiah" gagal lulus; fi
CEK_B="$({ echo "begin;"; cat db/uji/alat.sql db/data_awal/cek_gaji.sql; echo "rollback;"; } | psql "$DB_URL" -X -q -t -o /dev/null 2>&1 || true)"
echo "$CEK_B" | sed -E 's/^psql:[^ ]+ (NOTICE|WARNING):  /  /' | grep -E "LULUS|GAGAL|hasil:" || true
cek "U5/U3 Pabrik B: pemeriksaan gaji tanpa GAGAL" "$(echo "$CEK_B" | grep -c GAGAL || true)" 0
cek "U5 Pabrik B: lembur tanpa perintah tidak dibayar dan diberi tanda (pengaturan wajib perintah)" \
  "$(nilai "select count(*) > 0 from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
            where v.jenis = 'hitung_gaji' and 'lembur_tidak_dibayar_tanpa_izin' = any(g.peringatan)")" t
cek "U5 Pabrik B: cuti bersama 24 Des 2026 tidak memotong cuti (cuti terpakai Desember = hari cuti saja)" \
  "$(nilai "select (select sum(g.cuti_terpakai) from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
                    join fakta.periode p on p.id = v.periode_id where v.jenis = 'hitung_gaji' and p.tanggal_awal = '2026-12-01')
                 = (select count(*) from hitung.hasil_harian h join hitung.versi_terakhir v on v.id = h.versi_id
                    join fakta.periode p on p.id = v.periode_id where p.tanggal_awal = '2026-12-01' and h.status = 'cuti')")" t

echo "== U10: anomali gaji (Pabrik B, periode April; tanda bawaan tanpa ditanam dicatat sebagai pembanding)"
for p in 2026-03-01 2026-04-01 2026-12-01; do
  echo "  Tanda sebelum ditanam, periode $p: $(nilai "select coalesce(string_agg(jenis || ' ' || n, ', ' order by jenis), 'tidak ada')
    from (select jenis, count(*) n from hitung.anomali_gaji((select id from fakta.periode where tanggal_awal = '$p')) group by jenis) x")"
done
psql "$DB_URL" -X -q -o /dev/null -v ON_ERROR_STOP=1 -f sistem/uji/tanam_anomali.sql
for j in gaji_berubah lembur_divisi_naik aktif_tanpa_tap; do
  K="$(nilai "select kunci from public.tanam_anomali where jenis = '$j'")"
  cek "U10 $j ($K) belum bertanda sebelum ditanam" "$(nilai "select sebelum from public.tanam_anomali where jenis = '$j'")" f
  cek "U10 $j ($K) tertangkap sesudah ditanam" "$(nilai "select exists (select 1 from hitung.anomali_gaji((select id from fakta.periode
      where tanggal_awal = '2026-04-01')) a where a.jenis = '$j' and (a.id_karyawan = '$K' or a.divisi = '$K'))")" t
done
echo "  Isi tanda: $(nilai "select string_agg(a.keterangan, ' | ') from hitung.anomali_gaji((select id from fakta.periode
  where tanggal_awal = '2026-04-01')) a join public.tanam_anomali t on t.jenis = a.jenis and (a.id_karyawan = t.kunci or a.divisi = t.kunci)")"
if python3 sistem/uji/u2_pembanding.py > /dev/null; then cek "U10: sesudah ditanam, pembanding tetap sama dengan sistem" lulus lulus;
else cek "U10: sesudah ditanam, pembanding tetap sama dengan sistem" gagal lulus; fi

for db in uji_sim_a uji_sim_tanpa_koreksi uji_sim_ekspor uji_sim_attlog uji_sim_b; do
  psql "$ADMIN_URL" -X -q -c "drop database if exists $db"
done
echo
echo "Hasil uji simulasi: $LULUS lulus, $GAGAL gagal."
[ "$GAGAL" -eq 0 ]
