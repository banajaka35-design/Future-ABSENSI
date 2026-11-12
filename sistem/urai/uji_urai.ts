// Uji pembaca file (Tahap 3): kasus jebakan bagian A dan F yang menyangkut bentuk file.
// Pemakaian: node --test sistem/urai/uji_urai.ts
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { gunzipSync } from "node:zlib";
import { PESAN, kenaliFormat, pecahCsv, urai, uraiAttlog, uraiEkspor } from "./urai.ts";

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
