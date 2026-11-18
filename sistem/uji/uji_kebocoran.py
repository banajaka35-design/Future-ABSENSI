"""Uji kebocoran gaji rahasia (F15b, paket 6a-3) untuk gudang mana pun yang gajinya sudah dihitung.

Dipakai untuk Pabrik B (1 orang rahasia: kasus paling berbahaya). Sheets tiruan: isi lalu periksa (pemeriksa memuat
uji "total - jumlah baris terlihat = 0"); halaman demo: buat data lalu periksa (memuat uji yang sama). Juga dihitung
langsung di sini: total Ringkasan - jumlah gaji bersih semua baris yang terlihat = 0.
Pemakaian: DB_URL=... python3 sistem/uji/uji_kebocoran.py <nama pabrik>
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uji_sheets import AKAR, SID, SA, port_kosong  # noqa: E402

nama = sys.argv[1] if len(sys.argv) > 1 else "?"
gagal = 0


def cek(judul, ok, ket=""):
    global gagal
    print(f"  {'LULUS' if ok else 'GAGAL'}  F15b {nama}: {judul}{'' if ok else ' ' + str(ket)}")
    gagal += 0 if ok else 1


kerja = tempfile.mkdtemp()
pribadi, publik = os.path.join(kerja, "k.pem"), os.path.join(kerja, "p.pem")
subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", pribadi],
               check=True, capture_output=True)
subprocess.run(["openssl", "pkey", "-in", pribadi, "-pubout", "-out", publik], check=True, capture_output=True)
port = port_kosong()
tiruan = subprocess.Popen([sys.executable, os.path.join(AKAR, "sistem/uji/sheets_tiruan.py"), str(port), publik, SID])
alamat = f"http://127.0.0.1:{port}"
try:
    for _ in range(50):
        try:
            urllib.request.urlopen(alamat + "/uji/keadaan", data=b"{}", timeout=1)
            break
        except OSError:
            time.sleep(0.1)
    with open(pribadi) as f:
        kunci = {"client_email": SA, "private_key": f.read(), "token_uri": alamat + "/token"}
    env = dict(os.environ, GOOGLE_SA_KEY=json.dumps(kunci), SHEETS_ID=SID, SHEETS_API_URL=alamat, GITHUB_SHA="uji-6a-3")
    jalan = lambda *a: subprocess.run([sys.executable, *a], cwd=AKAR, env=env, capture_output=True, text=True)  # noqa: E731
    r = jalan("web/isi_sheets.py", "isi")
    cek("Sheets tiruan terisi", r.returncode == 0, r.stderr[-300:])
    r = jalan("web/periksa_sheets.py")
    cek("pemeriksa Sheets lulus (termasuk uji kebocoran)", r.returncode == 0, (r.stdout + r.stderr)[-600:])
    print("    " + r.stdout.strip().splitlines()[-1])
    k = json.loads(urllib.request.urlopen(alamat + "/uji/keadaan", data=b"{}").read())
    ring = next(t for t in k["tab"] if t["title"] == "Ringkasan")["values"]
    for b in ring[4:]:
        awal = b[1]
        tabs = [t for t in k["tab"] if t["title"].startswith(f"Gaji {awal} sd ")]
        kepala = tabs[0]["values"][1]
        ib = kepala.index("Gaji bersih")
        terlihat = sum(r[ib] for t in tabs for r in t["values"][2:] if len(r) > ib and isinstance(r[ib], int))
        cek(f"periode {awal}: total Ringkasan - jumlah gaji bersih terlihat = 0 ({b[16]} orang rahasia)",
            b[9] - terlihat == 0 and b[16] >= 1, (b[9], terlihat))
    demo = tempfile.mkdtemp()
    r = subprocess.run([sys.executable, "web/buat_data.py", demo], cwd=AKAR, capture_output=True, text=True)
    cek("data halaman demo dibuat", r.returncode == 0, r.stderr[-300:])
    r = subprocess.run([sys.executable, "web/periksa_data.py", demo], cwd=AKAR, capture_output=True, text=True)
    cek("pemeriksa halaman demo lulus (termasuk uji kebocoran)", r.returncode == 0, (r.stdout + r.stderr)[-600:])
    print("    " + r.stdout.strip().splitlines()[-1])
finally:
    tiruan.terminate()
sys.exit(1 if gagal else 0)
