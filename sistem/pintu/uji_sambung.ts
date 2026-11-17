// Uji penyambung Edge Function (paket 5c, kasus S1 di docs/pemberitahuan-segera.md): sistem/pintu/sambung.ts
// dijalankan dengan postgres.js sungguhan (versi yang sama dengan index.ts) ke Postgres sementara sebagai peran `pintu`,
// dan Telegram tiruan lewat fetch palsu. Menangkap kesalahan jenis 616651f (isian jsonb terbaca kosong).
// Dijalankan oleh sistem/uji/uji_pintu.sh sesudah uji_pintu.ts (database berisi akun dan kiriman dari uji itu).
// Pemakaian: PINTU_URL=postgresql://pintu:...@localhost:5432/uji_pintu DB_URL=... node --test sistem/pintu/uji_sambung.ts
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import postgres from "postgres";
import { urai } from "../urai/urai.ts";
import { buatAlat, layani } from "./sambung.ts";

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

const alat = buatAlat(sql, "TOKEN-UJI", urai, fetchPalsu);

async function kirim(badan: unknown, kepala: Record<string, string>) {
  const awal = panggilan.length;
  const { respon, latar } = await layani(
    new Request("http://lokal/pintu-telegram", { method: "POST", headers: kepala, body: JSON.stringify(badan) }),
    alat, RAHASIA, RAHASIA_PENGINGAT,
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
