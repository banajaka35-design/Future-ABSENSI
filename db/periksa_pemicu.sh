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

# Paket 6e (celah C1): Reset tidak boleh dijalankan ulang ("Re-run") dari riwayat, karena token pemicu Isi Sheets
# berizin menjalankan ulang run lama; hanya percobaan pertama dari dorongan ke cabang yang sah.
if [ "$KATA" = "RESET" ] && [ "${GITHUB_RUN_ATTEMPT:-1}" != "1" ]; then
  echo "GAGAL: Reset tidak boleh dijalankan ulang (percobaan ke-$GITHUB_RUN_ATTEMPT). Dorong ulang ke cabang reset. Tidak ada yang diubah." >&2
  exit 1
fi

MAIN="$(gh api "repos/$GITHUB_REPOSITORY/commits/main" --jq .sha)"
if [ "$GITHUB_SHA" != "$MAIN" ]; then
  echo "GAGAL: cabang $GITHUB_REF_NAME menunjuk $GITHUB_SHA, bukan commit terbaru main ($MAIN). Tidak ada yang diubah." >&2
  exit 1
fi
# Paket H1 (hemat menit GitHub): uji otomatis hanya jalan untuk push ke main dan dilewati bila yang berubah hanya
# docs/. Maka syaratnya: telusuri dari commit ini ke belakang (paling jauh BATAS commit) sampai commit yang uji
# otomatisnya lulus. Commit yang dilewati di tengah jalan harus hanya mengubah docs/ dan tidak boleh punya uji
# yang gagal, dibatalkan, atau belum selesai.
BATAS="${BATAS_TELUSUR:-30}"
hasil_uji() {
  gh api "repos/$GITHUB_REPOSITORY/commits/$1/check-runs" \
    --jq '[.check_runs[] | select(.name == "uji") | .conclusion] | if length == 0 then "tidak_ada" elif any(. == "failure" or . == "cancelled" or . == "timed_out") then "gagal" elif any(. == null) then "belum" elif any(. == "success") then "success" else "lain" end'
}
c="$GITHUB_SHA"; n=0
while :; do
  n=$((n + 1))
  if [ "$n" -gt "$BATAS" ]; then
    echo "GAGAL: tidak ditemukan commit dengan uji lulus dalam $BATAS commit terakhir. Tidak ada yang diubah." >&2
    exit 1
  fi
  h="$(hasil_uji "$c")"
  case "$h" in
    success)
      [ "$c" = "$GITHUB_SHA" ] && echo "Uji otomatis commit ini lulus." \
        || echo "Uji otomatis lulus di commit $c; commit sesudahnya hanya mengubah docs/."
      break ;;
    tidak_ada)
      INFO="$(gh api "repos/$GITHUB_REPOSITORY/commits/$c" --jq '(.parents | length | tostring) + " " + (.parents[0].sha // "-") + " " + ([.files[].filename] | map(select(startswith("docs/") | not)) | length | tostring) + " " + (.files | length | tostring)')"
      read -r JML_INDUK INDUK DI_LUAR JML_BERKAS <<< "$INFO"
      if [ "$JML_INDUK" != "1" ] || [ "$DI_LUAR" != "0" ] || [ "$JML_BERKAS" = "0" ] || [ "$JML_BERKAS" -ge 300 ]; then
        echo "GAGAL: commit $c belum diuji dan bukan perubahan docs/ saja (induk $JML_INDUK, berkas di luar docs/ $DI_LUAR). Tidak ada yang diubah." >&2
        exit 1
      fi
      c="$INDUK" ;;
    *)
      echo "GAGAL: uji otomatis untuk commit $c belum lulus (hasil: $h). Tidak ada yang diubah." >&2
      exit 1 ;;
  esac
done
echo "Dorongan ke cabang $GITHUB_REF_NAME sah: commit terbaru main, uji otomatis lulus."
