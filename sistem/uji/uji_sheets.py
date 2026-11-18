"""Uji paket 6a dengan Sheets tiruan dan gudang berisi data simulasi (docs/rekap-sheets.md bagian 6).

Butuh DB_URL ke gudang yang gajinya sudah dihitung (dipanggil dari sistem/uji/jalankan_simulasi.sh).
Mencetak satu baris "  LULUS ..." atau "  GAGAL ..." per uji; keluar 1 bila ada yang gagal.
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

AKAR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SID = "spreadsheet-uji"
SA = "isi-sheets@uji.iam.gserviceaccount.com"
hasil = {"lulus": 0, "gagal": 0}


def cek(nama, ok, keterangan=""):
    if ok:
        print(f"  LULUS  Sheets: {nama}")
        hasil["lulus"] += 1
    else:
        print(f"  GAGAL  Sheets: {nama} {keterangan}")
        hasil["gagal"] += 1


def port_kosong():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def main():
    kerja = tempfile.mkdtemp()
    pribadi, publik = os.path.join(kerja, "k.pem"), os.path.join(kerja, "p.pem")
    subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", pribadi],
                   check=True, capture_output=True)
    subprocess.run(["openssl", "pkey", "-in", pribadi, "-pubout", "-out", publik], check=True, capture_output=True)
    port = port_kosong()
    tiruan = subprocess.Popen([sys.executable, os.path.join(AKAR, "sistem/uji/sheets_tiruan.py"), str(port), publik, SID])
    alamat = f"http://127.0.0.1:{port}"
    for _ in range(50):
        try:
            urllib.request.urlopen(alamat + "/uji/keadaan", data=b"{}", timeout=1)
            break
        except OSError:
            time.sleep(0.1)
    with open(pribadi) as f:
        kunci = {"type": "service_account", "client_email": SA, "private_key": f.read(), "token_uri": alamat + "/token"}
    env = dict(os.environ, GOOGLE_SA_KEY=json.dumps(kunci), SHEETS_ID=SID, SHEETS_API_URL=alamat,
               GITHUB_SHA="uji-6a", PEMICU="uji")

    def jalan(*arg, e=None):
        r = subprocess.run([sys.executable, *arg], cwd=AKAR, env=e or env, capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def isi(e=None):
        return jalan("web/isi_sheets.py", "isi", e=e)

    def periksa():
        return jalan("web/periksa_sheets.py")

    def admin(jalan_, isi_=None):
        with urllib.request.urlopen(alamat + jalan_, data=json.dumps(isi_ or {}).encode(), timeout=10) as r:
            return json.loads(r.read())

    def tab(k, judul):
        return next(t for t in k["tab"] if t["title"] == judul)

    try:
        # 1. Isi pertama dan periksa.
        mulai = time.monotonic()
        kode, keluar = isi()
        lama = round((time.monotonic() - mulai) * 1000)
        cek("isi pertama berhasil", kode == 0, keluar[-800:])
        print("    " + "\n    ".join(x for x in keluar.splitlines() if x.strip()))
        print(f"    Lama isi pertama di Sheets tiruan (termasuk baca gudang): {lama} ms")
        kode, keluar = periksa()
        cek("pemeriksa lulus sesudah isi", kode == 0, keluar[-1500:])
        print("    " + keluar.strip().splitlines()[-1])

        k = admin("/uji/keadaan")
        judul = [t["title"] for t in k["tab"]]
        gaji = [t for t in judul if t.startswith("Gaji ")]
        cek("8 tab Gaji (transfer + tunai per periode) + Ringkasan + Riwayat isi + tab HRD",
            len(gaji) == 8 and sum(x.endswith(" transfer") for x in gaji) == 4 and sum(x.endswith(" tunai") for x in gaji) == 4
            and "Ringkasan" in judul
            and "Riwayat isi" in judul and "Sheet1" in judul, judul)
        cek("tab buatan HRD tidak disentuh", tab(k, "Sheet1")["values"] == [["catatan HRD, jangan disentuh sistem"]])
        g = tab(k, gaji[0])
        kepala = g["values"][1]
        cek("tidak ada kolom rekening", not any("rekening" in str(x).lower() for x in kepala), kepala)
        cek("ID ditulis sebagai teks di semua baris", all(isinstance(r[0], str) for r in g["values"][2:]))
        i_bersih = kepala.index("Gaji bersih")
        rahasia = [r for r in g["values"][2:] if len(r) > i_bersih and r[i_bersih] is None]
        cek("3 orang rahasia: angka kosong, hitungan hadir terisi",
            len(rahasia) == 3 and all(all(x is None for x in r[13:]) and isinstance(r[4], int) for r in rahasia),
            [r[:6] for r in rahasia])
        cek("setiap tab milik sistem punya tepat 1 kunci untuk akun layanan saja",
            all(len(t["protectedRanges"]) == 1 and t["protectedRanges"][0]["editors"]["users"] == [SA]
                for t in k["tab"] if t["title"] != "Sheet1"))
        tunai = [x for x in gaji if x.endswith(" tunai")]
        kt = tab(k, tunai[0])["values"][1]
        semua_tunai = [r for x in tunai for r in tab(k, x)["values"][2:]]
        cek("tab tunai: semua orang tunai dan bagian Gudang",
            semua_tunai and all(r[3] == "tunai" and r[2] == "GDG" for r in semua_tunai), {(r[2], r[3]) for r in semua_tunai})
        semua_transfer = [r for x in gaji if x.endswith(" transfer") for r in tab(k, x)["values"][2:]]
        cek("tab transfer: semua orang transfer, tidak ada Gudang",
            semua_transfer and all(r[3] == "transfer" and r[2] != "GDG" for r in semua_transfer))
        i_amp = [i for i, x in enumerate(kt) if str(x).startswith("Amplop Rp")]
        nilai_amp = [int(str(kt[i]).split("Rp")[1].split(" ")[0].replace(".", "")) for i in i_amp]
        i_dibayar = kt.index("Dibayar")
        cek("tab tunai punya 7 kolom amplop (Rp100.000 sampai Rp1.000)", nilai_amp == [100000, 50000, 20000, 10000, 5000, 2000, 1000], nilai_amp)
        cek("isi amplop setiap orang tunai = dibayar",
            all(sum(r[i] * d for i, d in zip(i_amp, nilai_amp)) == max(r[i_dibayar], 0) for r in semua_tunai))
        cek("tab transfer tanpa kolom amplop", not any(str(x).startswith("Amplop") for x in tab(k, gaji[0])["values"][1]))
        cek("baris 1-2 dibekukan di tab Gaji, 1-4 di Ringkasan",
            g["frozenRowCount"] == 2 and tab(k, "Ringkasan")["frozenRowCount"] == 4)

        # 2. Status selesai.
        kode, _ = jalan("web/isi_sheets.py", "status", "SELESAI")
        k = admin("/uji/keadaan")
        cek("status SELESAI tertulis", kode == 0 and str(tab(k, "Ringkasan")["values"][1][1]).startswith("SELESAI"))

        # 3. Isi ulang: tidak dobel.
        kode, _ = isi()
        k = admin("/uji/keadaan")
        cek("isi ulang: jumlah tab dan kunci tetap",
            kode == 0 and len(k["tab"]) == 11 and all(len(t["protectedRanges"]) == 1 for t in k["tab"] if t["title"] != "Sheet1"))
        cek("isi ulang: Riwayat isi bertambah satu baris", len(tab(k, "Riwayat isi")["values"]) == 4)
        cek("isi ulang: status kembali SEDANG DIISI sampai diperiksa",
            str(tab(k, "Ringkasan")["values"][1][1]).startswith("SEDANG DIISI"))
        cek("pemeriksa lulus sesudah isi ulang", periksa()[0] == 0)

        # 4. Satu sel angka diubah -> GAGAL.
        baris = next(i for i, r in enumerate(tab(k, gaji[1])["values"][2:], 2) if r[i_bersih] is not None)
        asli = tab(k, gaji[1])["values"][baris][i_bersih]
        admin("/uji/ubah_sel", {"tab": gaji[1], "baris": baris, "kolom": i_bersih, "nilai": asli + 1})
        kode, keluar = periksa()
        cek("satu sel gaji bersih diubah 1 rupiah -> pemeriksa GAGAL", kode == 1 and "Gaji bersih" in keluar, keluar[-600:])
        isi()

        # 5. Sel orang rahasia diisi -> GAGAL.
        k = admin("/uji/keadaan")
        g = tab(k, gaji[0])
        br = next(i for i, r in enumerate(g["values"][2:], 2) if len(r) > i_bersih and r[i_bersih] is None)
        admin("/uji/ubah_sel", {"tab": gaji[0], "baris": br, "kolom": i_bersih, "nilai": 5000000})
        cek("angka orang rahasia muncul -> pemeriksa GAGAL", periksa()[0] == 1)
        isi()

        # 6. ID menjadi angka -> GAGAL.
        k = admin("/uji/keadaan")
        g = tab(k, gaji[2])
        admin("/uji/ubah_sel", {"tab": gaji[2], "baris": 2, "kolom": 0, "nilai": int(g["values"][2][0])})
        kode, keluar = periksa()
        cek("ID tersimpan sebagai angka -> pemeriksa GAGAL", kode == 1 and "bukan teks" in keluar, keluar[-400:])
        isi()

        # 7. Uji teks panjang rusak -> GAGAL.
        k = admin("/uji/keadaan")
        rw = tab(k, "Riwayat isi")["values"]
        admin("/uji/ubah_sel", {"tab": "Riwayat isi", "baris": len(rw) - 1, "kolom": 6, "nilai": 123456789012345680})
        cek("teks 18 digit berubah jadi angka -> pemeriksa GAGAL", periksa()[0] == 1)
        isi()

        # 8. Tab Gaji periode yang tidak ada -> GAGAL, lalu dihapus oleh isi.
        admin("/uji/tambah_tab", {"judul": "Gaji 2025-01-01 sd 2025-01-31"})
        cek("tab Gaji lama tertinggal -> pemeriksa GAGAL", periksa()[0] == 1)
        isi()
        k = admin("/uji/keadaan")
        cek("isi menghapus tab Gaji lama", all(t["title"] != "Gaji 2025-01-01 sd 2025-01-31" for t in k["tab"]))
        cek("pemeriksa lulus lagi", periksa()[0] == 0)

        # 8a. Tab versi 1 (tanpa akhiran transfer/tunai) dihapus oleh isi.
        admin("/uji/tambah_tab", {"judul": "Gaji 2026-01-21 sd 2026-02-20"})
        cek("tab Gaji versi 1 tertinggal -> pemeriksa GAGAL", periksa()[0] == 1)
        isi()
        k = admin("/uji/keadaan")
        cek("isi menghapus tab Gaji versi 1", all(t["title"] != "Gaji 2026-01-21 sd 2026-02-20" for t in k["tab"]))

        # 8d. Satu lembar amplop diubah -> GAGAL.
        g = tab(k, tunai[0])
        admin("/uji/ubah_sel", {"tab": tunai[0], "baris": 2, "kolom": i_amp[0], "nilai": g["values"][2][i_amp[0]] + 1})
        kode, keluar = periksa()
        cek("satu lembar amplop ditambah -> pemeriksa GAGAL", kode == 1 and "amplop" in keluar.lower(), keluar[-400:])
        isi()

        # 8e. Orang transfer ditaruh di tab tunai -> GAGAL.
        k = admin("/uji/keadaan")
        id_transfer = tab(k, gaji[0])["values"][2][0]
        admin("/uji/ubah_sel", {"tab": tunai[0], "baris": 2, "kolom": 0, "nilai": id_transfer})
        kode, keluar = periksa()
        cek("orang transfer di tab tunai -> pemeriksa GAGAL", kode == 1 and "cara bayar tunai" in keluar, keluar[-400:])
        isi()
        cek("pemeriksa lulus sesudah dipulihkan", periksa()[0] == 0)

        # 8b. Ringkasan diubah -> GAGAL.
        k = admin("/uji/keadaan")
        admin("/uji/ubah_sel", {"tab": "Ringkasan", "baris": 4, "kolom": 9, "nilai": tab(k, "Ringkasan")["values"][4][9] - 1})
        kode, keluar = periksa()
        cek("total gaji bersih di Ringkasan diubah -> pemeriksa GAGAL", kode == 1 and "Total gaji bersih" in keluar, keluar[-400:])
        isi()

        # 8f. Total Ringkasan dikembalikan ke cara lama (termasuk orang rahasia) -> GAGAL (F15b).
        lama = subprocess.run(["psql", os.environ["DB_URL"], "-X", "-q", "-t", "-A", "-c",
                               "select sum(g.gaji_bersih) from hitung.ringkasan_gaji g join hitung.versi_terakhir v "
                               "on v.id = g.versi_id and v.jenis = 'hitung_gaji' join fakta.periode p on p.id = v.periode_id "
                               "where p.tanggal_awal = (select min(tanggal_awal) from fakta.periode)"],
                              capture_output=True, text=True, check=True).stdout.strip()
        k = admin("/uji/keadaan")
        sekarang = tab(k, "Ringkasan")["values"][4][9]
        cek("Ringkasan tanpa orang rahasia (lebih kecil dari total lengkap gudang)", int(lama) > sekarang, (lama, sekarang))
        cek("Ringkasan berketerangan rahasia di baris 3", str(tab(k, "Ringkasan")["values"][2][0]).startswith("Total tidak termasuk"))
        admin("/uji/ubah_sel", {"tab": "Ringkasan", "baris": 4, "kolom": 9, "nilai": int(lama)})
        kode, keluar = periksa()
        cek("total cara lama (termasuk rahasia) -> pemeriksa GAGAL (F15b)", kode == 1 and "F15b" in keluar, keluar[-500:])
        isi()

        # 8c. Kunci dilonggarkan (orang lain boleh mengubah) -> GAGAL.
        admin("/uji/ubah_kunci", {"tab": gaji[0], "isi": {"editors": {"users": [SA, "orang.lain@contoh.id"]}}})
        cek("kunci tab mengizinkan akun lain -> pemeriksa GAGAL", periksa()[0] == 1)
        admin("/uji/ubah_kunci", {"tab": gaji[0], "isi": {"warningOnly": True, "editors": {"users": [SA]}}})
        cek("kunci tab hanya peringatan -> pemeriksa GAGAL", periksa()[0] == 1)
        admin("/uji/ubah_kunci", {"tab": gaji[0], "isi": {"warningOnly": False}})
        cek("kunci dikembalikan -> pemeriksa lulus", periksa()[0] == 0)

        # 9. Google sesaat menolak (503 dua kali) -> isi tetap berhasil lewat coba ulang.
        admin("/uji/gangguan", {"n": 2})
        kode, keluar = isi()
        cek("dua jawaban 503 -> coba ulang, isi berhasil", kode == 0 and "coba ulang" in keluar, keluar[-400:])
        cek("pemeriksa lulus sesudah gangguan", periksa()[0] == 0)

        # 10. Secret kosong -> GAGAL dengan pesan jelas.
        kode, keluar = isi(e=dict(env, GOOGLE_SA_KEY=""))
        cek("GOOGLE_SA_KEY kosong -> GAGAL dengan pesan", kode == 1 and "GOOGLE_SA_KEY" in keluar, keluar[-300:])
        kode, keluar = isi(e=dict(env, SHEETS_ID=""))
        cek("SHEETS_ID kosong -> GAGAL dengan pesan", kode == 1 and "SHEETS_ID" in keluar, keluar[-300:])

        # 11. Status GAGAL bisa ditulis.
        jalan("web/isi_sheets.py", "status", "GAGAL")
        k = admin("/uji/keadaan")
        cek("status GAGAL tertulis", str(tab(k, "Ringkasan")["values"][1][1]).startswith("GAGAL"))
        print(f"    Permintaan ke Sheets tiruan selama uji: {k['jumlah']}")
    finally:
        tiruan.terminate()
    sys.exit(1 if hasil["gagal"] else 0)


if __name__ == "__main__":
    main()
