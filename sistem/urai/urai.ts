// Pembaca file mesin finger (Tahap 3).
// Mengubah isi file menjadi daftar tap baku: ID mesin (teks), jam lokal mesin, status, nomor baris asal.
// Tidak memakai pustaka luar dan tidak memakai API khusus Node atau Deno, supaya modul yang sama
// bisa dipakai di uji otomatis (Node) dan di Supabase Edge Functions (Deno) pada Tahap 5.
// Aturan yang diterapkan di sini hanya aturan bentuk file (PRD bagian 7 langkah "Bakukan",
// celah M1 dan M8, kasus A04, A05, A10, A12, F01, F09). Jendela tap, telat, dan dobel diurus database.
// Larangan: modul ini tidak boleh mengimpor apa pun dari generator/.

import { bacaTeks, bukaXls, bukaXlsx, GalatBerkas, jenisBerkas, type Sel } from "./berkas.ts";

// ekspor_aplikasi_v1: log tap mentah berbentuk tabel teks (CSV/TXT); ekspor_xls dan ekspor_xlsx: tabel yang sama di dalam Excel
// (paket F1). attlog_zkteco: berkas attlog.dat.
export type Format = "ekspor_aplikasi_v1" | "ekspor_xls" | "ekspor_xlsx" | "attlog_zkteco";

export interface TapBaku {
  id_mesin: string;
  jam_lokal: string; // "YYYY-MM-DD HH:MM:SS", jam mesin apa adanya (belum dikoreksi)
  status: "Masuk" | "Keluar" | null;
  baris: number; // nomor baris di file, mulai 1 (baris judul ikut dihitung)
}

export interface BarisDitolak {
  baris: number;
  alasan: string;
}

export interface HasilUrai {
  hasil: "diterima" | "ditolak";
  alasan: string | null; // diisi bila seluruh file ditolak
  format: Format | null;
  tap: TapBaku[];
  baris_ditolak: BarisDitolak[]; // baris yang dibuang, file tetap diterima (contoh: tanggal mustahil)
  tanggal_awal: string | null;
  tanggal_akhir: string | null;
  // Paket F2: diisi bila tabel ditolak HANYA karena judul kolomnya tidak dikenali (bukan rekap, kolom ganda, file rusak):
  // judul kolom apa adanya, sidiknya, dan analisa isi tiap kolom untuk percakapan konfirmasi di bot.
  judul?: string[];
  sidik_judul?: string;
  analisa?: AnalisaKolom[];
}

// Paket F2: susunan tanggal teks di file. dmy = hari/bulan/tahun, mdy = bulan/hari/tahun, ymd = tanpa tanggal a/b/tahun
// (tahun-bulan-hari atau tanggal angka Excel saja).
export type Susunan = "dmy" | "mdy" | "ymd";

// Paket F2: profil format satu mesin yang disetujui HRD/pembangun. Kolom ditulis dengan judul aslinya; dicocokkan setelah
// dinormalkan. Profil hanya dipakai untuk tabel yang sidik judul kolomnya sama persis (K3: judul berubah = ditanya lagi).
export interface ProfilUrai {
  sidik_judul: string;
  kolom_id: string;
  kolom_waktu?: string | null;
  kolom_tanggal?: string | null;
  kolom_jam?: string | null;
  susunan: Susunan;
}

// Paket F2: isi satu kolom. ab = jumlah tanggal teks a/b/tahun; a12 / b12 = yang angka pertama / kedua di atas 12;
// contoh = contoh tanggal a/b/tahun yang bisa dibaca dua cara; ymd = tanggal tahun-bulan-hari; angka = sel angka (Excel).
export interface AnalisaKolom {
  ab: number;
  a12: number;
  b12: number;
  contoh: string | null;
  ymd: number;
  angka: number;
  isi: number;
}

export interface PilihanUrai {
  // Tanggal kirim (YYYY-MM-DD). Tap bertanggal lebih dari satu hari setelahnya dianggap mustahil.
  tanggal_kirim?: string;
  // Tanggal paling awal yang masuk akal. Jam mesin yang tereset biasanya kembali ke tahun 2000 (kasus A12).
  tanggal_paling_awal?: string;
  // Paket F2: profil format mesin. Tanpa profil, aturan F1 (daftar sinonim) berlaku apa adanya.
  profil?: ProfilUrai | null;
}

const PALING_AWAL_BAWAAN = "2020-01-01";

export const PESAN = {
  kosong: "File kosong atau tidak berisi baris data.",
  // Semua penolakan bentuk file diawali "Format file tidak dikenal": awalan ini dikenali database sebagai kejadian segera
  // (fakta.jenis_tolak_segera, migrasi 0018), sehingga pembangun diberi tahu.
  formatTidakDikenal:
    "Format file tidak dikenal. Kirim log/data absensi mentah dari aplikasi mesin: satu baris setiap tap, dengan kolom ID " +
    "(misalnya No.ID) dan tanggal-jam (misalnya Tgl/Waktu). File .xls, .xlsx, .csv, .txt, dan attlog.dat bisa dibaca.",
  rekap:
    "Format file tidak dikenal: file ini berbentuk rekap (jam masuk dan pulang per hari), bukan log tap mentah. Rekap sudah " +
    "diolah aplikasi mesin sehingga tap ganda, shift malam, dan lupa tap tidak bisa diperiksa. Ekspor ulang menu " +
    "\"log/data absensi\" (satu baris setiap tap) dari aplikasi mesin.",
  kolomGanda: "Format file tidak dikenal: ada lebih dari satu kolom yang bisa berarti ID karyawan",
  berkasRusak: "Format file tidak dikenal: ",
  idRusakExcel:
    "No.ID rusak (tertulis seperti 1,98E+17) karena file dibuka lalu disimpan di Excel. Kirim file langsung dari mesin tanpa dibuka di Excel.",
  idAngkaPanjang:
    "No.ID rusak: ID lebih dari 15 angka tersimpan sebagai angka di Excel sehingga digit terakhirnya hilang. Kirim file langsung " +
    "dari mesin, atau simpan kolom ID sebagai teks.",
  idTidakSah: "No.ID berisi karakter yang tidak sah",
  waktuTidakTerbaca: "Tgl/Waktu tidak bisa dibaca",
  tanggalCampur:
    "Tanggal di file bercampur antara hari/bulan dan bulan/hari. File ditolak supaya tidak salah baca; ekspor ulang dari aplikasi mesin.",
  tanggalMustahil: "tanggal mustahil (jam mesin kemungkinan tereset atau salah)",
  semuaBarisDitolak: "Semua baris data ditolak; tidak ada tap yang bisa dipakai.",
};

// ---------------------------------------------------------------------------
// Pembantu
// ---------------------------------------------------------------------------

function dua(n: number): string {
  return n < 10 ? "0" + n : String(n);
}

function tanggalSah(t: number, b: number, h: number): boolean {
  if (b < 1 || b > 12 || h < 1) return false;
  const panjang = [31, (t % 4 === 0 && t % 100 !== 0) || t % 400 === 0 ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return h <= panjang[b - 1];
}

function tambahHari(iso: string, n: number): string {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// ID mesin selalu teks. Bentuk notasi ilmiah adalah tanda file pernah disimpan ulang di Excel (celah M1).
const POLA_NOTASI_ILMIAH = /^[0-9]+([.,][0-9]+)?[eE]\+?[0-9]+$/;
const POLA_ID = /^[0-9A-Za-z]+$/;

// Pemisah CSV sederhana yang memahami tanda kutip ganda.
export function pecahCsv(teks: string, pemisah = ","): string[][] {
  const baris: string[][] = [];
  let kolom: string[] = [];
  let sel = "";
  let dalamKutip = false;
  for (let i = 0; i < teks.length; i++) {
    const c = teks[i];
    if (dalamKutip) {
      if (c === '"') {
        if (teks[i + 1] === '"') {
          sel += '"';
          i++;
        } else {
          dalamKutip = false;
        }
      } else {
        sel += c;
      }
      continue;
    }
    if (c === '"') {
      dalamKutip = true;
    } else if (c === pemisah) {
      kolom.push(sel);
      sel = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && teks[i + 1] === "\n") i++;
      kolom.push(sel);
      baris.push(kolom);
      kolom = [];
      sel = "";
    } else {
      sel += c;
    }
  }
  if (sel !== "" || kolom.length > 0) {
    kolom.push(sel);
    baris.push(kolom);
  }
  return baris;
}

function bersihkanBom(teks: string): string {
  return teks.charCodeAt(0) === 0xfeff ? teks.slice(1) : teks;
}

interface Waktu {
  jam_lokal: string;
  tanggal: string;
  // Untuk deteksi pola campur: angka pertama dan kedua pada tanggal bergaya a/b/yyyy.
  a?: number;
  b?: number;
}

// Tgl/Waktu ekspor aplikasi: "dd/mm/yyyy jj.mm.dd", "dd/mm/yyyy jj.mm", atau dengan pemisah titik dua.
const POLA_WAKTU_EKSPOR = /^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2})[.:](\d{2})(?:[.:](\d{2}))?$/;
// attlog ZKTeco: "yyyy-mm-dd jj:mm:dd".
const POLA_WAKTU_ISO = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/;

function susunWaktu(t: number, b: number, h: number, j: number, m: number, d: number): Waktu | null {
  if (!tanggalSah(t, b, h) || j > 23 || m > 59 || d > 59) return null;
  const tanggal = `${t}-${dua(b)}-${dua(h)}`;
  return { jam_lokal: `${tanggal} ${dua(j)}:${dua(m)}:${dua(d)}`, tanggal };
}

// ---------------------------------------------------------------------------
// Ekspor aplikasi mesin (bentuk file asli Februari 2026 dan data simulasi)
// ---------------------------------------------------------------------------

// Log tap mentah berbentuk tabel (paket F1): CSV/TXT, .xls, .xlsx. Kolom dikenali dari judulnya; baris judul boleh didahului
// baris judul laporan. Wajib: satu kolom ID dan waktu (satu kolom tanggal-jam, atau kolom tanggal + kolom jam). Nama dan status
// tidak wajib: masuk/pulang ditentukan dari jam (kasus A01). Sinonim di luar bentuk file asli (No.ID, Tgl/Waktu) berstatus
// [Menebak] sampai ada contoh file sungguhan dari mesin lain.
const normal = (v: Sel) => String(v ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
const SINONIM_ID = ["noid", "id", "acno", "pin", "nik", "nip", "nopegawai", "idpegawai", "idkaryawan", "nokaryawan",
  "employeeid", "empid", "userid", "enrollid", "enrollnumber", "badgenumber", "noabsen", "idabsen", "idmesin"];
const SINONIM_GABUNGAN = ["tglwaktu", "datetime", "tanggalwaktu", "tanggaljam", "tgljam", "checktime", "waktuabsen", "datetimeabsen"];
const SINONIM_TANGGAL = ["tanggal", "tgl", "date", "tanggalabsen", "tglabsen"];
// Keputusan pemilik 25 Nov 2026 (pilihan A): kolom bernama "Waktu" atau "Time" saja TIDAK dikenali, sesuai kasus jebakan F09
// (format baru ditolak, pembangun diberi tahu). Ditambahkan hanya dari contoh file sungguhan.
const SINONIM_JAM = ["jam", "jamabsen", "pukul"];
const SINONIM_NAMA = ["nama", "name", "namakaryawan", "namapegawai", "employeename"];
const SINONIM_STATUS = ["status", "state", "statusabsen", "inout", "checktype", "jenisabsen"];
const SINONIM_REKAP = ["masuk", "pulang", "jammasuk", "jampulang", "scanmasuk", "scanpulang", "checkin", "checkout",
  "clockin", "clockout", "datang", "jamdatang"];

interface Kolom { id: number; gabungan: number; tanggal: number; jam: number; nama: number; status: number }

function cariKolom(judul: string[]): Kolom | "rekap" | "ganda" | null {
  const cari = (daftar: string[]) => judul.map((j, i) => (daftar.includes(j) ? i : -1)).filter((i) => i >= 0);
  const id = cari(SINONIM_ID);
  if (id.length === 0) return null;
  const gabungan = cari(SINONIM_GABUNGAN);
  const tanggal = cari(SINONIM_TANGGAL);
  let kol: Kolom | null = null;
  const sisa = (i: number) => (i >= 0 ? i : -1);
  if (gabungan.length >= 1) {
    kol = { id: id[0], gabungan: gabungan[0], tanggal: -1, jam: -1, nama: -1, status: -1 };
  } else if (tanggal.length >= 1) {
    const jam = cari(SINONIM_JAM).filter((i) => !tanggal.includes(i));
    if (jam.length >= 1) kol = { id: id[0], gabungan: -1, tanggal: tanggal[0], jam: jam[0], nama: -1, status: -1 };
    else if (cari(SINONIM_REKAP).length > 0) return "rekap";
  } else if (cari(SINONIM_REKAP).length > 0) {
    return "rekap";
  }
  if (!kol) return null;
  if (id.length > 1) return "ganda";
  kol.nama = sisa(cari(SINONIM_NAMA)[0] ?? -1);
  kol.status = sisa(cari(SINONIM_STATUS)[0] ?? -1);
  return kol;
}

// Tanggal angka Excel -> {t, b, h, j, m, d}. Sistem 1900 (dasar 30 Des 1899, benar untuk tanggal sesudah Feb 1900) atau 1904.
function dariAngkaExcel(v: number, tanggal1904: boolean) {
  if (!Number.isFinite(v) || v < 0 || v > 2958465) return null;
  let hari = Math.floor(v);
  let detik = Math.round((v - hari) * 86400);
  if (detik >= 86400) {
    hari += 1;
    detik -= 86400;
  }
  const dasar = tanggal1904 ? Date.UTC(1904, 0, 1) : Date.UTC(1899, 11, 30);
  const d = new Date(dasar + hari * 86400000);
  return { t: d.getUTCFullYear(), b: d.getUTCMonth() + 1, h: d.getUTCDate(),
           j: Math.floor(detik / 3600), m: Math.floor((detik % 3600) / 60), d: detik % 60 };
}

const POLA_TANGGAL_DMY = /^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})$/;
const POLA_TANGGAL_YMD = /^(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})$/;
const POLA_JAM = /^(\d{1,2})[.:](\d{2})(?:[.:](\d{2}))?$/;

// Hasil: waktu, ditambah angka di posisi bulan pada tanggal bergaya a/b/yyyy untuk penjaga hari/bulan tercampur (kasus A10).
// Susunan dmy (bawaan, aturan F1): angka kedua = bulan. Paket F2: mdy = angka pertama bulan; ymd = tanggal a/b/yyyy tidak dibaca.
function bacaWaktu(selWaktu: Sel, selJam: Sel | undefined, terpisah: boolean, tanggal1904: boolean, susunan: Susunan = "dmy"):
  { w: Waktu; b2: number | null } | null {
  let t: number, b: number, h: number, j = 0, m = 0, d = 0;
  let b2: number | null = null;
  if (typeof selWaktu === "number") {
    const x = dariAngkaExcel(terpisah ? Math.floor(selWaktu) : selWaktu, tanggal1904);
    if (!x) return null;
    ({ t, b, h, j, m, d } = x);
  } else {
    const teks = String(selWaktu ?? "").trim();
    const [bagTanggal, ...bagJam] = terpisah ? [teks] : teks.split(/\s+|T(?=\d)/);
    let k = POLA_TANGGAL_DMY.exec(bagTanggal);
    if (k) {
      if (susunan === "ymd") return null;
      h = Number(k[susunan === "mdy" ? 2 : 1]);
      b = Number(k[susunan === "mdy" ? 1 : 2]);
      t = Number(k[3]);
      b2 = b;
    } else if ((k = POLA_TANGGAL_YMD.exec(bagTanggal))) {
      t = Number(k[1]);
      b = Number(k[2]);
      h = Number(k[3]);
    } else return null;
    if (!terpisah) {
      if (bagJam.length !== 1) return null;
      const pj = POLA_JAM.exec(bagJam[0]);
      if (!pj) return null;
      j = Number(pj[1]);
      m = Number(pj[2]);
      d = Number(pj[3] ?? "0");
    }
  }
  if (terpisah) {
    if (typeof selJam === "number") {
      const x = dariAngkaExcel(selJam % 1, tanggal1904);
      if (!x) return null;
      ({ j, m, d } = x);
    } else {
      const pj = POLA_JAM.exec(String(selJam ?? "").trim());
      if (!pj) return null;
      j = Number(pj[1]);
      m = Number(pj[2]);
      d = Number(pj[3] ?? "0");
    }
  }
  // Angka kedua > 12 pada tanggal a/b/yyyy berarti isinya bulan/hari: susunWaktu menolak bulan > 12, penjaga A10 menolak file.
  const w = susunWaktu(t, b, h, j, m, d);
  if (!w && b2 !== null && b2 > 12) return { w: { jam_lokal: "", tanggal: "" }, b2 };
  return w ? { w, b2 } : null;
}

// ---------------------------------------------------------------------------
// Paket F2: judul kolom yang belum dikenal (untuk konfirmasi HRD) dan pembacaan dengan profil mesin
// ---------------------------------------------------------------------------

const kosongSel = (s: Sel) => String(s ?? "").trim() === "";
const kosongBaris = (r: Sel[]) => r.every(kosongSel);
const isiBaris = (r: Sel[]) => r.filter((s) => !kosongSel(s)).length;
// Sel yang tampak seperti data (angka, tanggal, jam), bukan judul.
const SEL_DATA = /^[\d\s.,:\/\-+]+$/;

// Sidik judul kolom: judul yang dinormalkan (huruf kecil, hanya huruf dan angka), dipisah "|", sel kosong di ujung dibuang.
export function sidikJudul(r: Sel[]): string {
  const n = r.map(normal);
  while (n.length && n[n.length - 1] === "") n.pop();
  return n.join("|");
}

// Baris judul calon untuk tabel yang judulnya tidak dikenali: dari 30 baris tidak kosong pertama, baris berisi paling sedikit
// 2 sel yang semuanya teks bukan data dan diikuti baris berisi paling sedikit 2 sel; dipilih yang selnya paling banyak.
export function calonJudul(barisSel: Sel[][]): number {
  const tidakKosong: number[] = [];
  for (let i = 0; i < barisSel.length && tidakKosong.length < 31; i++) if (!kosongBaris(barisSel[i] ?? [])) tidakKosong.push(i);
  let pilih = -1;
  let terbanyak = 0;
  for (let n = 0; n < Math.min(30, tidakKosong.length - 1); n++) {
    const r = barisSel[tidakKosong[n]];
    const sel = r.filter((s) => !kosongSel(s));
    if (sel.length < 2 || sel.length <= terbanyak) continue;
    if (sel.some((s) => typeof s === "number" || SEL_DATA.test(String(s).trim()))) continue;
    if (isiBaris(barisSel[tidakKosong[n + 1]]) < 2) continue;
    pilih = tidakKosong[n];
    terbanyak = sel.length;
  }
  return pilih;
}

// Isi tiap kolom di bawah baris judul (untuk pertanyaan susunan tanggal dan pengaman kolom yang mustahil).
export function analisaKolom(barisSel: Sel[][], iJudul: number, lebar: number): AnalisaKolom[] {
  const a: AnalisaKolom[] = Array.from({ length: lebar }, () => ({ ab: 0, a12: 0, b12: 0, contoh: null, ymd: 0, angka: 0, isi: 0 }));
  for (let i = iJudul + 1; i < barisSel.length; i++) {
    const r = barisSel[i] ?? [];
    for (let k = 0; k < lebar; k++) {
      const s = r[k];
      if (kosongSel(s)) continue;
      a[k].isi++;
      if (typeof s === "number") {
        a[k].angka++;
        continue;
      }
      const token = String(s).trim().split(/\s+|T(?=\d)/)[0];
      const dmy = POLA_TANGGAL_DMY.exec(token);
      if (dmy) {
        const x = Number(dmy[1]);
        const y = Number(dmy[2]);
        a[k].ab++;
        if (x > 12) a[k].a12++;
        if (y > 12) a[k].b12++;
        if (x <= 12 && y <= 12 && x !== y && x >= 1 && y >= 1 && a[k].contoh === null) a[k].contoh = token;
      } else if (POLA_TANGGAL_YMD.test(token)) {
        a[k].ymd++;
      }
    }
  }
  return a;
}

// Pilihan susunan tanggal yang mungkin untuk satu kolom: [] = tercampur (tidak bisa disimpan), satu pilihan = pasti,
// dua pilihan = HRD ditanya.
export function susunanMungkin(x: AnalisaKolom | undefined): Susunan[] {
  if (!x || x.ab === 0) return ["ymd"];
  if (x.a12 > 0 && x.b12 > 0) return [];
  if (x.a12 > 0) return ["dmy"];
  if (x.b12 > 0) return ["mdy"];
  return ["dmy", "mdy"];
}

function kolomProfil(judul: Sel[], p: ProfilUrai): Kolom | null {
  const n = judul.map(normal);
  const cari = (nama: string | null | undefined) => {
    const x = normal(nama ?? "");
    if (!x) return -1;
    const i = n.indexOf(x);
    return i >= 0 && n.indexOf(x, i + 1) < 0 ? i : -1; // judul ganda tidak dipakai
  };
  const kol: Kolom = { id: cari(p.kolom_id), gabungan: cari(p.kolom_waktu), tanggal: cari(p.kolom_tanggal), jam: cari(p.kolom_jam),
                       nama: -1, status: -1 };
  if (kol.id < 0 || (kol.gabungan < 0 && (kol.tanggal < 0 || kol.jam < 0))) return null;
  const dipakai = [kol.id, kol.gabungan, kol.tanggal, kol.jam];
  const lain = (daftar: string[]) => n.findIndex((j, i) => daftar.includes(j) && !dipakai.includes(i));
  kol.nama = lain(SINONIM_NAMA);
  kol.status = lain(SINONIM_STATUS);
  return kol;
}

// Menerima baris sel dari CSV/TXT atau lembar Excel. Nama lama (uraiBarisEkspor) tetap untuk CSV.
export function uraiTabel(barisSel: Sel[][], pilihan: PilihanUrai = {}, format: Format = "ekspor_aplikasi_v1",
                          tanggal1904 = false): HasilUrai {
  const hasil: HasilUrai = {
    hasil: "ditolak", alasan: null, format, tap: [], baris_ditolak: [], tanggal_awal: null, tanggal_akhir: null,
  };
  const kosong = kosongBaris;
  if (barisSel.findIndex((r) => r && !kosong(r)) < 0) {
    hasil.alasan = PESAN.kosong;
    return hasil;
  }
  // Baris judul: baris tidak kosong pertama (dari 30 baris pertama) yang memuat kolom ID dan kolom waktu.
  // Paket F2: dengan profil, baris judul = baris yang sidik judulnya sama persis dengan profil.
  let iJudul = -1;
  let kol: Kolom | null = null;
  let temuan: "rekap" | "ganda" | null = null;
  const profil = pilihan.profil ?? null;
  for (let i = 0, dicek = 0; i < barisSel.length && dicek < 30; i++) {
    const r = barisSel[i] ?? [];
    if (kosong(r)) continue;
    dicek++;
    if (profil) {
      if (sidikJudul(r) !== profil.sidik_judul) continue;
      const k = kolomProfil(r, profil);
      if (k) {
        iJudul = i;
        kol = k;
      }
      break;
    }
    const k = cariKolom(r.map(normal));
    if (k === "rekap" || k === "ganda") {
      temuan = temuan ?? k;
      continue;
    }
    if (k) {
      iJudul = i;
      kol = k;
      break;
    }
  }
  if (!kol) {
    hasil.alasan = temuan === "rekap" ? PESAN.rekap : temuan === "ganda" ? PESAN.kolomGanda : PESAN.formatTidakDikenal;
    // Paket F2: hanya penolakan karena judul tidak dikenali yang membawa judul kolom (C6: rekap dan kolom ganda tidak).
    if (temuan === null) {
      const c = calonJudul(barisSel);
      if (c >= 0) {
        const r = barisSel[c];
        let lebar = r.length;
        while (lebar > 0 && kosongSel(r[lebar - 1])) lebar--;
        hasil.judul = r.slice(0, lebar).map((s) => String(s ?? "").trim());
        hasil.sidik_judul = sidikJudul(r);
        hasil.analisa = analisaKolom(barisSel, c, lebar);
      }
    }
    return hasil;
  }
  const susunan: Susunan = profil?.susunan ?? "dmy";

  const paling_awal = pilihan.tanggal_paling_awal ?? PALING_AWAL_BAWAAN;
  const paling_akhir = pilihan.tanggal_kirim ? tambahHari(pilihan.tanggal_kirim, 1) : null;
  const terpisah = kol.gabungan < 0;
  let adaBulanLebihDari12 = false; // angka kedua > 12: pasti bulan/hari

  for (let i = iJudul + 1; i < barisSel.length; i++) {
    const r = barisSel[i] ?? [];
    if (kosong(r)) continue;
    const nomor = i + 1;
    const selId = r[kol.id];
    let id: string;
    if (typeof selId === "number") {
      // ID yang disimpan Excel sebagai angka: lebih dari 15 angka bermakna sudah kehilangan digit (celah C2).
      if (!Number.isInteger(selId) || Math.abs(selId) >= 1e15) {
        hasil.alasan = Number.isInteger(selId) ? PESAN.idAngkaPanjang : PESAN.idRusakExcel;
        hasil.tap = [];
        return hasil;
      }
      id = String(selId);
    } else {
      id = String(selId ?? "").trim();
    }
    if (POLA_NOTASI_ILMIAH.test(id)) {
      hasil.alasan = PESAN.idRusakExcel;
      hasil.tap = [];
      return hasil;
    }
    if (!POLA_ID.test(id)) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.idTidakSah}: "${id}"` });
      continue;
    }
    const selW = terpisah ? r[kol.tanggal] : r[kol.gabungan];
    const teksWaktu = terpisah ? `${String(r[kol.tanggal] ?? "").trim()} ${String(r[kol.jam] ?? "").trim()}`
      : String(selW ?? "").trim();
    const x = bacaWaktu(selW ?? null, terpisah ? r[kol.jam] ?? null : undefined, terpisah, tanggal1904, susunan);
    if (x && x.b2 !== null && x.b2 > 12) adaBulanLebihDari12 = true;
    if (!x || !x.w.jam_lokal) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.waktuTidakTerbaca}: "${teksWaktu}"` });
      continue;
    }
    const w = x.w;
    if (w.tanggal < paling_awal || (paling_akhir !== null && w.tanggal > paling_akhir)) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.tanggalMustahil}: "${teksWaktu}"` });
      continue;
    }
    const s = kol.status >= 0 ? String(r[kol.status] ?? "").trim().toLowerCase() : "";
    const status = s.endsWith("masuk") || /^(c\/)?(check ?)?in$/.test(s) ? "Masuk"
      : s.endsWith("keluar") || /^(c\/)?(check ?)?out$/.test(s) ? "Keluar" : null;
    hasil.tap.push({ id_mesin: id, jam_lokal: w.jam_lokal, status, baris: nomor });
  }

  // Kasus A10: aplikasi menulis hari/bulan. Ada tanggal yang hanya masuk akal sebagai bulan/hari
  // berarti isinya bercampur; lebih aman ditolak daripada salah baca.
  if (adaBulanLebihDari12) {
    hasil.alasan = PESAN.tanggalCampur;
    hasil.tap = [];
    return hasil;
  }
  return selesaikan(hasil);
}

export function uraiBarisEkspor(barisSel: string[][], pilihan: PilihanUrai = {}): HasilUrai {
  return uraiTabel(barisSel, pilihan);
}

// Pemisah tabel teks: koma (bentuk file asli dan data simulasi), titik koma (CSV Excel berbahasa Indonesia), atau tab
// (simpanan Excel "Unicode text"). Dipilih pemisah pertama yang membuat baris judul dikenali; bila tidak ada, koma.
// Paket F2: dengan profil, pemisah yang membuat sidik judul profil ditemukan. Bila judul tidak dikenali dengan pemisah mana pun,
// dipilih pemisah yang memberi judul calon paling banyak kolom (hanya mengubah judul yang ditawarkan ke HRD; alasan tolak sama).
export function pemisahTeks(teks: string, profil: ProfilUrai | null = null): string {
  const awal = teks.split(/\r?\n/).slice(0, 40).join("\n");
  let cadangan = ",";
  let terbanyak = 0;
  for (const p of [",", ";", "\t"]) {
    const baris = pecahCsv(awal, p).filter((r) => r.some((x) => x.trim() !== "")).slice(0, 30);
    if (profil ? baris.some((r) => sidikJudul(r) === profil.sidik_judul) : baris.some((r) => cariKolom(r.map(normal)) !== null)) {
      return p;
    }
    const c = calonJudul(baris);
    if (c >= 0 && isiBaris(baris[c]) > terbanyak) {
      terbanyak = isiBaris(baris[c]);
      cadangan = p;
    }
  }
  return cadangan;
}

export function uraiEkspor(teks: string, pilihan: PilihanUrai = {}): HasilUrai {
  const bersih = bersihkanBom(teks);
  return uraiTabel(pecahCsv(bersih, pemisahTeks(bersih, pilihan.profil ?? null)), pilihan);
}

// ---------------------------------------------------------------------------
// attlog.dat ZKTeco: ID, waktu, mesin, status (0 masuk, 1 keluar), verifikasi, kode kerja
// ---------------------------------------------------------------------------

export function uraiAttlog(teks: string, pilihan: PilihanUrai = {}): HasilUrai {
  const hasil: HasilUrai = {
    hasil: "ditolak",
    alasan: null,
    format: "attlog_zkteco",
    tap: [],
    baris_ditolak: [],
    tanggal_awal: null,
    tanggal_akhir: null,
  };
  const paling_awal = pilihan.tanggal_paling_awal ?? PALING_AWAL_BAWAAN;
  const paling_akhir = pilihan.tanggal_kirim ? tambahHari(pilihan.tanggal_kirim, 1) : null;
  const baris = bersihkanBom(teks).split(/\r?\n/);
  for (let i = 0; i < baris.length; i++) {
    const isi = baris[i];
    if (isi.trim() === "") continue;
    const nomor = i + 1;
    const kol = isi.split("\t").map((s) => s.trim());
    const id = kol[0] ?? "";
    if (POLA_NOTASI_ILMIAH.test(id)) {
      hasil.alasan = PESAN.idRusakExcel;
      hasil.tap = [];
      return hasil;
    }
    if (!POLA_ID.test(id)) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.idTidakSah}: "${id}"` });
      continue;
    }
    const m = POLA_WAKTU_ISO.exec(kol[1] ?? "");
    const w = m ? susunWaktu(Number(m[1]), Number(m[2]), Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])) : null;
    if (!w) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.waktuTidakTerbaca}: "${kol[1] ?? ""}"` });
      continue;
    }
    if (w.tanggal < paling_awal || (paling_akhir !== null && w.tanggal > paling_akhir)) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.tanggalMustahil}: "${kol[1]}"` });
      continue;
    }
    const kode = kol[3];
    const status = kode === "0" ? "Masuk" : kode === "1" ? "Keluar" : null;
    hasil.tap.push({ id_mesin: id, jam_lokal: w.jam_lokal, status, baris: nomor });
  }
  return selesaikan(hasil);
}

// ---------------------------------------------------------------------------
// Pintu umum: kenali bentuk file dari isinya, bukan dari nama file
// ---------------------------------------------------------------------------

export function kenaliFormat(teks: string): Format | null {
  const pertama = bersihkanBom(teks).split(/\r?\n/).find((b) => b.trim() !== "");
  if (!pertama) return null;
  const kol = pertama.split("\t").map((s) => s.trim());
  if (kol.length >= 2 && POLA_WAKTU_ISO.test(kol[1])) return "attlog_zkteco";
  // Tabel teks: ada pemisah koma, titik koma, atau tab di salah satu baris awal (baris judul laporan boleh di atasnya).
  const awal = bersihkanBom(teks).split(/\r?\n/).slice(0, 40);
  if (awal.some((b) => /[,;\t]/.test(b))) return "ekspor_aplikasi_v1";
  return null;
}

export function urai(teks: string, pilihan: PilihanUrai = {}): HasilUrai {
  const f = kenaliFormat(teks);
  if (f === "attlog_zkteco") return uraiAttlog(teks, pilihan);
  if (f === "ekspor_aplikasi_v1") return uraiEkspor(teks, pilihan);
  return {
    hasil: "ditolak",
    alasan: teks.trim() === "" ? PESAN.kosong : PESAN.formatTidakDikenal,
    format: null,
    tap: [],
    baris_ditolak: [],
    tanggal_awal: null,
    tanggal_akhir: null,
  };
}

// Pintu untuk isi file apa adanya (paket F1): bot dan halaman unggah meneruskan isi biner. Jenis berkas dikenali dari tanda awal
// isinya; Excel dibuka di berkas.ts, lalu lembar pertama yang judulnya dikenali diurai dengan aturan yang sama dengan CSV.
export async function uraiBerkas(isi: Uint8Array, pilihan: PilihanUrai = {}): Promise<HasilUrai> {
  const jenis = jenisBerkas(isi);
  if (jenis === "teks") return urai(bacaTeks(isi), pilihan);
  const tolak = (alasan: string): HasilUrai => ({
    hasil: "ditolak", alasan, format: jenis === "xls" ? "ekspor_xls" : "ekspor_xlsx", tap: [], baris_ditolak: [],
    tanggal_awal: null, tanggal_akhir: null,
  });
  let buku;
  try {
    buku = jenis === "xls" ? bukaXls(isi) : await bukaXlsx(isi);
  } catch (e) {
    if (e instanceof GalatBerkas) return tolak(PESAN.berkasRusak + e.message);
    return tolak(PESAN.berkasRusak + "file Excel tidak bisa dibuka.");
  }
  const format: Format = jenis === "xls" ? "ekspor_xls" : "ekspor_xlsx";
  let pertama: HasilUrai | null = null;
  let berjudul: HasilUrai | null = null;
  for (const l of buku.lembar) {
    const h = uraiTabel(l.baris, pilihan, format, buku.tanggal1904);
    pertama = pertama ?? h;
    if (h.judul) berjudul = berjudul ?? h;
    // Lembar yang judulnya tidak dikenali dilewati; lembar pertama yang dikenali dipakai (diterima atau ditolak).
    if (h.hasil === "diterima" || !(h.alasan ?? "").startsWith(PESAN.formatTidakDikenal.slice(0, 25))) return h;
  }
  // Paket F2: tidak ada lembar yang dikenali -> lembar pertama yang punya judul calon (untuk konfirmasi HRD).
  return berjudul ?? pertama ?? tolak(PESAN.kosong);
}

// Paket 6f (bug B1): sebutkan alasan terbanyak dan contohnya, supaya HRD tahu langkahnya (misalnya jam mesin salah).
// Awalan pesan tetap PESAN.semuaBarisDitolak (dicocokkan database).
export function rincianTolak(daftar: BarisDitolak[]): string {
  const hitung = new Map<string, { n: number; contoh: string }>();
  for (const b of daftar) {
    const i = b.alasan.indexOf(': "');
    const jenis = i >= 0 ? b.alasan.slice(0, i) : b.alasan;
    const contoh = i >= 0 ? b.alasan.slice(i + 2) : "";
    const h = hitung.get(jenis) ?? { n: 0, contoh };
    h.n++;
    hitung.set(jenis, h);
  }
  const urut = [...hitung.entries()].sort((a, b) => b[1].n - a[1].n);
  const [jenis, { n, contoh }] = urut[0];
  const angka = (x: number) => x.toLocaleString("id-ID");
  let teks = `${angka(n)} baris: ${jenis}${contoh ? `, contoh ${contoh.slice(0, 60)}` : ""}.`;
  const sisa = daftar.length - n;
  if (sisa > 0) teks += ` ${angka(sisa)} baris lain dengan alasan berbeda.`;
  return teks;
}

function selesaikan(hasil: HasilUrai): HasilUrai {
  if (hasil.tap.length === 0) {
    hasil.hasil = "ditolak";
    hasil.alasan = hasil.baris_ditolak.length > 0
      ? `${PESAN.semuaBarisDitolak} ${rincianTolak(hasil.baris_ditolak)}`
      : PESAN.kosong;
    return hasil;
  }
  let awal = hasil.tap[0].jam_lokal;
  let akhir = awal;
  for (const t of hasil.tap) {
    if (t.jam_lokal < awal) awal = t.jam_lokal;
    if (t.jam_lokal > akhir) akhir = t.jam_lokal;
  }
  hasil.hasil = "diterima";
  hasil.alasan = null;
  hasil.tanggal_awal = awal.slice(0, 10);
  hasil.tanggal_akhir = akhir.slice(0, 10);
  return hasil;
}
