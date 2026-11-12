"""Uji U1 (PRD bagian 16): hasil baca tap per orang per hari dibandingkan dengan kunci jawaban simulasi.

Kunci jawaban (data/simulasi/<pabrik>/kunci/) mencatat kejadian sebenarnya: hadir, alpha, sakit, libur,
lupa tap, tukar shift, beserta setiap tap yang ditulis ke file mesin. Skrip ini hanya membaca file data
dan hasil di database; ia tidak mengimpor kode generator dan tidak memakai kode sistem.

Setiap hari-orang masuk satu kelompok. Kelompok "wajib cocok" harus cocok 100%. Kelompok lain
(kejadian yang memang tidak bisa diketahui sistem dari data) diperiksa terhadap aturan bawaannya.
Pemakaian: DB_URL=... python3 sistem/uji/u1_banding.py A [--periode 1,2,3,4] [--tanpa-koreksi]
Keluar dengan kode 1 bila ada kelompok wajib cocok yang tidak cocok.
"""
import csv
import gzip
import io
import os
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta

AKAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "simulasi")


def psql_csv(sql):
    keluaran = subprocess.run(
        ["psql", os.environ["DB_URL"], "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c", f"copy ({sql}) to stdout with csv header"],
        check=True, capture_output=True, text=True).stdout
    return list(csv.DictReader(io.StringIO(keluaran)))


def baca_gz(jalur):
    with gzip.open(jalur, "rt", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def jam(s):
    return datetime.strptime(s[:19], "%Y-%m-%d %H:%M:%S") if s else None


def main():
    args = sys.argv[1:]
    pabrik = args[0] if args else "A"
    periode = [1, 2, 3, 4]
    if "--periode" in args:
        periode = [int(x) for x in args[args.index("--periode") + 1].split(",")]
    tanpa_koreksi = "--tanpa-koreksi" in args

    # Hasil sistem: versi terakhir tiap periode. Waktu dibaca dalam WIB.
    hasil = {}
    for r in psql_csv("""
        select h.id_karyawan, h.tanggal, h.status, h.asal, h.kode_jadwal, h.lupa_tap, h.ambigu, h.menit_telat,
               to_char(h.masuk at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS') as masuk,
               to_char(h.pulang at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS') as pulang,
               array_to_string(h.tanda, ',') as tanda
        from hitung.hasil_harian h join hitung.versi_terakhir v on v.id = h.versi_id"""):
        hasil[(r["id_karyawan"], r["tanggal"])] = r
    usulan = {(r["id_karyawan"], r["tanggal"]) for r in psql_csv(
        "select a.id_karyawan, a.tanggal from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id "
        "where a.jenis = 'usulan_tukar_shift'")}
    # Tap yang oleh sistem dimasukkan ke hari kerja tertentu (untuk mengenali tap pagi yang diambil
    # jendela shift malam hari sebelumnya).
    tap_ke_hari = {(r["id_karyawan"], r["w"]): r["tanggal_kerja"] for r in psql_csv(
        "select b.id_karyawan, to_char(b.waktu_baku at time zone 'Asia/Jakarta', 'YYYY-MM-DD HH24:MI:SS') as w, "
        "b.tanggal_kerja from hitung.tap_bersih b join hitung.versi_terakhir v on v.id = b.versi_id "
        "where b.tanggal_kerja is not null")}
    belum_daftar = {r["id_karyawan"] for r in psql_csv(
        "select a.id_karyawan from hitung.anomali a join hitung.versi_terakhir v on v.id = a.versi_id "
        "where a.jenis = 'belum_terdaftar_mesin'")}

    kelompok = Counter()
    jumlah_hari = 0
    tidak_cocok = defaultdict(list)
    wajib = set()

    def catat(nama, cocok, contoh, harus=True):
        if harus:
            wajib.add(nama)
        kelompok[(nama, cocok)] += 1
        if not cocok and len(tidak_cocok[nama]) < 8:
            tidak_cocok[nama].append(contoh)

    # Jam jadwal (data induk simulasi) untuk menilai tap tunggal: generator menaruh "tap tengah" 3-5 jam
    # setelah jam masuk tanpa melihat panjang shift, jadi di shift Sabtu 5 jam tap itu sebenarnya dekat jam pulang.
    jadwal = {}
    with open(os.path.join(AKAR, pabrik, "induk", "jam_jadwal.csv"), encoding="utf-8") as f:
        for j in csv.DictReader(f):
            jadwal[j["kode"]] = (j["masuk"], j["pulang"])
    # Absen manual dari HRD (masukan HRD): sistem mengikuti perintah HRD walau kunci mencatat orang itu alpha.
    absen_manual = set()
    for jalur in sorted(os.listdir(os.path.join(AKAR, pabrik, "masukan_hrd"))):
        for m in baca_gz(os.path.join(AKAR, pabrik, "masukan_hrd", jalur)):
            if m["jenis"] == "absen_manual":
                absen_manual.add((m["nilai"], m["tanggal_mulai"]))
    belum_daftar_hari = Counter()
    for p in periode:
        for k in baca_gz(os.path.join(AKAR, pabrik, "kunci", f"{pabrik}_p{p}_kejadian.csv.gz")):
            if k["kejadian"] == "hadir" and "belum terdaftar di mesin" in k["catatan"]:
                belum_daftar_hari[k["id_karyawan"]] += 1

    def dekat_pulang(kode, tanggal, t):
        m, pl = jadwal[kode]
        awal = datetime.strptime(f"{tanggal} {m}", "%Y-%m-%d %H:%M")
        akhir = datetime.strptime(f"{tanggal} {pl}", "%Y-%m-%d %H:%M")
        if akhir <= awal:
            akhir += timedelta(days=1)
        return t >= akhir - (akhir - awal) / 4

    # Semua periode dibaca supaya hari sebelah di periode lain (misalnya tanggal 20 untuk tanggal 21) terlihat.
    per_hari = {}
    for p in (1, 2, 3, 4):
        jalur = os.path.join(AKAR, pabrik, "kunci", f"{pabrik}_p{p}_kejadian.csv.gz")
        if os.path.exists(jalur):
            for k in baca_gz(jalur):
                per_hari[(k["id_karyawan"], k["tanggal_kerja"])] = k

    def tetangga(k, geser):
        d = (datetime.strptime(k["tanggal_kerja"], "%Y-%m-%d") + timedelta(days=geser)).strftime("%Y-%m-%d")
        return per_hari.get((k["id_karyawan"], d)) or {}

    # Tap per orang per hari kerja dari jejak tap (waktu mesin dikurangi selisih jam = waktu sebenarnya).
    tap = defaultdict(list)
    for p in (1, 2, 3, 4):
        jalur = os.path.join(AKAR, pabrik, "kunci", f"{pabrik}_p{p}_jejak_tap.csv.gz")
        if not os.path.exists(jalur):
            continue
        for t in baca_gz(jalur):
            if not t["id_karyawan"]:
                continue
            w = jam(t["waktu"])
            if not tanpa_koreksi:
                w -= timedelta(minutes=int(t["selisih_jam"] or 0))
            tap[(t["id_karyawan"], t["tanggal_kerja"])].append(w)

    def hari_geser(k, geser):
        return (datetime.strptime(k["tanggal_kerja"], "%Y-%m-%d") + timedelta(days=geser)).strftime("%Y-%m-%d")

    def silang(k):
        # Data simulasi kadang menulis tap datang shift berikutnya lebih awal dari tap pulang shift
        # sebelumnya (tidak mungkin bagi satu orang). Sistem memakai urutan waktu, jadi kedua hari itu
        # tidak bisa dicocokkan per tap.
        for a, b in ((hari_geser(k, -1), k["tanggal_kerja"]), (k["tanggal_kerja"], hari_geser(k, 1))):
            ta, tb = tap.get((k["id_karyawan"], a)), tap.get((k["id_karyawan"], b))
            if ta and tb and max(ta) > min(tb):
                return True
        return False

    for p in periode:
        kejadian = baca_gz(os.path.join(AKAR, pabrik, "kunci", f"{pabrik}_p{p}_kejadian.csv.gz"))

        for k in kejadian:
            jumlah_hari += 1
            kunci = (k["id_karyawan"], k["tanggal_kerja"])
            h = hasil.get(kunci)
            kj = k["kejadian"]
            contoh = f"{kunci} kunci={kj}/{k['kode_jadwal']} {k['catatan']} -> " + (
                f"{h['status']}/{h['kode_jadwal']} masuk={h['masuk']} pulang={h['pulang']} lupa={h['lupa_tap']} {h['tanda']}"
                if h else "TIDAK ADA")
            if h is None:
                catat("hari ada di kunci dan di hasil", False, contoh)
                continue
            if h["status"] == "menunggu":
                catat("menunggu data (jendela melewati cakupan file)", True, contoh, harus=False)
                continue
            besok = tetangga(k, 1)
            if k["kode_jadwal"] == "M" and besok.get("kejadian") == "lembur_hari_libur":
                # Data simulasi tidak realistis: lembur shift pagi di hari libur tepat setelah shift malam.
                # Tap datang lembur (sekitar jam 07) tercampur dengan tap pulang shift malam.
                catat("shift malam diikuti lembur hari libur (tap pagi tercampur)", True, contoh, harus=False)
                continue
            if besok.get("tukar_shift_ke") and besok.get("dilaporkan_hrd") == "tidak":
                # Tap hari berikutnya mengikuti shift lain yang tidak dilaporkan; bisa masuk jendela hari ini.
                catat("hari sebelum tukar shift tidak dilaporkan", True, contoh, harus=False)
                continue
            tak_lapor = k["tukar_shift_ke"] and k["dilaporkan_hrd"] == "tidak"
            if silang(k) and not tak_lapor:
                catat("shift berurutan dengan tap tidak berurutan di data simulasi", h["status"] in ("hadir", "lembur_hari_libur"),
                      contoh, harus=False)
                continue
            if kj in ("libur", "libur_nasional", "cuti_bersama_dibayar"):
                catat("libur", h["status"] == "libur", contoh)
            elif kj in ("sakit", "izin", "cuti"):
                catat("sakit/izin/cuti dari perintah HRD", h["status"] == kj and h["asal"] == "perintah", contoh)
            elif kj == "hadir_tidak_wajib_tap":
                catat("tidak wajib tap", h["status"] == "hadir" and h["asal"] == "tidak_wajib_tap", contoh)
            elif kj == "alpha" and (k["divisi"], k["tanggal_kerja"]) in absen_manual:
                catat("alpha di hari absen manual HRD: mengikuti perintah HRD", h["status"] == "hadir" and h["asal"] == "manual", contoh)
            elif kj == "alpha":
                catat("alpha", h["status"] in ("alpha", "tanpa_tap_massal"), contoh)
            elif kj == "lembur_hari_libur" and (
                    tetangga(k, -1).get("kode_jadwal") == "M"
                    or (tap[kunci] and tap_ke_hari.get((k["id_karyawan"], min(tap[kunci]).isoformat(" ")))
                        == (datetime.strptime(k["tanggal_kerja"], "%Y-%m-%d") - timedelta(days=1)).strftime("%Y-%m-%d"))):
                # Data simulasi: lembur shift pagi di hari libur tepat setelah shift malam; tap datang lembur
                # (sekitar jam 07) tercampur dengan tap pulang shift malam dan masuk jendela shift malam.
                catat("lembur hari libur tepat setelah shift malam (tap pagi diambil shift malam)",
                      h["status"] == "lembur_hari_libur", contoh, harus=False)
            elif kj == "lembur_hari_libur":
                ts = sorted(tap[kunci])
                ok = h["status"] == "lembur_hari_libur" and h["masuk"] == (ts[0].isoformat(" ") if ts else None)
                catat("lembur hari libur", ok, contoh)
            elif kj == "hadir" and k["mesin_mati"] == "dilaporkan":
                catat("mesin mati, absen manual HRD", h["status"] == "hadir" and h["asal"] == "manual", contoh)
            elif kj == "hadir" and "belum terdaftar di mesin" in k["catatan"]:
                # Sistem tidak bisa tahu: aturan bawaan alpha + pemberitahuan "belum didaftar di mesin?" (F13).
                catat("karyawan baru belum terdaftar: alpha", h["status"] in ("alpha", "tanpa_tap_massal"), contoh)
                if belum_daftar_hari[k["id_karyawan"]] >= 2:
                    # PRD celah P3: tanda setelah 2-3 hari kerja tanpa tap.
                    catat("karyawan baru belum terdaftar 2 hari kerja atau lebih: ada pemberitahuan",
                          k["id_karyawan"] in belum_daftar, contoh)
            elif kj == "hadir" and k["tukar_shift_ke"] and k["dilaporkan_hrd"] == "tidak":
                # Sebelum disetujui hasil mengikuti jadwal (F11); yang diperiksa: ada usulan tukar shift.
                catat("tukar shift tidak dilaporkan: ada usulan", kunci in usulan, contoh, harus=False)
            elif kj == "hadir":
                ts = sorted(tap[kunci])
                if not ts:
                    catat("hadir tanpa tap di file", False, contoh)
                    continue
                awal, akhir = ts[0].isoformat(" "), ts[-1].isoformat(" ")
                if k["tap_tengah"] == "ya" and dekat_pulang(k["kode_jadwal"], k["tanggal_kerja"], ts[0]):
                    ok = h["status"] == "hadir" and h["lupa_tap"] == "masuk" and h["pulang"] == akhir
                    catat("tap tunggal dekat jam pulang shift pendek (B07)", ok, contoh)
                elif k["tap_tengah"] == "ya":
                    ok = h["status"] == "hadir" and h["lupa_tap"] == "pulang" and h["ambigu"] == "t" and h["masuk"] == awal
                    catat("tap tunggal di tengah shift (B08)", ok, contoh)
                elif k["lupa_tap"] == "masuk":
                    catat("lupa tap masuk", h["status"] == "hadir" and h["lupa_tap"] == "masuk" and h["pulang"] == akhir, contoh)
                elif k["lupa_tap"] == "pulang":
                    catat("lupa tap pulang", h["status"] == "hadir" and h["lupa_tap"] == "pulang" and h["masuk"] == awal, contoh)
                else:
                    ok = (h["status"] == "hadir" and h["lupa_tap"] == "" and h["masuk"] == awal and h["pulang"] == akhir)
                    nama = "hadir (tukar shift dilaporkan)" if k["tukar_shift_ke"] else "hadir, masuk dan pulang sama dengan tap"
                    catat(nama, ok, contoh)
                    if ok and not k["tukar_shift_ke"]:
                        catat("kode jadwal sama dengan kunci", h["kode_jadwal"] == k["kode_jadwal"], contoh)
            else:
                catat(f"kejadian lain: {kj}", False, contoh)

    gagal = False
    print(f"U1 Pabrik {pabrik}, periode {periode}{' (tanpa koreksi jam mesin)' if tanpa_koreksi else ''}")
    nama_kelompok = sorted({n for n, _ in kelompok})
    for n in nama_kelompok:
        cocok, beda = kelompok[(n, True)], kelompok[(n, False)]
        tanda = "wajib" if n in wajib else "info "
        print(f"  [{tanda}] {n}: {cocok} cocok, {beda} tidak cocok")
        if beda and n in wajib:
            gagal = True
        for c in tidak_cocok[n]:
            print(f"           {c}")
    print(f"  Hari-orang di kunci jawaban: {jumlah_hari}; hari-orang di hasil sistem: {len(hasil)}")
    print("U1: " + ("GAGAL" if gagal else "LULUS"))
    sys.exit(1 if gagal else 0)


if __name__ == "__main__":
    main()
