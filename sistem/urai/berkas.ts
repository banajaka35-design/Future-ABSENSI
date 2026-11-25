// Pembuka berkas file mesin (paket F1, docs/rencana-f1-format-file.md): .xls (Excel 97-2003: berkas OLE berisi BIFF8),
// .xlsx (ZIP berisi XML), dan teks (UTF-8, UTF-8 dengan BOM, UTF-16, atau Windows-1252).
// Tanpa pustaka luar dan tanpa API khusus Node atau Deno (DecompressionStream dan TextDecoder ada di keduanya), supaya modul
// yang sama dipakai uji otomatis (Node) dan Edge Function (Deno). Hanya membaca nilai sel; format tampilan, rumus, dan gaya
// diabaikan. Aturan isi (kolom, tanggal, ID) ada di urai.ts.
// Larangan: modul ini tidak boleh mengimpor apa pun dari generator/.

export type Sel = string | number | null;
export interface Lembar {
  nama: string;
  baris: Sel[][];
}
export interface Buku {
  jenis: "xls" | "xlsx";
  lembar: Lembar[];
  tanggal1904: boolean; // Excel Mac lama: tanggal angka dihitung dari 1 Jan 1904
}

export class GalatBerkas extends Error {}

// Batas pengaman (celah C4): berkas rusak atau sengaja dibuat aneh tidak boleh membuat Edge Function macet.
export const BATAS_BARIS = 200_000;
const BATAS_KOLOM = 256;
const BATAS_TERURAI = 64 * 1024 * 1024; // isi satu berkas di dalam ZIP sesudah dibuka

export const PESAN_BERKAS = {
  rusak: "File Excel rusak atau tidak lengkap; ekspor ulang dari aplikasi mesin.",
  terkunci: "File Excel dikunci dengan kata sandi; simpan ulang tanpa kata sandi.",
  terlaluLama: "File Excel versi lama (sebelum Excel 97) belum bisa dibaca; simpan ulang sebagai .xlsx atau CSV.",
  terlaluBesar: "File terlalu besar setelah dibuka.",
  terlaluBanyakBaris: `File berisi lebih dari ${BATAS_BARIS.toLocaleString("id-ID")} baris.`,
};

// ---------------------------------------------------------------------------
// Mengenali jenis berkas dari tanda awal isinya (bukan dari nama file)
// ---------------------------------------------------------------------------

export function jenisBerkas(isi: Uint8Array): "xls" | "xlsx" | "teks" {
  if (isi.length >= 8 && isi[0] === 0xd0 && isi[1] === 0xcf && isi[2] === 0x11 && isi[3] === 0xe0 &&
      isi[4] === 0xa1 && isi[5] === 0xb1 && isi[6] === 0x1a && isi[7] === 0xe1) return "xls";
  if (isi.length >= 4 && isi[0] === 0x50 && isi[1] === 0x4b && isi[2] === 0x03 && isi[3] === 0x04) return "xlsx";
  return "teks";
}

// ---------------------------------------------------------------------------
// Teks: tanda BOM, lalu UTF-8 ketat, bila gagal Windows-1252 (CSV dari Excel lama)
// ---------------------------------------------------------------------------

export function bacaTeks(isi: Uint8Array): string {
  if (isi.length >= 3 && isi[0] === 0xef && isi[1] === 0xbb && isi[2] === 0xbf) {
    return new TextDecoder("utf-8").decode(isi.subarray(3));
  }
  if (isi.length >= 2 && isi[0] === 0xff && isi[1] === 0xfe) return new TextDecoder("utf-16le").decode(isi.subarray(2));
  if (isi.length >= 2 && isi[0] === 0xfe && isi[1] === 0xff) return new TextDecoder("utf-16be").decode(isi.subarray(2));
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(isi);
  } catch {
    return new TextDecoder("windows-1252").decode(isi);
  }
}

// ---------------------------------------------------------------------------
// .xls: berkas OLE (Compound File Binary) berisi aliran "Workbook" berformat BIFF8
// ---------------------------------------------------------------------------

const AKHIR_RANTAI = 0xfffffffe;
const SEKTOR_BEBAS = 0xffffffff;

function u16(b: Uint8Array, i: number): number {
  if (i + 2 > b.length) throw new GalatBerkas(PESAN_BERKAS.rusak);
  return b[i] | (b[i + 1] << 8);
}
function u32(b: Uint8Array, i: number): number {
  if (i + 4 > b.length) throw new GalatBerkas(PESAN_BERKAS.rusak);
  return (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16)) + b[i + 3] * 0x1000000;
}
function f64(b: Uint8Array, i: number): number {
  if (i + 8 > b.length) throw new GalatBerkas(PESAN_BERKAS.rusak);
  return new DataView(b.buffer, b.byteOffset + i, 8).getFloat64(0, true);
}

// Isi aliran bernama dari berkas OLE.
function aliranOle(isi: Uint8Array, namaDicari: string[]): Uint8Array | null {
  if (isi.length < 512) throw new GalatBerkas(PESAN_BERKAS.rusak);
  const ukuranSektor = 1 << u16(isi, 0x1e);
  const ukuranMini = 1 << u16(isi, 0x20);
  if (ukuranSektor !== 512 && ukuranSektor !== 4096) throw new GalatBerkas(PESAN_BERKAS.rusak);
  const sektorDir = u32(isi, 0x30);
  const batasMini = u32(isi, 0x38);
  const sektorMiniFat = u32(isi, 0x3c);
  const sektorDifat = u32(isi, 0x44);
  const jumlahSektor = Math.floor((isi.length - ukuranSektor) / ukuranSektor) + 1;
  const awalSektor = (s: number) => ukuranSektor + s * ukuranSektor;

  // Daftar sektor FAT dari DIFAT di kepala berkas (109 isian) dan rantai DIFAT sesudahnya.
  const daftarFat: number[] = [];
  for (let i = 0; i < 109; i++) {
    const s = u32(isi, 0x4c + i * 4);
    if (s !== SEKTOR_BEBAS && s !== AKHIR_RANTAI) daftarFat.push(s);
  }
  let d = sektorDifat;
  const sudahDifat = new Set<number>();
  while (d !== AKHIR_RANTAI && d !== SEKTOR_BEBAS) {
    if (sudahDifat.has(d) || d >= jumlahSektor) throw new GalatBerkas(PESAN_BERKAS.rusak);
    sudahDifat.add(d);
    const a = awalSektor(d);
    const n = ukuranSektor / 4 - 1;
    for (let i = 0; i < n; i++) {
      const s = u32(isi, a + i * 4);
      if (s !== SEKTOR_BEBAS && s !== AKHIR_RANTAI) daftarFat.push(s);
    }
    d = u32(isi, a + n * 4);
  }
  const fat: number[] = [];
  for (const s of daftarFat) {
    if (s >= jumlahSektor) throw new GalatBerkas(PESAN_BERKAS.rusak);
    const a = awalSektor(s);
    for (let i = 0; i < ukuranSektor / 4; i++) fat.push(u32(isi, a + i * 4));
  }
  // Rantai sektor, dengan penjaga putaran (celah C4).
  const rantai = (awal: number, tabel: number[], batas: number): number[] => {
    const hasil: number[] = [];
    const sudah = new Set<number>();
    let s = awal;
    while (s !== AKHIR_RANTAI && s !== SEKTOR_BEBAS) {
      if (sudah.has(s) || s >= batas || s >= tabel.length) throw new GalatBerkas(PESAN_BERKAS.rusak);
      sudah.add(s);
      hasil.push(s);
      s = tabel[s];
    }
    return hasil;
  };
  const baca = (awal: number, ukuran: number): Uint8Array => {
    const sektor = rantai(awal, fat, jumlahSektor);
    const keluar = new Uint8Array(sektor.length * ukuranSektor);
    sektor.forEach((s, i) => {
      const a = awalSektor(s);
      keluar.set(isi.subarray(a, Math.min(a + ukuranSektor, isi.length)), i * ukuranSektor);
    });
    return ukuran >= 0 ? keluar.subarray(0, Math.min(ukuran, keluar.length)) : keluar;
  };

  const dir = baca(sektorDir, -1);
  interface Entri { nama: string; jenis: number; awal: number; ukuran: number }
  const entri: Entri[] = [];
  for (let i = 0; i + 128 <= dir.length; i += 128) {
    const panjangNama = u16(dir, i + 0x40);
    let nama = "";
    for (let k = 0; k + 2 < panjangNama && k < 64; k += 2) nama += String.fromCharCode(u16(dir, i + k));
    entri.push({ nama, jenis: dir[i + 0x42], awal: u32(dir, i + 0x74), ukuran: u32(dir, i + 0x78) });
  }
  const akar = entri.find((e) => e.jenis === 5);
  const dicari = entri.find((e) => e.jenis === 2 && namaDicari.includes(e.nama));
  if (!dicari) return null;
  if (dicari.ukuran >= batasMini || !akar) return baca(dicari.awal, dicari.ukuran);
  // Aliran kecil disimpan di aliran mini milik entri akar.
  const miniFatBytes = sektorMiniFat === AKHIR_RANTAI ? new Uint8Array(0) : baca(sektorMiniFat, -1);
  const miniFat: number[] = [];
  for (let i = 0; i + 4 <= miniFatBytes.length; i += 4) miniFat.push(u32(miniFatBytes, i));
  const aliranMini = baca(akar.awal, akar.ukuran);
  const sektorMini = rantai(dicari.awal, miniFat, Math.floor(aliranMini.length / ukuranMini));
  const keluar = new Uint8Array(sektorMini.length * ukuranMini);
  sektorMini.forEach((s, i) => keluar.set(aliranMini.subarray(s * ukuranMini, (s + 1) * ukuranMini), i * ukuranMini));
  return keluar.subarray(0, dicari.ukuran);
}

// Rangkaian potongan rekaman (rekaman utama + CONTINUE). Teks yang terpotong di batas rekaman melanjutkan dengan satu byte
// penanda baru (lebar huruf) di awal rekaman CONTINUE.
class Potongan {
  private i = 0;
  private k = 0;
  private bagian: Uint8Array[];
  constructor(bagian: Uint8Array[]) {
    this.bagian = bagian;
  }
  private pastikan() {
    while (this.k < this.bagian.length && this.i >= this.bagian[this.k].length) {
      this.k++;
      this.i = 0;
    }
    if (this.k >= this.bagian.length) throw new GalatBerkas(PESAN_BERKAS.rusak);
  }
  byte(): number {
    this.pastikan();
    return this.bagian[this.k][this.i++];
  }
  u16(): number {
    return this.byte() | (this.byte() << 8);
  }
  u32(): number {
    return this.u16() + this.u16() * 0x10000;
  }
  lewati(n: number) {
    for (let j = 0; j < n; j++) this.byte();
  }
  // Teks BIFF8 (XLUnicodeRichExtendedString) dengan jumlah huruf `n`.
  teks(n: number): string {
    let penanda = this.byte();
    const kaya = penanda & 0x08 ? this.u16() : 0;
    const tambahan = penanda & 0x04 ? this.u32() : 0;
    let hasil = "";
    let sisa = n;
    while (sisa > 0) {
      if (this.k < this.bagian.length && this.i >= this.bagian[this.k].length) {
        this.k++;
        this.i = 0;
        penanda = this.byte(); // CONTINUE: lebar huruf bisa berganti
      }
      this.pastikan();
      const lebar = penanda & 0x01 ? 2 : 1;
      const tersedia = Math.floor((this.bagian[this.k].length - this.i) / lebar);
      const ambil = Math.min(sisa, Math.max(tersedia, 1));
      for (let j = 0; j < ambil; j++) hasil += String.fromCharCode(lebar === 2 ? this.u16() : this.byte());
      sisa -= ambil;
    }
    this.lewati(kaya * 4 + tambahan);
    return hasil;
  }
}

function nilaiRk(rk: number): number {
  let v: number;
  if (rk & 0x02) {
    v = rk >> 2; // bilangan bulat 30 bit bertanda
  } else {
    const dv = new DataView(new ArrayBuffer(8));
    dv.setUint32(4, (rk & 0xfffffffc) >>> 0, true);
    v = dv.getFloat64(0, true);
  }
  return rk & 0x01 ? v / 100 : v;
}

export function bukaXls(isi: Uint8Array): Buku {
  const wb = aliranOle(isi, ["Workbook", "Book"]);
  if (!wb) throw new GalatBerkas(PESAN_BERKAS.rusak);
  // Pecah aliran menjadi rekaman [jenis, isi].
  const rekaman: { jenis: number; isi: Uint8Array; awal: number }[] = [];
  for (let p = 0; p + 4 <= wb.length;) {
    const jenis = u16(wb, p);
    const panjang = u16(wb, p + 2);
    if (p + 4 + panjang > wb.length) break;
    rekaman.push({ jenis, isi: wb.subarray(p + 4, p + 4 + panjang), awal: p });
    p += 4 + panjang;
  }
  if (!rekaman.length || rekaman[0].jenis !== 0x0809) throw new GalatBerkas(PESAN_BERKAS.rusak);
  if (u16(rekaman[0].isi, 0) !== 0x0600) throw new GalatBerkas(PESAN_BERKAS.terlaluLama);

  const sst: string[] = [];
  const lembarInfo: { nama: string; awal: number }[] = [];
  let tanggal1904 = false;
  let r = 1;
  for (; r < rekaman.length && rekaman[r].jenis !== 0x000a; r++) {
    const { jenis, isi: d } = rekaman[r];
    if (jenis === 0x002f) throw new GalatBerkas(PESAN_BERKAS.terkunci);
    if (jenis === 0x0022) tanggal1904 = u16(d, 0) === 1;
    if (jenis === 0x0085 && d.length >= 8) {
      // BOUNDSHEET: posisi BOF lembar (u32), keadaan tampil, jenis lembar (0 = lembar kerja), nama (cch u8, penanda, huruf).
      if (d[5] === 0) lembarInfo.push({ awal: u32(d, 0), nama: new Potongan([d.subarray(7)]).teks(d[6]) });
    }
    if (jenis === 0x00fc) {
      const bagian = [d.subarray(8)];
      while (r + 1 < rekaman.length && rekaman[r + 1].jenis === 0x003c) bagian.push(rekaman[++r].isi);
      const unik = u32(d, 4);
      const pt = new Potongan(bagian);
      for (let i = 0; i < unik; i++) sst.push(pt.teks(pt.u16()));
    }
  }

  const lembar: Lembar[] = [];
  for (const info of lembarInfo) {
    let i = rekaman.findIndex((x) => x.awal === info.awal);
    if (i < 0 || rekaman[i].jenis !== 0x0809) continue;
    if (u16(rekaman[i].isi, 2) !== 0x0010) continue; // hanya lembar kerja biasa
    const baris: Sel[][] = [];
    const isiSel = (b: number, k: number, v: Sel) => {
      if (b >= BATAS_BARIS) throw new GalatBerkas(PESAN_BERKAS.terlaluBanyakBaris);
      if (k >= BATAS_KOLOM) return;
      while (baris.length <= b) baris.push([]);
      const rr = baris[b];
      while (rr.length < k) rr.push(null);
      rr[k] = v;
    };
    let rumusTeks: [number, number] | null = null;
    for (i++; i < rekaman.length && rekaman[i].jenis !== 0x000a; i++) {
      const { jenis, isi: d } = rekaman[i];
      switch (jenis) {
        case 0x00fd: // LABELSST
          isiSel(u16(d, 0), u16(d, 2), sst[u32(d, 6)] ?? "");
          break;
        case 0x0204: // LABEL
          isiSel(u16(d, 0), u16(d, 2), new Potongan([d.subarray(8)]).teks(u16(d, 6)));
          break;
        case 0x0203: // NUMBER
          isiSel(u16(d, 0), u16(d, 2), f64(d, 6));
          break;
        case 0x027e: // RK
          isiSel(u16(d, 0), u16(d, 2), nilaiRk(u32(d, 6)));
          break;
        case 0x00bd: { // MULRK
          const b = u16(d, 0);
          const awal = u16(d, 2);
          const n = (d.length - 6) / 6;
          for (let j = 0; j < n; j++) isiSel(b, awal + j, nilaiRk(u32(d, 4 + j * 6 + 2)));
          break;
        }
        case 0x0006: { // FORMULA: hanya nilai tersimpan
          const b = u16(d, 0);
          const k = u16(d, 2);
          if (d[12] === 0xff && d[13] === 0xff) {
            if (d[6] === 0x00) rumusTeks = [b, k];
            else if (d[6] === 0x01) isiSel(b, k, d[8] ? "TRUE" : "FALSE");
          } else {
            isiSel(b, k, f64(d, 6));
          }
          break;
        }
        case 0x0207: // STRING (hasil teks rumus sebelumnya)
          if (rumusTeks) {
            const bagian = [d.subarray(2)];
            while (i + 1 < rekaman.length && rekaman[i + 1].jenis === 0x003c) bagian.push(rekaman[++i].isi);
            isiSel(rumusTeks[0], rumusTeks[1], new Potongan(bagian).teks(u16(d, 0)));
            rumusTeks = null;
          }
          break;
      }
    }
    lembar.push({ nama: info.nama, baris });
  }
  return { jenis: "xls", lembar, tanggal1904 };
}

// ---------------------------------------------------------------------------
// .xlsx: ZIP berisi XML (workbook, sharedStrings, worksheets)
// ---------------------------------------------------------------------------

async function bukaDeflate(data: Uint8Array, ukuranDiharap: number): Promise<Uint8Array> {
  const aliran = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  const pembaca = aliran.getReader();
  const potong: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { value, done } = await pembaca.read();
    if (done) break;
    total += value.length;
    if (total > BATAS_TERURAI || (ukuranDiharap > 0 && total > ukuranDiharap)) {
      await pembaca.cancel();
      throw new GalatBerkas(PESAN_BERKAS.terlaluBesar);
    }
    potong.push(value);
  }
  const keluar = new Uint8Array(total);
  let p = 0;
  for (const c of potong) {
    keluar.set(c, p);
    p += c.length;
  }
  return keluar;
}

async function isiZip(isi: Uint8Array): Promise<Map<string, () => Promise<Uint8Array>>> {
  let eocd = -1;
  for (let i = isi.length - 22; i >= Math.max(0, isi.length - 22 - 65535); i--) {
    if (isi[i] === 0x50 && isi[i + 1] === 0x4b && isi[i + 2] === 0x05 && isi[i + 3] === 0x06) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new GalatBerkas(PESAN_BERKAS.rusak);
  const jumlah = u16(isi, eocd + 10);
  let p = u32(isi, eocd + 16);
  const hasil = new Map<string, () => Promise<Uint8Array>>();
  for (let n = 0; n < jumlah; n++) {
    if (u32(isi, p) !== 0x02014b50) throw new GalatBerkas(PESAN_BERKAS.rusak);
    const cara = u16(isi, p + 10);
    const ukuranPadat = u32(isi, p + 20);
    const ukuranAsli = u32(isi, p + 24);
    const pjNama = u16(isi, p + 28);
    const pjTambahan = u16(isi, p + 30);
    const pjKomentar = u16(isi, p + 32);
    const lokal = u32(isi, p + 42);
    const nama = new TextDecoder().decode(isi.subarray(p + 46, p + 46 + pjNama));
    p += 46 + pjNama + pjTambahan + pjKomentar;
    hasil.set(nama, async () => {
      if (u32(isi, lokal) !== 0x04034b50) throw new GalatBerkas(PESAN_BERKAS.rusak);
      const awal = lokal + 30 + u16(isi, lokal + 26) + u16(isi, lokal + 28);
      const data = isi.subarray(awal, awal + ukuranPadat);
      if (cara === 0) return data;
      if (cara === 8) return await bukaDeflate(data, ukuranAsli);
      throw new GalatBerkas(PESAN_BERKAS.rusak);
    });
  }
  return hasil;
}

function bukaEntitas(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);/g, (_, e: string) =>
    e === "amp" ? "&" : e === "lt" ? "<" : e === "gt" ? ">" : e === "quot" ? '"' : e === "apos" ? "'"
      : String.fromCodePoint(e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)));
}
// Teks di dalam <si> atau <is>: gabungan semua <t>, tanpa teks fonetik <rPh>.
function teksXml(isi: string): string {
  return [...isi.replace(/<rPh\b[\s\S]*?<\/rPh>/g, "").matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)]
    .map((m) => bukaEntitas(m[1])).join("");
}
function kolomDariRef(ref: string): number {
  let k = 0;
  for (const c of ref) {
    const n = c.charCodeAt(0);
    if (n < 65 || n > 90) break;
    k = k * 26 + (n - 64);
  }
  return k - 1;
}

export async function bukaXlsx(isi: Uint8Array): Promise<Buku> {
  const zip = await isiZip(isi);
  const teks = async (nama: string) => {
    const f = zip.get(nama);
    return f ? new TextDecoder().decode(await f()) : null;
  };
  const wb = await teks("xl/workbook.xml");
  if (wb === null) throw new GalatBerkas(PESAN_BERKAS.rusak);
  const tanggal1904 = /<workbookPr\b[^>]*\bdate1904="(1|true)"/.test(wb);
  const rels = (await teks("xl/_rels/workbook.xml.rels")) ?? "";
  const target = new Map<string, string>();
  for (const m of rels.matchAll(/<Relationship\b[^>]*>/g)) {
    const id = /\bId="([^"]+)"/.exec(m[0])?.[1];
    const t = /\bTarget="([^"]+)"/.exec(m[0])?.[1];
    if (id && t) target.set(id, t.startsWith("/") ? t.slice(1) : "xl/" + t.replace(/^\.\//, ""));
  }
  const ss = (await teks("xl/sharedStrings.xml")) ?? "";
  const sst = [...ss.matchAll(/<si>([\s\S]*?)<\/si>/g)].map((m) => teksXml(m[1]));

  const lembar: Lembar[] = [];
  for (const m of wb.matchAll(/<sheet\b[^>]*>/g)) {
    const nama = bukaEntitas(/\bname="([^"]*)"/.exec(m[0])?.[1] ?? "");
    const rid = /\br:id="([^"]+)"/.exec(m[0])?.[1] ?? "";
    const xml = await teks(target.get(rid) ?? "");
    if (xml === null) continue;
    const baris: Sel[][] = [];
    let nomorBaris = 0;
    for (const rm of xml.matchAll(/<row\b([^>]*?)(?:\/>|>([\s\S]*?)<\/row>)/g)) {
      const r = /\br="(\d+)"/.exec(rm[1]);
      const b = r ? Number(r[1]) - 1 : nomorBaris;
      nomorBaris = b + 1;
      if (b >= BATAS_BARIS) throw new GalatBerkas(PESAN_BERKAS.terlaluBanyakBaris);
      if (!rm[2]) continue;
      while (baris.length <= b) baris.push([]);
      const rr = baris[b];
      let kolomBerikut = 0;
      for (const cm of rm[2].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const ref = /\br="([A-Z]+)\d*"/.exec(cm[1]);
        const k = ref ? kolomDariRef(ref[1]) : kolomBerikut;
        kolomBerikut = k + 1;
        if (k >= BATAS_KOLOM) continue;
        const t = /\bt="([^"]+)"/.exec(cm[1])?.[1] ?? "n";
        const isiC = cm[2] ?? "";
        const v = /<v>([\s\S]*?)<\/v>/.exec(isiC)?.[1];
        let nilai: Sel = null;
        if (t === "s" && v !== undefined) nilai = sst[Number(v)] ?? "";
        else if (t === "inlineStr") nilai = teksXml(/<is>([\s\S]*?)<\/is>/.exec(isiC)?.[1] ?? "");
        else if (t === "str" && v !== undefined) nilai = bukaEntitas(v);
        else if (t === "b" && v !== undefined) nilai = v === "1" ? "TRUE" : "FALSE";
        else if (t === "n" && v !== undefined && v !== "") nilai = Number(v);
        else if (t === "d" && v !== undefined) nilai = bukaEntitas(v);
        while (rr.length < k) rr.push(null);
        rr[k] = nilai;
      }
    }
    lembar.push({ nama, baris });
  }
  return { jenis: "xlsx", lembar, tanggal1904 };
}
