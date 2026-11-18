// Edge Function pintu-telegram (paket 5b, docs/pintu-telegram.md; paket 5c, docs/pemberitahuan-segera.md;
// paket 5d, docs/unggah-web.md; paket 5e, docs/login-email.md).
// Hanya pembuka: penyambung ada di sambung.ts (sistem/pintu/sambung.ts, diuji di Node dengan postgres.js sungguhan),
// logika di inti.ts (sistem/pintu/inti.ts), pembaca file di urai.ts (sistem/urai/urai.ts).
// Ketiganya disalin ke folder ini oleh workflow pemasangan sebelum dipasang; salinan tidak masuk repo.
// Pustaka luar satu-satunya: postgres.js (versi dikunci), untuk sambungan langsung sebagai peran `pintu`.
import postgres from "npm:postgres@3.4.5";
import { urai } from "./urai.ts";
import { buatAlat, layani } from "./sambung.ts";

const sql = postgres(Deno.env.get("PINTU_DB_URL") ?? "", { prepare: false, max: 1, idle_timeout: 20 });
const ASAL_WEB = Deno.env.get("ASAL_WEB") ?? ""; // alamat halaman unggah (paket 5d), mis. https://future-absensi-demo.pages.dev
// Pengirim email kode masuk (paket 5e, docs/login-email.md). Kosong = jalur email menjawab "belum disiapkan".
const BREVO_KUNCI = Deno.env.get("BREVO_API_KEY") ?? "";
const EMAIL_PENGIRIM = Deno.env.get("EMAIL_PENGIRIM") ?? "";
const alat = buatAlat(sql, Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "", urai, fetch, ASAL_WEB ? `${ASAL_WEB}/unggah/` : "",
  undefined, BREVO_KUNCI && EMAIL_PENGIRIM ? { kunci: BREVO_KUNCI, pengirim: EMAIL_PENGIRIM } : null,
  // Pemicu Isi Sheets (paket 6e, docs/pintu-telegram.md). Kosong = "belum disiapkan".
  Deno.env.get("PICU_SHEETS_TOKEN") ? { token: Deno.env.get("PICU_SHEETS_TOKEN") ?? "", repo: "banajaka35-design/Future-ABSENSI" } : null);
const RAHASIA = Deno.env.get("TELEGRAM_RAHASIA") ?? "";
const RAHASIA_PENGINGAT = Deno.env.get("PENGINGAT_RAHASIA") ?? "";

Deno.serve(async (req) => {
  const { respon, latar } = await layani(req, alat, RAHASIA, RAHASIA_PENGINGAT, ASAL_WEB);
  // deno-lint-ignore no-explicit-any
  if (latar) (globalThis as any).EdgeRuntime.waitUntil(latar.catch((e) => console.error(e)));
  return respon;
});
