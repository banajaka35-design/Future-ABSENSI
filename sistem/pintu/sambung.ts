// Penyambung Edge Function pintu-telegram (paket 5b; dipisah dari index.ts di paket 5c supaya bisa diuji di Node
// dengan postgres.js sungguhan, sistem/pintu/uji_sambung.ts). Tidak memakai API khusus Deno.
// index.ts hanya membuat sambungan database, membaca rahasia, dan memanggil `layani`.
import { apiBoleh, tanganiPengingat, tanganiPermintaan, type Alat, type HasilUraiRingkas } from "./inti.ts";

// Bagian postgres.js yang dipakai.
export interface Sql {
  unsafe(kueri: string, parameter?: unknown[]): Promise<any[]>;
}

export function buatAlat(
  sql: Sql,
  token: string,
  urai: (teks: string, pilihan: { tanggal_kirim?: string }) => HasilUraiRingkas,
  ambil: typeof fetch = fetch,
): Alat {
  return {
    async api(nama, isi) {
      if (!apiBoleh(nama)) throw new Error(`fungsi ${nama} tidak boleh dipanggil`);
      const baris = isi === undefined
        ? await sql.unsafe(`select api.${nama}() as h`)
        // $1 sebagai teks lalu diubah ke jsonb oleh database. Dengan `$1::jsonb` saja, postgres.js mengubah teks JSON
        // menjadi JSON sekali lagi (string di dalam jsonb), sehingga semua isian terbaca kosong (ditemukan uji nyata 17 Nov).
        : await sql.unsafe(`select api.${nama}($1::text::jsonb) as h`, [JSON.stringify(isi)]);
      return baris[0].h;
    },
    async telegram(metode, isi) {
      const r = await ambil(`https://api.telegram.org/bot${token}/${metode}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(isi),
      });
      const j = await r.json();
      if (!j.ok) throw new Error(`Telegram ${metode}: ${j.description ?? r.status}`);
      return j.result;
    },
    async unduh(jalur) {
      const r = await ambil(`https://api.telegram.org/file/bot${token}/${jalur}`);
      if (!r.ok) throw new Error(`unduh file gagal: ${r.status}`);
      return new Uint8Array(await r.arrayBuffer());
    },
    urai,
    sekarang: () => Date.now(),
    tidur: (ms) => new Promise((s) => setTimeout(s, ms)),
  };
}

// Satu permintaan HTTP. Kepala `x-pengingat-rahasia` -> pengingat kirim file (dari pg_cron atau pemicu manual);
// selain itu pesan dari Telegram. Kerja berat dikembalikan sebagai `latar` untuk EdgeRuntime.waitUntil.
export async function layani(
  req: Request,
  alat: Alat,
  rahasiaTelegram: string,
  rahasiaPengingat: string,
): Promise<{ respon: Response; latar: Promise<void> | null }> {
  try {
    const kodePengingat = req.headers.get("x-pengingat-rahasia");
    if (kodePengingat !== null) {
      const { status, hasil } = await tanganiPengingat(req.method, kodePengingat, await req.text(), rahasiaPengingat, alat);
      return {
        respon: new Response(status === 200 ? JSON.stringify(hasil) : "ditolak", {
          status,
          headers: { "content-type": status === 200 ? "application/json" : "text/plain" },
        }),
        latar: null,
      };
    }
    const { status, latar } = await tanganiPermintaan(
      req.method,
      req.headers.get("x-telegram-bot-api-secret-token"),
      await req.text(),
      rahasiaTelegram,
      alat,
    );
    return { respon: new Response(status === 200 ? "ok" : "ditolak", { status }), latar };
  } catch (e) {
    // Tetap 200 supaya Telegram tidak mengirim ulang terus; nomor pesan sudah tercatat.
    console.error(e);
    return { respon: new Response("ok", { status: 200 }), latar: null };
  }
}
