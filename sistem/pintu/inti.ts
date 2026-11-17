// Inti pintu Telegram (paket 5b, docs/pintu-telegram.md).
// Tidak memakai API khusus Node atau Deno (hanya fetch, crypto.subtle, TextDecoder, Intl), dan semua akses keluar
// lewat `alat`, supaya modul yang sama diuji di Node (sistem/pintu/uji_pintu.ts) dan dipakai di Edge Function.
// Database hanya disentuh lewat fungsi skema api (peran `pintu`); pembaca file adalah sistem/urai (diberikan lewat alat).

export interface HasilUraiRingkas {
  hasil: "diterima" | "ditolak";
  alasan: string | null;
  tap: { id_mesin: string; jam_lokal: string; status: string | null; baris: number }[];
  baris_ditolak: { baris: number; alasan: string }[];
  tanggal_awal: string | null;
  tanggal_akhir: string | null;
}

export interface Alat {
  api(nama: string, isi?: unknown): Promise<any>;
  telegram(metode: string, isi: Record<string, unknown>): Promise<any>;
  unduh(jalurFile: string): Promise<Uint8Array>;
  urai(teks: string, pilihan: { tanggal_kirim?: string }): HasilUraiRingkas;
  sekarang(): number; // milidetik
  tidur(ms: number): Promise<void>;
}

export const BATAS_UKURAN = 20 * 1024 * 1024; // batas unduh file lewat bot Telegram
export const BATAS_KERJA_MS = 110_000; // Edge Function gratis hidup paling lama 150 detik

const API_BOLEH = new Set(["pintu_pesan", "pintu_tunda", "pintu_ambil_tunda", "pintu_terima_file", "pintu_kerjakan"]);
export function apiBoleh(nama: string): boolean {
  return API_BOLEH.has(nama);
}

const rp = (n: number) => "Rp" + Number(n).toLocaleString("id-ID");
const angka = (n: number) => Number(n).toLocaleString("id-ID");

function tanggalWib(detikUnix: number): string {
  return new Date((detikUnix + 7 * 3600) * 1000).toISOString().slice(0, 10);
}

async function sidikSha256(isi: Uint8Array): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", isi));
  return Array.from(h, (b) => b.toString(16).padStart(2, "0")).join("");
}

function kirim(alat: Alat, chat: number, teks: string, tambahan: Record<string, unknown> = {}) {
  return alat.telegram("sendMessage", { chat_id: chat, text: teks, ...tambahan });
}

// Pintu HTTP: kode rahasia Telegram diperiksa sebelum apa pun (kasus T8).
export async function tanganiPermintaan(
  metode: string,
  rahasiaMasuk: string | null,
  badan: string,
  rahasia: string,
  alat: Alat,
): Promise<{ status: number; latar: Promise<void> | null }> {
  if (metode !== "POST") return { status: 405, latar: null };
  if (!rahasia || rahasiaMasuk !== rahasia) return { status: 401, latar: null };
  let update: any;
  try {
    update = JSON.parse(badan);
  } catch {
    return { status: 400, latar: null };
  }
  return { status: 200, latar: await tanganiUpdate(update, alat) };
}

// Bagian cepat (sebelum balasan HTTP): kenali pesan, balas, dan kembalikan kerja berat sebagai janji (promise).
export async function tanganiUpdate(update: any, alat: Alat): Promise<Promise<void> | null> {
  const updateId = Number(update?.update_id);
  if (!Number.isFinite(updateId)) return null;

  const pesan = update.message;
  const tombol = update.callback_query;
  if (pesan?.document) {
    const chat = pesan.chat.id;
    const tg = pesan.from?.id;
    const info = await alat.api("pintu_pesan", { update_id: updateId, telegram_id: tg, jenis: "dokumen" });
    if (!info.baru) return null; // Telegram mengirim ulang (A10)
    if (!info.hrd) {
      await kirim(alat, chat, "Akun Anda belum terdaftar untuk mengirim file. File tidak disimpan.");
      return null;
    }
    const dok = pesan.document;
    const nama = String(dok.file_name ?? "file");
    if (Number(dok.file_size ?? 0) > BATAS_UKURAN) {
      await kirim(alat, chat, `File ${nama} lebih dari 20 MB; bot Telegram tidak bisa mengunduhnya.`);
      return null;
    }
    const daftar: string[] = info.mesin ?? [];
    const kata = String(pesan.caption ?? "").toUpperCase().split(/[^0-9A-Z]+/);
    let mesin = daftar.find((m) => kata.includes(m.toUpperCase())) ?? null;
    if (!mesin && daftar.length === 1) mesin = daftar[0];
    if (!mesin) {
      await alat.api("pintu_tunda", { update_id: updateId, telegram_id: tg, file_id: dok.file_id, nama_file: nama });
      await kirim(alat, chat, `File ${nama} dari mesin mana?`, {
        reply_markup: { inline_keyboard: [daftar.map((m) => ({ text: m, callback_data: `m|${updateId}|${m}` }))] },
      });
      return null;
    }
    await kirim(alat, chat, `File ${nama} diterima (mesin ${mesin}), sedang diproses.`);
    return proses(alat, chat, tg, updateId, dok.file_id, nama, mesin, tanggalWib(pesan.date));
  }

  if (tombol) {
    const chat = tombol.message?.chat?.id;
    const tg = tombol.from?.id;
    const info = await alat.api("pintu_pesan", { update_id: updateId, telegram_id: tg, jenis: "tombol" });
    await alat.telegram("answerCallbackQuery", { callback_query_id: tombol.id });
    if (!info.baru) return null;
    const [jenis, asal, mesin] = String(tombol.data ?? "").split("|");
    if (jenis !== "m" || !asal || !mesin) return null;
    if (!info.hrd) {
      await kirim(alat, chat, "Akun Anda belum terdaftar untuk mengirim file.");
      return null;
    }
    const tunda = await alat.api("pintu_ambil_tunda", { update_id: Number(asal), telegram_id: tg });
    if (!tunda) {
      await kirim(alat, chat, "Pilihan ini sudah diproses sebelumnya.");
      return null;
    }
    await kirim(alat, chat, `File ${tunda.nama_file} diterima (mesin ${mesin}), sedang diproses.`);
    const tanggal = tanggalWib(Math.floor(alat.sekarang() / 1000));
    return proses(alat, chat, tg, Number(tunda.update_id), tunda.file_id, tunda.nama_file, mesin, tanggal);
  }

  if (pesan?.text !== undefined) {
    const info = await alat.api("pintu_pesan", { update_id: updateId, telegram_id: pesan.from?.id, jenis: "teks" });
    if (!info.baru) return null;
    await kirim(
      alat,
      pesan.chat.id,
      info.hrd
        ? "Kirim file ekspor dari aplikasi mesin finger sebagai dokumen. Tulis kode mesin di keterangan bila perlu."
        : "Akun Anda belum terdaftar untuk mengirim file.",
    );
  }
  return null;
}

// Bagian berat (sesudah balasan HTTP): unduh, urai, simpan, kerjakan antrean, kirim ringkasan.
async function proses(
  alat: Alat,
  chat: number,
  tg: number,
  updateId: number,
  fileId: string,
  nama: string,
  mesin: string,
  tanggalKirim: string,
): Promise<void> {
  const mulai = alat.sekarang();
  try {
    const f = await alat.telegram("getFile", { file_id: fileId });
    const isi = await alat.unduh(f.file_path);
    const sidik = await sidikSha256(isi);
    const teks = new TextDecoder("utf-8").decode(isi);
    const h = alat.urai(teks, { tanggal_kirim: tanggalKirim });
    const r = await alat.api("pintu_terima_file", {
      update_id: updateId,
      telegram_id: tg,
      nama_file: nama,
      sidik,
      mesin,
      tap: h.tap.map((t) => [t.id_mesin, t.jam_lokal, t.status, t.baris]),
      alasan: h.alasan,
    });
    if (r.hasil !== "diterima") {
      await kirim(alat, chat, `File ${nama} ditolak: ${r.alasan}`);
      return;
    }
    const dibuang = h.baris_ditolak.length ? `, ${angka(h.baris_ditolak.length)} baris dibuang` : "";
    await kirim(
      alat,
      chat,
      `File ${nama} tersimpan: ${angka(r.jumlah_tap)} tap, ${r.tanggal_awal} s.d. ${r.tanggal_akhir}${dibuang}. Menghitung ulang...`,
    );
    await kerjakanAntrean(alat, chat, mulai);
  } catch (e) {
    await kirim(alat, chat, `File ${nama} gagal diproses: ${(e as Error).message}`);
    throw e;
  }
}

export async function kerjakanAntrean(alat: Alat, chat: number, mulai: number): Promise<void> {
  while (alat.sekarang() - mulai < BATAS_KERJA_MS) {
    const r = await alat.api("pintu_kerjakan");
    if (r.kosong) return;
    if (r.sibuk) {
      await kirim(alat, chat, "Hitungan lain sedang berjalan; periode ini akan dihitung sesudahnya.");
      return;
    }
    const p = r.periode;
    if (r.hasil?.galat) {
      await kirim(alat, chat, `Periode ${p.awal} s.d. ${p.akhir} gagal dihitung: ${r.hasil.galat}`);
    } else {
      const x = r.hasil;
      await kirim(
        alat,
        chat,
        `Periode ${p.awal} s.d. ${p.akhir}: ${angka(x.orang)} orang, gaji bersih ${rp(x.bersih)}. ` +
          (x.bisa_diajukan ? "Bisa diajukan." : "Belum bisa diajukan.") +
          (x.segera > 0 ? ` ${angka(x.segera)} pemberitahuan penting perlu diperiksa.` : ""),
      );
    }
    if (r.sisa === 0) return;
  }
  await kirim(alat, chat, "Sebagian periode masih di antrean; dihitung saat pesan berikutnya masuk.");
}
