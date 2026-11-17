// Uji penyambung Edge Function (paket 5c, kasus S1 di docs/pemberitahuan-segera.md; paket 5d, kasus W10 dan
// unggah multipart di docs/unggah-web.md): sistem/pintu/sambung.ts
// dijalankan dengan postgres.js sungguhan (versi yang sama dengan index.ts) ke Postgres sementara sebagai peran `pintu`,
// dan Telegram tiruan lewat fetch palsu. Menangkap kesalahan jenis 616651f (isian jsonb terbaca kosong).
// Dijalankan oleh sistem/uji/uji_pintu.sh sesudah uji_pintu.ts (database berisi akun dan kiriman dari uji itu).
// Pemakaian: PINTU_URL=postgresql://pintu:...@localhost:5432/uji_pintu DB_URL=... node --test sistem/pintu/uji_sambung.ts
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import postgres from "postgres";
import { urai } from "../urai/urai.ts";
import { buatAlat, layani, PESAN_GANGGUAN, type Sql } from "./sambung.ts";

const DB = process.env.DB_URL!;
const sql = postgres(process.env.PINTU_URL!, { prepare: false, max: 1, idle_timeout: 20, onnotice: () => {} });
after(() => sql.end());

const HRD = 111;
const PEMBANGUN = 444;
const RAHASIA = "rahasia-telegram";
const RAHASIA_PENGINGAT = "rahasia-pengingat";
const FILE_EXCEL = new TextEncoder().encode(
  "Nama,No.ID,Tgl/Waktu,Status\r\nBudi,\"1,98E+17\",21/02/2026 07:00:00,Masuk\r\n",
);

function nilai(kueri: string): string {
  const r = spawnSync("psql", [DB, "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c", kueri], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout.trim();
}

const panggilan: { metode: string; isi: any }[] = [];
const fetchPalsu = (async (alamat: string | URL, pilihan?: RequestInit) => {
  const a = String(alamat);
  if (a.includes("/file/bot")) return new Response(FILE_EXCEL);
  const metode = a.split("/").at(-1)!;
  const isi = JSON.parse(String(pilihan?.body ?? "{}"));
  panggilan.push({ metode, isi });
  const hasil = metode === "getFile" ? { file_path: "dokumen/excel.csv" } : {};
  return Response.json({ ok: true, result: hasil });
}) as typeof fetch;

const ASAL_WEB = "https://halaman.uji";
const alat = buatAlat(sql, "TOKEN-UJI", urai, fetchPalsu, `${ASAL_WEB}/unggah/`);

async function kirim(badan: unknown, kepala: Record<string, string>, jalur = "", metode = "POST") {
  const awal = panggilan.length;
  const isi = metode === "OPTIONS" ? undefined : badan instanceof FormData ? badan : JSON.stringify(badan);
  const { respon, latar } = await layani(
    new Request(`http://lokal/pintu-telegram${jalur ? `?jalur=${jalur}` : ""}`, { method: metode, headers: kepala, body: isi }),
    alat, RAHASIA, RAHASIA_PENGINGAT, ASAL_WEB,
  );
  if (latar) await latar;
  return { respon, pesan: panggilan.slice(awal).filter((p) => p.metode === "sendMessage").map((p) => p.isi) };
}
const dariTelegram = { "x-telegram-bot-api-secret-token": RAHASIA, "content-type": "application/json" };

test("S1: kode rahasia Telegram salah -> 401", async () => {
  const r = await kirim({ update_id: 7001, message: { chat: { id: HRD }, from: { id: HRD }, text: "x" } },
                        { "x-telegram-bot-api-secret-token": "salah" });
  assert.equal(r.respon.status, 401);
  assert.equal(nilai("select count(*) from fakta.pesan_telegram where update_id = 7001"), "0");
});

test("S1: isian jsonb lewat postgres.js terbaca utuh (update_id, telegram_id, jenis)", async () => {
  const r = await kirim({ update_id: 7002, message: { message_id: 1, chat: { id: HRD }, from: { id: HRD }, text: "halo" } },
                        dariTelegram);
  assert.equal(r.respon.status, 200);
  assert.equal(nilai("select telegram_id || '/' || jenis from fakta.pesan_telegram where update_id = 7002"), `${HRD}/teks`);
  assert.match(r.pesan[0].text, /Kirim file ekspor/); // hrd dikenali, berarti telegram_id sampai ke database
});

test("S1: hasil null dari database (tombol tanpa file tertunda) ditangani", async () => {
  const r = await kirim({ update_id: 7003, callback_query: { id: "cb", data: "m|99999|MA1", from: { id: HRD },
                                                            message: { chat: { id: HRD } } } }, dariTelegram);
  assert.equal(r.respon.status, 200);
  assert.match(r.pesan[0].text, /sudah diproses sebelumnya/);
});

test("S1 + N4: file rusak Excel lewat penyambung -> ditolak, pemberitahuan segera ke semua penerima", async () => {
  const r = await kirim({
    update_id: 7004,
    message: { message_id: 2, date: 1771635600, chat: { id: HRD }, from: { id: HRD }, caption: "MA2",
               document: { file_id: "F-X", file_name: "excel_sambung.csv", file_size: FILE_EXCEL.length } },
  }, dariTelegram);
  assert.equal(r.respon.status, 200);
  assert.equal(nilai("select hasil from fakta.kiriman_file where nama_file = 'excel_sambung.csv'"), "ditolak");
  for (const tg of [HRD, PEMBANGUN]) {
    assert.ok(r.pesan.some((p) => p.chat_id === tg && /^PEMBERITAHUAN SEGERA[\s\S]*excel_sambung\.csv/.test(p.text)), String(tg));
  }
  assert.equal(nilai(`select status from fakta.pemberitahuan where isi ->> 'nama_file' = 'excel_sambung.csv'`), "terkirim");
});

test("S1 + P7: pengingat lewat penyambung: rahasia salah 401, benar 200 dengan ringkasan JSON", async () => {
  const salah = await kirim({ tanggal: "2026-04-21" }, { "x-pengingat-rahasia": "salah" });
  assert.equal(salah.respon.status, 401);
  const r = await kirim({ tanggal: "2026-04-21" }, { "x-pengingat-rahasia": RAHASIA_PENGINGAT });
  assert.equal(r.respon.status, 200);
  const j = await r.respon.json();
  assert.equal(j.hari_ke, 1);
  assert.equal(j.tutup_buku, "2026-04-20");
  assert.ok(r.pesan.some((p) => p.chat_id === HRD && /^PENGINGAT \(hari ke-1 sesudah tutup buku 20-04-2026\)/.test(p.text)));
});

// ---------------------------------------------------------------------------
// Paket 5d: halaman unggah lewat penyambung (multipart sungguhan, aturan alamat asal)
// ---------------------------------------------------------------------------

let KODE = "";
const dariHalaman = { origin: ASAL_WEB, "content-type": "text/plain" };

test("W1 lewat penyambung: /unggah membalas tautan ke alamat halaman", async () => {
  const r = await kirim({ update_id: 7101, message: { message_id: 3, chat: { id: HRD }, from: { id: HRD }, text: "/unggah" } },
                        dariTelegram);
  KODE = /#kode=([0-9a-f]{64})$/.exec(r.pesan[0].text)?.[1] ?? "";
  assert.ok(r.pesan[0].text.includes(`${ASAL_WEB}/unggah/#kode=`));
  assert.equal(KODE.length, 64);
});

test("W10: permintaan dari alamat lain atau tanpa alamat asal ditolak 403", async () => {
  assert.equal((await kirim({ kode: KODE }, { origin: "https://jahat.contoh", "content-type": "text/plain" }, "periksa")).respon.status, 403);
  assert.equal((await kirim({ kode: KODE }, { "content-type": "text/plain" }, "periksa")).respon.status, 403);
});

test("CORS: pemeriksaan awal (OPTIONS) dari alamat halaman diizinkan", async () => {
  const r = await kirim(null, { origin: ASAL_WEB }, "status", "OPTIONS");
  assert.equal(r.respon.status, 204);
  assert.equal(r.respon.headers.get("access-control-allow-origin"), ASAL_WEB);
});

test("periksa tautan lewat penyambung: sah dengan daftar mesin; kode palsu 401", async () => {
  const r = await kirim({ kode: KODE }, dariHalaman, "periksa");
  assert.equal(r.respon.status, 200);
  assert.equal(r.respon.headers.get("access-control-allow-origin"), ASAL_WEB);
  assert.deepEqual((await r.respon.json()).mesin, ["MA1", "MA2"]);
  assert.equal((await kirim({ kode: "1".repeat(64) }, dariHalaman, "periksa")).respon.status, 401);
});

test("W8 lewat penyambung: unggah multipart file rusak Excel -> ditolak, asal web, pemberitahuan segera", async () => {
  const f = new FormData();
  f.append("kode", KODE);
  f.append("mesin", "MA2");
  f.append("file", new File([FILE_EXCEL], "excel_web_sambung.csv", { type: "text/csv" }));
  const r = await kirim(f, { origin: ASAL_WEB }, "unggah");
  assert.equal(r.respon.status, 200);
  const j = await r.respon.json();
  assert.equal(j.hasil, "ditolak");
  assert.match(j.alasan, /Excel/);
  assert.equal(nilai("select asal from fakta.kiriman_file where nama_file = 'excel_web_sambung.csv'"), "web");
  for (const tg of [HRD, PEMBANGUN]) {
    assert.ok(r.pesan.some((p) => p.chat_id === tg && /^PEMBERITAHUAN SEGERA[\s\S]*excel_web_sambung\.csv/.test(p.text)), String(tg));
  }
  // status kiriman dari halaman
  const s = await kirim({ kode: KODE, kiriman_id: j.kiriman_id }, dariHalaman, "status");
  assert.equal(s.respon.status, 200);
  assert.equal((await s.respon.json()).kiriman.hasil, "ditolak");
});

test("unggah tanpa file -> 400; kode palsu -> 401", async () => {
  const f = new FormData();
  f.append("kode", KODE);
  f.append("mesin", "MA1");
  assert.equal((await kirim(f, { origin: ASAL_WEB }, "unggah")).respon.status, 400);
  const g = new FormData();
  g.append("kode", "2".repeat(64));
  g.append("mesin", "MA1");
  g.append("file", new File([FILE_EXCEL], "x.csv"));
  assert.equal((await kirim(g, { origin: ASAL_WEB }, "unggah")).respon.status, 401);
});

// ---------------------------------------------------------------------------
// Paket 5d-2: bot tidak diam bila database menolak masuk (temuan 5c dan 5d)
// ---------------------------------------------------------------------------

// Database tiruan di depan postgres.js sungguhan: menolak masuk `gagal` kali dulu (kode 28P01 seperti pooler Supabase).
function sqlRewel(gagal: number, kode = "28P01"): Sql & { percobaan: number } {
  const x = {
    percobaan: 0,
    async unsafe(kueri: string, parameter?: unknown[]) {
      x.percobaan++;
      if (gagal-- > 0) {
        throw Object.assign(new Error('password authentication failed for user "pintu"'), { code: kode });
      }
      return sql.unsafe(kueri, parameter);
    },
  };
  return x;
}

async function kirimDengan(s: Sql, badan: unknown) {
  const a = buatAlat(s, "TOKEN-UJI", urai, fetchPalsu, `${ASAL_WEB}/unggah/`, [0, 0]);
  const awal = panggilan.length;
  const { respon, latar } = await layani(
    new Request("http://lokal/pintu-telegram", { method: "POST", headers: dariTelegram, body: JSON.stringify(badan) }),
    a, RAHASIA, RAHASIA_PENGINGAT, ASAL_WEB,
  );
  if (latar) await latar;
  return { respon, pesan: panggilan.slice(awal).filter((p) => p.metode === "sendMessage").map((p) => p.isi) };
}
const teks = (u: number) => ({ update_id: u, message: { message_id: u, chat: { id: HRD }, from: { id: HRD }, text: "halo" } });

test("5d-2: masuk ditolak sekali lalu berhasil -> pesan diproses biasa, satu balasan", async () => {
  const s = sqlRewel(1);
  const r = await kirimDengan(s, teks(7201));
  assert.equal(r.respon.status, 200);
  assert.equal(r.pesan.length, 1);
  assert.match(r.pesan[0].text, /Kirim file ekspor/);
  assert.equal(s.percobaan, 2);
  assert.equal(nilai("select count(*) from fakta.pesan_telegram where update_id = 7201"), "1");
});

test("5d-2: database menolak terus -> 503, pengirim diberi tahu, tidak ada yang tercatat; kiriman ulang Telegram diproses sekali", async () => {
  const s = sqlRewel(99);
  const r = await kirimDengan(s, teks(7202));
  assert.equal(r.respon.status, 503);
  assert.deepEqual(r.pesan.map((p) => p.text), [PESAN_GANGGUAN]);
  assert.equal(s.percobaan, 3);
  assert.equal(nilai("select count(*) from fakta.pesan_telegram where update_id = 7202"), "0");
  // Telegram mengirim ulang pesan yang sama sesudah database pulih
  const ulang = await kirimDengan(sql, teks(7202));
  assert.equal(ulang.respon.status, 200);
  assert.match(ulang.pesan[0].text, /Kirim file ekspor/);
  const lagi = await kirimDengan(sql, teks(7202));
  assert.equal(lagi.respon.status, 200);
  assert.deepEqual(lagi.pesan, []);
  assert.equal(nilai("select count(*) from fakta.pesan_telegram where update_id = 7202"), "1");
});

test("5d-2: tombol saat database menolak terus -> pesan gangguan ke chat tombol, 503", async () => {
  const r = await kirimDengan(sqlRewel(99), { update_id: 7203, callback_query: { id: "cb7203", data: "m|1|MA1",
    from: { id: HRD }, message: { chat: { id: HRD } } } });
  assert.equal(r.respon.status, 503);
  assert.equal(r.pesan[0].chat_id, HRD);
});

test("5d-2: teks galat pooler dikenali walau kodenya lain", async () => {
  const r = await kirimDengan(sqlRewel(1, "XX000"), teks(7206));
  assert.equal(r.respon.status, 200);
  assert.match(r.pesan[0].text, /Kirim file ekspor/);
});

test("5d-2: galat lain (bukan sambungan) tetap 200 tanpa pesan gangguan", async () => {
  const s = { async unsafe() { throw Object.assign(new Error("function does not exist"), { code: "42883" }); } };
  const r = await kirimDengan(s, teks(7204));
  assert.equal(r.respon.status, 200);
  assert.ok(!r.pesan.some((p) => p.text === PESAN_GANGGUAN));
});

test("5d-2: kode rahasia salah tetap 401 tanpa menyentuh database", async () => {
  const s = sqlRewel(99);
  const a = buatAlat(s, "TOKEN-UJI", urai, fetchPalsu, "", [0, 0]);
  const { respon } = await layani(new Request("http://lokal/x", { method: "POST",
    headers: { "x-telegram-bot-api-secret-token": "salah" }, body: JSON.stringify(teks(7205)) }), a, RAHASIA, RAHASIA_PENGINGAT);
  assert.equal(respon.status, 401);
  assert.equal(s.percobaan, 0);
});
