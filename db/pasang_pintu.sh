#!/usr/bin/env bash
# Pemasangan pintu Telegram (paket 5b), dijalankan workflow "Pasang ke Supabase" sesudah migrasi.
# Dilewati (bukan gagal) bila secret pintu belum diisi pemilik, supaya pemasangan lain tetap jalan.
# Yang dilakukan:
#   1. Kata sandi peran `pintu` dibuat acak di sini, dipasang ke database dan ke rahasia Edge Function. Tidak ditulis ke log.
#   2. Akun Telegram pemilik proyek (secret PEMBANGUN_TELEGRAM_ID) didaftarkan dengan hak akses `pembangun` bila belum ada.
#   3. Edge Function pintu-telegram dipasang (inti.ts dan urai.ts disalin dari sistem/ lebih dulu).
#   4. Rahasia Edge Function diisi, lalu alamat bot didaftarkan ke Telegram dengan kode rahasia baru.
#   5. Penjadwal pengingat kirim file (paket 5c, docs/pemberitahuan-segera.md): pg_net dan pg_cron dinyalakan,
#      kode rahasia pengingat (acak, baru setiap pemasangan) disimpan di Vault, fungsi jadwal.picu_pengingat dibuat,
#      dan jadwal harian 01.00 UTC (08.00 WIB) dipasang. Skema `jadwal` di luar skema proyek: tidak ikut cadangan
#      dan tidak terhapus oleh Reset Supabase.
# Butuh: DB_URL, SUPABASE_ACCESS_TOKEN, TELEGRAM_BOT_TOKEN, PEMBANGUN_TELEGRAM_ID.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?DB_URL belum diisi}"

kurang=""
[ -n "${SUPABASE_ACCESS_TOKEN:-}" ] || kurang="$kurang SUPABASE_ACCESS_TOKEN"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || kurang="$kurang TELEGRAM_BOT_TOKEN"
[ -n "${PEMBANGUN_TELEGRAM_ID:-}" ] || kurang="$kurang PEMBANGUN_TELEGRAM_ID"
if [ -n "$kurang" ]; then
  echo "Pintu Telegram dilewati: secret belum diisi:$kurang"
  exit 0
fi
if ! [[ "$PEMBANGUN_TELEGRAM_ID" =~ ^[0-9]+$ ]]; then
  echo "GAGAL: PEMBANGUN_TELEGRAM_ID harus angka." >&2
  exit 1
fi

# Nomor proyek dan alamat sambungan peran pintu, diturunkan dari DB_URL (pooler: pengguna postgres.<proyek>).
read -r REF PINTU_URL_TANPA_SANDI < <(python3 - <<'EOF'
import os, re, urllib.parse as u
p = u.urlsplit(os.environ["DB_URL"])
user = p.username or ""
ref = user.split(".", 1)[1] if "." in user else (re.match(r"db\.([a-z0-9]+)\.supabase\.co", p.hostname or "") or [None, ""])[1]
pintu = "pintu." + ref if "." in user else "pintu"
print(ref, f"postgresql://{pintu}:SANDI@{p.hostname}:{p.port or 5432}{p.path or '/postgres'}")
EOF
)
if [ -z "$REF" ]; then
  echo "GAGAL: nomor proyek Supabase tidak bisa dibaca dari DB_URL." >&2
  exit 1
fi

RUNNER_TEMP_PINTU="$(mktemp)"
SANDI="$(openssl rand -hex 24)"
RAHASIA="$(openssl rand -hex 32)"
RAHASIA_PENGINGAT="$(openssl rand -hex 32)"
echo "::add-mask::$SANDI"
echo "::add-mask::$RAHASIA"
echo "::add-mask::$RAHASIA_PENGINGAT"
PINTU_DB_URL="${PINTU_URL_TANPA_SANDI/SANDI/$SANDI}"

echo "== Peran pintu: kata sandi baru dan batas waktu perintah"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -v sandi="$SANDI" <<'EOF'
alter role pintu password :'sandi';
alter role pintu set statement_timeout = '120s';
EOF

# Paket 5d-2: sesudah kata sandi diganti, percobaan masuk pertama lewat pooler Supabase ditolak (temuan 5c dan 5d).
# Skrip ini masuk sebagai `pintu` lebih dulu sampai berhasil, supaya kegagalan itu tidak jatuh ke pesan HRD, dan
# mencatat berapa percobaan yang dibutuhkan. Edge Function juga mencoba ulang sendiri (sistem/pintu/sambung.ts).
echo "== Masuk sebagai pintu lewat pooler sampai berhasil"
berhasil=""
for ke in $(seq 1 10); do
  if PGCONNECT_TIMEOUT=10 psql "$PINTU_DB_URL" -X -q -t -A -c "select 1" > /dev/null 2> "$RUNNER_TEMP_PINTU"; then
    berhasil="$ke"
    break
  fi
  echo "  percobaan $ke ditolak: $(head -c 200 "$RUNNER_TEMP_PINTU" | tr '\n' ' ' | sed -E 's/postgresql:[^ ]*/[alamat]/g')"
  sleep 3
done
if [ -z "$berhasil" ]; then
  echo "GAGAL: peran pintu tidak bisa masuk lewat pooler sesudah 10 percobaan." >&2
  exit 1
fi
echo "  berhasil pada percobaan ke-$berhasil"

echo "== Akun pembangun"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -v tg="$PEMBANGUN_TELEGRAM_ID" <<'EOF'
begin;
set local app.pengguna = 'pasang-pintu';
insert into induk.pengguna (telegram_id, peran)
select :'tg'::bigint, 'pembangun' where not exists (select 1 from induk.pengguna where telegram_id = :'tg'::bigint);
select 'Akun pengirim file terdaftar: ' || count(*) from induk.pengguna where peran in ('hrd', 'pembangun') and aktif;
commit;
EOF

echo "== Edge Function pintu-telegram"
FUNGSI=supabase/functions/pintu-telegram
cp sistem/urai/urai.ts "$FUNGSI/urai.ts"
cp sistem/pintu/inti.ts "$FUNGSI/inti.ts"
cp sistem/pintu/sambung.ts "$FUNGSI/sambung.ts"
mulai=$(date +%s%N)
npx --yes supabase@2 functions deploy pintu-telegram --project-ref "$REF" --no-verify-jwt --use-api
echo "Lama memasang: $(( ($(date +%s%N) - mulai) / 1000000 )) ms"

BERKAS="$(mktemp)"
trap 'rm -f "$BERKAS" "$RUNNER_TEMP_PINTU"' EXIT
# ASAL_WEB: alamat halaman unggah (paket 5d); Edge Function hanya menerima unggahan web dari alamat ini.
ASAL_WEB="${ASAL_WEB:-https://future-absensi-demo.pages.dev}"
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_RAHASIA=%s\nPINTU_DB_URL=%s\nPENGINGAT_RAHASIA=%s\nASAL_WEB=%s\n' \
  "$TELEGRAM_BOT_TOKEN" "$RAHASIA" "$PINTU_DB_URL" "$RAHASIA_PENGINGAT" "$ASAL_WEB" > "$BERKAS"
npx --yes supabase@2 secrets set --project-ref "$REF" --env-file "$BERKAS"

echo "== Alamat bot di Telegram"
ALAMAT="https://$REF.supabase.co/functions/v1/pintu-telegram"
curl -fsS -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -H 'content-type: application/json' \
  -d "{\"url\": \"$ALAMAT\", \"secret_token\": \"$RAHASIA\", \"allowed_updates\": [\"message\", \"callback_query\"]}" \
  | python3 -c 'import json,sys; j=json.load(sys.stdin); print("setWebhook:", j.get("ok"), j.get("description"))'
curl -fsS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getWebhookInfo" \
  | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print("Alamat:", r.get("url")); print("Antre:", r.get("pending_update_count")); print("Galat terakhir:", r.get("last_error_message"))'

echo "== Penjadwal pengingat kirim file (pg_cron 01.00 UTC = 08.00 WIB)"
psql "$DB_URL" -X -q -t -v ON_ERROR_STOP=1 -v rahasia="$RAHASIA_PENGINGAT" -v alamat="$ALAMAT" <<'EOF'
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create schema if not exists jadwal;
revoke all on schema jadwal from public;
select set_config('pasang.rahasia', :'rahasia', false), set_config('pasang.alamat', :'alamat', false) \gset
do $do$
declare
  v uuid;
begin
  select id into v from vault.secrets where name = 'pengingat_rahasia';
  if v is null then
    perform vault.create_secret(current_setting('pasang.rahasia'), 'pengingat_rahasia',
                                'Kode rahasia pengingat kirim file (db/pasang_pintu.sh)');
  else
    perform vault.update_secret(v, current_setting('pasang.rahasia'));
  end if;
  execute format($f$
    create or replace function jadwal.picu_pengingat(p_tanggal date default null) returns bigint
    language plpgsql security definer set search_path = '' as $b$
    begin
      return net.http_post(
        url := %L,
        body := case when p_tanggal is null then '{}'::jsonb else jsonb_build_object('tanggal', p_tanggal) end,
        headers := jsonb_build_object(
          'content-type', 'application/json',
          'x-pengingat-rahasia', (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'pengingat_rahasia')),
        timeout_milliseconds := 30000);
    end $b$ $f$, current_setting('pasang.alamat'));
end $do$;
select set_config('pasang.rahasia', '', false) \gset
revoke all on function jadwal.picu_pengingat(date) from public;
select 'Jadwal nomor ' || cron.schedule('pengingat-kirim-file', '0 1 * * *', 'select jadwal.picu_pengingat()');
select 'Zona waktu pg_cron: ' || coalesce(current_setting('cron.timezone', true), '(tidak terbaca)');
select 'Jadwal terpasang: ' || jobname || ' | ' || schedule || ' | ' || command || ' | aktif=' || active
from cron.job where jobname = 'pengingat-kirim-file';
EOF
