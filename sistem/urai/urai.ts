// Pembaca file mesin finger (Tahap 3).
// Mengubah isi file menjadi daftar tap baku: ID mesin (teks), jam lokal mesin, status, nomor baris asal.
// Tidak memakai pustaka luar dan tidak memakai API khusus Node atau Deno, supaya modul yang sama
// bisa dipakai di uji otomatis (Node) dan di Supabase Edge Functions (Deno) pada Tahap 5.
// Aturan yang diterapkan di sini hanya aturan bentuk file (PRD bagian 7 langkah "Bakukan",
// celah M1 dan M8, kasus A04, A05, A10, A12, F01, F09). Jendela tap, telat, dan dobel diurus database.
// Larangan: modul ini tidak boleh mengimpor apa pun dari generator/.

export type Format = "ekspor_aplikasi_v1" | "attlog_zkteco";

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
}

export interface PilihanUrai {
  // Tanggal kirim (YYYY-MM-DD). Tap bertanggal lebih dari satu hari setelahnya dianggap mustahil.
  tanggal_kirim?: string;
  // Tanggal paling awal yang masuk akal. Jam mesin yang tereset biasanya kembali ke tahun 2000 (kasus A12).
  tanggal_paling_awal?: string;
}

const PALING_AWAL_BAWAAN = "2020-01-01";

export const PESAN = {
  kosong: "File kosong atau tidak berisi baris data.",
  formatTidakDikenal:
    "Format file tidak dikenal. Kolom yang dibutuhkan: Nama, No.ID, Tgl/Waktu, Status. Kirim file ekspor langsung dari aplikasi mesin.",
  idRusakExcel:
    "No.ID rusak (tertulis seperti 1,98E+17) karena file dibuka lalu disimpan di Excel. Kirim file langsung dari mesin tanpa dibuka di Excel.",
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
export function pecahCsv(teks: string): string[][] {
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
    } else if (c === ",") {
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

// Menerima baris yang sudah dipecah per sel. Dipakai untuk CSV sekarang; di Tahap 5 sel dari .xls
// (dibaca dengan pustaka lembar kerja di Edge Function) masuk lewat fungsi yang sama.
export function uraiBarisEkspor(barisSel: string[][], pilihan: PilihanUrai = {}): HasilUrai {
  const hasil: HasilUrai = {
    hasil: "ditolak",
    alasan: null,
    format: "ekspor_aplikasi_v1",
    tap: [],
    baris_ditolak: [],
    tanggal_awal: null,
    tanggal_akhir: null,
  };
  const kosong = (r: string[]) => r.every((s) => s.trim() === "");
  const iJudul = barisSel.findIndex((r) => !kosong(r));
  if (iJudul < 0) {
    hasil.alasan = PESAN.kosong;
    return hasil;
  }
  const judul = barisSel[iJudul].map((s) => s.trim().toLowerCase());
  const kNama = judul.indexOf("nama");
  const kId = judul.indexOf("no.id");
  const kWaktu = judul.indexOf("tgl/waktu");
  const kStatus = judul.indexOf("status");
  // Kolom tanpa judul (salinan waktu tanpa detik, kasus A04) dan kolom lain diabaikan.
  if (kNama < 0 || kId < 0 || kWaktu < 0 || kStatus < 0) {
    hasil.alasan = PESAN.formatTidakDikenal;
    return hasil;
  }

  const paling_awal = pilihan.tanggal_paling_awal ?? PALING_AWAL_BAWAAN;
  const paling_akhir = pilihan.tanggal_kirim ? tambahHari(pilihan.tanggal_kirim, 1) : null;
  let adaBulanLebihDari12 = false; // angka kedua > 12: pasti bulan/hari

  for (let i = iJudul + 1; i < barisSel.length; i++) {
    const r = barisSel[i];
    if (kosong(r)) continue;
    const nomor = i + 1;
    const id = (r[kId] ?? "").trim();
    if (POLA_NOTASI_ILMIAH.test(id)) {
      hasil.alasan = PESAN.idRusakExcel;
      hasil.tap = [];
      return hasil;
    }
    if (!POLA_ID.test(id)) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.idTidakSah}: "${id}"` });
      continue;
    }
    const teksWaktu = (r[kWaktu] ?? "").trim();
    const m = POLA_WAKTU_EKSPOR.exec(teksWaktu);
    if (!m) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.waktuTidakTerbaca}: "${teksWaktu}"` });
      continue;
    }
    const a = Number(m[1]);
    const b = Number(m[2]);
    if (b > 12) adaBulanLebihDari12 = true;
    const w = susunWaktu(Number(m[3]), b, a, Number(m[4]), Number(m[5]), Number(m[6] ?? "0"));
    if (!w) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.waktuTidakTerbaca}: "${teksWaktu}"` });
      continue;
    }
    if (w.tanggal < paling_awal || (paling_akhir !== null && w.tanggal > paling_akhir)) {
      hasil.baris_ditolak.push({ baris: nomor, alasan: `${PESAN.tanggalMustahil}: "${teksWaktu}"` });
      continue;
    }
    const s = (r[kStatus] ?? "").trim().toLowerCase();
    const status = s.endsWith("masuk") ? "Masuk" : s.endsWith("keluar") ? "Keluar" : null;
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

export function uraiEkspor(teks: string, pilihan: PilihanUrai = {}): HasilUrai {
  return uraiBarisEkspor(pecahCsv(bersihkanBom(teks)), pilihan);
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
  if (pertama.includes(",")) return "ekspor_aplikasi_v1";
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
