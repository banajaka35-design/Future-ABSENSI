#!/usr/bin/env bash
# Paket E1 (docs/rencana-e1.md): enkripsi file cadangan sebelum diunggah ke GitHub.
# Kunci = kalimat rahasia dari secret GitHub CADANGAN_KUNCI (variabel lingkungan), gpg simetris AES-256.
# Kalimat rahasia dikirim lewat pipa (bukan argumen), jadi tidak tampil di daftar proses atau log.
# Pemakaian:
#   CADANGAN_KUNCI=... db/kunci_cadangan.sh periksa                      -> GAGAL bila kunci kosong (dipakai sebelum cadangan dibuat)
#   CADANGAN_KUNCI=... db/kunci_cadangan.sh kunci <file>                 -> <file>.gpg, file asli dihapus
#   CADANGAN_KUNCI=... db/kunci_cadangan.sh buka <file.gpg> <keluaran>   -> <keluaran>
set -euo pipefail
if [ -z "${CADANGAN_KUNCI:-}" ]; then
  echo "GAGAL: secret CADANGAN_KUNCI kosong atau tidak ditemukan; cadangan tidak dibuat tanpa enkripsi." >&2
  echo "       Isi secret GitHub CADANGAN_KUNCI (Settings > Secrets and variables > Actions), lihat docs/cadangan.md." >&2
  exit 1
fi
GPG=(gpg --batch --yes --quiet --no-tty --pinentry-mode loopback --passphrase-fd 0)
case "${1:-}" in
  periksa)
    echo "Kunci cadangan tersedia."
    ;;
  kunci)
    FILE="${2:?file belum diisi}"
    [ -s "$FILE" ] || { echo "GAGAL: file cadangan $FILE kosong atau tidak ada." >&2; exit 1; }
    printf '%s' "$CADANGAN_KUNCI" | "${GPG[@]}" --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
      --s2k-count 65011712 --output "$FILE.gpg" "$FILE"
    [ -s "$FILE.gpg" ] || { echo "GAGAL: file terenkripsi tidak terbentuk." >&2; exit 1; }
    rm -f "$FILE"
    echo "Cadangan dikunci: $FILE.gpg ($(stat -c %s "$FILE.gpg") byte)."
    ;;
  buka)
    MASUK="${2:?file .gpg belum diisi}"
    KELUAR="${3:?file keluaran belum diisi}"
    if ! printf '%s' "$CADANGAN_KUNCI" | "${GPG[@]}" --decrypt --output "$KELUAR" "$MASUK"; then
      rm -f "$KELUAR"
      echo "GAGAL: cadangan tidak bisa dibuka (kalimat rahasia salah atau file rusak)." >&2
      exit 1
    fi
    echo "Cadangan dibuka: $KELUAR."
    ;;
  *)
    echo "Pemakaian: db/kunci_cadangan.sh periksa | kunci <file> | buka <file.gpg> <keluaran>" >&2
    exit 2
    ;;
esac
