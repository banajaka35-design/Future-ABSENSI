"""Sheets tiruan untuk uji paket 6a (docs/rekap-sheets.md bagian 6). Tanpa internet, hanya pustaka bawaan.

Meniru bagian Google Sheets API yang dipakai web/isi_sheets.py dan web/periksa_sheets.py:
masuk dengan token (tanda tangan RS256 diperiksa dengan kunci publik uji), info spreadsheet, batchUpdate
(addSheet, deleteSheet, updateSheetProperties, addProtectedRange), values:batchClear, values:batchUpdate,
values:append, values:batchGet. Sengaja ketat:
  - valueInputOption selain RAW ditolak (400);
  - menulis di luar ukuran grid ditolak (400), seperti Google;
  - nilai yang dibaca: sel kosong di ujung baris dan baris kosong di ujung tab dibuang, seperti Google.
Jalan pintas untuk uji (tidak ada di Google): /uji/keadaan, /uji/ubah_sel, /uji/tambah_tab, /uji/ubah_kunci, /uji/gangguan.

Pemakaian: python3 sistem/uji/sheets_tiruan.py <port> <kunci_publik.pem> <id_spreadsheet>
"""
import base64
import json
import re
import subprocess
import sys
import tempfile
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, KUNCI_PUBLIK, SID = int(sys.argv[1]), sys.argv[2], sys.argv[3]
TOKEN = "token-uji-6a"
kunci_kunci = threading.Lock()
keadaan = {"tab": [], "id_berikut": 100, "gangguan": 0, "jumlah": 0}


def tab_baru(judul, baris=1000, kolom=26):
    t = {"sheetId": keadaan["id_berikut"], "title": judul, "rowCount": baris, "columnCount": kolom,
         "frozenRowCount": 0, "protectedRanges": [], "values": []}
    keadaan["id_berikut"] += 1
    keadaan["tab"].append(t)
    return t


tab_baru("Sheet1")["values"] = [["catatan HRD, jangan disentuh sistem"]]


def cari(judul):
    for t in keadaan["tab"]:
        if t["title"] == judul:
            return t
    return None


def b64d(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def urai_rentang(r):
    m = re.fullmatch(r"'((?:[^']|'')*)'(?:!([A-Z]+)(\d+)(?::([A-Z]+)(\d+))?)?", r)
    if not m:
        raise ValueError(f"rentang tidak dikenal: {r}")
    def kol(h):
        n = 0
        for ch in h:
            n = n * 26 + ord(ch) - 64
        return n - 1
    judul = m.group(1).replace("''", "'")
    if m.group(2) is None:
        return judul, 0, 0, None, None
    akhir_k = kol(m.group(4)) if m.group(4) else None
    akhir_b = int(m.group(5)) - 1 if m.group(5) else None
    return judul, int(m.group(3)) - 1, kol(m.group(2)), akhir_b, akhir_k


def tulis_sel(t, b0, k0, baris):
    if b0 + len(baris) > t["rowCount"] or any(k0 + len(b) > t["columnCount"] for b in baris):
        raise ValueError(f"di luar grid tab {t['title']} ({t['rowCount']}x{t['columnCount']})")
    v = t["values"]
    for i, b in enumerate(baris):
        while len(v) <= b0 + i:
            v.append([])
        r = v[b0 + i]
        for j, x in enumerate(b):
            while len(r) <= k0 + j:
                r.append(None)
            if not (x is None or isinstance(x, (str, int, float, bool))):
                raise ValueError("nilai bukan teks atau angka")
            r[k0 + j] = None if x == "" else x


def bersih(baris):
    hasil = []
    for b in baris:
        b = list(b)
        while b and b[-1] is None:
            b.pop()
        hasil.append(["" if x is None else x for x in b])
    while hasil and not hasil[-1]:
        hasil.pop()
    return hasil


class Penjawab(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def jawab(self, kode, isi):
        data = json.dumps(isi).encode()
        self.send_response(kode)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def badan(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def do_GET(self):
        self.tangani("GET")

    def do_POST(self):
        self.tangani("POST")

    def tangani(self, cara):
        with kunci_kunci:
            try:
                self._tangani(cara)
            except ValueError as e:
                self.jawab(400, {"error": {"code": 400, "message": str(e)}})

    def _tangani(self, cara):
        u = urllib.parse.urlsplit(self.path)
        tanya = urllib.parse.parse_qs(u.query)
        jalan = urllib.parse.unquote(u.path)
        if jalan.startswith("/uji/"):
            return self.uji(jalan, self.badan())
        keadaan["jumlah"] += 1
        if keadaan["gangguan"] > 0:
            keadaan["gangguan"] -= 1
            self.badan()
            return self.jawab(503, {"error": {"code": 503, "message": "gangguan tiruan"}})
        if jalan == "/token":
            return self.token(self.badan())
        if self.headers.get("Authorization") != "Bearer " + TOKEN:
            return self.jawab(401, {"error": {"code": 401, "message": "token salah"}})
        awal = f"/v4/spreadsheets/{SID}"
        if not jalan.startswith(awal):
            return self.jawab(404, {"error": {"code": 404, "message": "spreadsheet tidak ada"}})
        sisa = jalan[len(awal):]
        badan = json.loads(self.badan() or b"{}")
        if cara == "GET" and sisa == "":
            return self.jawab(200, {"sheets": [{"properties": {
                "sheetId": t["sheetId"], "title": t["title"],
                "gridProperties": {"rowCount": t["rowCount"], "columnCount": t["columnCount"],
                                   "frozenRowCount": t["frozenRowCount"]}},
                **({"protectedRanges": t["protectedRanges"]} if t["protectedRanges"] else {})} for t in keadaan["tab"]]})
        if cara == "POST" and sisa == ":batchUpdate":
            for m in badan["requests"]:
                self.ubah(m)
            return self.jawab(200, {"replies": [{} for _ in badan["requests"]]})
        if cara == "POST" and sisa == "/values:batchClear":
            for r in badan["ranges"]:
                judul, *_ = urai_rentang(r)
                cari(judul)["values"] = []
            return self.jawab(200, {})
        if cara == "POST" and sisa == "/values:batchUpdate":
            if badan.get("valueInputOption") != "RAW":
                raise ValueError("uji: valueInputOption harus RAW")
            for d in badan["data"]:
                judul, b0, k0, _, _ = urai_rentang(d["range"])
                t = cari(judul)
                if t is None:
                    raise ValueError(f"tab {judul} tidak ada")
                tulis_sel(t, b0, k0, d["values"])
            return self.jawab(200, {})
        m = re.fullmatch(r"/values/(.+):append", sisa)
        if cara == "POST" and m:
            if tanya.get("valueInputOption") != ["RAW"]:
                raise ValueError("uji: valueInputOption harus RAW")
            judul, *_ = urai_rentang(m.group(1))
            t = cari(judul)
            b0 = len(bersih(t["values"]))
            t["rowCount"] = max(t["rowCount"], b0 + len(badan["values"]))
            tulis_sel(t, b0, 0, badan["values"])
            return self.jawab(200, {})
        if cara == "GET" and sisa == "/values:batchGet":
            if tanya.get("valueRenderOption") != ["UNFORMATTED_VALUE"]:
                raise ValueError("uji: harus UNFORMATTED_VALUE")
            hasil = []
            for r in tanya.get("ranges", []):
                judul, b0, k0, b1, k1 = urai_rentang(r)
                t = cari(judul)
                if t is None:
                    raise ValueError(f"tab {judul} tidak ada")
                v = t["values"]
                if b1 is not None:
                    v = [row[k0:k1 + 1] for row in v[b0:b1 + 1]]
                hasil.append({"range": r, "values": bersih(v)})
            return self.jawab(200, {"valueRanges": hasil})
        return self.jawab(404, {"error": {"code": 404, "message": f"tidak dikenal: {cara} {sisa}"}})

    def ubah(self, m):
        if "addSheet" in m:
            judul = m["addSheet"]["properties"]["title"]
            if cari(judul):
                raise ValueError(f"tab {judul} sudah ada")
            tab_baru(judul)
        elif "deleteSheet" in m:
            sid = m["deleteSheet"]["sheetId"]
            keadaan["tab"] = [t for t in keadaan["tab"] if t["sheetId"] != sid]
        elif "updateSheetProperties" in m:
            p = m["updateSheetProperties"]["properties"]
            t = next(t for t in keadaan["tab"] if t["sheetId"] == p["sheetId"])
            g = p.get("gridProperties", {})
            for k in ("rowCount", "columnCount", "frozenRowCount"):
                if k in g:
                    t[k] = g[k]
            t["values"] = [r[:t["columnCount"]] for r in t["values"][:t["rowCount"]]]
        elif "addProtectedRange" in m:
            pr = dict(m["addProtectedRange"]["protectedRange"])
            t = next(t for t in keadaan["tab"] if t["sheetId"] == pr["range"]["sheetId"])
            pr["protectedRangeId"] = len(t["protectedRanges"]) + 1
            t["protectedRanges"].append(pr)
        else:
            raise ValueError(f"permintaan tidak dikenal: {list(m)}")

    def token(self, badan):
        isi = urllib.parse.parse_qs(badan.decode())
        jwt = isi["assertion"][0]
        kepala, muatan, tanda = jwt.split(".")
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(b64d(tanda))
            jalur = f.name
        cek = subprocess.run(["openssl", "dgst", "-sha256", "-verify", KUNCI_PUBLIK, "-signature", jalur],
                             input=f"{kepala}.{muatan}".encode(), capture_output=True)
        m = json.loads(b64d(muatan))
        if cek.returncode != 0 or json.loads(b64d(kepala))["alg"] != "RS256" \
                or m.get("scope") != "https://www.googleapis.com/auth/spreadsheets" or not m.get("iss"):
            return self.jawab(401, {"error": "invalid_grant"})
        return self.jawab(200, {"access_token": TOKEN, "expires_in": 3600})

    def uji(self, jalan, badan):
        isi = json.loads(badan or b"{}")
        if jalan == "/uji/keadaan":
            return self.jawab(200, keadaan)
        if jalan == "/uji/ubah_sel":
            t = cari(isi["tab"])
            t["values"][isi["baris"]][isi["kolom"]] = isi["nilai"]
            return self.jawab(200, {})
        if jalan == "/uji/tambah_tab":
            tab_baru(isi["judul"])
            return self.jawab(200, {})
        if jalan == "/uji/ubah_kunci":
            cari(isi["tab"])["protectedRanges"][0].update(isi["isi"])
            return self.jawab(200, {})
        if jalan == "/uji/gangguan":
            keadaan["gangguan"] = isi["n"]
            return self.jawab(200, {})
        return self.jawab(404, {})


ThreadingHTTPServer(("127.0.0.1", PORT), Penjawab).serve_forever()
