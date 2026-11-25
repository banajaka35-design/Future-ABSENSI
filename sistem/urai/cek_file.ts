// Alat cek contoh file mesin (paket F1): membaca satu file dengan pembaca yang sama dengan bot, tanpa menyimpan apa pun dan
// tanpa menulis nama karyawan. Dipakai di langkah 1 panduan pasang PT (docs/pasang/README.md, pertanyaan A5) untuk memastikan
// file dari mesin PT terbaca sebelum pemasangan.
// Pemakaian: node sistem/urai/cek_file.ts FILE [--tanggal-kirim YYYY-MM-DD]
import { readFileSync } from "node:fs";
import { basename } from "node:path";
import { bacaTeks, bukaXls, bukaXlsx, jenisBerkas } from "./berkas.ts";
import { rincianTolak, uraiBerkas } from "./urai.ts";

const args = process.argv.slice(2);
const iTanggal = args.indexOf("--tanggal-kirim");
const tanggalKirim = iTanggal >= 0 ? args.splice(iTanggal, 2)[1] : new Date().toISOString().slice(0, 10);
if (args.length !== 1) {
  console.error("Pemakaian: node sistem/urai/cek_file.ts FILE [--tanggal-kirim YYYY-MM-DD]");
  process.exit(2);
}
const isi = new Uint8Array(readFileSync(args[0]));
const jenis = jenisBerkas(isi);
console.log(`File: ${basename(args[0])} (${(isi.length / 1024).toFixed(0)} KB), jenis berkas: ${jenis}`);

// Judul kolom (baris tidak kosong pertama yang memuat lebih dari satu sel), tanpa isi data.
let judul: string[] = [];
try {
  if (jenis === "teks") {
    const baris = bacaTeks(isi).split(/\r?\n/).filter((b) => /[,;\t]/.test(b));
    judul = baris.length ? baris[0].split(/[,;\t]/) : [];
  } else {
    const buku = jenis === "xls" ? bukaXls(isi) : await bukaXlsx(isi);
    console.log(`Lembar: ${buku.lembar.map((l) => `${l.nama} (${l.baris.length} baris)`).join(", ")}`);
    const l = buku.lembar[0];
    judul = (l?.baris.find((r) => r.filter((s) => s !== null && String(s).trim() !== "").length > 1) ?? []).map((s) => String(s ?? ""));
  }
} catch (e) {
  console.log(`Tidak bisa dibuka: ${(e as Error).message}`);
}
console.log(`Judul kolom: ${judul.map((j) => `"${j.trim()}"`).join(", ")}`);

const h = await uraiBerkas(isi, { tanggal_kirim: tanggalKirim });
console.log(`Hasil: ${h.hasil.toUpperCase()}${h.format ? ` (dibaca sebagai ${h.format})` : ""}`);
if (h.alasan) console.log(`Alasan: ${h.alasan}`);
if (h.hasil === "diterima") {
  const orang = new Set(h.tap.map((t) => t.id_mesin));
  const panjang = [...new Set([...orang].map((x) => x.length))].sort((a, b) => a - b);
  console.log(`Tap: ${h.tap.length.toLocaleString("id-ID")}, ID berbeda: ${orang.size} (panjang ID: ${panjang.join("/")} angka)`);
  console.log(`Rentang tanggal: ${h.tanggal_awal} s.d. ${h.tanggal_akhir}`);
  const st = { Masuk: 0, Keluar: 0, kosong: 0 };
  for (const t of h.tap) st[t.status ?? "kosong"]++;
  console.log(`Status di file: masuk ${st.Masuk}, keluar ${st.Keluar}, kosong ${st.kosong} (masuk/pulang tetap ditentukan dari jam)`);
  console.log(`Contoh tap pertama: ID ${h.tap[0].id_mesin}, ${h.tap[0].jam_lokal}`);
}
if (h.baris_ditolak.length) console.log(`Baris dibuang: ${rincianTolak(h.baris_ditolak)}`);
