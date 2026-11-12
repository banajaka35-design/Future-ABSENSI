#!/usr/bin/env bash
# Pemeriksaan izin sebelum workflow mengubah Supabase (aturan 8 di CLAUDE.md). Dipakai oleh
# workflow "Pasang ke Supabase" dan "Reset Supabase".
#   - Dipicu tombol: pemilik harus mengetik kata konfirmasi yang benar.
#   - Dipicu dorongan ke cabang khusus: commit-nya harus commit terbaru main, dan uji otomatis
#     untuk commit itu harus lulus (tidak boleh ada yang gagal).
# Pemakaian (di GitHub Actions): KATA=<kata yang diwajibkan> KONFIRMASI=<isian tombol> GH_TOKEN=... db/periksa_pemicu.sh
set -euo pipefail
: "${KATA:?KATA belum diisi}"

if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]; then
  if [ "${KONFIRMASI:-}" != "$KATA" ]; then
    echo "GAGAL: konfirmasi bukan $KATA. Tidak ada yang diubah." >&2
    exit 1
  fi
  echo "Konfirmasi $KATA diterima dari tombol."
  exit 0
fi

MAIN="$(gh api "repos/$GITHUB_REPOSITORY/commits/main" --jq .sha)"
if [ "$GITHUB_SHA" != "$MAIN" ]; then
  echo "GAGAL: cabang $GITHUB_REF_NAME menunjuk $GITHUB_SHA, bukan commit terbaru main ($MAIN). Tidak ada yang diubah." >&2
  exit 1
fi
# Dorongan ke cabang khusus juga memicu uji otomatis baru; cukup satu yang lulus dan tidak boleh ada yang gagal.
HASIL="$(gh api "repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA/check-runs" \
  --jq '[.check_runs[] | select(.name == "uji") | .conclusion] | if any(. == "failure" or . == "cancelled") then "gagal" elif any(. == "success") then "success" else "belum" end')"
if [ "$HASIL" != "success" ]; then
  echo "GAGAL: uji otomatis untuk commit ini belum lulus (hasil: $HASIL). Tidak ada yang diubah." >&2
  exit 1
fi
echo "Dorongan ke cabang $GITHUB_REF_NAME sah: commit terbaru main, uji otomatis lulus."
