#!/usr/bin/env bash
# Pemasangan ke database utama (Supabase), dipakai oleh workflow pasang-supabase.
# Dua bagian, dijalankan terpisah supaya cadangan sudah tersimpan sebelum apa pun diubah (aturan F13):
#   DB_URL=... db/pasang_supabase.sh cadangan <file>   -> salin skema milik proyek ke <file>
#   DB_URL=... db/pasang_supabase.sh pasang            -> migrasi, data awal bila kosong, pemeriksaan
#   db/pasang_supabase.sh mode                         -> hanya menulis jenis pemasangan yang akan dipakai (tanpa database)
# Pengaman ada di skrip ini sendiri, bukan di pengaturan koneksi: lewat Session pooler,
# pengaturan seperti default_transaction_read_only diabaikan (lihat docs/serah-terima.md).
#
# Paket 9d: pemasangan perusahaan (PT) memakai dua isian:
#   SUSUNAN_PERUSAHAAN = file SQL susunan PT (mesin, divisi, jadwal, pengaturan, aturan perusahaan, periode pertama),
#                        bentuknya sama dengan db/data_awal/pabrik_a_struktur.sql (docs/pasang/README.md langkah 4)
#   DATA_KARYAWAN      = folder berisi karyawan.csv, pemetaan_id_mesin.csv, mutasi_regu.csv (templat docs/pasang/templat/)
# Tanpa SUSUNAN_PERUSAHAAN, isi simulasi Pabrik A hanya dimuat bila skrip berjalan di repo demo
# (GITHUB_REPOSITORY = banajaka35-design/future-absensi, diisi otomatis oleh GitHub Actions). Di repo lain pemasangan
# DITOLAK sebelum database disentuh, supaya data karangan Pabrik A tidak mungkin masuk ke database PT. Penanda ini
# sengaja bukan file di repo: salinan repo untuk PT akan ikut membawa file apa pun, tetapi nama repo-nya pasti berbeda.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_DEMO="banajaka35-design/future-absensi"

# Jenis pemasangan: "perusahaan", "demo", atau "tolak" (dengan alasan di keluaran galat).
jenis_pasang() {
  if [ -n "${SUSUNAN_PERUSAHAAN:-}" ]; then
    if [ ! -f "$SUSUNAN_PERUSAHAAN" ]; then echo "tolak: file SUSUNAN_PERUSAHAAN tidak ada: $SUSUNAN_PERUSAHAAN"; return; fi
    if [ -z "${DATA_KARYAWAN:-}" ] || [ ! -f "$DATA_KARYAWAN/karyawan.csv" ]; then
      echo "tolak: DATA_KARYAWAN harus folder berisi karyawan.csv (sekarang: '${DATA_KARYAWAN:-}')"; return
    fi
    echo "perusahaan"
  elif [ "$(echo "${GITHUB_REPOSITORY:-}" | tr '[:upper:]' '[:lower:]')" = "$REPO_DEMO" ]; then
    echo "demo"
  else
    echo "tolak: ini bukan repo demo ($REPO_DEMO) dan SUSUNAN_PERUSAHAAN belum diisi; data simulasi Pabrik A tidak dimuat"
  fi
}
if [ "${1:-}" = "mode" ]; then jenis_pasang; exit 0; fi
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

pasang_demo() {
  echo "== Migrasi"
  db/pasang.sh

  echo "== Data awal Pabrik A"
  muat_bila_kosong "struktur Pabrik A" \
    '"${PSQL[@]}" -o /dev/null -f db/data_awal/pabrik_a_struktur.sql' \
    induk.mesin induk.divisi induk.kalender aturan.pengali_lembur aturan.pengaturan
  muat_bila_kosong "karyawan Pabrik A" \
    'python3 db/data_awal/muat_karyawan.py A | "${PSQL[@]}" -o /dev/null' \
    induk.karyawan induk.karyawan_riwayat induk.status_kerja induk.penugasan_regu induk.pemetaan_id_mesin

  echo "== Data aturan resmi (kalender, batas JP; aman dijalankan berulang)"
  "${PSQL[@]}" -o /dev/null -f db/data_awal/aturan_resmi.sql

  echo "== Isian pajak awal tahun 2026 KARANGAN untuk demo (paket 8b; aman dijalankan berulang)"
  local isian_sebelum isian_sesudah
  isian_sebelum="$(nilai "select count(*) from induk.pajak_awal_tahun")"
  "${PSQL[@]}" -o /dev/null -f db/data_awal/pajak_awal_tahun_simulasi.sql
  isian_sesudah="$(nilai "select count(*) from induk.pajak_awal_tahun")"
  echo "  isian: $isian_sebelum -> $isian_sesudah baris"

  echo "== Data simulasi Tahap 3 Pabrik A"
  muat_bila_kosong "periode uji" \
    '"${PSQL[@]}" -o /dev/null -f db/data_awal/pabrik_a_tahap3.sql' \
    fakta.periode
  muat_bila_kosong "koreksi jam mesin" \
    '"${PSQL[@]}" -o /dev/null -f db/data_awal/pabrik_a_koreksi_jam.sql' \
    induk.koreksi_jam_mesin
  muat_bila_kosong "masukan HRD simulasi" \
    'python3 db/data_awal/muat_masukan_hrd.py A | "${PSQL[@]}" -o /dev/null' \
    fakta.perintah_hrd
  muat_bila_kosong "file mesin simulasi (lewat pembaca file)" \
    'db/data_awal/muat_tap_simulasi.sh ekspor > /dev/null' \
    fakta.kiriman_file fakta.tap_mentah

  echo "== Baca tap (periode yang belum punya hasil, atau hasil terakhirnya dari versi kode pembaca tap lama)"
  local p mulai daftar_baca
  # Paket 8b: periode dirilis/dikunci tidak pernah dihitung ulang (dijaga juga oleh pemicu di database).
  daftar_baca="$(nilai "select p.id from fakta.periode p
                        where p.status not in ('dirilis', 'dikunci') and (not exists (select 1 from hitung.versi_hitung v where v.periode_id = p.id and v.jenis = 'baca_tap'
                                            and v.sidik_hasil is not null)
                           or exists (select 1 from hitung.versi_terakhir v where v.periode_id = p.id and v.jenis = 'baca_tap'
                                        and v.versi_kode <> hitung.versi_kode_baca()))
                        order by p.id")"
  for p in $daftar_baca; do
    mulai=$(date +%s%N)
    "${PSQL[@]}" -t -A -o /dev/null -c "select hitung.baca_tap($p)"
    echo "  periode $p: $(( ($(date +%s%N) - mulai) / 1000000 )) ms dari server GitHub, \
$(nilai "select lama_ms from hitung.versi_hitung where periode_id = $p and jenis = 'baca_tap' order by nomor desc limit 1") ms di database"
  done

  echo "== Hitung gaji (periode tanpa hasil gaji dari baca tap terakhir dan versi kode terbaru, atau tahun bayarnya mendapat"
  echo "   isian pajak awal tahun baru; urut tanggal; periode dirilis/dikunci dilewati)"
  # Daftar diambil dulu ke variabel: galat di dalam "for ... in $(...)" tidak menghentikan skrip.
  local daftar_gaji
  daftar_gaji="$(nilai "select p.id from fakta.periode p
                        join hitung.versi_terakhir b on b.periode_id = p.id and b.jenis = 'baca_tap'
                        where p.status not in ('dirilis', 'dikunci')
                          and (not exists (select 1 from hitung.versi_terakhir g
                                          where g.periode_id = p.id and g.jenis = 'hitung_gaji' and g.versi_sumber = b.id
                                            and g.versi_kode = hitung.versi_kode_gaji())
                               or $([ "$isian_sesudah" != "$isian_sebelum" ] && echo true || echo false)
                                  and extract(year from p.tanggal_bayar) in (select tahun from induk.pajak_awal_tahun))
                        order by p.tanggal_awal")"
  for p in $daftar_gaji; do
    mulai=$(date +%s%N)
    "${PSQL[@]}" -t -A -o /dev/null -c "select hitung.hitung_gaji($p)"
    echo "  periode $p: $(( ($(date +%s%N) - mulai) / 1000000 )) ms dari server GitHub, \
$(nilai "select lama_ms from hitung.versi_hitung where periode_id = $p and jenis = 'hitung_gaji' order by nomor desc limit 1") ms di database"
  done

  # Kejadian segera yang muncul dari hitungan pemasangan (bukan dari file HRD) tidak dikirim (paket 5c).
  if [ "$(nilai "select to_regproc('fakta.tandai_kejadian_lama') is not null")" = "t" ]; then
    echo "== Kejadian segera dari pemasangan dicatat sebagai lama: $(nilai "select fakta.tandai_kejadian_lama()")"
  fi

  echo "== Pemeriksaan data awal"
  # Alat uji tidak boleh tertinggal di database utama: dipasang dan dijalankan dalam satu transaksi
  # yang dibatalkan di akhir.
  local log
  log="$(mktemp)"
  { echo "begin;"; cat db/uji/alat.sql db/data_awal/cek_data_awal.sql db/data_awal/cek_tahap3.sql db/data_awal/cek_gaji.sql; echo "rollback;"; } \
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
  "${PSQL[@]}" -f db/hitung_baris.sql

  if [ "$gagal" -ne 0 ] || [ "$lulus" -eq 0 ]; then
    exit 1
  fi
}

# Pemasangan PT (paket 9d): migrasi, susunan PT, karyawan PT, aturan pemerintah bersama. Tidak ada data simulasi,
# tidak ada isian pajak karangan, dan tidak ada baca tap/hitung gaji: periode dihitung saat file mesin pertama masuk lewat bot.
pasang_perusahaan() {
  echo "== Pemasangan perusahaan: susunan $SUSUNAN_PERUSAHAAN, data karyawan $DATA_KARYAWAN"
  echo "== Migrasi"
  db/pasang.sh

  echo "== Susunan perusahaan"
  muat_bila_kosong "susunan perusahaan" \
    '"${PSQL[@]}" -o /dev/null -f "$SUSUNAN_PERUSAHAAN"' \
    induk.mesin induk.divisi induk.kode_jadwal aturan.pengaturan fakta.periode
  echo "== Data aturan pemerintah (aman dijalankan berulang)"
  if [ "$(nilai "select count(*) from aturan.pengali_lembur")" -eq 0 ]; then
    echo "GAGAL: susunan perusahaan belum berisi pengali lembur dan BPJS (salin bagiannya dari pabrik_a_struktur.sql)." >&2
    exit 1
  fi
  "${PSQL[@]}" -o /dev/null -f db/data_awal/aturan_resmi.sql

  echo "== Karyawan perusahaan"
  muat_bila_kosong "karyawan perusahaan" \
    'python3 db/data_awal/muat_karyawan.py "$DATA_KARYAWAN" | "${PSQL[@]}" -o /dev/null' \
    induk.karyawan induk.karyawan_riwayat induk.status_kerja induk.penugasan_regu induk.pemetaan_id_mesin

  echo "== Pemeriksaan pemasangan perusahaan"
  local log lulus gagal
  log="$(mktemp)"
  { echo "begin;"; cat db/uji/alat.sql; cat <<'SQL'
select uji.sama('perusahaan: ada mesin absen', (select count(*) > 0 from induk.mesin), true);
select uji.sama('perusahaan: ada divisi', (select count(*) > 0 from induk.divisi), true);
select uji.sama('perusahaan: setiap divisi memakai mesin yang terdaftar',
  (select count(*) from induk.divisi d where not exists (select 1 from induk.mesin m where m.kode = d.mesin_utama))::int, 0);
select uji.sama('perusahaan: ada periode gaji', (select count(*) > 0 from fakta.periode), true);
select uji.sama('perusahaan: UMK terisi', (select count(*) > 0 from aturan.upah_minimum), true);
select uji.sama('perusahaan: tarif BPJS terisi', (select count(*) > 0 from aturan.bpjs), true);
select uji.sama('perusahaan: ada karyawan', (select count(*) > 0 from induk.karyawan), true);
select uji.sama('perusahaan: setiap karyawan punya riwayat gaji',
  (select count(*) from induk.karyawan k
   where not exists (select 1 from induk.karyawan_riwayat r where r.id_karyawan = k.id))::int, 0);
select uji.sama('perusahaan: setiap karyawan punya regu sejak mulai kerja',
  (select count(*) from induk.karyawan k
   join induk.status_kerja s on s.id_karyawan = k.id and s.jenis = 'mulai'
   where not exists (select 1 from induk.penugasan_regu p
                     where p.id_karyawan = k.id and daterange(p.berlaku_dari, p.berlaku_sampai, '[)') @> s.tanggal))::int, 0);
select uji.sama('perusahaan: setiap karyawan wajib tap punya ID mesin',
  (select count(*) from induk.karyawan k
   join induk.karyawan_riwayat r on r.id_karyawan = k.id and r.wajib_tap
   where not exists (select 1 from induk.pemetaan_id_mesin p where p.id_karyawan = k.id))::int, 0);
select uji.sama('perusahaan: orang bergaji rahasia dibayar transfer (aturan 8d)',
  (select count(*) from induk.karyawan_riwayat r where r.gaji_rahasia and r.cara_bayar <> 'transfer')::int, 0);
SQL
    echo "rollback;"; } | "${PSQL[@]}" -t -o /dev/null 2>&1 | sed -E 's/^(psql:[^ ]+ )?(NOTICE|WARNING):  /  /' | tee "$log"
  lulus="$(grep -c "LULUS" "$log" || true)"
  gagal="$(grep -c "GAGAL" "$log" || true)"
  if [ "$(nilai "select to_regnamespace('uji') is null")" != "t" ]; then
    echo "GAGAL: skema uji tertinggal di database utama." >&2
    exit 1
  fi
  echo "Pemeriksaan: $lulus lulus, $gagal gagal."
  echo "== Jumlah baris per tabel"
  "${PSQL[@]}" -f db/hitung_baris.sql
  if [ "$gagal" -ne 0 ] || [ "$lulus" -eq 0 ]; then exit 1; fi
}

pasang() {
  local jenis
  jenis="$(jenis_pasang)"
  case "$jenis" in
    perusahaan) pasang_perusahaan ;;
    demo) pasang_demo ;;
    *) echo "DITOLAK, database tidak disentuh. Alasan: ${jenis#tolak: }" >&2; exit 3 ;;
  esac
}

case "${1:-}" in
  cadangan) cadangan "${2:-}" ;;
  pasang) pasang ;;
  *) echo "Pemakaian: db/pasang_supabase.sh cadangan <file> | pasang | mode" >&2; exit 2 ;;
esac
