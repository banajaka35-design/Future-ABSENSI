// Uji pintu Telegram (paket 5b, kasus T1-T8 di docs/pintu-telegram.md) dengan pesan Telegram tiruan,
// file simulasi Pabrik A, dan Postgres sementara. Database dipanggil sebagai peran `pintu`, seperti Edge Function.
// Pemakaian: DB_URL=... node --test sistem/pintu/uji_pintu.ts  (database sudah berisi struktur dan karyawan Pabrik A,
// periode, tanpa tap; disiapkan oleh sistem/uji/uji_pintu.sh)
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import { urai } from "../urai/urai.ts";
import { tanganiPermintaan, apiBoleh, type Alat } from "./inti.ts";

const DB = process.env.DB_URL!;
const RAHASIA = "rahasia-uji";
const HRD = 111;
const BUKAN = 222;

function psql(sql: string, sebagaiPintu = false): string {
  const r = spawnSync("psql", [DB, "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1"], {
    input: (sebagaiPintu ? "set role pintu;\n" : "") + sql,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout.trim();
}
const nilai = (sql: string) => psql(sql);

const fileSim = (nama: string) => gunzipSync(readFileSync(`data/simulasi/A/mesin/${nama}.gz`));
const BERKAS: Record<string, Uint8Array> = {
  F_MA1: fileSim("A_p1_MA1.csv"),
  F_MA2: fileSim("A_p1_MA2.csv"),
  // T4: file yang dibuka lalu disimpan di Excel; No.ID panjang menjadi notasi ilmiah.
  F_EXCEL: new TextEncoder().encode(
    fileSim("A_p1_MA2.csv").toString("utf8").split("\r\n").map((b, i) => {
      if (i === 0 || !b) return b;
      const k = b.split(",");
      k[1] = "\"1,98E+17\"";
      return k.join(",");
    }).join("\r\n"),
  ),
  F_TEKS: new TextEncoder().encode("halo, ini bukan file mesin\nbaris kedua\n"),
};

const terkirim: { metode: string; isi: any }[] = [];
const diunduh: string[] = [];
const alat: Alat = {
  async api(nama, isi) {
    assert.ok(apiBoleh(nama));
    const arg = isi === undefined ? "" : `$j$${JSON.stringify(isi)}$j$::jsonb`;
    const keluar = psql(`select api.${nama}(${arg});`, true);
    return keluar === "" ? null : JSON.parse(keluar);
  },
  async telegram(metode, isi) {
    terkirim.push({ metode, isi });
    if (metode === "getFile") return { file_path: isi.file_id };
    return {};
  },
  async unduh(jalur) {
    diunduh.push(jalur);
    return BERKAS[jalur];
  },
  urai,
  sekarang: () => Date.now(),
  tidur: async () => {},
};

function dokumen(updateId: number, dari: number, fileId: string, nama: string, caption?: string) {
  return JSON.stringify({
    update_id: updateId,
    message: { message_id: updateId, date: 1771635600, chat: { id: dari }, from: { id: dari },
               document: { file_id: fileId, file_name: nama, file_size: BERKAS[fileId].length }, caption },
  });
}
async function kirimUpdate(badan: string, rahasia = RAHASIA) {
  const awal = terkirim.length;
  const r = await tanganiPermintaan("POST", rahasia, badan, RAHASIA, alat);
  if (r.latar) await r.latar;
  return { status: r.status, pesan: terkirim.slice(awal).filter((t) => t.metode === "sendMessage").map((t) => t.isi) };
}

test("persiapan: HRD 111 terdaftar, 222 bukan HRD", () => {
  psql(`insert into induk.pengguna (telegram_id, peran) values (${HRD}, 'hrd'), (${BUKAN}, 'karyawan');`);
});

test("T8: kode rahasia salah ditolak tanpa menyimpan apa pun", async () => {
  const r = await kirimUpdate(dokumen(1, HRD, "F_MA1", "A_p1_MA1.csv", "MA1"), "salah");
  assert.equal(r.status, 401);
  assert.equal(nilai("select count(*) from fakta.pesan_telegram"), "0");
});

test("T1: file sah diterima, disimpan, dan periode terkena dihitung", async () => {
  const mulai = Date.now();
  const r = await kirimUpdate(dokumen(1, HRD, "F_MA1", "A_p1_MA1.csv", "mesin ma1"));
  assert.equal(r.status, 200);
  assert.match(r.pesan[0].text, /diterima \(mesin MA1\), sedang diproses/);
  const harap = urai(new TextDecoder().decode(BERKAS.F_MA1), { tanggal_kirim: "2026-02-21" }).tap.length;
  assert.equal(nilai("select hasil || '/' || nomor_pesan || '/' || mesin from fakta.kiriman_file where nama_file = 'A_p1_MA1.csv'"),
               "diterima/1/MA1");
  assert.equal(nilai("select count(*) from fakta.tap_mentah"), String(harap));
  assert.equal(nilai("select count(*) from fakta.antrean_kerja where status <> 'selesai'"), "0");
  assert.ok(Number(nilai("select count(*) from fakta.antrean_kerja where status = 'selesai'")) >= 1);
  assert.equal(nilai(`select count(*) from hitung.versi_terakhir v join fakta.periode p on p.id = v.periode_id
                      where p.tanggal_awal = '2026-01-21' and v.jenis in ('baca_tap', 'hitung_gaji')`), "2");
  assert.ok(r.pesan.some((p) => /Periode 2026-01-21 s\.d\. 2026-02-20: [\d.]+ orang, gaji bersih Rp/.test(p.text)), JSON.stringify(r.pesan));
  console.log(`  T1 selesai dalam ${Date.now() - mulai} ms; ${r.pesan.length} pesan: ${r.pesan.map((p) => p.text).join(" | ")}`);
});

test("T3: update_id yang sama diabaikan tanpa balasan", async () => {
  const r = await kirimUpdate(dokumen(1, HRD, "F_MA1", "A_p1_MA1.csv", "MA1"));
  assert.deepEqual(r.pesan, []);
  assert.equal(nilai("select count(*) from fakta.kiriman_file"), "1");
});

test("T2: file yang sama dikirim lagi ditolak sebagai dobel", async () => {
  const tap = nilai("select count(*) from fakta.tap_mentah");
  const r = await kirimUpdate(dokumen(2, HRD, "F_MA1", "salinan.csv", "MA1"));
  assert.match(r.pesan.at(-1).text, /ditolak: File yang sama sudah diterima sebelumnya/);
  assert.equal(nilai("select count(*) from fakta.tap_mentah"), tap);
});

test("T4: file rusak karena Excel ditolak dengan alasan", async () => {
  const tap = nilai("select count(*) from fakta.tap_mentah");
  const r = await kirimUpdate(dokumen(3, HRD, "F_EXCEL", "rusak.csv", "MA2"));
  assert.match(r.pesan.at(-1).text, /ditolak: .*Excel/);
  assert.equal(nilai("select hasil from fakta.kiriman_file where nama_file = 'rusak.csv'"), "ditolak");
  assert.equal(nilai("select count(*) from fakta.tap_mentah"), tap);
});

test("T5: file bukan file mesin ditolak", async () => {
  const r = await kirimUpdate(dokumen(4, HRD, "F_TEKS", "catatan.txt", "MA1"));
  assert.match(r.pesan.at(-1).text, /ditolak: Format file tidak dikenal/);
});

test("T6: pengirim bukan HRD ditolak; file tidak diunduh dan tidak dicatat", async () => {
  const unduhSebelum = diunduh.length;
  const r = await kirimUpdate(dokumen(5, BUKAN, "F_MA2", "dari_orang_lain.csv", "MA2"));
  assert.match(r.pesan[0].text, /belum terdaftar sebagai HRD/);
  assert.equal(diunduh.length, unduhSebelum);
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'dari_orang_lain.csv'"), "0");
});

test("T7: tanpa kode mesin -> tombol pilihan; tombol ditekan -> diproses; tekan lagi -> tidak diproses dua kali", async () => {
  const r = await kirimUpdate(dokumen(6, HRD, "F_MA2", "A_p1_MA2.csv"));
  assert.match(r.pesan[0].text, /dari mesin mana/);
  assert.deepEqual(r.pesan[0].reply_markup.inline_keyboard[0].map((t: any) => t.text), ["MA1", "MA2"]);
  const tekan = (u: number) => JSON.stringify({
    update_id: u, callback_query: { id: `cb${u}`, data: "m|6|MA2", from: { id: HRD }, message: { chat: { id: HRD } } },
  });
  const r2 = await kirimUpdate(tekan(7));
  assert.match(r2.pesan[0].text, /A_p1_MA2.csv diterima \(mesin MA2\)/);
  assert.equal(nilai("select hasil || '/' || mesin || '/' || nomor_pesan from fakta.kiriman_file where nama_file = 'A_p1_MA2.csv'"),
               "diterima/MA2/6");
  const r3 = await kirimUpdate(tekan(8));
  assert.match(r3.pesan[0].text, /sudah diproses sebelumnya/);
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'A_p1_MA2.csv'"), "1");
});

test("pesan teks dari HRD dijawab petunjuk", async () => {
  const r = await kirimUpdate(JSON.stringify({ update_id: 9, message: { message_id: 9, chat: { id: HRD }, from: { id: HRD }, text: "halo" } }));
  assert.match(r.pesan[0].text, /Kirim file ekspor/);
});
