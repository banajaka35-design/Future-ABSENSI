"""Penghubung kecil ke Google Sheets API untuk paket 6a (docs/rekap-sheets.md bagian 3).

Hanya pustaka bawaan Python dan `openssl` (untuk tanda tangan RS256). Dipakai oleh web/isi_sheets.py
dan web/periksa_sheets.py.

Lingkungan:
  GOOGLE_SA_KEY   isi file JSON kunci akun layanan (dari secret GitHub). Tidak pernah dicetak.
  SHEETS_ID       ID spreadsheet.
  SHEETS_API_URL  alamat API (bawaan https://sheets.googleapis.com; uji memakai Sheets tiruan).
"""
import base64
import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

LINGKUP = "https://www.googleapis.com/auth/spreadsheets"
TAB_RINGKASAN = "Ringkasan"
TAB_RIWAYAT = "Riwayat isi"
AWALAN_GAJI = "Gaji "
TANDA_KUNCI = "isi-otomatis"
CATATAN = ("Diisi otomatis dari gudang data. Jangan diubah dengan tangan: "
           "isinya ditimpa setiap kali diisi ulang.")


def milik_sistem(judul):
    return judul in (TAB_RINGKASAN, TAB_RIWAYAT) or judul.startswith(AWALAN_GAJI)


def rentang(judul, sel=""):
    nama = "'" + judul.replace("'", "''") + "'"
    return f"{nama}!{sel}" if sel else nama


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class Gagal(Exception):
    pass


class Sheets:
    def __init__(self):
        isi = os.environ.get("GOOGLE_SA_KEY", "")
        if not isi.strip():
            raise Gagal("secret GOOGLE_SA_KEY kosong")
        try:
            self.kunci = json.loads(isi)
        except json.JSONDecodeError:
            raise Gagal("GOOGLE_SA_KEY bukan JSON (isi dengan seluruh isi file kunci dari Google Cloud)") from None
        for k in ("client_email", "private_key", "token_uri"):
            if k not in self.kunci:
                raise Gagal(f"GOOGLE_SA_KEY tidak punya bagian {k}")
        self.email = self.kunci["client_email"]
        self.id = os.environ.get("SHEETS_ID", "").strip()
        if not self.id:
            raise Gagal("secret SHEETS_ID kosong")
        self.api = os.environ.get("SHEETS_API_URL", "https://sheets.googleapis.com").rstrip("/")
        self._token = None
        self._token_habis = 0
        self.jumlah_permintaan = 0

    # --- masuk -------------------------------------------------------------------------------
    def _jwt(self):
        sekarang = int(time.time())
        kepala = _b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
        isi = _b64(json.dumps({"iss": self.email, "scope": LINGKUP, "aud": self.kunci["token_uri"],
                               "iat": sekarang, "exp": sekarang + 3600}).encode())
        pesan = f"{kepala}.{isi}".encode()
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            os.chmod(f.name, 0o600)
            f.write(self.kunci["private_key"])
            jalur = f.name
        try:
            tanda = subprocess.run(["openssl", "dgst", "-sha256", "-sign", jalur], input=pesan,
                                   capture_output=True, check=True).stdout
        except subprocess.CalledProcessError:
            raise Gagal("kunci pribadi di GOOGLE_SA_KEY tidak bisa dipakai openssl") from None
        finally:
            os.unlink(jalur)
        return f"{kepala}.{isi}.{_b64(tanda)}"

    def token(self):
        if self._token and time.time() < self._token_habis - 60:
            return self._token
        badan = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                        "assertion": self._jwt()}).encode()
        jawab = self._kirim("POST", self.kunci["token_uri"], badan,
                            {"Content-Type": "application/x-www-form-urlencoded"}, pakai_token=False)
        self._token = jawab["access_token"]
        self._token_habis = time.time() + int(jawab.get("expires_in", 3600))
        return self._token

    # --- kirim dengan coba ulang -------------------------------------------------------------
    def _kirim(self, cara, alamat, badan=None, kepala=None, pakai_token=True):
        kepala = dict(kepala or {})
        for jeda in (1, 2, 4, 8, None):
            if pakai_token:
                kepala["Authorization"] = "Bearer " + self.token()
            minta = urllib.request.Request(alamat, data=badan, method=cara, headers=kepala)
            self.jumlah_permintaan += 1
            try:
                with urllib.request.urlopen(minta, timeout=120) as r:
                    teks = r.read().decode()
                    return json.loads(teks) if teks else {}
            except urllib.error.HTTPError as e:
                pesan = e.read().decode(errors="replace")[:500]
                if (e.code == 429 or e.code >= 500) and jeda is not None:
                    print(f"  Google menjawab HTTP {e.code}; coba ulang {jeda} detik lagi")
                    time.sleep(jeda)
                    continue
                raise Gagal(f"Google menjawab HTTP {e.code} untuk {cara} {alamat.split('?')[0]}: {pesan}") from None
            except urllib.error.URLError as e:
                if jeda is not None:
                    print(f"  Google tidak bisa dihubungi ({e.reason}); coba ulang {jeda} detik lagi")
                    time.sleep(jeda)
                    continue
                raise Gagal(f"Google tidak bisa dihubungi: {e.reason}") from None
        raise Gagal("tidak terjangkau")

    def _api(self, cara, jalan, badan=None, tanya=None):
        alamat = f"{self.api}/v4/spreadsheets/{urllib.parse.quote(self.id)}{jalan}"
        if tanya:
            alamat += "?" + urllib.parse.urlencode(tanya, doseq=True)
        data = json.dumps(badan).encode() if badan is not None else None
        return self._kirim(cara, alamat, data, {"Content-Type": "application/json"} if data else None)

    # --- perintah yang dipakai ---------------------------------------------------------------
    def info(self):
        return self._api("GET", "", tanya={"fields": "sheets(properties(sheetId,title,gridProperties),protectedRanges)"})

    def ubah(self, permintaan):
        if permintaan:
            return self._api("POST", ":batchUpdate", {"requests": permintaan})
        return {}

    def kosongkan(self, daftar_rentang):
        if daftar_rentang:
            self._api("POST", "/values:batchClear", {"ranges": daftar_rentang})

    def tulis(self, rentang_awal, baris):
        self._api("POST", "/values:batchUpdate",
                  {"valueInputOption": "RAW", "data": [{"range": rentang_awal, "values": baris}]})

    def tambah_baris(self, judul, baris):
        self._api("POST", "/values/" + urllib.parse.quote(rentang(judul, "A1"), safe="") + ":append",
                  {"values": baris}, tanya={"valueInputOption": "RAW", "insertDataOption": "INSERT_ROWS"})

    def baca(self, daftar_rentang):
        jawab = self._api("GET", "/values:batchGet", tanya={"ranges": daftar_rentang,
                                                             "valueRenderOption": "UNFORMATTED_VALUE"})
        return [v.get("values", []) for v in jawab.get("valueRanges", [])]
