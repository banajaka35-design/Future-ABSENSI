// Penyambung Edge Function pintu-telegram (paket 5b; dipisah dari index.ts di paket 5c supaya bisa diuji di Node
// dengan postgres.js sungguhan, sistem/pintu/uji_sambung.ts). Tidak memakai API khusus Deno.
// index.ts hanya membuat sambungan database, membaca rahasia, dan memanggil `layani`.
import {
  apiBoleh, BATAS_UKURAN_WEB, tanganiPengingat, tanganiPermintaan, webMintaKode, webPeriksa, webStatus, webTukarKode,
  webUnggah,
  type Alat, type HasilUraiRingkas, type JawabanWeb,
} from "./inti.ts";

// Bagian postgres.js yang dipakai.
export interface Sql {
  unsafe(kueri: string, parameter?: unknown[]): Promise<any[]>;
}

// Galat sambungan ke database (masuk ditolak atau sambungan gagal): perintahnya belum sempat berjalan di database,
// jadi aman dicoba ulang. Paket 5d-2: sesudah "Pasang ke Supabase" mengganti kata sandi peran `pintu`, percobaan
// masuk pertama lewat pooler ditolak ("password authentication failed"), percobaan berikutnya berhasil.
const KODE_GANGGUAN = new Set([
  "28P01", "28000", "08000", "08001", "08003", "08004", "08006", "57P01", "57P03",
  "CONNECT_TIMEOUT", "CONNECTION_CLOSED", "CONNECTION_ENDED", "CONNECTION_DESTROYED", "ECONNREFUSED", "ECONNRESET",
]);
export function gangguanDatabase(e: unknown): boolean {
  const x = e as { code?: string; message?: string; gangguanDatabase?: boolean } | null;
  return !!x && (x.gangguanDatabase === true || (typeof x.code === "string" && KODE_GANGGUAN.has(x.code)) ||
    // Kode dari pooler belum dipastikan; teks galat yang tercatat di log Supabase (17 Nov 2026) ikut dikenali.
    /password authentication failed/i.test(String(x.message ?? "")));
}

export function buatAlat(
  sql: Sql,
  token: string,
  urai: (teks: string, pilihan: { tanggal_kirim?: string }) => HasilUraiRingkas,
  ambil: typeof fetch = fetch,
  alamatUnggah = "",
  jedaCobaUlang: number[] = [1000, 2000], // tiga percobaan: langsung, sesudah 1 detik, sesudah 2 detik lagi
  brevo: { kunci: string; pengirim: string } | null = null, // pengirim email (paket 5e); null = belum disiapkan
  github: { token: string; repo: string } | null = null, // pemicu Isi Sheets (paket 6e); null = belum disiapkan
): Alat {
  const jalankan = async (kueri: string, parameter?: unknown[]) => {
    for (let ke = 0; ; ke++) {
      try {
        return await sql.unsafe(kueri, parameter);
      } catch (e) {
        if (!gangguanDatabase(e)) throw e;
        if (ke >= jedaCobaUlang.length) {
          console.error(`database tidak bisa dihubungi sesudah ${ke + 1} percobaan`, e);
          throw Object.assign(new Error("database tidak bisa dihubungi"), { gangguanDatabase: true, sebab: e });
        }
        console.error(`percobaan ${ke + 1} ke database gagal (${(e as { code?: string }).code}); dicoba lagi`);
        await new Promise((s) => setTimeout(s, jedaCobaUlang[ke]));
      }
    }
  };
  // Brevo, dokumen resmi: POST https://api.brevo.com/v3/smtp/email, kepala api-key, isi sender/to/subject/textContent.
  const email = brevo && brevo.kunci && brevo.pengirim
    ? async (ke: string, judul: string, isi: string) => {
      const r = await ambil("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: { "api-key": brevo.kunci, "content-type": "application/json", "accept": "application/json" },
        body: JSON.stringify({
          sender: { name: "Future-ABSENSI", email: brevo.pengirim },
          to: [{ email: ke }],
          subject: judul,
          textContent: isi,
        }),
      });
      if (!r.ok) throw new Error(`Brevo ${r.status}: ${(await r.text()).slice(0, 300)}`);
    }
    : undefined;
  // GitHub, dokumen resmi "Create a workflow dispatch event": POST /repos/{repo}/actions/workflows/{file}/dispatches,
  // isi {ref, inputs}; berhasil = 204 (atau 200 bila GitHub mengembalikan rincian run). Satu kali coba ulang untuk
  // 5xx atau jaringan. Token tidak pernah ikut di pesan galat.
  const picuSheets = github && github.token && github.repo
    ? async (masukan: { pemicu: string; waktu_file: string }) => {
      let alasan = "";
      for (let ke = 0; ke < 2; ke++) {
        try {
          const r = await ambil(`https://api.github.com/repos/${github.repo}/actions/workflows/isi-sheets.yml/dispatches`, {
            method: "POST",
            headers: {
              "authorization": `Bearer ${github.token}`,
              "accept": "application/vnd.github+json",
              "x-github-api-version": "2022-11-28",
              "user-agent": "future-absensi-pintu",
              "content-type": "application/json",
            },
            body: JSON.stringify({ ref: "main", inputs: masukan }),
          });
          if (r.status === 204 || r.status === 200) return { ok: true };
          let pesan = "";
          try {
            pesan = String((await r.json())?.message ?? "");
          } catch {
            // isi bukan JSON
          }
          alasan = `GitHub ${r.status}${pesan ? ": " + pesan.slice(0, 120) : ""}`;
          if (r.status < 500) break;
        } catch (e) {
          alasan = `GitHub tidak bisa dihubungi: ${String((e as Error).message ?? e).slice(0, 120)}`;
        }
      }
      return { ok: false, alasan: alasan.split(github.token).join("[token]") };
    }
    : undefined;
  return {
    alamatUnggah,
    email,
    picuSheets,
    async api(nama, isi) {
      if (!apiBoleh(nama)) throw new Error(`fungsi ${nama} tidak boleh dipanggil`);
      const baris = isi === undefined
        ? await jalankan(`select api.${nama}() as h`)
        // $1 sebagai teks lalu diubah ke jsonb oleh database. Dengan `$1::jsonb` saja, postgres.js mengubah teks JSON
        // menjadi JSON sekali lagi (string di dalam jsonb), sehingga semua isian terbaca kosong (ditemukan uji nyata 17 Nov).
        : await jalankan(`select api.${nama}($1::text::jsonb) as h`, [JSON.stringify(isi)]);
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
  const badan = await req.text();
  try {
    const kodePengingat = req.headers.get("x-pengingat-rahasia");
    if (kodePengingat !== null) {
      const { status, hasil } = await tanganiPengingat(req.method, kodePengingat, badan, rahasiaPengingat, alat);
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
      badan,
      rahasiaTelegram,
      alat,
    );
    return { respon: new Response(status === 200 ? "ok" : "ditolak", { status }), latar };
  } catch (e) {
    console.error(e);
    if (gangguanDatabase(e)) {
      // Database tidak bisa dihubungi: pesan belum tercatat. Jawab 503 supaya Telegram mengirim ulang pesan ini nanti
      // (Telegram mengulang permintaan yang tidak dijawab 2xx, lalu menyerah sesudah beberapa kali); pencatatan nomor
      // pesan mencegah pesan yang sama diproses dua kali. Pengirim diberi tahu supaya tidak mengira bot mati.
      // Kode rahasia sudah lolos di tanganiPermintaan sebelum database disentuh, jadi badan ini memang dari Telegram.
      await balasGangguan(alat, badan);
      return { respon: new Response("gangguan database", { status: 503 }), latar: null };
    }
    // Galat lain tetap 200 supaya Telegram tidak mengirim ulang terus.
    return { respon: new Response("ok", { status: 200 }), latar: null };
  }
}

export const PESAN_GANGGUAN =
  "Sedang ada gangguan sambungan ke database. Pesan Anda akan diproses otomatis begitu pulih; tidak perlu kirim ulang.";

async function balasGangguan(alat: Alat, badan: string) {
  try {
    const u = JSON.parse(badan);
    const chat = u?.message?.chat?.id ?? u?.callback_query?.message?.chat?.id;
    if (chat === undefined || chat === null) return;
    await alat.telegram("sendMessage", { chat_id: chat, text: PESAN_GANGGUAN });
  } catch {
    // pesan gangguan gagal dikirim: tidak apa-apa, Telegram tetap mengirim ulang pesan aslinya
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
    if (jalur === "minta_kode") return json(await webMintaKode(alat, String(badan.email ?? "")));
    if (jalur === "tukar_kode") return json(await webTukarKode(alat, String(badan.email ?? ""), String(badan.kode ?? "")));
    if (jalur === "status") return json(await webStatus(alat, String(badan.kode ?? ""), Number(badan.kiriman_id)));
    return json({ status: 404, isi: { alasan: "Jalur tidak dikenal." }, latar: null });
  } catch (e) {
    console.error(e);
    return json({ status: 500, isi: { hasil: "gagal", alasan: "Terjadi galat di server; coba lagi." }, latar: null });
  }
}
