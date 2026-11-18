"""Pemeriksaan pengamanan workflow GitHub (paket 6f, celah S4).

Nilai dari luar (`inputs.*`, `github.event.*`, `github.head_ref`) tidak boleh dimasukkan langsung ke perintah `run:`
(cara pengamanan resmi GitHub Actions: lewat `env:`). Keluar 1 bila ada.
Pemakaian: python3 sistem/uji/periksa_workflow.py .github/workflows/*.yml
"""
import re
import sys

POLA = re.compile(r"\$\{\{\s*(inputs\.|github\.event\.|github\.head_ref)")
salah = []
for jalur in sys.argv[1:]:
    baris = open(jalur, encoding="utf-8").read().splitlines()
    dalam_run, lekuk = False, 0
    for i, b in enumerate(baris, 1):
        isi = b.strip()
        if dalam_run and isi and (len(b) - len(b.lstrip())) <= lekuk:
            dalam_run = False
        m = re.match(r"^(\s*)(-\s+)?run:\s*(.*)$", b)
        if m:
            lekuk = len(m.group(1)) + (len(m.group(2)) if m.group(2) else 0)
            if POLA.search(m.group(3)):
                salah.append(f"{jalur}:{i}: {isi}")
            dalam_run = m.group(3).strip() in ("|", ">", "|-", ">-", "")
            continue
        if dalam_run and POLA.search(b):
            salah.append(f"{jalur}:{i}: {isi}")
for s in salah:
    print("  NILAI LUAR DI run:", s)
print(f"Pemeriksaan workflow: {len(sys.argv) - 1} file, {len(salah)} temuan")
sys.exit(1 if salah else 0)
