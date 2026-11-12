// Mengubah file mesin menjadi perintah SQL yang memanggil fakta.terima_kiriman (pintu masuk kiriman).
// Dipakai uji otomatis dan pemuatan data simulasi. Di Tahap 5, Edge Function memanggil fungsi yang sama
// dengan hasil urai yang sama, jadi jalur masuk file tidak berbeda antara uji dan sistem sungguhan.
// Pemakaian:
//   node sistem/urai/kirim.ts --mesin MA1 --diterima "2026-02-21 00:00:00+07" [--tanggal-kirim 2026-02-21] FILE [FILE...]
//   | psql "$DB_URL" -v ON_ERROR_STOP=1
// File .gz dibuka dulu; sidik dihitung dari isi yang sudah dibuka (sama dengan file yang dikirim HRD).
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { basename } from "node:path";
import { gunzipSync } from "node:zlib";
import { urai } from "./urai.ts";

function ambilArg(nama: string, args: string[]): string | undefined {
  const i = args.indexOf(nama);
  if (i < 0) return undefined;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
}

function kutip(s: string | null | undefined): string {
  if (s === null || s === undefined) return "null";
  return "'" + s.replace(/'/g, "''") + "'";
}

const args = process.argv.slice(2);
const mesin = ambilArg("--mesin", args);
const diterima = ambilArg("--diterima", args);
const tanggalKirim = ambilArg("--tanggal-kirim", args) ?? (diterima ? diterima.slice(0, 10) : undefined);
const nomorPesan = ambilArg("--nomor-pesan", args);
if (!mesin || args.length === 0) {
  console.error("Pemakaian: node sistem/urai/kirim.ts --mesin KODE [--diterima WAKTU] FILE...");
  process.exit(2);
}

for (const jalur of args) {
  let isi = readFileSync(jalur);
  let nama = basename(jalur);
  if (jalur.endsWith(".gz")) {
    isi = gunzipSync(isi);
    nama = nama.slice(0, -3);
  }
  const teks = isi.toString("utf8");
  const sidik = createHash("sha256").update(isi).digest("hex");
  const h = urai(teks, { tanggal_kirim: tanggalKirim });
  const tap = h.tap.map((t) => [t.id_mesin, t.jam_lokal, t.status, t.baris]);
  const json = JSON.stringify(tap);
  if (json.includes("$tap$")) throw new Error("isi file tidak boleh memuat penanda $tap$");
  const catatan = h.baris_ditolak.length > 0 ? ` (${h.baris_ditolak.length} baris dibuang)` : "";
  console.log(`\\echo Kiriman ${nama}: ${h.hasil}, ${h.tap.length} tap${catatan}`);
  console.log(
    `select fakta.terima_kiriman(${kutip(nama)}, ${kutip(sidik)}, ${kutip(mesin)}, $tap$${json}$tap$::jsonb, ` +
      `${kutip(h.alasan)}, ${diterima ? kutip(diterima) + "::timestamptz" : "now()"}, ` +
      `${nomorPesan ?? "null"});`,
  );
}
