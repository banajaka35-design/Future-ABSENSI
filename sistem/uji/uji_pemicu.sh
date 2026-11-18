#!/usr/bin/env bash
# Uji db/periksa_pemicu.sh (paket H1): syarat "uji lulus" boleh berasal dari commit lebih awal bila commit
# sesudahnya hanya mengubah docs/. Memakai gh tiruan yang menjalankan ekspresi --jq asli terhadap JSON contoh,
# jadi ekspresi jq di skrip ikut teruji. Butuh bash dan jq; tanpa internet.
# Pemakaian: sistem/uji/uji_pemicu.sh
set -uo pipefail
AKAR="$(cd "$(dirname "$0")/../.." && pwd)"
KERJA="$(mktemp -d)"; trap 'rm -rf "$KERJA"' EXIT
mkdir -p "$KERJA/bin"
cat > "$KERJA/bin/gh" <<'GH'
#!/usr/bin/env bash
# gh tiruan: gh api <jalur> --jq <ekspresi>; jawaban diambil dari $CONTOH/<jalur dengan / diganti _>.json
jalur="$2"; shift 2; ekspr="."
while [ $# -gt 0 ]; do [ "$1" = "--jq" ] && ekspr="$2"; shift; done
f="$CONTOH/$(echo "$jalur" | sed 's#^repos/[^/]*/[^/]*/##; s#/#_#g').json"
[ -f "$f" ] || { echo "gh tiruan: tidak ada $f" >&2; exit 1; }
jq -r "$ekspr" "$f"
GH
chmod +x "$KERJA/bin/gh"

LULUS=0; GAGAL=0
cek() { if [ "$2" = "$3" ]; then echo "  LULUS  $1"; LULUS=$((LULUS + 1)); else echo "  GAGAL  $1 (dapat $2, harap $3)"; GAGAL=$((GAGAL + 1)); fi; }

# Bahan: commit(sha, induk, berkas...) dan uji(sha, hasil...) dengan hasil success/failure/null.
commit() { local s="$1" i="$2"; shift 2
  printf '{"parents":[%s],"files":[%s]}' "$( [ "$i" = "-" ] || printf '{"sha":"%s"}' "$i")" \
    "$( [ $# -eq 0 ] || printf '{"filename":"%s"},' "$@" | sed 's/,$//')" > "$CONTOH/commits_$s.json"; }
uji() { local s="$1"; shift
  printf '{"check_runs":[%s]}' "$(for h in "$@"; do [ "$h" = null ] && printf '{"name":"uji","conclusion":null},' \
    || printf '{"name":"uji","conclusion":"%s"},' "$h"; done | sed 's/,$//')" > "$CONTOH/commits_${s}_check-runs.json"; }
kepala() { printf '{"sha":"%s"}' "$1" > "$CONTOH/commits_main.json"; }
jalan() { PATH="$KERJA/bin:$PATH" GITHUB_EVENT_NAME=push GITHUB_REPOSITORY=pemilik/repo GITHUB_REF_NAME=pasang \
    GITHUB_SHA="$1" KATA=PASANG bash "$AKAR/db/periksa_pemicu.sh" > "$KERJA/keluar" 2>&1; r=$?; grep -q "gh tiruan" "$KERJA/keluar" && r=99; [ -n "${TAMPIL:-}" ] && sed "s/^/      /" "$KERJA/keluar" >&2; echo $r; }
baru() { CONTOH="$(mktemp -d -p "$KERJA")"; export CONTOH; }

echo "Uji pemeriksa pemicu Pasang/Reset (paket H1)"

baru; kepala c3; commit c3 c2 docs/a.md; uji c3; commit c2 c1 docs/b.md docs/c.md; uji c2; commit c1 c0 db/x.sql; uji c1 success
cek "dua commit docs saja sesudah commit yang lulus -> boleh" "$(jalan c3)" 0

baru; kepala c2; commit c2 c1 sistem/x.ts; uji c2; commit c1 c0 db/x.sql; uji c1 success
cek "commit kode tanpa uji sesudah commit yang lulus -> ditolak" "$(jalan c2)" 1

baru; kepala c2; commit c2 c1 docs/a.md sistem/x.ts; uji c2; commit c1 c0 db/x.sql; uji c1 success
cek "commit campuran docs + kode tanpa uji -> ditolak" "$(jalan c2)" 1

baru; kepala c2; commit c2 c1 docs/a.md; uji c2; commit c1 - docs/b.md; uji c1
cek "tidak ada commit yang lulus sampai awal riwayat -> ditolak" "$(jalan c2)" 1

baru; kepala c2; commit c2 c1 docs/a.md; uji c2; commit c1 c0 db/x.sql; uji c1 failure success
cek "commit dasar punya uji gagal -> ditolak" "$(jalan c2)" 1

baru; kepala c2; commit c2 c1 docs/a.md; uji c2 failure; commit c1 c0 db/x.sql; uji c1 success
cek "commit docs dengan uji gagal -> ditolak" "$(jalan c2)" 1

baru; kepala c1; commit c1 c0 db/x.sql; uji c1 null
cek "uji commit ini belum selesai -> ditolak" "$(jalan c1)" 1

baru; kepala c9; commit c1 c0 db/x.sql; uji c1 success
cek "bukan commit terbaru main -> ditolak" "$(jalan c1)" 1

baru; kepala c1; commit c1 c0 db/x.sql; uji c1 success
cek "commit ini sendiri lulus -> boleh" "$(jalan c1)" 0

baru; kepala c2; printf '{"parents":[{"sha":"a"},{"sha":"b"}],"files":[{"filename":"docs/a.md"}]}' > "$CONTOH/commits_c2.json"; uji c2
cek "commit gabungan (dua induk) tanpa uji -> ditolak" "$(jalan c2)" 1

baru; kepala c2; commit c2 c1; uji c2; commit c1 c0 db/x.sql; uji c1 success
cek "commit tanpa berkas tanpa uji -> ditolak" "$(jalan c2)" 1

baru; kepala c40; for i in $(seq 1 40); do commit "c$i" "c$((i - 1))" docs/a.md; uji "c$i"; done; commit c0 - db/x.sql; uji c0 success
cek "lebih dari 30 commit docs berturut-turut -> ditolak" "$(jalan c40)" 1

echo "Hasil: $LULUS lulus, $GAGAL gagal"
[ "$GAGAL" -eq 0 ]
