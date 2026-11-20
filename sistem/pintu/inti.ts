// Inti pintu Telegram (paket 5b, docs/pintu-telegram.md; pemberitahuan segera dan pengingat paket 5c,
// docs/pemberitahuan-segera.md; unggah lewat web paket 5d, docs/unggah-web.md; kode email paket 5e, docs/login-email.md).
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
  alamatUnggah?: string; // alamat halaman unggah (paket 5d), misalnya https://.../unggah/
  email?(ke: string, judul: string, isi: string): Promise<void>; // pengirim email (paket 5e); tidak ada = belum disiapkan
  // Pemicu workflow "Isi Sheets" di GitHub (paket 6e); tidak ada = belum disiapkan (token kosong).
  picuSheets?(masukan: { pemicu: string; waktu_file: string }): Promise<{ ok: boolean; alasan?: string }>;
}

export const BATAS_UKURAN = 20 * 1024 * 1024; // batas unduh file lewat bot Telegram
export const BATAS_KERJA_MS = 110_000; // Edge Function gratis hidup paling lama 150 detik
export const BATAS_UKURAN_WEB = 50 * 1024 * 1024; // batas unggah lewat web (paket 5d)

const API_BOLEH = new Set([
  "pintu_pesan", "pintu_tunda", "pintu_ambil_tunda", "pintu_terima_file", "pintu_kerjakan",
  "pintu_pemberitahuan_ambil", "pintu_pengingat", "pintu_pemberitahuan_hasil",
  "pintu_buat_tautan", "pintu_periksa_tautan", "pintu_terima_web", "pintu_status_kiriman",
  "pintu_minta_kode_email", "pintu_tukar_kode_email", "pintu_kode_email_gagal", "pintu_catat_picu",
  "pintu_buat_kode", "pintu_daftar", "pintu_daftar_jawab", "pintu_akun",
  "pintu_atur_pin", "pintu_daftar_periode", "pintu_ajukan", "pintu_setujui", "pintu_rilis",
  "pintu_batal", "pintu_daftar_pin", "pintu_hapus_pin", "pintu_undang", "pintu_gabung", "pintu_minta_pin", "pintu_ambil_pin",
  "pintu_pengingat_rilis",
  "pintu_kirim_gaji_ambil", "pintu_kirim_gaji_hasil", "pintu_gaji_saya", "pintu_contoh_gaji",
]);
export function apiBoleh(nama: string): boolean {
  return API_BOLEH.has(nama);
}

const rp = (n: number) => "Rp" + Number(n).toLocaleString("id-ID");
const angka = (n: number) => Number(n).toLocaleString("id-ID");

// Paket G1-3 (T1, F15b/F15c): kalimat hasil hitung satu periode, dipakai bot dan halaman unggah. Angka dari database
// sudah tanpa orang rahasia (hitung.ringkasan_terlihat); baris lama tanpa angka ditulis apa adanya.
export function teksHasil(x: any): string {
  if (x?.dilewati) {
    return `sudah ${x.dilewati}; tidak dihitung ulang. Tap baru tetap tersimpan.`;
  }
  const batal = x?.pengajuan_batal ? " Pengajuan rilis periode ini batal karena angkanya dihitung ulang; ajukan lagi." : "";
  return teksHasilDasar(x) + batal;
}

function teksHasilDasar(x: any): string {
  const dasar = x?.angka_dihapus || x?.bersih === undefined || x?.bersih === null
    ? "angka gaji tidak ditampilkan"
    : `${angka(x.orang)} orang, gaji bersih ${rp(x.bersih)}` +
      (Number(x.rahasia) > 0 ? ` (tidak termasuk ${angka(x.rahasia)} orang rahasia)` : "");
  return dasar + "." + (x?.bisa_diajukan ? " Bisa diajukan." : " Belum bisa diajukan.") +
    (Number(x?.segera) > 0 ? ` ${angka(x.segera)} pemberitahuan penting perlu diperiksa.` : "");
}

// Paket G1-3 (C2): bot hanya melayani chat pribadi. Izin diperiksa dari pengirim, tetapi balasan (tautan unggah,
// angka gaji, pemberitahuan) dikirim ke chat asal; di grup semua anggota ikut membacanya.
export const PESAN_HANYA_PRIBADI = "Bot ini hanya melayani chat pribadi. Kirim file atau /unggah lewat chat pribadi dengan bot.";
function chatPribadi(chat: any, dari: any): boolean {
  return chat?.id !== undefined && chat?.id !== null && chat.id === dari?.id &&
    (chat.type === undefined || chat.type === "private");
}

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

// Kirim tanpa menghentikan pekerjaan bila Telegram gagal (unggah lewat web tetap jalan saat Telegram bermasalah).
async function kirimAman(alat: Alat, chat: number | null, teks: string) {
  if (chat === null) return;
  try {
    await kirim(alat, chat, teks);
  } catch {
    // diabaikan: hasil tetap tersimpan di database dan terbaca di halaman unggah
  }
}

async function sidikTeks(teks: string): Promise<string> {
  return sidikSha256(new TextEncoder().encode(teks));
}

function kodeAcak(): string {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
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
  if (pesan && !chatPribadi(pesan.chat, pesan.from)) {
    const info = await alat.api("pintu_pesan", { update_id: updateId, telegram_id: pesan.from?.id, jenis: "lain" });
    if (info.baru && pesan.chat?.id !== undefined) await kirim(alat, pesan.chat.id, PESAN_HANYA_PRIBADI);
    return null;
  }
  if (tombol && !chatPribadi(tombol.message?.chat, tombol.from)) {
    const info = await alat.api("pintu_pesan", { update_id: updateId, telegram_id: tombol.from?.id, jenis: "lain" });
    await alat.telegram("answerCallbackQuery", { callback_query_id: tombol.id });
    if (info.baru && tombol.message?.chat?.id !== undefined) await kirim(alat, tombol.message.chat.id, PESAN_HANYA_PRIBADI);
    return null;
  }

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
    const [, , , keempat] = String(tombol.data ?? "").split("|");
    if ((jenis === "a" || jenis === "s") && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "") && /^\d+$/.test(keempat ?? "")) {
      if (jenis === "a") await jawabAjukan(alat, chat, tg, Number(mesin), Number(keempat), asal === "y");
      else await putuskan(alat, chat, tg, Number(mesin), Number(keempat), asal === "y");
      return null;
    }
    if ((jenis === "r" || jenis === "p") && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      await mintaPin(alat, chat, tg, jenis === "r" ? "rilis" : asal === "y" ? "setujui" : "tolak", Number(mesin));
      return null;
    }
    if (jenis === "b" && asal === "y" && /^\d+$/.test(mesin ?? "")) {
      await batalAjukan(alat, chat, tg, info.hrd, mesin);
      return null;
    }
    if (jenis === "u" && (asal === "hrd" || asal === "bos")) {
      await undangAkun(alat, chat, tg, asal);
      return null;
    }
    if (jenis === "h" && asal === "y" && /^\d+$/.test(mesin ?? "")) {
      await hapusPin(alat, chat, tg, Number(mesin));
      return null;
    }
    if (jenis === "d" && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      const jawab = await jawabDaftar(alat, tg, Number(mesin), asal === "y");
      const baru = jawab.startsWith("Terdaftar:");
      await kirim(alat, chat, jawab, baru ? papanTombol("karyawan") : {});
      // Paket 8c: karyawan yang baru daftar langsung menerima rincian gaji periode terakhir yang sudah dirilis.
      if (baru) {
        await pasangMenu(alat, chat, "karyawan");
        await gajiSaya(alat, chat, tg, undefined, true);
      }
      return null;
    }
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
    // Paket 8b-4: jawaban atas pertanyaan bot (balasan pesan "Ketik ID karyawan ..." atau "Buat PIN ...").
    const ditanya = String(pesan.reply_to_message?.from?.is_bot ? pesan.reply_to_message?.text ?? "" : "");
    const jawab = String(pesan.text).trim();
    if (ditanya.startsWith(TANYA_PIN)) {
      await hapusPesan(alat, pesan.chat.id, pesan.message_id);
      const [a, b, lebih] = jawab.split(/\s+/);
      await kirim(alat, pesan.chat.id, lebih !== undefined
        ? "Format salah. Buat PIN: 6 angka. Ganti PIN: PIN lama, spasi, PIN baru."
        : await aturPin(alat, pesan.from?.id, info.hrd, a, b), await papanAkun(alat, pesan.from?.id));
      return null;
    }
    if (ditanya.startsWith(TANYA_ID)) {
      const [id, tambahan] = jawab.split(/\s+/);
      await kirim(alat, pesan.chat.id, await buatKodeDaftar(alat, pesan.from?.id, info.hrd, id, tambahan), await papanAkun(alat, pesan.from?.id));
      return null;
    }
    const teks = rapikanPerintah(teksTombol(jawab));
    if (teks === "/tombol_kode" || teks === "/tombol_pin") {
      if (!info.hrd) await kirim(alat, pesan.chat.id, BUKAN_HRD_RILIS);
      else await kirim(alat, pesan.chat.id, teks === "/tombol_kode"
        ? `${TANYA_ID}, misalnya 10001. Untuk ganti HP karyawan, ketik ID lalu kata ganti, misalnya 10001 ganti.`
        : `${TANYA_PIN}. Pesan berisi PIN dihapus otomatis.`,
        { reply_markup: { force_reply: true, input_field_placeholder: teks === "/tombol_kode" ? "ID karyawan" : "PIN" } });
      return null;
    }
    if (teks === "/tombol_undang") {
      await kirim(alat, pesan.chat.id, "Undang akun sebagai apa? (hanya akun pembangun)", { reply_markup: { inline_keyboard: [[
        { text: "HRD", callback_data: "u|hrd" }, { text: "Bos", callback_data: "u|bos" },
      ]] } });
      return null;
    }
    // Paket 8b-3: pesan 6 angka dianggap PIN untuk tombol/perintah yang sedang menunggu; pesannya selalu dihapus.
    if (/^\d{6}$/.test(teks)) {
      await hapusPesan(alat, pesan.chat.id, pesan.message_id);
      await pakaiPin(alat, pesan.chat.id, pesan.from?.id, info.hrd, teks);
      return null;
    }
    if (/^\/(?:bantuan|start)(?:@\w+)?\s*$/i.test(teks)) {
      await bantuan(alat, pesan.chat.id, pesan.from?.id);
      return null;
    }
    const kode = /^\/kode(?:@\w+)?(?:\s+(\S+))?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (kode) {
      await kirim(alat, pesan.chat.id, await buatKodeDaftar(alat, pesan.from?.id, info.hrd, kode[1], kode[2]));
      return null;
    }
    const pin = /^\/pin(?:@\w+)?(?:\s+(\S+))?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (pin) {
      if (pin[1]) await hapusPesan(alat, pesan.chat.id, pesan.message_id);
      await kirim(alat, pesan.chat.id, await aturPin(alat, pesan.from?.id, info.hrd, pin[1], pin[2]));
      return null;
    }
    if (/^\/ajukan(?:@\w+)?\s*$/i.test(teks)) {
      await daftarPeriode(alat, pesan.chat.id, pesan.from?.id, info.hrd, "ajukan");
      return null;
    }
    const rilis = /^\/rilis(?:@\w+)?(?:\s+(\S+))?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (rilis) {
      if (rilis[2]) await hapusPesan(alat, pesan.chat.id, pesan.message_id);
      if (!rilis[1]) await daftarPeriode(alat, pesan.chat.id, pesan.from?.id, info.hrd, "rilis");
      else if (!/^\d+$/.test(rilis[1])) {
        await kirim(alat, pesan.chat.id, "Cara pakai: /rilis untuk melihat periode; /rilis <nomor periode> lalu ketik PIN.");
      } else if (!rilis[2]) await mintaPin(alat, pesan.chat.id, pesan.from?.id, "rilis", Number(rilis[1]));
      else await rilisGaji(alat, pesan.chat.id, pesan.from?.id, info.hrd, rilis[1], rilis[2]);
      return null;
    }
    const putus = /^\/(setujui|tolak)(?:@\w+)?(?:\s+(\S+))?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (putus) {
      if (putus[3]) await hapusPesan(alat, pesan.chat.id, pesan.message_id);
      const setuju = putus[1].toLowerCase() === "setujui";
      if (!/^\d+$/.test(putus[2] ?? "")) {
        await kirim(alat, pesan.chat.id, "Cara pakai: /setujui <nomor periode> atau /tolak <nomor periode>, lalu ketik PIN. Nomor periode terlihat di /rilis.");
      } else if (!putus[3]) await mintaPin(alat, pesan.chat.id, pesan.from?.id, setuju ? "setujui" : "tolak", Number(putus[2]));
      else await putuskan(alat, pesan.chat.id, pesan.from?.id, Number(putus[2]), null, setuju, putus[3]);
      return null;
    }
    const gaji = /^\/gaji(?:@\w+)?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (gaji) {
      await gajiSaya(alat, pesan.chat.id, pesan.from?.id, gaji[1]);
      return null;
    }
    const contoh = /^\/contohgaji(?:@\w+)?(?:\s+(\S+))?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (contoh) {
      await contohGaji(alat, pesan.chat.id, pesan.from?.id, contoh[1], contoh[2]);
      return null;
    }
    const batal = /^\/batal(?:@\w+)?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (batal) {
      await batalAjukan(alat, pesan.chat.id, pesan.from?.id, info.hrd, batal[1]);
      return null;
    }
    if (/^\/hapuspin(?:@\w+)?\s*$/i.test(teks)) {
      await daftarHapusPin(alat, pesan.chat.id, pesan.from?.id);
      return null;
    }
    const undang = /^\/undang(?:@\w+)?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (undang) {
      await undangAkun(alat, pesan.chat.id, pesan.from?.id, undang[1]);
      return null;
    }
    const gab = /^\/gabung(?:@\w+)?(?:\s+(.*))?$/i.exec(teks);
    if (gab) {
      await gabung(alat, pesan.chat.id, pesan.from?.id, gab[1] ?? "");
      return null;
    }
    const daftar = /^\/daftar(?:@\w+)?(?:\s+(.*))?$/i.exec(teks);
    if (daftar) {
      const [isi, tambahan] = await mintaDaftar(alat, pesan.from?.id, daftar[1] ?? "");
      await kirim(alat, pesan.chat.id, isi, tambahan);
      return null;
    }
    if (/^\/unggah(@\w+)?\s*$/i.test(teks)) {
      await kirim(alat, pesan.chat.id, await buatTautan(alat, pesan.from?.id, info.hrd), {
        link_preview_options: { is_disabled: true },
      });
      return null;
    }
    if (info.hrd) {
      await kirim(alat, pesan.chat.id,
        "Kirim file ekspor dari aplikasi mesin finger sebagai dokumen. Tulis kode mesin di keterangan bila perlu.");
      return null;
    }
    const akun = await alat.api("pintu_akun", { telegram_id: pesan.from?.id });
    await kirim(alat, pesan.chat.id, akun.peran === "karyawan" && akun.nama
      ? `Akun ini terdaftar sebagai karyawan ${akun.nama}. Rincian gaji akan dikirim lewat chat ini setelah gaji dirilis.`
      : akun.peran
        ? "Akun Anda belum terdaftar untuk mengirim file."
        : "Akun Anda belum terdaftar. Karyawan: minta kode daftar ke HRD, lalu ketik /daftar KODE di chat ini.");
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
      await kirimPemberitahuan(alat, chat); // file rusak Excel atau format tidak dikenal: tingkat segera (U14)
      return;
    }
    const dibuang = h.baris_ditolak.length ? `, ${angka(h.baris_ditolak.length)} baris dibuang` : "";
    await kirim(
      alat,
      chat,
      `File ${nama} tersimpan: ${angka(r.jumlah_tap)} tap, ${r.tanggal_awal} s.d. ${r.tanggal_akhir}${dibuang}. Menghitung ulang...`,
    );
    await kerjakanAntrean(alat, chat, mulai, "telegram");
  } catch (e) {
    await kirim(alat, chat, `File ${nama} gagal diproses: ${(e as Error).message}`);
    throw e;
  }
}

export async function kerjakanAntrean(
  alat: Alat,
  chat: number | null,
  mulai: number,
  asal: "telegram" | "web" = "telegram",
): Promise<void> {
  const berhasil = await kerjakanSemua(alat, chat, mulai);
  if (berhasil > 0) await picuSheets(alat, chat, mulai, asal);
}

// Paket 6e: minta GitHub mengisi ulang Sheets, kabari pengirim, catat hasilnya (gagal -> pemberitahuan segera).
export async function picuSheets(alat: Alat, chat: number | null, mulai: number, asal: "telegram" | "web",
                                 karenaStatus = false): Promise<void> {
  // Paket 8b-5: status periode berubah (ajukan, setujui, tolak, rilis, batal) -> Sheets dan demo diisi ulang;
  // waktu_file kosong supaya kabar SELESAI tidak menulis "lama sejak file masuk".
  const waktuFile = karenaStatus ? "" : new Date(mulai).toISOString();
  let hasil: "terkirim" | "gagal" | "belum_disiapkan";
  let alasan: string | undefined;
  if (!alat.picuSheets) {
    hasil = "belum_disiapkan";
  } else {
    try {
      const r = await alat.picuSheets({
        pemicu: karenaStatus ? "status periode" : asal === "web" ? "file web" : "file Telegram", waktu_file: waktuFile,
      });
      hasil = r.ok ? "terkirim" : "gagal";
      alasan = r.ok ? undefined : (r.alasan ?? "tanpa alasan").slice(0, 200);
    } catch (e) {
      hasil = "gagal";
      alasan = String((e as Error).message ?? e).slice(0, 200);
    }
  }
  await kirimAman(
    alat,
    chat,
    hasil === "terkirim"
      ? "Sheets sedang diperbarui otomatis; bot akan mengabarkan bila sudah SELESAI (biasanya beberapa menit)."
      : hasil === "gagal"
      ? `Sheets BELUM diperbarui (${alasan}); angka di Sheets masih yang lama.`
      : "Sheets belum diperbarui otomatis (pemicu belum disiapkan); angka di Sheets masih yang lama.",
  );
  try {
    await alat.api("pintu_catat_picu", { asal, hasil, alasan: alasan ?? null, waktu_file: waktuFile || null });
    if (hasil !== "terkirim") await kirimPemberitahuan(alat, chat);
  } catch {
    // catatan gagal tidak menggagalkan hasil hitung yang sudah tersimpan
  }
}

// Kerjakan antrean sampai kosong, sibuk, atau batas waktu. Mengembalikan jumlah periode yang berhasil dihitung.
async function kerjakanSemua(alat: Alat, chat: number | null, mulai: number): Promise<number> {
  let berhasil = 0;
  while (alat.sekarang() - mulai < BATAS_KERJA_MS) {
    const r = await alat.api("pintu_kerjakan");
    if (r.kosong) return berhasil;
    if (r.sibuk) {
      await kirimAman(alat, chat, "Hitungan lain sedang berjalan; periode ini akan dihitung sesudahnya.");
      return berhasil;
    }
    const p = r.periode;
    if (r.hasil?.galat) {
      await kirimAman(alat, chat, `Periode ${p.awal} s.d. ${p.akhir} gagal dihitung: ${r.hasil.galat}`);
    } else {
      berhasil++;
      await kirimAman(alat, chat, `Periode ${p.awal} s.d. ${p.akhir}: ${teksHasil(r.hasil)}`);
    }
    await kirimPemberitahuan(alat, chat); // sesudah setiap periode, bukan menunggu seluruh antrean (U14)
    if (r.sisa === 0) return berhasil;
  }
  await kirimAman(alat, chat, "Sebagian periode masih di antrean; dihitung saat pesan berikutnya masuk.");
  return berhasil;
}

// ---------------------------------------------------------------------------
// Pemberitahuan tingkat segera (paket 5c, U14)
// ---------------------------------------------------------------------------

export const BATAS_PESAN = 3800; // Telegram menerima paling banyak 4096 karakter per pesan

// Judul dan langkah yang perlu dilakukan HRD, per jenis kejadian (PRD bagian 9).
export const JENIS_SEGERA: Record<string, { judul: string; langkah: string }> = {
  periode_dirilis_kena_file: {
    judul: "File baru menyentuh periode yang gajinya SUDAH DIRILIS (periode itu tidak dihitung ulang)",
    langkah: "Periksa apakah file ini memang untuk periode itu. Tap baru tersimpan tetapi gaji yang dirilis tidak berubah; koreksi masuk periode berikutnya.",
  },
  sheets_tidak_terpicu: {
    judul: "Sheets TIDAK diperbarui otomatis sesudah file masuk (angka di Sheets masih yang lama)",
    langkah: "Pembangun: jalankan workflow \"Isi Sheets\" lewat tombol di GitHub dan periksa secret GTHUB_PICU_TOKEN (token mungkin habis masa berlaku).",
  },
  file_rusak_excel: {
    judul: "File ditolak: pernah dibuka dan disimpan di Excel (No.ID rusak)",
    langkah: "Ekspor ulang dari aplikasi mesin, lalu kirim tanpa membukanya di Excel.",
  },
  format_tidak_dikenal: {
    judul: "File ditolak: format file tidak dikenal",
    langkah: "Periksa apakah aplikasi mesin berubah; kirim file ekspor asli dari mesin.",
  },
  file_terpotong: {
    judul: "File mesin kemungkinan terpotong",
    langkah: "Ekspor ulang file lengkap dari mesin. Karyawan yang hilang dari file tidak dijadikan alpha.",
  },
  tap_terakhir_lama: {
    judul: "Memori mesin penuh atau mesin mati?",
    langkah: "Periksa mesin, lalu kirim file terbaru.",
  },
  jam_mesin_melenceng: {
    judul: "Jam mesin kemungkinan melenceng",
    langkah: "Cocokkan jam mesin dengan jam sebenarnya.",
  },
  tanpa_tap_massal: {
    judul: "Hari tanpa tap massal (mungkin libur mendadak)",
    langkah: "Tetapkan libur, absen manual, atau alpha. Periode tertahan sampai ditetapkan.",
  },
  belum_terdaftar_mesin: {
    judul: "Karyawan baru belum terdaftar di mesin?",
    langkah: "Daftarkan sidik jarinya di mesin. Sampai dikoreksi, hari tanpa tap tetap alpha.",
  },
};

export interface Kejadian {
  id: number;
  jenis: string;
  isi: Record<string, any>;
}

function barisKejadian(k: Kejadian): string {
  if (k.jenis === "file_rusak_excel" || k.jenis === "format_tidak_dikenal") {
    return `File ${k.isi.nama_file} (mesin ${k.isi.mesin ?? "-"}, kiriman no. ${k.isi.kiriman_id})`;
  }
  if (k.jenis === "periode_dirilis_kena_file") {
    return `Periode ${k.isi.awal} s.d. ${k.isi.akhir}: file ${k.isi.nama_file ?? "-"} (kiriman no. ${k.isi.kiriman_id ?? "-"})`;
  }
  if (k.jenis === "sheets_tidak_terpicu") {
    return `${k.isi.waktu ?? "-"} WIB, file lewat ${k.isi.asal === "web" ? "web" : "Telegram"}: ` +
      (k.isi.hasil === "belum_disiapkan" ? "pemicu belum disiapkan" : `pemicu gagal (${k.isi.alasan ?? "tanpa alasan"})`);
  }
  return String(k.isi.keterangan ?? k.jenis);
}

// Satu atau beberapa pesan (bila panjang) berisi semua kejadian, dikelompokkan per jenis.
export function susunPesanSegera(kejadian: Kejadian[]): string[] {
  const kelompok = new Map<string, Kejadian[]>();
  for (const k of kejadian) kelompok.set(k.jenis, [...(kelompok.get(k.jenis) ?? []), k]);
  const blok: string[] = [];
  for (const [jenis, daftar] of kelompok) {
    const j = JENIS_SEGERA[jenis] ?? { judul: jenis, langkah: "Periksa kejadian ini." };
    blok.push(`${j.judul}\n${daftar.map((k) => `• ${barisKejadian(k)}`).join("\n")}\nLangkah: ${j.langkah}`);
  }
  const kepala = `PEMBERITAHUAN SEGERA (${angka(kejadian.length)} kejadian)`;
  const pesan: string[] = [];
  let kini = kepala;
  const batasBlok = BATAS_PESAN - kepala.length - 20; // ruang untuk kepala "lanjutan"
  for (const b of blok.flatMap((x) => (x.length > batasBlok ? pecah(x, batasBlok) : [x]))) {
    if (kini.length + 2 + b.length > BATAS_PESAN) {
      pesan.push(kini);
      kini = `${kepala}, lanjutan`;
    }
    kini += "\n\n" + b;
  }
  pesan.push(kini);
  return pesan;
}

function pecah(teks: string, batas: number): string[] {
  const hasil: string[] = [];
  let kini = "";
  for (const baris of teks.split("\n")) {
    if (kini && kini.length + 1 + baris.length > batas) {
      hasil.push(kini);
      kini = "";
    }
    kini = kini ? kini + "\n" + baris : baris.slice(0, batas);
  }
  if (kini) hasil.push(kini);
  return hasil;
}

// Kirim pesan yang sama ke setiap penerima; kembalikan hasil per penerima ("ok" atau "galat: ...").
async function kirimKeSemua(alat: Alat, penerima: number[], pesan: string[]): Promise<Record<string, string>> {
  const hasil: Record<string, string> = {};
  for (const tg of penerima) {
    try {
      for (const teks of pesan) await kirim(alat, tg, teks);
      hasil[String(tg)] = "ok";
    } catch (e) {
      hasil[String(tg)] = `galat: ${(e as Error).message}`.slice(0, 300);
    }
  }
  return hasil;
}

// Ambil kejadian segera yang baru (database mencatatnya lebih dulu), kirim ke semua penerima, catat hasilnya.
export async function kirimPemberitahuan(alat: Alat, chat: number | null): Promise<number> {
  try {
    const r = await alat.api("pintu_pemberitahuan_ambil");
    const kejadian: Kejadian[] = r?.kejadian ?? [];
    if (kejadian.length === 0) return 0;
    const hasil = await kirimKeSemua(alat, r.penerima ?? [], susunPesanSegera(kejadian));
    await alat.api("pintu_pemberitahuan_hasil", { id: kejadian.map((k) => k.id), hasil });
    return kejadian.length;
  } catch (e) {
    if (chat !== null) await kirim(alat, chat, `Pemberitahuan penting gagal dikirim: ${(e as Error).message}`);
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Pengingat kirim file (paket 5c, celah A13): dipanggil penjadwal pg_cron atau dipicu manual
// ---------------------------------------------------------------------------

const tglId = (iso: string) => iso.split("-").reverse().join("-");

export function susunPesanPengingat(r: any, kelompok: any): string {
  const mesin = (kelompok.mesin as string[]).join(", ");
  const kepala = kelompok.kepada === "bos"
    ? `PENGINGAT UNTUK BOS: dua hari sesudah tutup buku ${tglId(r.tutup_buku)}, file mesin ${mesin} belum masuk.`
    : `PENGINGAT (hari ke-${r.hari_ke} sesudah tutup buku ${tglId(r.tutup_buku)}): file mesin ${mesin} ` +
      `untuk periode ${tglId(r.periode_awal)} s.d. ${tglId(r.tutup_buku)} belum masuk.`;
  return kelompok.kepada === "bos"
    ? `${kepala} Gaji periode ini belum bisa dihitung lengkap.`
    : `${kepala} Kirim file ekspor dari mesin ke bot ini.` +
      (r.hari_ke === 2 ? " Bila belum masuk hari ini, bos juga diberi tahu." : "");
}

export async function tanganiPengingat(
  metode: string,
  rahasiaMasuk: string | null,
  badan: string,
  rahasia: string,
  alat: Alat,
): Promise<{ status: number; hasil: any }> {
  if (metode !== "POST") return { status: 405, hasil: null };
  if (!rahasia || rahasiaMasuk !== rahasia) return { status: 401, hasil: null };
  let isi: any = {};
  try {
    isi = badan.trim() ? JSON.parse(badan) : {};
  } catch {
    return { status: 400, hasil: null };
  }
  if (isi?.tugas === "kirim_gaji") return { status: 200, hasil: await kirimAntreanGaji(alat) };
  const tanggal = isi?.tanggal;
  if (tanggal !== undefined && tanggal !== null && !/^\d{4}-\d{2}-\d{2}$/.test(String(tanggal))) {
    return { status: 400, hasil: null };
  }
  const r = await alat.api("pintu_pengingat", tanggal ? { tanggal } : {});
  const terkirim: any[] = [];
  for (const k of r.kirim ?? []) {
    const hasil = await kirimKeSemua(alat, k.penerima ?? [], [susunPesanPengingat(r, k)]);
    await alat.api("pintu_pemberitahuan_hasil", { id: k.id, hasil });
    terkirim.push({ kepada: k.kepada, mesin: k.mesin, hasil });
  }
  const pengingatRilis = await kirimPengingatRilis(alat, tanggal ? String(tanggal) : undefined);
  return {
    status: 200,
    hasil: { tanggal: r.tanggal, tutup_buku: r.tutup_buku, hari_ke: r.hari_ke, terkirim, dilewati: r.dilewati ?? [],
             pengingat_rilis: pengingatRilis },
  };
}

// ---------------------------------------------------------------------------
// Unggah cadangan lewat web (paket 5d, docs/unggah-web.md)
// ---------------------------------------------------------------------------

// Perintah /unggah: kode acak, database menyimpan sidiknya saja, tautan berlaku 15 menit.
// ---------------------------------------------------------------------------
// Rilis gaji (paket 8b, docs/rencana-8b.md; PRD v2 celah K5): /pin, /ajukan, persetujuan bos, /rilis dengan PIN.
// Paket 8b-2: pembangun menyetujui/menolak dengan PIN. Paket 8b-3 (docs/rencana-8b-3.md): urutan rilis, tombol yang
// meminta PIN, /batal, /hapuspin, /undang, /gabung, menu perintah, kabar rilis, pengingat ke bos.
// ---------------------------------------------------------------------------

const BUKAN_HRD_RILIS = "Perintah ini hanya untuk HRD.";
const BUKAN_PEMBANGUN = "Perintah ini hanya untuk akun pembangun.";

// Menu perintah per peran (paket 8b-3). Dipasang saat Pasang (sistem/pintu/pasang_menu.ts) dan sesudah /gabung.
type Perintah = { command: string; description: string };
const P = (command: string, description: string): Perintah => ({ command, description });
const MENU_HRD = [
  P("unggah", "Tautan unggah file mesin lewat web"), P("kode", "Kode daftar karyawan: /kode <ID>"),
  P("ajukan", "Ajukan rilis gaji"), P("rilis", "Lihat dan rilis gaji yang siap"), P("batal", "Batalkan pengajuan: /batal <nomor>"),
  P("pin", "Buat atau ganti PIN"), P("contohgaji", "Contoh pesan gaji: /contohgaji <ID> <nomor>"), P("bantuan", "Daftar perintah"),
];
export const MENU: Record<string, Perintah[]> = {
  umum: [P("daftar", "Daftar karyawan dengan kode dari HRD"), P("gabung", "Gabung sebagai HRD/bos dengan kode undangan"),
         P("bantuan", "Daftar perintah")],
  karyawan: [P("gaji", "Rincian gaji terakhir (atau /gaji <nomor>)"), P("bantuan", "Daftar perintah")],
  hrd: MENU_HRD,
  bos: [P("bantuan", "Daftar perintah")],
  pembangun: [...MENU_HRD.slice(0, -1), P("setujui", "Setujui pengajuan: /setujui <nomor>"), P("tolak", "Tolak pengajuan: /tolak <nomor>"),
              P("undang", "Undang akun: /undang hrd atau /undang bos"), P("hapuspin", "Hapus PIN akun yang lupa PIN"),
              P("bantuan", "Daftar perintah")],
};

export async function pasangMenu(alat: Alat, chat: number, peran: string | null): Promise<void> {
  try {
    await alat.telegram("setMyCommands", { commands: MENU[peran ?? "umum"] ?? MENU.umum, scope: { type: "chat", chat_id: chat } });
  } catch {
    // menu hanya kemudahan; perintah tetap bisa diketik
  }
}

const BANTUAN: Record<string, string> = {
  hrd: "Perintah HRD:\n/unggah tautan unggah file\n/kode <ID> kode daftar karyawan\n/ajukan ajukan rilis gaji\n" +
    "/rilis lihat gaji yang siap dirilis (tombol Rilis lalu ketik PIN)\n/batal <nomor> batalkan pengajuan\n/pin buat atau ganti PIN\n" +
    "/contohgaji <ID> <nomor> contoh pesan rincian gaji untuk karyawan\n" +
    "Kirim file mesin sebagai dokumen untuk menghitung gaji.",
  bos: "Pengajuan rilis gaji dikirim ke chat ini dengan tombol Setujui dan Tolak. Bila belum dijawab, bot mengingatkan setiap pagi.",
  pembangun: "",
  karyawan: "Rincian gaji dikirim lewat chat ini setelah gaji dirilis.\nTombol Gaji saya (atau /gaji) mengirim ulang " +
    "rincian gaji terakhir; /gaji <nomor> untuk periode tertentu.",
  umum: "Karyawan: minta kode daftar ke HRD, lalu ketik /daftar KODE.\nHRD atau bos: minta kode undangan ke pembangun, lalu ketik /gabung KODE.",
};
BANTUAN.pembangun = BANTUAN.hrd + "\n\nKhusus pembangun:\n/setujui <nomor> dan /tolak <nomor> (lalu ketik PIN)\n" +
  "/undang hrd atau /undang bos kode undangan akun\n/hapuspin hapus PIN akun yang lupa PIN";

// Perintah yang diketik tanpa garis miring tetap dikenali (paket 8b-3, temuan 6).
const KATA_PERINTAH = new Set(["pin", "ajukan", "rilis", "setujui", "tolak", "batal", "hapuspin", "undang", "gabung", "daftar",
  "kode", "unggah", "bantuan", "gaji", "contohgaji"]);
export function rapikanPerintah(teks: string): string {
  const m = /^([a-z]+)(?:\s|$)/i.exec(teks);
  return m && KATA_PERINTAH.has(m[1].toLowerCase()) ? "/" + teks : teks;
}

// Paket 8b-4: tombol tetap di bawah kolom ketik, per peran. Teks tombol diterjemahkan ke perintah.
export const TOMBOL_TETAP: Record<string, string[][]> = {
  hrd: [["Kirim file", "Ajukan", "Rilis"], ["Kode karyawan", "PIN", "Bantuan"]],
  pembangun: [["Kirim file", "Ajukan", "Rilis"], ["Kode karyawan", "PIN", "Undang"], ["Hapus PIN", "Bantuan"]],
  bos: [["Bantuan"]],
  karyawan: [["Gaji saya", "Bantuan"]],
};
export function papanTombol(peran: string | null): Record<string, unknown> {
  const baris = TOMBOL_TETAP[peran ?? ""];
  return baris
    ? { reply_markup: { keyboard: baris.map((b) => b.map((text) => ({ text }))), resize_keyboard: true, is_persistent: true } }
    : { reply_markup: { remove_keyboard: true } };
}
// Paket 8b-5: sesudah pertanyaan force reply dijawab, tombol tetap dikirim lagi supaya muncul kembali.
async function papanAkun(alat: Alat, tg: number): Promise<Record<string, unknown>> {
  return papanTombol((await alat.api("pintu_akun", { telegram_id: tg }))?.peran ?? null);
}
const TEKS_TOMBOL: Record<string, string> = {
  "kirim file": "/unggah", "ajukan": "/ajukan", "rilis": "/rilis", "bantuan": "/bantuan", "hapus pin": "/hapuspin",
  "kode karyawan": "/tombol_kode", "pin": "/tombol_pin", "undang": "/tombol_undang",
  "gaji saya": "/gaji", "menu": "/bantuan",
};
export function teksTombol(teks: string): string {
  return TEKS_TOMBOL[teks.trim().toLowerCase()] ?? teks;
}
// Pertanyaan bot yang dijawab dengan membalas pesannya (force reply); awal teks dipakai untuk mengenali jawabannya.
export const TANYA_ID = "Ketik ID karyawan yang dibuatkan kode daftar";
export const TANYA_PIN = "Buat PIN: ketik 6 angka. Ganti PIN: ketik PIN lama, spasi, PIN baru";

const tombolRilis = (periode: number) => ({ reply_markup: { inline_keyboard: [[{ text: "Rilis (PIN)", callback_data: `r|y|${periode}` }]] } });
// Paket 8b-4: baris tombol "Batalkan pengajuan" ditambahkan di bawah tombol lain.
function denganBatal(tambahan: any, periode: number): Record<string, unknown> {
  const baris = [...(tambahan?.reply_markup?.inline_keyboard ?? []), [{ text: "Batalkan pengajuan", callback_data: `b|y|${periode}` }]];
  return { reply_markup: { inline_keyboard: baris } };
}
const tombolPembangun = (periode: number) => ({ reply_markup: { inline_keyboard: [[
  { text: "Setujui (PIN)", callback_data: `p|y|${periode}` }, { text: "Tolak (PIN)", callback_data: `p|n|${periode}` },
]] } });
const tombolBos = (periode: number, pengajuan: number) => ({ reply_markup: { inline_keyboard: [[
  { text: "Setujui", callback_data: `s|y|${periode}|${pengajuan}` }, { text: "Tolak", callback_data: `s|n|${periode}|${pengajuan}` },
]] } });

// Pesan yang memuat PIN dihapus dari chat (bot boleh menghapus pesan masuk di chat pribadi).
async function hapusPesan(alat: Alat, chat: number, messageId: number | undefined): Promise<void> {
  if (messageId === undefined) return;
  try {
    await alat.telegram("deleteMessage", { chat_id: chat, message_id: messageId });
  } catch {
    await kirimAman(alat, chat, "Pesan berisi PIN tidak bisa dihapus otomatis; hapus pesan itu sendiri.");
  }
}

// Ringkasan periode untuk HRD dan bos (K5): tanpa orang rahasia, dengan transfer dan tunai.
export function teksRingkasan(x: any): string {
  const rahasia = Number(x.rahasia) > 0 ? ` (tidak termasuk ${angka(x.rahasia)} orang rahasia)` : "";
  return `Periode no. ${x.periode_id}: ${x.awal} s.d. ${x.akhir}, dibayar ${x.bayar}.\n` +
    `${angka(x.orang ?? 0)} orang, gaji bersih ${rp(x.bersih ?? 0)}${rahasia}.\n` +
    `Transfer ${rp(x.transfer ?? 0)}, tunai ${rp(x.tunai ?? 0)}.`;
}

async function aturPin(alat: Alat, tg: number, hrd: boolean, a?: string, b?: string): Promise<string> {
  if (!hrd) return BUKAN_HRD_RILIS;
  if (!a) return "Cara pakai: /pin <PIN baru 6 angka>. Ganti PIN: /pin <PIN lama> <PIN baru>. Pesan berisi PIN dihapus otomatis.";
  const r = await alat.api("pintu_atur_pin", b ? { telegram_id: tg, pin_lama: a, pin_baru: b } : { telegram_id: tg, pin_baru: a });
  switch (r.hasil) {
    case "dibuat": return "PIN dibuat. Simpan baik-baik; PIN dipakai untuk merilis gaji.";
    case "diganti": return "PIN diganti.";
    case "lemah": return "PIN harus 6 angka dan tidak boleh angka sama semua atau berurutan (misalnya 111111 atau 123456).";
    case "perlu_pin_lama": return "PIN sudah ada. Untuk mengganti: /pin <PIN lama> <PIN baru>. Lupa PIN: minta akun pembangun menghapusnya (/hapuspin).";
    case "salah": return "PIN lama salah.";
    case "terkunci": return "Terlalu banyak PIN salah. Coba lagi 1 jam lagi.";
    default: return BUKAN_HRD_RILIS;
  }
}

// Paket 8b-5: status periode berubah -> Isi Sheets dipicu (Sheets dan halaman demo menampilkan status rilis).
// Kabar "Sheets sedang diperbarui" dikirim sesudah balasan utama (urutan pesan: hasil dulu, lalu kabar Sheets).
async function statusBerubah(alat: Alat, chat: number): Promise<void> {
  await picuSheets(alat, chat, alat.sekarang(), "telegram", true);
}

const tungguUrutan = (menunggu: number) => `rilis dulu periode no. ${menunggu}`;

async function daftarPeriode(alat: Alat, chat: number, tg: number, hrd: boolean, untuk: "ajukan" | "rilis"): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  const r = await alat.api("pintu_daftar_periode", { telegram_id: tg, untuk });
  const daftar: any[] = r.periode ?? [];
  const tertahan: any[] = r.tertahan_urutan ?? [];
  if (r.hasil !== "ada" || (daftar.length === 0 && tertahan.length === 0)) {
    await kirim(alat, chat, untuk === "ajukan"
      ? "Tidak ada periode yang bisa diajukan (periode harus sudah dihitung dan tidak ada orang yang PPh-nya tertahan)."
      : "Tidak ada periode yang sedang diajukan atau disetujui.");
    return;
  }
  for (const x of daftar) {
    if (untuk === "ajukan") {
      await kirim(alat, chat, `${teksRingkasan(x)}\nAjukan rilis gaji periode ini?`, {
        reply_markup: { inline_keyboard: [[
          { text: "Ajukan", callback_data: `a|y|${x.periode_id}|${x.versi_gaji}` },
          { text: "Batal", callback_data: `a|n|${x.periode_id}|${x.versi_gaji}` },
        ]] },
      });
    } else {
      const tunggu = r.perlu_bos && x.status !== "disetujui";
      if (tunggu) {
        await kirim(alat, chat, `${teksRingkasan(x)}\nStatus: ${x.status}. Menunggu persetujuan bos.` +
          (r.pembangun ? `\n${caraPembangun(x.periode_id)}` : ""),
          denganBatal(r.pembangun ? tombolPembangun(x.periode_id) : {}, x.periode_id));
      } else if (x.menunggu) {
        await kirim(alat, chat, `${teksRingkasan(x)}\nStatus: ${x.status}. Belum bisa dirilis: ${tungguUrutan(x.menunggu)}.`,
          denganBatal({}, x.periode_id));
      } else {
        await kirim(alat, chat, `${teksRingkasan(x)}\nStatus: ${x.status}. Tekan Rilis lalu ketik PIN, ` +
          `atau ketik: /rilis ${x.periode_id} <PIN> (pesan berisi PIN dihapus otomatis).`, denganBatal(tombolRilis(x.periode_id), x.periode_id));
      }
    }
  }
  if (tertahan.length) {
    await kirim(alat, chat, "Belum bisa diajukan karena gaji harus dirilis berurutan:\n" +
      tertahan.map((t) => `Periode no. ${t.periode_id} (${t.awal} s.d. ${t.akhir}): ${tungguUrutan(t.menunggu)}.`).join("\n"));
  }
}

async function jawabAjukan(alat: Alat, chat: number, tg: number, periode: number, versi: number, ya: boolean): Promise<void> {
  if (!ya) {
    await kirim(alat, chat, "Tidak jadi diajukan.");
    return;
  }
  const r = await alat.api("pintu_ajukan", { telegram_id: tg, periode_id: periode, versi_gaji: versi });
  try {
    switch (r.hasil) {
      case "diajukan": {
        if (!r.perlu_bos) {
          await kirim(alat, chat, `Diajukan.\n${teksRingkasan(r)}\nTekan Rilis lalu ketik PIN, atau ketik: /rilis ${r.periode_id} <PIN>.`,
            tombolRilis(r.periode_id));
          return;
        }
        const bos: number[] = r.bos ?? [];
        const pembangun: number[] = r.pembangun ?? [];
        const sayaPembangun = pembangun.includes(tg);
        await kirim(alat, chat, `Diajukan.\n${teksRingkasan(r)}\n` + (bos.length
          ? "Menunggu persetujuan bos."
          : pembangun.length
            ? "Belum ada akun bos yang terdaftar; akun pembangun bisa menyetujui."
            : "Belum ada akun bos yang terdaftar, jadi pengajuan ini belum bisa disetujui.") +
          (sayaPembangun ? `\n${caraPembangun(r.periode_id)}` : ""), sayaPembangun ? tombolPembangun(r.periode_id) : {});
        for (const b of bos) {
          await kirimAman2(alat, b, `Pengajuan rilis gaji:\n${teksRingkasan(r)}`, tombolBos(r.periode_id, r.pengajuan_id));
        }
        for (const b of pembangun) {
          if (b !== tg) {
            await kirimAman2(alat, b, `Pengajuan rilis gaji:\n${teksRingkasan(r)}\n${caraPembangun(r.periode_id)}`, tombolPembangun(r.periode_id));
          }
        }
        return;
      }
      case "versi_berubah":
        await kirim(alat, chat, "Angka periode ini sudah dihitung ulang sejak daftar ditampilkan. Ketik /ajukan lagi.");
        return;
      case "tunggu_periode":
        await kirim(alat, chat, `Periode ini belum bisa diajukan: ${tungguUrutan(r.menunggu)}. Gaji harus dirilis berurutan.`);
        return;
      case "tidak_bisa":
        await kirim(alat, chat, `Periode ini tidak bisa diajukan (status: ${r.status ?? "-"}).`);
        return;
      default:
        await kirim(alat, chat, BUKAN_HRD_RILIS);
    }
  } finally {
    if (r.hasil === "diajukan") await statusBerubah(alat, chat);
  }
}

async function kirimAman2(alat: Alat, chat: number, teks: string, tambahan: Record<string, unknown>): Promise<void> {
  try {
    await kirim(alat, chat, teks, tambahan);
  } catch {
    // akun yang tidak bisa dihubungi tidak menggagalkan pekerjaan
  }
}

export function caraPembangun(periode: number): string {
  return `Sebagai pembangun: tekan Setujui atau Tolak lalu ketik PIN, atau ketik /setujui ${periode} <PIN> atau ` +
    `/tolak ${periode} <PIN> (pesan berisi PIN dihapus otomatis).`;
}

// Persetujuan rilis: tombol bos (dengan nomor pengajuan, tanpa PIN) atau pembangun (tanpa nomor pengajuan, dengan PIN).
async function putuskan(alat: Alat, chat: number, tg: number, periode: number, pengajuan: number | null, setuju: boolean,
                        pin?: string): Promise<void> {
  const isi: Record<string, unknown> = { telegram_id: tg, periode_id: periode, setuju };
  if (pengajuan !== null) isi.pengajuan_id = pengajuan;
  if (pin !== undefined) isi.pin = pin;
  const r = await alat.api("pintu_setujui", isi);
  try {
    switch (r.hasil) {
      case "disetujui":
      case "ditolak": {
        const kata = r.hasil === "disetujui" ? "disetujui" : "ditolak (kembali ke dihitung)";
        const siapa = r.oleh === "pembangun" ? "Pembangun" : "Bos";
        const lanjut = r.hasil === "disetujui" ? `\nTekan Rilis lalu ketik PIN, atau ketik: /rilis ${r.periode_id} <PIN>.` : "";
        const tombol = r.hasil === "disetujui" ? tombolRilis(r.periode_id) : {};
        if (r.pengaju && r.pengaju !== tg) {
          await kirimAman2(alat, r.pengaju, `${siapa} ${r.hasil === "disetujui" ? "menyetujui" : "menolak"} pengajuan rilis:\n` +
            teksRingkasan(r) + lanjut, tombol);
          await kirim(alat, chat, `Pengajuan ${kata}.\n${teksRingkasan(r)}`);
          return;
        }
        await kirim(alat, chat, `Pengajuan ${kata}.\n${teksRingkasan(r)}` + (r.pengaju === tg ? lanjut : ""),
          r.pengaju === tg ? tombol : {});
        return;
      }
      case "tidak_berlaku":
        await kirim(alat, chat, "Pengajuan ini tidak berlaku lagi (sudah diputuskan, dihitung ulang, ada pengajuan baru, atau periode belum diajukan).");
        return;
      case "belum_ada_pin": await kirim(alat, chat, "Belum ada PIN. Buat dulu dengan /pin <PIN baru 6 angka>."); return;
      case "pin_salah": await kirim(alat, chat, "PIN salah."); return;
      case "terkunci": await kirim(alat, chat, "Terlalu banyak PIN salah. Coba lagi 1 jam lagi."); return;
      case "pakai_tombol": await kirim(alat, chat, "Akun bos menyetujui lewat tombol Setujui/Tolak di pesan pengajuan."); return;
      default: await kirim(alat, chat, "Persetujuan rilis hanya untuk akun bos atau pembangun.");
    }
  } finally {
    if (r.hasil === "disetujui" || r.hasil === "ditolak") await statusBerubah(alat, chat);
  }
}

async function rilisGaji(alat: Alat, chat: number, tg: number, hrd: boolean, nomor: string, pin: string): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  const r = await alat.api("pintu_rilis", { telegram_id: tg, periode_id: Number(nomor), pin });
  try {
    switch (r.hasil) {
      case "dirilis":
        await kirim(alat, chat, `Gaji DIRILIS.\n${teksRingkasan(r)}\nPeriode ini tidak dihitung ulang lagi.`);
        for (const t of (r.kabari ?? []) as number[]) {
          await kirimAman2(alat, t, `Gaji periode no. ${r.periode_id} DIRILIS.\n${teksRingkasan(r)}`, {});
        }
        return;
      case "belum_ada_pin": await kirim(alat, chat, "Belum ada PIN. Buat dulu dengan /pin <PIN baru 6 angka>."); return;
      case "pin_salah": await kirim(alat, chat, "PIN salah."); return;
      case "terkunci": await kirim(alat, chat, "Terlalu banyak PIN salah. Coba lagi 1 jam lagi."); return;
      case "belum_disetujui": await kirim(alat, chat, "Periode ini belum disetujui bos."); return;
      case "tunggu_periode": await kirim(alat, chat, `Periode ini belum bisa dirilis: ${tungguUrutan(r.menunggu)}.`); return;
      case "versi_berubah": await kirim(alat, chat, "Angka periode ini sudah dihitung ulang sejak diajukan. Ajukan lagi dengan /ajukan."); return;
      case "tidak_bisa": await kirim(alat, chat, `Periode ini tidak bisa dirilis (status: ${r.status ?? "tidak ada"}).`); return;
      default: await kirim(alat, chat, BUKAN_HRD_RILIS);
    }
  } finally {
    if (r.hasil === "dirilis") await statusBerubah(alat, chat);
  }
}

// Tombol Rilis / Setujui / Tolak dan perintah tanpa PIN: bot meminta PIN, berlaku 5 menit.
const KATA_AKSI: Record<string, string> = { rilis: "merilis gaji", setujui: "menyetujui pengajuan", tolak: "menolak pengajuan" };
async function mintaPin(alat: Alat, chat: number, tg: number, aksi: "rilis" | "setujui" | "tolak", periode: number): Promise<void> {
  const r = await alat.api("pintu_minta_pin", { telegram_id: tg, aksi, periode_id: periode });
  switch (r.hasil) {
    case "menunggu":
      // Paket 8b-5: tanpa force reply (6 angka dikenali dari catatan menunggu PIN), supaya tombol tetap tidak tertutup.
      await kirim(alat, chat, `Ketik PIN 6 angka untuk ${KATA_AKSI[aksi]} periode no. ${periode}. Berlaku 5 menit; pesan PIN dihapus otomatis.`);
      return;
    case "bukan_pembangun": await kirim(alat, chat, "Persetujuan dengan PIN hanya untuk akun pembangun; akun bos memakai tombol."); return;
    case "tidak_ada": await kirim(alat, chat, "Periode tidak ditemukan."); return;
    default: await kirim(alat, chat, BUKAN_HRD_RILIS);
  }
}

// Pesan 6 angka: PIN untuk tombol/perintah yang sedang menunggu. Pesannya selalu dihapus.
async function pakaiPin(alat: Alat, chat: number, tg: number, hrd: boolean, pin: string): Promise<void> {
  const t = await alat.api("pintu_ambil_pin", { telegram_id: tg });
  if (t?.aksi === "rilis") return rilisGaji(alat, chat, tg, hrd, String(t.periode_id), pin);
  if (t?.aksi === "setujui" || t?.aksi === "tolak") return putuskan(alat, chat, tg, Number(t.periode_id), null, t.aksi === "setujui", pin);
  await kirim(alat, chat, t?.lewat
    ? "Waktu memasukkan PIN sudah lewat (5 menit). Tekan tombolnya lagi."
    : "Pesan berisi 6 angka sudah dihapus. Tidak ada perintah yang sedang menunggu PIN. " +
      "Untuk membuat atau mengganti PIN, tekan tombol PIN lalu balas pertanyaannya.");
}

async function batalAjukan(alat: Alat, chat: number, tg: number, hrd: boolean, nomor?: string): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  if (!/^\d+$/.test(nomor ?? "")) {
    await kirim(alat, chat, "Cara pakai: /batal <nomor periode>. Nomor periode terlihat di /rilis.");
    return;
  }
  const r = await alat.api("pintu_batal", { telegram_id: tg, periode_id: Number(nomor) });
  try {
    if (r.hasil === "dibatalkan") {
      await kirim(alat, chat, `Pengajuan dibatalkan; periode kembali ke dihitung.\n${teksRingkasan(r)}`);
      for (const t of (r.kabari ?? []) as number[]) {
        await kirimAman2(alat, t, `Pengajuan rilis periode no. ${r.periode_id} dibatalkan oleh ${r.oleh === "pembangun" ? "pembangun" : "HRD"}.`, {});
      }
    } else if (r.hasil === "tidak_bisa") {
      await kirim(alat, chat, `Periode ini tidak sedang diajukan atau disetujui (status: ${r.status ?? "tidak ada"}).`);
    } else {
      await kirim(alat, chat, BUKAN_HRD_RILIS);
    }
  } finally {
    if (r.hasil === "dibatalkan") await statusBerubah(alat, chat);
  }
}

async function daftarHapusPin(alat: Alat, chat: number, tg: number): Promise<void> {
  const r = await alat.api("pintu_daftar_pin", { telegram_id: tg });
  if (r.hasil !== "ada") {
    await kirim(alat, chat, BUKAN_PEMBANGUN);
    return;
  }
  const punya = (r.akun as any[]).filter((a) => a.punya_pin);
  if (!punya.length) {
    await kirim(alat, chat, "Belum ada akun yang punya PIN.");
    return;
  }
  await kirim(alat, chat, "Pilih akun yang PIN-nya dihapus. Sesudah dihapus, pemilik akun membuat PIN baru dengan /pin.", {
    reply_markup: { inline_keyboard: punya.map((a) => [{
      text: `Hapus PIN: ${a.peran === "hrd" ? "HRD" : "pembangun"} ${a.label}${a.sendiri ? " (akun ini)" : ""}`,
      callback_data: `h|y|${a.id}`,
    }]) },
  });
}

async function hapusPin(alat: Alat, chat: number, tg: number, pengguna: number): Promise<void> {
  const r = await alat.api("pintu_hapus_pin", { telegram_id: tg, pengguna_id: pengguna });
  switch (r.hasil) {
    case "dihapus":
      await kirim(alat, chat, `PIN akun ${r.label} dihapus. Pemilik akun membuat PIN baru dengan /pin <PIN baru 6 angka>.`);
      if (r.telegram_id !== tg) {
        await kirimAman2(alat, r.telegram_id, "PIN Anda dihapus oleh pembangun. Buat PIN baru dengan /pin <PIN baru 6 angka>.", {});
      }
      return;
    case "belum_ada_pin": await kirim(alat, chat, "Akun ini sudah tidak punya PIN."); return;
    case "tidak_ada": await kirim(alat, chat, "Akun tidak ditemukan."); return;
    default: await kirim(alat, chat, BUKAN_PEMBANGUN);
  }
}

async function undangAkun(alat: Alat, chat: number, tg: number, peran?: string): Promise<void> {
  const p = String(peran ?? "").toLowerCase();
  if (p !== "hrd" && p !== "bos") {
    await kirim(alat, chat, "Cara pakai: /undang hrd atau /undang bos (hanya akun pembangun).");
    return;
  }
  const kode = kodeDaftarAcak();
  const r = await alat.api("pintu_undang", { telegram_id: tg, peran: p, sidik: await sidikTeks(kode) });
  if (r.hasil !== "dibuat") {
    await kirim(alat, chat, BUKAN_PEMBANGUN);
    return;
  }
  await kirim(alat, chat, `Kode undangan ${p === "hrd" ? "HRD" : "bos"}: ${kode}\n` +
    `Berlaku sampai ${jamWib(r.berlaku_sampai)} (60 menit), sekali pakai. Berikan langsung ke orangnya, jangan lewat grup. ` +
    `Ia mengetik /gabung ${kode} di chat pribadi dengan bot.`);
}

async function gabung(alat: Alat, chat: number, tg: number, ketik: string): Promise<void> {
  const kode = rapikanKodeDaftar(ketik);
  if (!kode) {
    await kirim(alat, chat, "Cara pakai: /gabung KODE (kode undangan dari pembangun).");
    return;
  }
  const r = await alat.api("pintu_gabung", { telegram_id: tg, sidik: await sidikTeks(kode) });
  const nama = (p: string) => (p === "hrd" ? "HRD" : p === "bos" ? "bos" : p);
  switch (r.hasil) {
    case "terdaftar":
      await pasangMenu(alat, chat, r.peran);
      await kirim(alat, chat, `Terdaftar sebagai ${nama(r.peran)}.\n${BANTUAN[r.peran] ?? ""}`, papanTombol(r.peran));
      if (r.pembangun) await kirimAman2(alat, r.pembangun, `Kode undangan ${nama(r.peran)} sudah dipakai; akun baru terdaftar.`, {});
      return;
    case "sudah_terdaftar":
      await kirim(alat, chat, `Akun Telegram ini sudah terdaftar sebagai ${nama(r.peran)}.`);
      return;
    case "terkunci":
      await kirim(alat, chat, "Terlalu banyak kode salah. Coba lagi 1 jam lagi.");
      return;
    default:
      await kirim(alat, chat, `Kode tidak berlaku (salah, sudah dipakai, atau lewat 60 menit). Minta kode baru ke pembangun. ` +
        `Sisa percobaan dalam 1 jam: ${angka(r.sisa ?? 0)}.`);
  }
}

async function bantuan(alat: Alat, chat: number, tg: number): Promise<void> {
  const akun = await alat.api("pintu_akun", { telegram_id: tg });
  await pasangMenu(alat, chat, akun.peran);
  await kirim(alat, chat, (BANTUAN[akun.peran ?? "umum"] ?? BANTUAN.umum) +
    (TOMBOL_TETAP[akun.peran ?? ""] ? "\nTombol di bawah kolom ketik bisa dipakai sebagai ganti perintah." : ""), papanTombol(akun.peran));
}

// Pengingat harian ke bos untuk pengajuan yang belum dijawab (dipanggil bersama pengingat kirim file).
async function kirimPengingatRilis(alat: Alat, tanggal?: string): Promise<number> {
  const r = await alat.api("pintu_pengingat_rilis", tanggal ? { tanggal } : {});
  let n = 0;
  for (const k of r.kirim ?? []) {
    const hasil: Record<string, string> = {};
    const teks = `PENGINGAT: pengajuan rilis gaji menunggu persetujuan sejak ${k.sejak}.\n${teksRingkasan(k)}`;
    for (const [daftar, tombol] of [[k.bos ?? [], tombolBos(k.periode_id, k.pengajuan_id)],
                                    [k.pembangun ?? [], tombolPembangun(k.periode_id)]] as [number[], any][]) {
      for (const t of daftar) {
        try {
          await kirim(alat, t, teks, tombol);
          hasil[String(t)] = "ok";
        } catch (e) {
          hasil[String(t)] = `galat: ${(e as Error).message}`.slice(0, 300);
        }
      }
    }
    await alat.api("pintu_pemberitahuan_hasil", { id: [k.id], hasil });
    n++;
  }
  return n;
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Pesan rincian gaji (paket 8c, docs/rencana-8c.md): antrean sesudah rilis, minta ulang, contoh untuk HRD/pembangun.
// ---------------------------------------------------------------------------

const LABEL_KOMPONEN: Record<string, string> = {
  gaji_pokok: "Gaji pokok", tunjangan_tetap: "Tunjangan tetap", uang_makan: "Uang makan", lembur: "Lembur",
  premi_hadir: "Premi hadir", tunjangan_shift_malam: "Tunjangan shift malam", thr: "THR",
  pengembalian_pph21: "Pengembalian PPh 21", potongan_tidak_dibayar: "Potongan hari tidak dibayar",
  pph21: "PPh 21", bpjs_jht_karyawan: "BPJS JHT", bpjs_jp_karyawan: "BPJS Pensiun", bpjs_kesehatan_karyawan: "BPJS Kesehatan",
  bpjs_jht_perusahaan: "BPJS JHT", bpjs_jkk_perusahaan: "BPJS Kecelakaan Kerja", bpjs_jkm_perusahaan: "BPJS Kematian",
  bpjs_jp_perusahaan: "BPJS Pensiun", bpjs_kesehatan_perusahaan: "BPJS Kesehatan",
};
const labelKomponen = (k: string) => LABEL_KOMPONEN[k] ?? (k.charAt(0).toUpperCase() + k.slice(1).replace(/_/g, " "));
export const rupiah = (n: number) => (Number(n) < 0 ? "-" : "") + "Rp" + Math.abs(Number(n)).toLocaleString("id-ID");

// Susun pesan gaji satu orang; dipecah bila lebih panjang dari BATAS_PESAN (dipecah di antara baris).
export function susunPesanGaji(x: any, judul = "RINCIAN GAJI"): string[] {
  const baris: string[] = [
    judul,
    `Periode no. ${x.periode_id}: ${x.awal} s.d. ${x.akhir}, dibayar ${x.bayar}.`,
    `${x.nama} (ID ${x.id})${x.divisi ? `, ${x.divisi}` : ""}.`,
  ];
  const kelompok = (k: string) => (x.komponen ?? []).filter((c: any) => c.kelompok === k);
  const tulis = (daftar: any[]) => {
    for (const c of daftar) {
      baris.push(`- ${labelKomponen(c.komponen)}: ${rupiah(c.nominal)}`);
      if (c.bukti) baris.push(`  (${String(c.bukti).slice(0, 600)})`);
    }
  };
  baris.push("", "Pendapatan:");
  tulis(kelompok("pendapatan"));
  baris.push(`Total pendapatan: ${rupiah(x.pendapatan)}`, "", "Potongan:");
  tulis(kelompok("potongan"));
  baris.push(`Total potongan: ${rupiah(x.potongan)}`, "", `GAJI BERSIH: ${rupiah(x.bersih)}`);
  // Paket 8c-2: sisa pembulatan periode lalu ikut ditulis supaya bersih + sisa lalu = dibayar + sisa baru bisa dicocokkan.
  if (Number(x.sisa_lalu ?? 0) !== 0) baris.push(`Sisa pembulatan periode lalu (ditambahkan): ${rupiah(x.sisa_lalu)}`);
  baris.push(`Dibayar ${x.cara_bayar === "tunai" ? "tunai" : "lewat transfer"}: ${rupiah(x.dibayar)}`);
  if (Number(x.sisa) !== 0) baris.push(`Sisa pembulatan ${rupiah(x.sisa)} dibawa ke periode berikutnya.`);
  const perusahaan = kelompok("perusahaan");
  if (perusahaan.length) {
    baris.push("", "Dibayar perusahaan untuk Anda (tidak memotong gaji):");
    for (const c of perusahaan) baris.push(`- ${labelKomponen(c.komponen)}: ${rupiah(c.nominal)}`);
  }
  baris.push("", "Ada yang tidak sesuai? Hubungi HRD.");
  const pesan: string[] = [];
  let kini = "";
  for (const b of baris) {
    if (kini && kini.length + 1 + b.length > BATAS_PESAN) {
      pesan.push(kini);
      kini = "";
    }
    kini = kini ? `${kini}\n${b}` : b;
  }
  if (kini) pesan.push(kini);
  return pesan.map((p, i) => (pesan.length > 1 ? `(${i + 1}/${pesan.length})\n${p}` : p));
}

async function kirimBagian(alat: Alat, chat: number, bagian: string[], tambahan: Record<string, unknown> = {}): Promise<void> {
  for (let i = 0; i < bagian.length; i++) await kirim(alat, chat, bagian[i], i === bagian.length - 1 ? tambahan : {});
}

async function gajiSaya(alat: Alat, chat: number, tg: number, nomor?: string, dariDaftar = false): Promise<void> {
  if (nomor !== undefined && !/^\d+$/.test(nomor)) {
    await kirim(alat, chat, "Cara pakai: /gaji untuk rincian gaji terakhir, atau /gaji <nomor periode>.");
    return;
  }
  const r = await alat.api("pintu_gaji_saya", nomor ? { telegram_id: tg, periode_id: Number(nomor) } : { telegram_id: tg });
  switch (r.hasil) {
    case "ada": {
      let ok = true;
      let galat: string | undefined;
      try {
        await kirimBagian(alat, chat, susunPesanGaji(r));
      } catch (e) {
        ok = false;
        galat = String((e as Error).message ?? e).slice(0, 300);
      }
      await alat.api("pintu_kirim_gaji_hasil", { hasil: [{ kirim_id: r.kirim_id, ok, galat, telegram_id: tg }] });
      return;
    }
    case "belum_ada":
      if (!dariDaftar) {
        await kirim(alat, chat, nomor ? "Belum ada rincian gaji yang dirilis untuk Anda di periode itu."
          : "Belum ada rincian gaji yang dirilis untuk Anda.");
      }
      return;
    case "terlalu_sering": await kirim(alat, chat, "Rincian gaji sudah diminta 5 kali dalam 1 jam. Coba lagi nanti."); return;
    default: if (!dariDaftar) await kirim(alat, chat, "Perintah ini untuk karyawan yang sudah terdaftar.");
  }
}

async function contohGaji(alat: Alat, chat: number, tg: number, id?: string, nomor?: string): Promise<void> {
  if (!id || !/^\d+$/.test(nomor ?? "")) {
    await kirim(alat, chat, "Cara pakai: /contohgaji <ID karyawan> <nomor periode>. Nomor periode terlihat di /rilis atau Sheets.");
    return;
  }
  const r = await alat.api("pintu_contoh_gaji", { telegram_id: tg, id_karyawan: id, periode_id: Number(nomor) });
  switch (r.hasil) {
    case "ada": await kirimBagian(alat, chat, susunPesanGaji(r, "CONTOH RINCIAN GAJI (pesan yang diterima karyawan)")); return;
    case "rahasia": await kirim(alat, chat, "Gaji orang ini rahasia; contohnya hanya untuk akun pembangun."); return;
    case "tidak_ada": await kirim(alat, chat, "Tidak ada rincian gaji untuk ID dan periode itu."); return;
    default: await kirim(alat, chat, BUKAN_HRD_RILIS);
  }
}

// Penjadwal (pg_cron tiap menit, hanya bila ada pekerjaan): kirim antrean pesan gaji, sekitar 20 pesan per detik,
// paling lama 20 detik per panggilan (sisanya di panggilan berikutnya). Ringkasan ke HRD/pembangun saat periode selesai.
export const BATAS_KIRIM_GAJI_MS = 20_000;
export async function kirimAntreanGaji(alat: Alat): Promise<{ terkirim: number; gagal: number; selesai: number[] }> {
  const mulai = alat.sekarang();
  let terkirim = 0;
  let gagal = 0;
  const selesai: number[] = [];
  const ringkas = async (daftar: any[]) => {
    for (const s of daftar ?? []) {
      selesai.push(s.periode_id);
      const teks = `Pesan gaji periode no. ${s.periode_id} selesai dikirim: ${angka(s.terkirim)} terkirim, ` +
        `${angka(s.tanpa_akun)} belum punya akun Telegram, ${angka(s.gagal)} gagal. ` +
        "Yang belum terkirim bisa meminta rinciannya sendiri lewat tombol Gaji saya sesudah daftar.";
      for (const t of (s.penerima ?? []) as number[]) await kirimAman2(alat, t, teks, {});
    }
  };
  while (alat.sekarang() - mulai < BATAS_KIRIM_GAJI_MS) {
    const r = await alat.api("pintu_kirim_gaji_ambil", { batas: 25 });
    await ringkas(r.selesai);
    if (!(r.kirim ?? []).length) break;
    const hasil: any[] = [];
    for (const k of r.kirim) {
      try {
        await kirimBagian(alat, k.telegram_id, susunPesanGaji(k), papanTombol("karyawan"));
        hasil.push({ kirim_id: k.kirim_id, ok: true });
        terkirim++;
      } catch (e) {
        hasil.push({ kirim_id: k.kirim_id, ok: false, galat: String((e as Error).message ?? e).slice(0, 300) });
        gagal++;
      }
      await alat.tidur(50);
    }
    const h = await alat.api("pintu_kirim_gaji_hasil", { hasil });
    await ringkas(h.selesai);
  }
  return { terkirim, gagal, selesai };
}

// Pendaftaran karyawan (paket 8a, docs/rencana-8a.md; PRD v2 celah K1, K8)
// ---------------------------------------------------------------------------

export const HURUF_KODE_DAFTAR = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // tanpa O, 0, I, 1, L
export const PANJANG_KODE_DAFTAR = 10;

export function kodeDaftarAcak(): string {
  const n = HURUF_KODE_DAFTAR.length;
  const batas = 256 - (256 % n); // penolakan supaya setiap huruf sama peluangnya
  let kode = "";
  while (kode.length < PANJANG_KODE_DAFTAR) {
    const b = new Uint8Array(16);
    crypto.getRandomValues(b);
    for (const x of b) if (x < batas && kode.length < PANJANG_KODE_DAFTAR) kode += HURUF_KODE_DAFTAR[x % n];
  }
  return kode;
}

// Kode yang diketik karyawan: huruf besar, tanpa spasi atau tanda hubung.
export const rapikanKodeDaftar = (t: string) => t.toUpperCase().replace(/[^0-9A-Z]/g, "");

const jamWib = (iso: string) =>
  new Date(new Date(iso).getTime() + 7 * 3600 * 1000).toISOString().slice(11, 16) + " WIB";

async function buatKodeDaftar(alat: Alat, tg: number, hrd: boolean, id?: string, tambahan?: string): Promise<string> {
  if (!hrd) return "Perintah /kode hanya untuk HRD.";
  const ganti = String(tambahan ?? "").toLowerCase() === "ganti";
  if (!id || !/^[0-9A-Za-z]+$/.test(id) || (tambahan !== undefined && !ganti)) {
    return "Cara pakai: /kode <ID karyawan>, misalnya /kode 10001. Untuk ganti HP karyawan: /kode 10001 ganti.";
  }
  const kode = kodeDaftarAcak();
  const r = await alat.api("pintu_buat_kode", { telegram_id: tg, id_karyawan: id, ganti, sidik: await sidikTeks(kode) });
  const siapa = r.nama ? `${r.id} ${r.nama} (${r.divisi ?? "divisi tidak tercatat"})` : id;
  switch (r.hasil) {
    case "dibuat":
      return `Kode daftar untuk ${siapa}: ${kode}\n` +
        `Berlaku sampai ${jamWib(r.berlaku_sampai)} (60 menit), sekali pakai. Berikan langsung ke karyawannya, jangan lewat grup. ` +
        `Karyawan mengetik /daftar ${kode} di chat pribadi dengan bot.` +
        (r.ganti ? " Akun lama orang ini dinonaktifkan setelah akun baru selesai mendaftar." : "");
    case "sudah_punya_akun":
      return `${siapa} sudah punya akun aktif. Untuk ganti HP, ketik /kode ${r.id} ganti.`;
    case "berhenti":
      return `${siapa} sudah berhenti bekerja; kode tidak dibuat.`;
    case "tidak_ada":
      return `ID ${id} tidak ditemukan.`;
    default:
      return "Perintah /kode hanya untuk HRD.";
  }
}

async function mintaDaftar(alat: Alat, tg: number, ketik: string): Promise<[string, Record<string, unknown>]> {
  const kode = rapikanKodeDaftar(ketik);
  if (!kode) return ["Cara pakai: /daftar KODE (kode 10 huruf/angka dari HRD).", {}];
  const r = await alat.api("pintu_daftar", { telegram_id: tg, sidik: await sidikTeks(kode) });
  switch (r.hasil) {
    case "konfirmasi":
      return [`Kode cocok untuk:\n${r.nama}, divisi ${r.divisi ?? "-"} (ID ${r.id}).\nApakah ini Anda?`, {
        reply_markup: { inline_keyboard: [[
          { text: "Ya, ini saya", callback_data: `d|y|${r.kode_id}` },
          { text: "Bukan", callback_data: `d|n|${r.kode_id}` },
        ]] },
      }];
    case "sudah_terdaftar":
      return ["Akun Telegram ini sudah terdaftar. Bila perlu diubah, hubungi HRD.", {}];
    case "terkunci":
      return [`Terlalu banyak kode salah. Coba lagi setelah ${jamWib(r.sampai)}.`, {}];
    default:
      return [`Kode tidak berlaku (salah, sudah dipakai, atau lewat 60 menit). Minta kode baru ke HRD. ` +
        `Sisa percobaan dalam 1 jam: ${angka(r.sisa ?? 0)}.`, {}];
  }
}

async function jawabDaftar(alat: Alat, tg: number, kodeId: number, ya: boolean): Promise<string> {
  const r = await alat.api("pintu_daftar_jawab", { telegram_id: tg, kode_id: kodeId, jawab: ya ? "ya" : "bukan" });
  switch (r.hasil) {
    case "terdaftar":
      return `Terdaftar: ${r.nama} (ID ${r.id}). Rincian gaji akan dikirim lewat chat ini setelah gaji dirilis.`;
    case "dibatalkan":
      return "Kode dibatalkan. Minta kode baru ke HRD.";
    case "sudah_terdaftar":
      return "Akun Telegram ini sudah terdaftar. Bila perlu diubah, hubungi HRD.";
    case "sudah_punya_akun":
      return "ID ini sudah punya akun aktif. Untuk ganti HP, minta HRD membuat kode ganti.";
    default:
      return "Pilihan ini tidak berlaku lagi. Minta kode baru ke HRD bila perlu.";
  }
}

async function buatTautan(alat: Alat, telegramId: number, hrd: boolean): Promise<string> {
  if (!hrd) return "Akun Anda belum terdaftar untuk mengirim file.";
  if (!alat.alamatUnggah) return "Unggah lewat web belum disiapkan.";
  const kode = kodeAcak();
  const r = await alat.api("pintu_buat_tautan", { telegram_id: telegramId, sidik: await sidikTeks(kode) });
  if (r.hasil !== "dibuat") return r.alasan ?? "Tautan tidak bisa dibuat.";
  return `Tautan unggah file mesin (berlaku 15 menit, boleh untuk beberapa file, jangan dibagikan):\n` +
    `${alat.alamatUnggah}#kode=${kode}`;
}

export interface JawabanWeb {
  status: number;
  isi: any;
  latar: Promise<void> | null;
}

const TAUTAN_TIDAK_BERLAKU = "Tautan tidak berlaku atau sudah habis. Ketik /unggah di bot untuk tautan baru.";

export async function webPeriksa(alat: Alat, kode: string): Promise<JawabanWeb> {
  if (!/^[0-9a-f]{64}$/.test(kode)) return { status: 401, isi: { sah: false, alasan: TAUTAN_TIDAK_BERLAKU }, latar: null };
  const r = await alat.api("pintu_periksa_tautan", { kode_sidik: await sidikTeks(kode) });
  return r.sah
    ? { status: 200, isi: r, latar: null }
    : { status: 401, isi: { sah: false, alasan: TAUTAN_TIDAK_BERLAKU }, latar: null };
}

export async function webUnggah(
  alat: Alat,
  kode: string,
  nama: string,
  isi: Uint8Array,
  mesin: string,
): Promise<JawabanWeb> {
  const mulai = alat.sekarang();
  if (!/^[0-9a-f]{64}$/.test(kode)) return { status: 401, isi: { hasil: "ditolak", alasan: TAUTAN_TIDAK_BERLAKU }, latar: null };
  if (!mesin) return { status: 400, isi: { hasil: "ditolak", alasan: "Pilih mesin asal file." }, latar: null };
  if (isi.length > BATAS_UKURAN_WEB) {
    return { status: 413, isi: { hasil: "ditolak", alasan: "File lebih dari 50 MB." }, latar: null };
  }
  const sidik = await sidikSha256(isi);
  const h = alat.urai(new TextDecoder("utf-8").decode(isi), { tanggal_kirim: tanggalWib(Math.floor(mulai / 1000)) });
  const r = await alat.api("pintu_terima_web", {
    kode_sidik: await sidikTeks(kode),
    nama_file: nama,
    sidik,
    mesin,
    tap: h.tap.map((t) => [t.id_mesin, t.jam_lokal, t.status, t.baris]),
    alasan: h.alasan,
  });
  if (r.tautan === false) return { status: 401, isi: { hasil: "ditolak", alasan: TAUTAN_TIDAK_BERLAKU }, latar: null };
  // Akun yang masuk lewat email bisa tanpa ID Telegram: hasil hanya terlihat di halaman.
  const chat: number | null = r.telegram_id === null || r.telegram_id === undefined ? null : Number(r.telegram_id);
  const jawab = {
    hasil: r.hasil,
    alasan: r.alasan ?? null,
    kiriman_id: r.kiriman_id ?? null,
    jumlah_tap: r.jumlah_tap ?? 0,
    tanggal_awal: r.tanggal_awal ?? null,
    tanggal_akhir: r.tanggal_akhir ?? null,
    baris_dibuang: h.baris_ditolak.length,
    periode: r.periode ?? [],
  };
  const latar = r.hasil === "diterima"
    ? (async () => {
      await kirimAman(alat, chat, `File ${nama} diunggah lewat web (mesin ${mesin}): ${angka(r.jumlah_tap)} tap, ` +
        `${r.tanggal_awal} s.d. ${r.tanggal_akhir}. Menghitung ulang...`);
      await kerjakanAntrean(alat, chat, mulai, "web");
    })()
    : kirimPemberitahuan(alat, null).then(() => {}); // file rusak Excel atau format: tingkat segera (U14)
  return { status: 200, isi: jawab, latar };
}

export async function webStatus(alat: Alat, kode: string, kirimanId: number): Promise<JawabanWeb> {
  if (!/^[0-9a-f]{64}$/.test(kode) || !Number.isFinite(kirimanId)) {
    return { status: 401, isi: { alasan: TAUTAN_TIDAK_BERLAKU }, latar: null };
  }
  const r = await alat.api("pintu_status_kiriman", { kode_sidik: await sidikTeks(kode), kiriman_id: kirimanId });
  if (r.tautan === false) return { status: 401, isi: { alasan: TAUTAN_TIDAK_BERLAKU }, latar: null };
  if (!r.kiriman) return { status: 404, isi: { alasan: "Kiriman tidak ditemukan." }, latar: null };
  for (const p of r.periode ?? []) if (p.hasil && !p.galat) p.ringkasan = teksHasil(p.hasil); // kalimat sama dengan bot
  return { status: 200, isi: r, latar: null };
}

// ---------------------------------------------------------------------------
// Masuk lewat kode email (paket 5e, docs/login-email.md)
// ---------------------------------------------------------------------------

export const PESAN_KODE_DIKIRIM =
  "Bila email ini terdaftar sebagai akun HRD, kode 6 angka sudah dikirim (berlaku 10 menit). Periksa juga folder spam.";

function kodeEnamAngka(): string {
  // Penolakan nilai di ujung supaya setiap angka 000000-999999 sama peluangnya.
  const b = new Uint32Array(1);
  do crypto.getRandomValues(b); while (b[0] >= 4_294_000_000);
  return String(b[0] % 1_000_000).padStart(6, "0");
}

const emailSah = (e: string) => /^[^@\s]+@[^@\s]+$/.test(e) && e.length <= 254;

export async function webMintaKode(alat: Alat, emailMasuk: string): Promise<JawabanWeb> {
  if (!alat.email) return { status: 503, isi: { alasan: "Masuk lewat email belum disiapkan." }, latar: null };
  const email = String(emailMasuk ?? "").trim().toLowerCase();
  if (!emailSah(email)) return { status: 400, isi: { alasan: "Tulis alamat email yang benar." }, latar: null };
  const kode = kodeEnamAngka();
  const r = await alat.api("pintu_minta_kode_email", { email, sidik: await sidikTeks(`${email}:${kode}`) });
  if (r.kirim) {
    try {
      await alat.email(email, `Kode masuk unggah file: ${kode}`,
        `Kode masuk halaman unggah file mesin: ${kode}\n\nBerlaku 10 menit. Jangan berikan kode ini kepada siapa pun.\n` +
          `Bila Anda tidak meminta kode ini, abaikan email ini.`);
    } catch (e) {
      console.error(e);
      // Paket 5e-2: kode yang tidak terkirim tidak menghabiskan jatah 3 kode per 15 menit dan tidak bisa dipakai.
      try {
        await alat.api("pintu_kode_email_gagal", { id: r.id, email });
      } catch (e2) {
        console.error(e2);
      }
      return { status: 502, isi: { alasan: "Pengiriman email sedang gangguan; coba lagi sebentar." }, latar: null };
    }
  }
  return { status: 200, isi: { pesan: PESAN_KODE_DIKIRIM }, latar: null };
}

export async function webTukarKode(alat: Alat, emailMasuk: string, kodeMasuk: string): Promise<JawabanWeb> {
  const email = String(emailMasuk ?? "").trim().toLowerCase();
  const kodeEmail = String(kodeMasuk ?? "").replace(/\s+/g, "");
  if (!emailSah(email) || !/^\d{6}$/.test(kodeEmail)) {
    return { status: 400, isi: { alasan: "Kode terdiri dari 6 angka." }, latar: null };
  }
  const kodeTautan = kodeAcak();
  const r = await alat.api("pintu_tukar_kode_email", {
    email,
    sidik_kode: await sidikTeks(`${email}:${kodeEmail}`),
    sidik_tautan: await sidikTeks(kodeTautan),
  });
  if (r.hasil === "masuk") return { status: 200, isi: { kode: kodeTautan, berlaku_sampai: r.berlaku_sampai }, latar: null };
  if (r.hasil === "salah") {
    return { status: 401, isi: { alasan: `Kode salah. Sisa ${r.sisa} kali percobaan.` }, latar: null };
  }
  return { status: 401, isi: { alasan: "Kode tidak berlaku (salah 5 kali, lewat 10 menit, atau sudah dipakai). Minta kode baru." }, latar: null };
}
