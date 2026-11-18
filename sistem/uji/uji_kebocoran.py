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


def psql(sql):
    return subprocess.run(["psql", os.environ["DB_URL"], "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c", sql],
                          check=True, capture_output=True, text=True).stdout.strip()


def uji_f15c(jalan):
    """F15c (paket G1-2): satu orang rahasia berhenti rahasia mulai periode terakhir. Periode sebelumnya tetap tanpa
    angka (demo dan Sheets), periode terakhir tampil, kedua pemeriksa lulus; data dikembalikan ke aturan lama
    ("status terakhir") -> pemeriksa demo GAGAL. Basis data uji dikembalikan seperti semula sesudahnya."""
    global nama
    nama_asli, nama = nama, nama + " F15c"
    baris = psql("select r.id, r.id_karyawan from induk.karyawan_riwayat r where r.gaji_rahasia and r.berlaku_sampai is null "
                 "order by r.id_karyawan limit 1")
    per = [x.split("|") for x in psql("select p.id, p.tanggal_awal from fakta.periode p join hitung.versi_terakhir v "
                                      "on v.periode_id = p.id and v.jenis = 'hitung_gaji' order by p.tanggal_awal").splitlines()]
    if not baris or len(per) < 2:
        print("    (tidak ada orang rahasia atau kurang dari 2 periode; uji F15c dilewati)")
        nama = nama_asli
        return
    rid, orang = baris.split("|")
    akhir_id, akhir_tgl = per[-1]
    lama = [x[0] for x in per[:-1]]
    kolom = ("id_karyawan, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar, rekening_terenkripsi, "
             "wajib_tap, bpjs_kesehatan, bpjs_ketenagakerjaan")
    psql(f"update induk.karyawan_riwayat set berlaku_sampai = '{akhir_tgl}' where id = {rid}; "
         f"insert into induk.karyawan_riwayat (berlaku_dari, gaji_rahasia, {kolom}) "
         f"select '{akhir_tgl}', false, {kolom} from induk.karyawan_riwayat where id = {rid}")
    try:
        r = jalan("web/isi_sheets.py", "isi")
        cek("Sheets terisi sesudah status rahasia berubah", r.returncode == 0, r.stderr[-300:])
        r = jalan("web/periksa_sheets.py")
        cek("pemeriksa Sheets lulus dengan rahasia per periode", r.returncode == 0, (r.stdout + r.stderr)[-600:])
        k = json.loads(urllib.request.urlopen(alamat + "/uji/keadaan", data=b"{}").read())
        angka = {}
        for t_ in k["tab"]:
            if not t_["title"].startswith("Gaji "):
                continue
            ib = t_["values"][1].index("Gaji bersih")
            for b in t_["values"][2:]:
                if b and str(b[0]) == orang:
                    angka[t_["title"].split(" sd ")[0][5:]] = b[ib] if len(b) > ib else ""
        awal = {x[0]: x[1] for x in per}
        cek(f"Sheets: {orang} tanpa angka di periode lama, berangka di periode {akhir_tgl}",
            all(angka.get(awal[x]) in ("", None) for x in lama) and isinstance(angka.get(akhir_tgl), int), angka)
        demo = tempfile.mkdtemp()
        r = subprocess.run([sys.executable, "web/buat_data.py", demo], cwd=AKAR, capture_output=True, text=True)
        cek("data demo dibuat sesudah status rahasia berubah", r.returncode == 0, r.stderr[-300:])
        r = subprocess.run([sys.executable, "web/periksa_data.py", demo], cwd=AKAR, capture_output=True, text=True)
        cek("pemeriksa demo lulus dengan rahasia per periode", r.returncode == 0, (r.stdout + r.stderr)[-600:])
        jalur = os.path.join(demo, "data.json")
        data = json.load(open(jalur, encoding="utf-8"))
        ko = next(x for x in data["karyawan"] if x["id"] == orang)
        rinci = {x: json.load(open(os.path.join(demo, f"rincian_{x}.json"), encoding="utf-8")) for x, _ in per}
        cek(f"demo: {orang} tanpa angka dan tanpa rincian di periode lama, tampil di periode terakhir",
            all(ko["p"][x][1] is None and orang not in rinci[x] for x in lama)
            and ko["p"][akhir_id][1] is not None and orang in rinci[akhir_id], ko["p"])
        p_akhir = next(p for p in data["periode"] if str(p["id"]) == akhir_id)
        cek("demo: tanda anomali orang ini di periode terakhir (dibanding periode rahasia) tanpa keterangan",
            all(a.get("ket") is None for a in p_akhir["anomali"] if a.get("id") == orang))
        # Kebalikan: aturan lama "status terakhir" (orang ini tidak rahasia) -> angka periode lama terbuka.
        b_lama = int(psql(f"select gaji_bersih from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id "
                          f"and v.jenis = 'hitung_gaji' where v.periode_id = {lama[0]} and g.id_karyawan = '{orang}'"))
        ko["p"][lama[0]][1] = b_lama
        json.dump(data, open(jalur, "w", encoding="utf-8"))
        r = subprocess.run([sys.executable, "web/periksa_data.py", demo], cwd=AKAR, capture_output=True, text=True)
        cek("demo dengan aturan lama (gaji periode rahasia terbuka) -> pemeriksa GAGAL", r.returncode == 1, r.stdout[-300:])
    finally:
        # Kembalikan basis data uji (hanya di Postgres uji; pengaman baris bertanggal dilewati khusus di sini).
        psql(f"begin; set local session_replication_role = replica; "
             f"delete from induk.karyawan_riwayat where id_karyawan = '{orang}' and berlaku_dari = '{akhir_tgl}' and id <> {rid}; "
             f"update induk.karyawan_riwayat set berlaku_sampai = null where id = {rid}; commit")
        r = jalan("web/isi_sheets.py", "isi")
        cek("basis data uji dan Sheets tiruan dikembalikan", r.returncode == 0 and psql(
            f"select count(*) from induk.karyawan_riwayat where id_karyawan = '{orang}' and gaji_rahasia and berlaku_sampai is null") == "1")
        nama = nama_asli


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
    # G1: total grafik divisi yang memuat orang rahasia dikembalikan termasuk rahasia -> pemeriksa GAGAL.
    jalur_d = os.path.join(demo, "data.json")
    asli = open(jalur_d, encoding="utf-8").read()
    data_g = json.loads(asli)
    ber_r = [(p, d) for p in data_g["periode"] for d in p["divisi_biaya"] if d["rahasia"] > 0]
    cek(f"grafik divisi: {len(ber_r)} divisi-periode memuat orang rahasia, keterangan tersedia", len(ber_r) > 0)
    if ber_r:
        _, d = ber_r[0]
        d["bersih"] += 1_000_000
        json.dump(data_g, open(jalur_d, "w", encoding="utf-8"))
        r = subprocess.run([sys.executable, "web/periksa_data.py", demo], cwd=AKAR, capture_output=True, text=True)
        cek("total grafik divisi berahasia ditambah -> pemeriksa GAGAL (kebocoran)",
            r.returncode == 1 and "kebocoran grafik divisi" in r.stdout, r.stdout[-300:])
        open(jalur_d, "w", encoding="utf-8").write(asli)
    # 6a-4: tanda anomali divisi yang memuat orang rahasia tanpa angka; dikembalikan berangka -> pemeriksa GAGAL.
    jalur = os.path.join(demo, "data.json")
    data = json.load(open(jalur, encoding="utf-8"))
    samar = [(p, a) for p in data["periode"] for a in p["anomali"] if "tidak ditampilkan karena" in (a.get("ket") or "")]
    cek(f"tanda divisi berahasia tanpa angka: {len(samar)} tanda", all("Rp" not in a["ket"] for _, a in samar))
    if samar:
        _, a = samar[0]
        a["ket"] = f"Lembur divisi {a['divisi']} naik dari Rp1 menjadi Rp2"
        json.dump(data, open(jalur, "w", encoding="utf-8"))
        r = subprocess.run([sys.executable, "web/periksa_data.py", demo], cwd=AKAR, capture_output=True, text=True)
        cek("tanda divisi berahasia dikembalikan berangka -> pemeriksa GAGAL",
            r.returncode == 1 and "gaji rahasia" in r.stdout, r.stdout[-300:])
    else:
        print(f"    (tidak ada tanda divisi berahasia di data {nama}; uji kebalikan dilewati)")
    uji_f15c(jalan)
finally:
    tiruan.terminate()
sys.exit(1 if gagal else 0)
