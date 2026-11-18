// Uji penghitung ukuran grafik halaman demo (paket G1): web/demo/grafik_inti.js.
// Pemakaian: node --test sistem/uji/uji_grafik.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const konteks: any = {};
runInNewContext(readFileSync(new URL("../../web/demo/grafik_inti.js", import.meta.url), "utf8"), konteks);
const G = konteks.GrafikInti;

test("batang mendatar: nilai terbesar = lebar penuh, sebanding, nol tetap nol", () => {
  const b = G.batangMendatar([{ label: "A", nilai: 200 }, { label: "B", nilai: 50 }, { label: "C", nilai: 0 }], 400);
  assert.deepEqual(b.map((x: any) => x.panjang), [400, 100, 0]);
});

test("batang mendatar: nilai sangat kecil tetap terlihat 1 px; minus jadi 0 dan ditandai", () => {
  const b = G.batangMendatar([{ label: "besar", nilai: 2_250_888_000 }, { label: "kecil", nilai: 1000 }, { label: "minus", nilai: -5 }], 300);
  assert.equal(b[0].panjang, 300);
  assert.equal(b[1].panjang, 1);
  assert.equal(b[2].panjang, 0);
  assert.equal(b[2].minus, true);
});

test("batang mendatar: satu divisi saja, dan semua nol", () => {
  assert.equal(G.batangMendatar([{ label: "A", nilai: 7 }], 250)[0].panjang, 250);
  assert.deepEqual(G.batangMendatar([{ label: "A", nilai: 0 }, { label: "B", nilai: 0 }], 250).map((x: any) => x.panjang), [0, 0]);
});

test("kolom 31 tanggal: tinggi sebanding, puncak = indeks nilai tertinggi pertama", () => {
  const nilai = Array.from({ length: 31 }, (_, i) => (i === 6 ? 0 : (i % 7) + 1));
  nilai[20] = 40;
  const k = G.kolom(nilai, 120);
  assert.equal(k.tinggi.length, 31);
  assert.equal(k.tinggi[20], 120);
  assert.equal(k.tinggi[6], 0);
  assert.equal(k.puncak, 20);
  assert.equal(k.maks, 40);
});

test("selang label: layar sempit menjarangkan label, layar lebar tidak", () => {
  assert.equal(G.selangLabel(31, 1000, 28), 1);
  assert.equal(G.selangLabel(31, 320, 28), 3);
  assert.equal(G.selangLabel(0, 320, 28), 1);
});

test("persen: satu desimal dengan koma; total nol aman", () => {
  assert.equal(G.persen(703_802_826, 4_983_863_768), "14,1");
  assert.equal(G.persen(5, 0), "0,0");
});
