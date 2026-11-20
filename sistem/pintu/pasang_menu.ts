// Paket 8b-3: menu perintah Telegram per peran, dipasang oleh db/pasang_pintu.sh sesudah alamat bot didaftarkan.
// Menu umum (chat pribadi) untuk semua orang; menu per akun (lingkup chat) untuk akun aktif HRD, bos, pembangun, karyawan.
// Masukan stdin: baris "telegram_id peran". Butuh TELEGRAM_BOT_TOKEN. Galat satu akun tidak menghentikan yang lain.
// Pemakaian: psql ... | TELEGRAM_BOT_TOKEN=... node sistem/pintu/pasang_menu.ts
import { readFileSync } from "node:fs";
import { MENU } from "./inti.ts";

const token = process.env.TELEGRAM_BOT_TOKEN;
if (!token) {
  console.error("GAGAL: TELEGRAM_BOT_TOKEN belum diisi.");
  process.exit(1);
}

async function pasang(commands: unknown, scope: unknown): Promise<string> {
  const r = await fetch(`https://api.telegram.org/bot${token}/setMyCommands`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ commands, scope }),
  });
  const j: any = await r.json().catch(() => ({}));
  return j.ok ? "ok" : `galat ${r.status}: ${String(j.description ?? "").slice(0, 120)}`;
}

console.log(`Menu umum: ${await pasang(MENU.umum, { type: "all_private_chats" })}`);
const hitung: Record<string, number> = {};
for (const baris of readFileSync(0, "utf8").split("\n")) {
  const [tg, peran] = baris.trim().split(/\s+/);
  if (!/^\d+$/.test(tg ?? "") || !MENU[peran ?? ""]) continue;
  const hasil = await pasang(MENU[peran], { type: "chat", chat_id: Number(tg) });
  hitung[`${peran} ${hasil}`] = (hitung[`${peran} ${hasil}`] ?? 0) + 1;
}
for (const [k, n] of Object.entries(hitung)) console.log(`Menu akun ${k}: ${n}`);
