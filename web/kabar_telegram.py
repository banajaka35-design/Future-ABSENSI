"""Kabar akhir "Isi Sheets" ke Telegram (paket 6e, celah C3; docs/rekap-sheets.md bagian 4).

Dikirim ke semua akun aktif berperan hrd atau pembangun (fakta.penerima, dibaca dari gudang). Bot token tidak
pernah dicetak. Gagal mengirim tidak menggagalkan workflow (hasil isi Sheets sudah tertulis di Sheets).

Lingkungan: DB_URL, TELEGRAM_BOT_TOKEN, WAKTU_FILE (ISO, boleh kosong), ADA_RUN_MENUNGGU ("ya"/kosong),
TELEGRAM_API_URL (bawaan https://api.telegram.org; uji memakai tiruan).
Pemakaian: python3 web/kabar_telegram.py SELESAI|GAGAL
"""
import datetime
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

WIB = datetime.timezone(datetime.timedelta(hours=7))


def susun(status, sekarang, waktu_file, ada_menunggu):
    jam = sekarang.astimezone(WIB).strftime("%Y-%m-%d %H:%M WIB")
    lama = ""
    if waktu_file:
        try:
            awal = datetime.datetime.fromisoformat(waktu_file.replace("Z", "+00:00"))
            lama = f" Lama sejak file masuk: {round((sekarang - awal).total_seconds())} detik."
        except ValueError:
            lama = ""
    if status == "SELESAI":
        return f"Sheets SELESAI diperbarui {jam}, diperiksa sama dengan gudang.{lama}"
    lanjut = " Sudah ada pengisian ulang yang menunggu; tunggu kabar berikutnya." if ada_menunggu else ""
    return f"Sheets GAGAL diperbarui {jam}; JANGAN dipakai sampai ada kabar SELESAI.{lanjut}"


def penerima():
    keluar = subprocess.run(["psql", os.environ["DB_URL"], "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c",
                             "select array_to_json(fakta.penerima(array['hrd', 'pembangun']))"],
                            check=True, capture_output=True, text=True).stdout.strip()
    return json.loads(keluar or "[]")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("SELESAI", "GAGAL"):
        print(__doc__)
        sys.exit(2)
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    if not token:
        print("Kabar Telegram dilewati: TELEGRAM_BOT_TOKEN kosong")
        return
    teks = susun(sys.argv[1], datetime.datetime.now(datetime.timezone.utc), os.environ.get("WAKTU_FILE", ""),
                 os.environ.get("ADA_RUN_MENUNGGU") == "ya")
    api = os.environ.get("TELEGRAM_API_URL", "https://api.telegram.org").rstrip("/")
    try:
        daftar = penerima()
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        print("Kabar Telegram dilewati: daftar penerima tidak bisa dibaca")
        return
    terkirim = 0
    for tg in daftar:
        badan = json.dumps({"chat_id": tg, "text": teks}).encode()
        minta = urllib.request.Request(f"{api}/bot{token}/sendMessage", data=badan, method="POST",
                                       headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(minta, timeout=30) as r:
                terkirim += 1 if r.status == 200 else 0
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  gagal mengirim ke satu penerima ({getattr(e, 'code', 'jaringan')})")
    print(f"Kabar Telegram: {terkirim} dari {len(daftar)} penerima; isi: {teks}")


if __name__ == "__main__":
    main()
