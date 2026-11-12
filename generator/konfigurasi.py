"""Konfigurasi data simulasi Pabrik A dan Pabrik B (PRD v3.1 bagian 5 dan 11).

Semua angka di sini adalah karangan untuk menguji sistem. Generator hanya
memakai angka ini untuk membuat KEJADIAN; ia tidak menerapkan aturan telat,
jendela tap, atau rumus gaji.
"""

# Jam kerja per kode jadwal: (jam masuk, jam pulang, menit). Pulang lebih kecil
# dari masuk berarti melewati tengah malam.
JAM_JADWAL = {
    "P": ("07:00", "15:00"),    # shift pagi
    "S": ("15:00", "23:00"),    # shift siang
    "M": ("23:00", "07:00"),    # shift malam
    "K": ("08:00", "16:00"),    # kantor Senin-Jumat
    "K5": ("08:00", "13:00"),   # kantor Sabtu (hari pendek)
    "KR": ("08:00", "15:00"),   # kantor Ramadan Senin-Jumat
    "KR5": ("08:00", "12:00"),  # kantor Ramadan Sabtu
}

# Ramadan 1447 H: puasa mulai 19 Feb 2026, Idul Fitri 21 Mar 2026.
RAMADAN = ("2026-02-19", "2026-03-20")

# Kalender 2026 sesuai SKB 3 Menteri (dicek 12 Nov 2026).
LIBUR_NASIONAL = {
    "2026-01-16": "Isra Mikraj",
    "2026-02-17": "Tahun Baru Imlek",
    "2026-03-19": "Hari Suci Nyepi",
    "2026-03-21": "Idul Fitri",
    "2026-03-22": "Idul Fitri",
    "2026-04-03": "Wafat Yesus Kristus",
    "2026-04-05": "Paskah",
    "2026-12-25": "Natal",
}
CUTI_BERSAMA = {
    "2026-02-16": "Cuti bersama Imlek",
    "2026-03-18": "Cuti bersama Nyepi",
    "2026-03-20": "Cuti bersama Idul Fitri",
    "2026-03-23": "Cuti bersama Idul Fitri",
    "2026-03-24": "Cuti bersama Idul Fitri",
    "2026-12-24": "Cuti bersama Natal",
}

# Peluang kejadian per hari kerja terjadwal (PRD bagian 5).
PELUANG = {
    "alpha": 0.006,
    "sakit": 0.007,
    "izin": 0.004,
    "cuti": 0.005,
    "telat": 0.04,          # datang 6-90 menit setelah jam masuk
    "pulang_cepat": 0.01,   # pulang 15-120 menit sebelum jam pulang
    "lupa_tap": 0.015,      # separuh lupa masuk, separuh lupa pulang
    "tap_tengah": 0.002,    # hanya satu tap di tengah shift
    "tap_ulang": 0.03,      # tap kedua 1-5 menit setelah tap asli
    "status_terbalik": 0.05,  # per tap
    "baris_dobel": 0.002,   # per tap, baris identik ditulis dua kali
    "tukar_shift": 0.003,   # per hari kerja pola rotasi
    "tukar_dilaporkan": 0.7,  # sisanya tidak dilaporkan ke HRD (PRD P1)
    "lembur_libur": 0.01,   # per hari libur bergilir, datang bekerja
    "keluar_tengah": 0.01,  # per karyawan per periode: berhenti di tengah periode
    "masuk_tengah": 0.01,   # per karyawan per periode: karyawan baru
}
PELUANG_LEMBUR = {"PRD": 0.12, "QC": 0.08, "KAM": 0.05, "GDG": 0.08, "KTR": 0.04}

PABRIK = {
    "A": {
        "nama": "Pabrik A (simulasi, 1.000 karyawan)",
        "benih": 2026_1,
        "awal_id": 10001,
        "mesin": {"MA1": ["PRD", "QC", "KAM", "GDG"], "MA2": ["KTR"]},
        "divisi": [
            # kode, nama, jumlah, pola, jumlah regu
            ("PRD", "Produksi", 600, "rotasi4", 4),
            ("QC", "Quality Control", 80, "rotasi4", 4),
            ("KAM", "Keamanan", 50, "rotasi4", 4),
            ("GDG", "Gudang dan Logistik", 150, "gudang2", 2),
            ("KTR", "Kantor", 120, "kantor6", 1),
        ],
        "periode": [
            ("2026-01-21", "2026-02-20"),
            ("2026-02-21", "2026-03-20"),
            ("2026-03-21", "2026-04-20"),
            ("2026-11-21", "2026-12-20"),
        ],
        "cuti_bersama": "dibayar",
        "cara_bayar_tunai": 0.3,     # mayoritas transfer
        "tidak_wajib_tap": {"GDG": 4},  # sopir
        "gaji_rahasia": {"KTR": 3},
        # Kejadian khusus yang ditanam (PRD M2-M7, C06).
        "mesin_mati": [("MA2", "2026-02-06", "dilaporkan")],
        "selisih_jam": [("MA2", "2026-03-01", "2026-03-10", 4)],
        "id_ganda": True,
        "id_tidak_dikenal": 6,
    },
    "B": {
        "nama": "Pabrik B (simulasi, 180 karyawan)",
        "benih": 2026_2,
        "awal_id": 20001,
        "mesin": {"MB1": ["PRD", "GDG", "KTR", "KAM"]},
        "divisi": [
            ("PRD", "Produksi", 110, "dua_shift5", 2),
            ("GDG", "Gudang", 30, "gudang2", 2),
            ("KTR", "Kantor", 25, "kantor5", 1),
            ("KAM", "Keamanan", 15, "rotasi4", 4),
        ],
        "periode": [
            ("2026-02-01", "2026-02-28"),
            ("2026-03-01", "2026-03-31"),
            ("2026-04-01", "2026-04-30"),
            ("2026-12-01", "2026-12-31"),
        ],
        "cuti_bersama": "potong_cuti",
        "cara_bayar_tunai": 0.75,    # mayoritas tunai
        "tidak_wajib_tap": {},
        "gaji_rahasia": {"KTR": 1},
        "mesin_mati": [("MB1", "2026-03-11", "tidak_dilaporkan")],
        "selisih_jam": [],
        "id_ganda": False,
        "id_tidak_dikenal": 3,
        # Pola rotasi hanya dipakai 15 satpam, jadi peluang tukar shift dinaikkan
        # supaya kasus ini tetap muncul di setiap periode.
        "peluang_khusus": {"tukar_shift": 0.03},
    },
}

NAMA_DEPAN = [
    "Agus", "Budi", "Citra", "Dedi", "Eka", "Fajar", "Gita", "Hendra", "Indah", "Joko",
    "Kartika", "Lestari", "Maya", "Nanda", "Oki", "Putri", "Rahmat", "Sari", "Teguh", "Umar",
    "Vina", "Wahyu", "Yanti", "Zulkifli", "Andi", "Bayu", "Dewi", "Rina", "Siti", "Tono",
    "Hadi", "Lina", "Rudi", "Sinta", "Yusuf", "Wati", "Imam", "Nurul", "Ratna", "Bambang",
]
NAMA_BELAKANG = [
    "Saputra", "Lubis", "Nasution", "Siregar", "Harahap", "Sitorus", "Ginting", "Tarigan",
    "Sembiring", "Hasibuan", "Pane", "Daulay", "Rangkuti", "Pohan", "Batubara", "Purba",
    "Simanjuntak", "Manurung", "Panjaitan", "Hutagalung", "Wibowo", "Pratama", "Santoso",
    "Kurniawan", "Hidayat", "Rahayu", "Susanto", "Setiawan", "Gunawan", "Utami",
]
