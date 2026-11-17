// Penyambung Edge Function pintu-telegram (paket 5b; dipisah dari index.ts di paket 5c supaya bisa diuji di Node
// dengan postgres.js sungguhan, sistem/pintu/uji_sambung.ts). Tidak memakai API khusus Deno.
// index.ts hanya membuat sambungan database, membaca rahasia, dan memanggil `layani`.
import {
  apiBoleh, BATAS_UKURAN_WEB, tanganiPengingat, tanganiPermintaan, webPeriksa, webStatus, webUnggah,
  type Alat, type HasilUraiRingkas, type JawabanWeb,
} from "./inti.ts";

// Bagian postgres.js yang dipakai.
export interface Sql {
  unsafe(kueri: string, parameter?: unknown[]): Promise<any[]>;
}

export function buatAlat(
  sql: Sql,
  token: string,
  urai: (teks: string, pilihan: { tanggal_kirim?: string }) => HasilUraiRingkas,
  ambil: typeof fetch = fetch,
  alamatUnggah = "",
): Alat {
  return {
    alamatUnggah,
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

// Satu permintaan HTTP:
//   ?jalur=periksa|unggah|status -> halaman unggah (paket 5d), hanya dari alamat halaman (`asalWeb`);
//   kepala `x-pengingat-rahasia` -> pengingat kirim file (dari pg_cron atau pemicu manual);
//   selain itu pesan dari Telegram. Kerja berat dikembalikan sebagai `latar` untuk EdgeRuntime.waitUntil.
export async function layani(
  req: Request,
  alat: Alat,
  rahasiaTelegram: string,
  rahasiaPengingat: string,
  asalWeb = "",
): Promise<{ respon: Response; latar: Promise<void> | null }> {
  const jalur = new URL(req.url).searchParams.get("jalur");
  if (jalur !== null) return layaniWeb(req, jalur, alat, asalWeb);
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

// Halaman unggah (paket 5d, docs/unggah-web.md). Hanya dari alamat halaman demo; kode tautan diperiksa database.
async function layaniWeb(
  req: Request,
  jalur: string,
  alat: Alat,
  asalWeb: string,
): Promise<{ respon: Response; latar: Promise<void> | null }> {
  const asal = req.headers.get("origin");
  const kepala: Record<string, string> = { "vary": "origin" };
  if (!asalWeb || asal !== asalWeb) {
    return { respon: new Response("ditolak", { status: 403, headers: kepala }), latar: null };
  }
  kepala["access-control-allow-origin"] = asalWeb;
  if (req.method === "OPTIONS") {
    kepala["access-control-allow-methods"] = "POST";
    kepala["access-control-allow-headers"] = "content-type";
    kepala["access-control-max-age"] = "600";
    return { respon: new Response(null, { status: 204, headers: kepala }), latar: null };
  }
  const json = (j: JawabanWeb) => ({
    respon: new Response(JSON.stringify(j.isi), { status: j.status, headers: { ...kepala, "content-type": "application/json" } }),
    latar: j.latar,
  });
  try {
    if (req.method !== "POST") return json({ status: 405, isi: { alasan: "Harus POST." }, latar: null });
    if (jalur === "unggah") {
      const panjang = Number(req.headers.get("content-length") ?? 0);
      if (panjang > BATAS_UKURAN_WEB + 1024 * 1024) {
        return json({ status: 413, isi: { hasil: "ditolak", alasan: "File lebih dari 50 MB." }, latar: null });
      }
      const form = await req.formData();
      const file = form.get("file");
      if (!file || typeof file === "string") {
        return json({ status: 400, isi: { hasil: "ditolak", alasan: "File belum dipilih." }, latar: null });
      }
      const isi = new Uint8Array(await file.arrayBuffer());
      return json(await webUnggah(alat, String(form.get("kode") ?? ""), file.name || "file", isi, String(form.get("mesin") ?? "")));
    }
    let badan: any = {};
    try {
      badan = JSON.parse(await req.text());
    } catch {
      return json({ status: 400, isi: { alasan: "Isi permintaan tidak terbaca." }, latar: null });
    }
    if (jalur === "periksa") return json(await webPeriksa(alat, String(badan.kode ?? "")));
    if (jalur === "status") return json(await webStatus(alat, String(badan.kode ?? ""), Number(badan.kiriman_id)));
    return json({ status: 404, isi: { alasan: "Jalur tidak dikenal." }, latar: null });
  } catch (e) {
    console.error(e);
    return json({ status: 500, isi: { hasil: "gagal", alasan: "Terjadi galat di server; coba lagi." }, latar: null });
  }
}
