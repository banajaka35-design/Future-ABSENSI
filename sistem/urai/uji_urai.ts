// Uji pembaca file (Tahap 3): kasus jebakan bagian A dan F yang menyangkut bentuk file.
// Pemakaian: node --test sistem/urai/uji_urai.ts
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { gunzipSync } from "node:zlib";
import { PESAN, kenaliFormat, pecahCsv, urai, uraiAttlog, uraiBerkas, uraiEkspor } from "./urai.ts";
import { bacaTeks, jenisBerkas } from "./berkas.ts";

const JUDUL = "Nama,No.ID,Tgl/Waktu,,Status\r\n";
const baca = (jalur: string) => gunzipSync(readFileSync(new URL(jalur, import.meta.url))).toString("utf8");

test("bentuk file asli: 5 kolom, jam bertitik, status C/Masuk dan C/Keluar", () => {
  const h = uraiEkspor(JUDUL + "EKA,10001,22/01/2026 07.15.23,22/01/2026 07.15,C/Keluar\r\nEKA,10001,22/01/2026 22.40.57,22/01/2026 22.40,C/Masuk\r\n");
  assert.equal(h.hasil, "diterima");
  assert.deepEqual(h.tap, [
    { id_mesin: "10001", jam_lokal: "2026-01-22 07:15:23", status: "Keluar", baris: 2 },
    { id_mesin: "10001", jam_lokal: "2026-01-22 22:40:57", status: "Masuk", baris: 3 },
  ]);
  assert.equal(h.tanggal_awal, "2026-01-22");
  assert.equal(h.tanggal_akhir, "2026-01-22");
});

test("A04: kolom tanpa judul (jam tanpa detik) diabaikan, tidak menjadi tap ganda", () => {
  const h = uraiEkspor(JUDUL + "P1,7,02/02/2026 07.05.23,02/02/2026 07.05,C/Masuk\r\n");
  assert.equal(h.tap.length, 1);
  assert.equal(h.tap[0].jam_lokal, "2026-02-02 07:05:23");
});

test("A05: ID 18 digit disimpan sebagai teks, digit utuh", () => {
  const h = uraiEkspor(JUDUL + "P1,198001012010011001,02/02/2026 07.05.23,02/02/2026 07.05,C/Masuk\r\n");
  assert.equal(h.tap[0].id_mesin, "198001012010011001");
});

test("A05: seluruh file simulasi dengan ID diganti 18 digit terbaca utuh", () => {
  const asli = baca("../../data/simulasi/A/mesin/A_p1_MA2.csv.gz");
  const panjang = asli.replace(/^([^,\r\n]*),(\d{5}),/gm, (_, nama, id) => `${nama},19800101201001${id.padStart(4, "0").slice(-4)},`);
  const a = uraiEkspor(asli);
  const b = uraiEkspor(panjang);
  assert.equal(b.hasil, "diterima");
  assert.equal(b.tap.length, a.tap.length);
  assert.ok(b.tap.every((t) => t.id_mesin.length === 18));
  assert.deepEqual(b.tap.map((t) => t.jam_lokal), a.tap.map((t) => t.jam_lokal));
});

test("A10: tanggal yang hanya masuk akal sebagai bulan/hari membuat file ditolak", () => {
  const h = uraiEkspor(JUDUL + "P1,7,02/03/2026 07.05.00,,C/Masuk\r\nP1,7,03/13/2026 07.05.00,,C/Masuk\r\n");
  assert.equal(h.hasil, "ditolak");
  assert.equal(h.alasan, PESAN.tanggalCampur);
  assert.equal(h.tap.length, 0);
});

test("A10: 02/03 dan 13/03 dibaca hari/bulan", () => {
  const h = uraiEkspor(JUDUL + "P1,7,02/03/2026 07.05.00,,C/Masuk\r\nP1,7,13/03/2026 07.05.00,,C/Masuk\r\n");
  assert.equal(h.hasil, "diterima");
  assert.deepEqual(h.tap.map((t) => t.jam_lokal), ["2026-03-02 07:05:00", "2026-03-13 07:05:00"]);
});

test("A12: tap bertanggal 01/01/2000 (jam mesin tereset) dibuang dan dilaporkan, file tetap diterima", () => {
  const h = uraiEkspor(JUDUL + "P1,7,01/01/2000 00.01.00,,C/Masuk\r\nP1,7,02/02/2026 07.05.00,,C/Masuk\r\n");
  assert.equal(h.hasil, "diterima");
  assert.equal(h.tap.length, 1);
  assert.equal(h.baris_ditolak.length, 1);
  assert.equal(h.baris_ditolak[0].baris, 2);
  assert.match(h.baris_ditolak[0].alasan, /tanggal mustahil/);
});

test("A12: tap bertanggal lebih dari sehari setelah tanggal kirim dibuang", () => {
  const h = uraiEkspor(JUDUL + "P1,7,02/02/2026 07.05.00,,C/Masuk\r\nP1,7,15/02/2026 07.05.00,,C/Masuk\r\n", { tanggal_kirim: "2026-02-10" });
  assert.equal(h.tap.length, 1);
  assert.equal(h.baris_ditolak.length, 1);
});

test("A12: tanggal tidak ada di kalender (31/02) dibuang", () => {
  const h = uraiEkspor(JUDUL + "P1,7,31/02/2026 07.05.00,,C/Masuk\r\nP1,7,02/02/2026 07.05.00,,C/Masuk\r\n");
  assert.equal(h.tap.length, 1);
  assert.equal(h.baris_ditolak.length, 1);
});

test("F01: ID berbentuk 1,98E+17 (file disimpan ulang di Excel) membuat seluruh file ditolak", () => {
  const h = uraiEkspor(JUDUL + 'P1,"1,98E+17",02/02/2026 07.05.23,,C/Masuk\r\n');
  assert.equal(h.hasil, "ditolak");
  assert.equal(h.alasan, PESAN.idRusakExcel);
  const h2 = uraiEkspor(JUDUL + "P1,1.98001E+17,02/02/2026 07.05.23,,C/Masuk\r\n");
  assert.equal(h2.alasan, PESAN.idRusakExcel);
});

test("F09: kolom waktu bernama 'Waktu' (format belum dikenal) ditolak dengan alasan", () => {
  const h = urai("Nama,No.ID,Waktu,Status\r\nP1,7,02/02/2026 07.05.23,C/Masuk\r\n");
  assert.equal(h.hasil, "ditolak");
  assert.equal(h.alasan, PESAN.formatTidakDikenal);
});

test("file kosong atau hanya judul ditolak", () => {
  assert.equal(urai("").hasil, "ditolak");
  assert.equal(urai(JUDUL).hasil, "ditolak");
  assert.equal(urai(JUDUL).alasan, PESAN.kosong);
});

test("nama berisi koma di dalam tanda kutip tidak menggeser kolom", () => {
  assert.deepEqual(pecahCsv('"Lubis, Andi",7,x\r\n'), [["Lubis, Andi", "7", "x"]]);
  const h = uraiEkspor(JUDUL + '"Lubis, Andi",7,02/02/2026 07.05.23,,C/Masuk\r\n');
  assert.equal(h.tap[0].id_mesin, "7");
});

test("attlog.dat: ID rata kanan, status 0 masuk dan 1 keluar", () => {
  const h = uraiAttlog("    10739\t2026-01-21 06:30:04\t1\t0\t1\t0\n    10739\t2026-01-21 15:02:00\t1\t1\t1\t0\n");
  assert.equal(h.hasil, "diterima");
  assert.deepEqual(h.tap.map((t) => [t.id_mesin, t.jam_lokal, t.status]), [
    ["10739", "2026-01-21 06:30:04", "Masuk"],
    ["10739", "2026-01-21 15:02:00", "Keluar"],
  ]);
});

test("bentuk file dikenali dari isinya, bukan dari nama", () => {
  assert.equal(kenaliFormat("    1\t2026-01-21 06:30:04\t1\t0\t1\t0\n"), "attlog_zkteco");
  assert.equal(kenaliFormat(JUDUL), "ekspor_aplikasi_v1");
  assert.equal(kenaliFormat("sembarang teks"), null);
});

test("U6 (tingkat file): ekspor aplikasi dan attlog.dat simulasi berisi tap yang sama persis", () => {
  for (const [ekspor, attlog] of [
    ["../../data/simulasi/A/mesin/A_p1_MA1.csv.gz", "../../data/simulasi/A/attlog/A_p1_MA1.dat.gz"],
    ["../../data/simulasi/A/mesin/A_p3_MA2.csv.gz", "../../data/simulasi/A/attlog/A_p3_MA2.dat.gz"],
  ]) {
    const a = urai(baca(ekspor));
    const b = urai(baca(attlog));
    assert.equal(a.format, "ekspor_aplikasi_v1");
    assert.equal(b.format, "attlog_zkteco");
    const kunci = (t: { id_mesin: string; jam_lokal: string; status: string | null }) => `${t.id_mesin}|${t.jam_lokal}|${t.status}`;
    assert.deepEqual(a.tap.map(kunci).sort(), b.tap.map(kunci).sort());
  }
});

test("6f (B1): semua baris ditolak -> pesan menyebut alasan terbanyak, jumlah, dan contoh; awalan tetap", () => {
  const isi = JUDUL + Array.from({ length: 1500 }, (_, i) =>
    `P${i},${10000 + i},22/11/2026 07.0${i % 10}.00,,C/Masuk`).join("\r\n") + "\r\nP,X!,22/11/2026 07.00.00,,C/Masuk\r\n";
  const h = uraiEkspor(isi, { tanggal_kirim: "2026-11-18" });
  assert.equal(h.hasil, "ditolak");
  assert.ok(h.alasan!.startsWith(PESAN.semuaBarisDitolak), h.alasan!);
  assert.match(h.alasan!, /1\.500 baris: tanggal mustahil \(jam mesin kemungkinan tereset atau salah\), contoh "22\/11\/2026 07\.00\.00"\./);
  assert.match(h.alasan!, / 1 baris lain dengan alasan berbeda\.$/);
});

// ---------------------------------------------------------------------------
// Paket F1 (docs/rencana-f1-format-file.md): berbagai format file mesin. Berkas contoh di sistem/urai/contoh/ (dibuat oleh
// buat_contoh.py dari data simulasi; isinya karangan).
// ---------------------------------------------------------------------------
const CONTOH = new URL("./contoh/", import.meta.url);
const berkasContoh = (nama: string) => {
  const isi = readFileSync(new URL(nama, CONTOH));
  return new Uint8Array(nama.endsWith(".gz") ? gunzipSync(isi) : isi);
};
const csvSim = (nama: string) => gunzipSync(readFileSync(new URL(`../../data/simulasi/A/mesin/${nama}`, import.meta.url)));
const ringkas = (h: { tap: { id_mesin: string; jam_lokal: string; status: string | null; baris: number }[] }) =>
  h.tap.map((t) => `${t.id_mesin}|${t.jam_lokal}|${t.status}|${t.baris}`);

test("F1: data yang sama dalam CSV, .xls, .xlsx, tanggal angka Excel, CSV titik koma (Windows-1252), TXT UTF-16 -> tap sama persis", async () => {
  const pilihan = { tanggal_kirim: "2026-02-21" };
  const acuan = urai(csvSim("A_p1_MA2.csv.gz").toString("utf8"), pilihan);
  assert.equal(acuan.hasil, "diterima");
  for (const nama of ["A_p1_MA2.xls", "A_p1_MA2.xlsx", "A_p1_MA2_angka.xls", "A_p1_MA2_angka.xlsx", "A_p1_MA2_titikkoma.csv",
                      "A_p1_MA2_utf16.txt"]) {
    const h = await uraiBerkas(berkasContoh(nama), pilihan);
    assert.equal(h.hasil, "diterima", nama);
    assert.deepEqual(ringkas(h), ringkas(acuan), nama);
  }
  assert.equal((await uraiBerkas(berkasContoh("A_p1_MA2.xls"), pilihan)).format, "ekspor_xls");
  assert.equal((await uraiBerkas(berkasContoh("A_p1_MA2.xlsx"), pilihan)).format, "ekspor_xlsx");
});

test("F1: ID 'No. Pegawai', tanggal dan jam terpisah, tanpa status, diawali judul laporan -> ID dan jam sama", async () => {
  const acuan = urai(csvSim("A_p1_MA2.csv.gz").toString("utf8"), { tanggal_kirim: "2026-02-21" });
  const h = await uraiBerkas(berkasContoh("A_p1_MA2_terpisah.csv"), { tanggal_kirim: "2026-02-21" });
  assert.equal(h.hasil, "diterima");
  assert.deepEqual(h.tap.map((t) => `${t.id_mesin}|${t.jam_lokal}`), acuan.tap.map((t) => `${t.id_mesin}|${t.jam_lokal}`));
  assert.ok(h.tap.every((t) => t.status === null), "tanpa kolom status, status kosong (masuk/pulang dari jam)");
});

test("F1: Excel sistem tanggal 1904 (Mac) dibaca sama dengan sistem 1900", async () => {
  const acuan = urai(csvSim("A_p1_MA2.csv.gz").toString("utf8"), { tanggal_kirim: "2026-02-21" });
  const h = await uraiBerkas(berkasContoh("A_p1_MA2_1904.xlsx"), { tanggal_kirim: "2026-02-21" });
  assert.equal(h.hasil, "diterima");
  assert.deepEqual(ringkas(h), ringkas(acuan).slice(0, 39));
});

test("F1: satu periode MA1 (40.566 baris) dalam .xls sama dengan CSV, dan terbaca jauh di bawah batas 2 detik CPU", async () => {
  const acuan = urai(csvSim("A_p1_MA1.csv.gz").toString("utf8"), { tanggal_kirim: "2026-02-21" });
  const isi = berkasContoh("A_p1_MA1.xls.gz");
  const mulai = performance.now();
  const h = await uraiBerkas(isi, { tanggal_kirim: "2026-02-21" });
  const lama = performance.now() - mulai;
  console.log(`  waktu baca .xls 40.566 baris: ${Math.round(lama)} ms`);
  assert.deepEqual(ringkas(h), ringkas(acuan));
  assert.ok(lama < 1500, `terlalu lambat: ${Math.round(lama)} ms`);
});

test("F1: tiruan susunan file asli pemilik (.xls, kolom tanpa judul, ID 18 angka, 'C/Masuk' sore) terbaca utuh", async () => {
  const h = await uraiBerkas(berkasContoh("tiruan_asli.xls"), { tanggal_kirim: "2026-10-31" });
  assert.equal(h.hasil, "diterima");
  assert.equal(h.tap.length, 20);
  assert.deepEqual([...new Set(h.tap.map((t) => t.id_mesin))], ["198001012010011001", "198502022011012002"]); // A05: digit utuh
  assert.equal(h.tap[1].jam_lokal, "2026-10-01 16:08:45");
  assert.equal(h.tap[1].status, "Masuk"); // A01: status apa adanya; masuk/pulang ditentukan dari jam di database
});

test("F1: penolakan dengan alasan (rekap, F09 'Waktu' di .xlsx, ID 18 angka sebagai angka, dua kolom ID, Excel rusak)", async () => {
  const tolak = async (nama: string) => (await uraiBerkas(berkasContoh(nama), { tanggal_kirim: "2026-10-31" }));
  const rekap = await tolak("tolak_rekap.xlsx");
  assert.equal(rekap.hasil, "ditolak");
  assert.equal(rekap.alasan, PESAN.rekap);
  assert.equal((await tolak("tolak_waktu_saja.xlsx")).alasan, PESAN.formatTidakDikenal); // F09 (keputusan pemilik: pilihan A)
  assert.equal((await tolak("tolak_id_angka.xlsx")).alasan, PESAN.idAngkaPanjang);
  assert.equal((await tolak("tolak_dua_id.csv")).alasan, PESAN.kolomGanda);
  const rusak = await tolak("tolak_rusak.xls");
  assert.equal(rusak.hasil, "ditolak");
  assert.ok(rusak.alasan!.startsWith(PESAN.berkasRusak));
  // Semua penolakan bentuk file berawalan "Format file tidak dikenal" atau "No.ID rusak": dikenali database sebagai kejadian
  // segera (fakta.jenis_tolak_segera, migrasi 0018).
  for (const a of [PESAN.rekap, PESAN.kolomGanda, PESAN.berkasRusak, PESAN.formatTidakDikenal]) assert.ok(a.startsWith("Format file tidak dikenal"));
  assert.ok(PESAN.idAngkaPanjang.startsWith("No.ID rusak"));
});

test("F1: 'Waktu' atau 'Time' saja tidak dikenali, juga sebagai kolom jam (F09, pilihan A)", () => {
  assert.equal(urai("Nama,No.ID,Time,Status\r\nP1,7,02/02/2026 07.05.23,C/Masuk\r\n").alasan, PESAN.formatTidakDikenal);
  assert.equal(urai("No.ID,Tanggal,Waktu\r\n7,02/02/2026,07.05\r\n").alasan, PESAN.formatTidakDikenal);
  assert.equal(urai("No.ID,Tanggal,Jam\r\n7,02/02/2026,07.05\r\n").hasil, "diterima");
});

test("F1: jenis berkas dikenali dari isinya; teks Windows-1252 dan UTF-8 ber-BOM terbaca", async () => {
  assert.equal(jenisBerkas(berkasContoh("A_p1_MA2.xls")), "xls");
  assert.equal(jenisBerkas(berkasContoh("A_p1_MA2.xlsx")), "xlsx");
  assert.equal(jenisBerkas(new TextEncoder().encode(JUDUL)), "teks");
  assert.equal(bacaTeks(new Uint8Array([0x4a, 0x6f, 0x73, 0xe9])), "José");
  assert.equal(bacaTeks(new Uint8Array([0xef, 0xbb, 0xbf, 0x41])), "A");
  const h = await uraiBerkas(new TextEncoder().encode(JUDUL + "P1,7,02/02/2026 07.05.23,02/02/2026 07.05,C/Masuk\r\n"));
  assert.equal(h.hasil, "diterima");
});
