#!/usr/bin/env bash
# Pemasangan pintu Telegram (paket 5b), dijalankan workflow "Pasang ke Supabase" sesudah migrasi.
# Dilewati (bukan gagal) bila secret pintu belum diisi pemilik, supaya pemasangan lain tetap jalan.
# Yang dilakukan:
#   1. Kata sandi peran `pintu` dibuat acak di sini, dipasang ke database dan ke rahasia Edge Function. Tidak ditulis ke log.
#   2. Akun Telegram HRD (secret HRD_TELEGRAM_ID) didaftarkan bila belum ada.
#   3. Edge Function pintu-telegram dipasang (inti.ts dan urai.ts disalin dari sistem/ lebih dulu).
#   4. Rahasia Edge Function diisi, lalu alamat bot didaftarkan ke Telegram dengan kode rahasia baru.
# Butuh: DB_URL, SUPABASE_ACCESS_TOKEN, TELEGRAM_BOT_TOKEN, HRD_TELEGRAM_ID.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?DB_URL belum diisi}"

kurang=""
[ -n "${SUPABASE_ACCESS_TOKEN:-}" ] || kurang="$kurang SUPABASE_ACCESS_TOKEN"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || kurang="$kurang TELEGRAM_BOT_TOKEN"
[ -n "${HRD_TELEGRAM_ID:-}" ] || kurang="$kurang HRD_TELEGRAM_ID"
if [ -n "$kurang" ]; then
  echo "Pintu Telegram dilewati: secret belum diisi:$kurang"
  exit 0
fi
if ! [[ "$HRD_TELEGRAM_ID" =~ ^[0-9]+$ ]]; then
  echo "GAGAL: HRD_TELEGRAM_ID harus angka." >&2
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

SANDI="$(openssl rand -hex 24)"
RAHASIA="$(openssl rand -hex 32)"
echo "::add-mask::$SANDI"
echo "::add-mask::$RAHASIA"
PINTU_DB_URL="${PINTU_URL_TANPA_SANDI/SANDI/$SANDI}"

echo "== Peran pintu: kata sandi baru dan batas waktu perintah"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -v sandi="$SANDI" <<'EOF'
alter role pintu password :'sandi';
alter role pintu set statement_timeout = '120s';
EOF

echo "== Akun HRD"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -v tg="$HRD_TELEGRAM_ID" <<'EOF'
begin;
set local app.pengguna = 'pasang-pintu';
insert into induk.pengguna (telegram_id, peran)
select :'tg'::bigint, 'hrd' where not exists (select 1 from induk.pengguna where telegram_id = :'tg'::bigint);
select 'HRD terdaftar: ' || count(*) from induk.pengguna where peran = 'hrd' and aktif;
commit;
EOF

echo "== Edge Function pintu-telegram"
FUNGSI=supabase/functions/pintu-telegram
cp sistem/urai/urai.ts "$FUNGSI/urai.ts"
cp sistem/pintu/inti.ts "$FUNGSI/inti.ts"
mulai=$(date +%s%N)
npx --yes supabase@2 functions deploy pintu-telegram --project-ref "$REF" --no-verify-jwt --use-api
echo "Lama memasang: $(( ($(date +%s%N) - mulai) / 1000000 )) ms"

BERKAS="$(mktemp)"
trap 'rm -f "$BERKAS"' EXIT
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_RAHASIA=%s\nPINTU_DB_URL=%s\n' "$TELEGRAM_BOT_TOKEN" "$RAHASIA" "$PINTU_DB_URL" > "$BERKAS"
npx --yes supabase@2 secrets set --project-ref "$REF" --env-file "$BERKAS"

echo "== Alamat bot di Telegram"
ALAMAT="https://$REF.supabase.co/functions/v1/pintu-telegram"
curl -fsS -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -H 'content-type: application/json' \
  -d "{\"url\": \"$ALAMAT\", \"secret_token\": \"$RAHASIA\", \"allowed_updates\": [\"message\", \"callback_query\"]}" \
  | python3 -c 'import json,sys; j=json.load(sys.stdin); print("setWebhook:", j.get("ok"), j.get("description"))'
curl -fsS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getWebhookInfo" \
  | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print("Alamat:", r.get("url")); print("Antre:", r.get("pending_update_count")); print("Galat terakhir:", r.get("last_error_message"))'
