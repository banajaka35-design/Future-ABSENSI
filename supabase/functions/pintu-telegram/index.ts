// Edge Function pintu-telegram (paket 5b, docs/pintu-telegram.md). Hanya penyambung:
// logika ada di inti.ts (sistem/pintu/inti.ts) dan pembaca file di urai.ts (sistem/urai/urai.ts).
// Keduanya disalin ke folder ini oleh workflow pemasangan sebelum dipasang; salinan tidak masuk repo.
// Pustaka luar satu-satunya: postgres.js (versi dikunci), untuk sambungan langsung sebagai peran `pintu`.
import postgres from "npm:postgres@3.4.5";
import { urai } from "./urai.ts";
import { apiBoleh, tanganiPermintaan, type Alat } from "./inti.ts";

const TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const RAHASIA = Deno.env.get("TELEGRAM_RAHASIA") ?? "";
const sql = postgres(Deno.env.get("PINTU_DB_URL") ?? "", { prepare: false, max: 1, idle_timeout: 20 });

const alat: Alat = {
  async api(nama, isi) {
    if (!apiBoleh(nama)) throw new Error(`fungsi ${nama} tidak boleh dipanggil`);
    const baris = isi === undefined
      ? await sql.unsafe(`select api.${nama}() as h`)
      : await sql.unsafe(`select api.${nama}($1::jsonb) as h`, [JSON.stringify(isi)]);
    return baris[0].h;
  },
  async telegram(metode, isi) {
    const r = await fetch(`https://api.telegram.org/bot${TOKEN}/${metode}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(isi),
    });
    const j = await r.json();
    if (!j.ok) throw new Error(`Telegram ${metode}: ${j.description ?? r.status}`);
    return j.result;
  },
  async unduh(jalur) {
    const r = await fetch(`https://api.telegram.org/file/bot${TOKEN}/${jalur}`);
    if (!r.ok) throw new Error(`unduh file gagal: ${r.status}`);
    return new Uint8Array(await r.arrayBuffer());
  },
  urai,
  sekarang: () => Date.now(),
  tidur: (ms) => new Promise((s) => setTimeout(s, ms)),
};

Deno.serve(async (req) => {
  try {
    const { status, latar } = await tanganiPermintaan(
      req.method,
      req.headers.get("x-telegram-bot-api-secret-token"),
      await req.text(),
      RAHASIA,
      alat,
    );
    // deno-lint-ignore no-explicit-any
    if (latar) (globalThis as any).EdgeRuntime.waitUntil(latar.catch((e) => console.error(e)));
    return new Response(status === 200 ? "ok" : "ditolak", { status });
  } catch (e) {
    // Tetap 200 supaya Telegram tidak mengirim ulang terus; nomor pesan sudah tercatat.
    console.error(e);
    return new Response("ok", { status: 200 });
  }
});
