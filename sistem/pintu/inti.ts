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
  "pintu_pengingat_rilis", "pintu_cabut_daftar", "pintu_cabut_akun",
  "pintu_keberatan_siapkan", "pintu_keberatan_kirim", "pintu_keberatan_putuskan", "pintu_keberatan_daftar",
  "web_sesi_buat", "web_hrd",
  "pintu_kirim_gaji_ambil", "pintu_kirim_gaji_hasil", "pintu_gaji_saya", "pintu_contoh_gaji",
  "pintu_periode_gaji", "pintu_total_lengkap",
  "pintu_perintah_siapkan", "pintu_perintah_simpan", "pintu_perintah_hasil", "pintu_batal_siapkan", "pintu_perintah_terakhir",
  "pintu_kasbon_siapkan", "pintu_kasbon_saldo", "pintu_lembur_siapkan",
  "pintu_uang_minta_pin", "pintu_uang_putuskan", "pintu_uang_daftar",
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
    // Paket 9b-2: pengajuan karyawan baru / ubah gaji (Setujui/Tolak lalu PIN).
    if (jenis === "g" && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      await mintaPinUang(alat, chat, tg, Number(mesin), asal === "y");
      return null;
    }
    if (jenis === "l" && asal === "y" && /^\d+$/.test(mesin ?? "")) {
      await mintaPin(alat, chat, tg, "lengkap", Number(mesin));
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
    // Paket 8e: keberatan (karyawan Kirim/Batal; HRD Terima/Tolak).
    if (jenis === "e" && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      await kirimKeberatan(alat, chat, tg, Number(mesin), asal === "y", tombol.message?.message_id);
      return null;
    }
    if (jenis === "f" && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      if (asal === "y") await putuskanKeberatan(alat, chat, tg, Number(mesin), true, null);
      else await tanyaAlasanTolak(alat, chat, tg, Number(mesin));
      return null;
    }
    // Paket 8f: cabut akun (pilih -> konfirmasi Ya/Tidak).
    if (jenis === "k" && (asal === "p" || asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      await tombolCabut(alat, chat, tg, asal, Number(mesin));
      return null;
    }
    // Paket 7a: tombol Ya/Batal perintah HRD (izin, sakit, cuti).
    if (jenis === "c" && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      return jawabPerintah(alat, chat, tg, Number(mesin), asal === "y", tombol.message?.message_id);
    }
    if (jenis === "d" && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      let jawab = await jawabDaftar(alat, tg, Number(mesin), asal === "y");
      const baru = jawab.startsWith("Terdaftar:");
      // Paket 8c: karyawan yang baru daftar langsung menerima rincian gaji periode terakhir yang sudah dirilis.
      // Paket 8c-3: bila rincian itu ada, kalimat "akan dikirim setelah gaji dirilis" diganti supaya tidak janggal.
      const gaji = baru ? await alat.api("pintu_gaji_saya", { telegram_id: tg }) : null;
      if (gaji?.hasil === "ada") jawab = jawab.replace(KALIMAT_TUNGGU_RILIS, KALIMAT_SUDAH_RILIS);
      await kirim(alat, chat, jawab, baru ? papanTombol("karyawan") : {});
      if (baru) {
        await pasangMenu(alat, chat, "karyawan");
        await kirimHasilGaji(alat, chat, tg, gaji, undefined, true);
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
    const tolakKeberatan = new RegExp(`^${TANYA_TOLAK_KEBERATAN} (\\d+)`).exec(ditanya);
    if (tolakKeberatan) {
      await putuskanKeberatan(alat, pesan.chat.id, pesan.from?.id, Number(tolakKeberatan[1]), false, jawab);
      return null;
    }
    if (ditanya.startsWith(TANYA_ID)) {
      const [id, tambahan] = jawab.split(/\s+/);
      await kirim(alat, pesan.chat.id, await buatKodeDaftar(alat, pesan.from?.id, info.hrd, id, tambahan), await papanAkun(alat, pesan.from?.id));
      return null;
    }
    const teks = rapikanPerintah(teksTombol(jawab));
    if (ditanya.startsWith(TANYA_PERINTAH) && !RE_PERINTAH_HRD.test(teks) && !RE_KASBON.test(teks) && !RE_LEMBUR.test(teks)) {
      await kirim(alat, pesan.chat.id, CARA_PERINTAH, await papanAkun(alat, pesan.from?.id));
      return null;
    }
    if (teks === "/tombol_perintah") {
      if (!info.hrd) await kirim(alat, pesan.chat.id, BUKAN_HRD_RILIS);
      else await kirim(alat, pesan.chat.id, `${TANYA_PERINTAH}.\n${CONTOH_PERINTAH}`,
        { reply_markup: { force_reply: true, input_field_placeholder: "izin 10001 30-03-2026" } });
      return null;
    }
    const batalPerintah = /^\/batalperintah(?:@\w+)?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (batalPerintah) {
      await siapkanBatal(alat, pesan.chat.id, pesan.from?.id, info.hrd, batalPerintah[1]);
      return null;
    }
    if (/^\/perintahku(?:@\w+)?\s*$/i.test(teks)) {
      await perintahTerakhir(alat, pesan.chat.id, pesan.from?.id, info.hrd);
      return null;
    }
    const perintahLembur = RE_LEMBUR.exec(teks);
    if (perintahLembur) {
      await siapkanLembur(alat, pesan.chat.id, pesan.from?.id, info.hrd, perintahLembur[1].toLowerCase(), perintahLembur[2] ?? "");
      return null;
    }
    const perintahKasbon = RE_KASBON.exec(teks);
    if (perintahKasbon) {
      await siapkanKasbon(alat, pesan.chat.id, pesan.from?.id, info.hrd, perintahKasbon[1].toLowerCase(), perintahKasbon[2] ?? "");
      return null;
    }
    const perintahHrd = RE_PERINTAH_HRD.exec(teks);
    if (perintahHrd) {
      await siapkanPerintah(alat, pesan.chat.id, pesan.from?.id, info.hrd, perintahHrd[1].toLowerCase(), perintahHrd[2] ?? "");
      return null;
    }
    if (teks === "/tombol_kode" || teks === "/tombol_pin") {
      const bolehPin = teks === "/tombol_pin" && !info.hrd &&
        (await alat.api("pintu_akun", { telegram_id: pesan.from?.id }))?.peran === "bos";
      if (!info.hrd && !bolehPin) await kirim(alat, pesan.chat.id, BUKAN_HRD_RILIS);
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
    const lengkap = /^\/lengkap(?:@\w+)?(?:\s+(\S+))?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (lengkap) {
      if (lengkap[2]) await hapusPesan(alat, pesan.chat.id, pesan.message_id);
      if (!lengkap[1]) await pilihPeriodeLengkap(alat, pesan.chat.id, pesan.from?.id);
      else if (!/^\d+$/.test(lengkap[1])) await kirim(alat, pesan.chat.id, "Cara pakai: /lengkap <nomor periode>, lalu ketik PIN.");
      else if (!lengkap[2]) await mintaPin(alat, pesan.chat.id, pesan.from?.id, "lengkap", Number(lengkap[1]));
      else await totalLengkap(alat, pesan.chat.id, pesan.from?.id, Number(lengkap[1]), lengkap[2]);
      return null;
    }
    if (/^\/pengajuan(?:@\w+)?\s*$/i.test(teks)) {
      await daftarPengajuanUang(alat, pesan.chat.id, pesan.from?.id);
      return null;
    }
    const keberatan = /^\/keberatan(?:@\w+)?(?:\s+([\s\S]*))?$/i.exec(teks);
    if (keberatan) {
      await siapkanKeberatan(alat, pesan.chat.id, pesan.from?.id, (keberatan[1] ?? "").trim());
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
    if (/^\/cabutakun(?:@\w+)?\s*$/i.test(teks)) {
      await daftarCabut(alat, pesan.chat.id, pesan.from?.id);
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
      `File ${nama} tersimpan: ${angka(r.jumlah_tap)} tap, ${r.tanggal_awal} s.d. ${r.tanggal_akhir}${dibuang}. Menghitung ulang...` +
        teksPeriodeBaru(r.periode_baru),
    );
    await kerjakanAntrean(alat, chat, mulai, "telegram");
  } catch (e) {
    await kirim(alat, chat, `File ${nama} gagal diproses: ${(e as Error).message}`);
    throw e;
  }
}

// Paket P1: kabar periode gaji yang dibuat otomatis karena file berisi tap sesudah periode terakhir.
export function teksPeriodeBaru(daftar: { id: number; awal: string; akhir: string; bayar: string }[] | undefined): string {
  if (!daftar || !daftar.length) return "";
  return daftar.map((p) => `\nPeriode baru no. ${p.id} dibuat: ${tulisTanggal(p.awal, false)} – ${tulisTanggal(p.akhir, false)}, ` +
    `gajian ${tulisTanggal(p.bayar, false)}.`).join("");
}

export async function kerjakanAntrean(
  alat: Alat,
  chat: number | null,
  mulai: number,
  asal: "telegram" | "web" = "telegram",
  pemicu?: string,
): Promise<number> {
  const berhasil = await kerjakanSemua(alat, chat, mulai);
  if (berhasil > 0) await picuSheets(alat, chat, mulai, asal, false, pemicu);
  return berhasil;
}

// Paket 6e: minta GitHub mengisi ulang Sheets, kabari pengirim, catat hasilnya (gagal -> pemberitahuan segera).
export async function picuSheets(alat: Alat, chat: number | null, mulai: number, asal: "telegram" | "web",
                                 karenaStatus = false, pemicu?: string): Promise<void> {
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
        pemicu: karenaStatus ? "status periode" : pemicu ?? (asal === "web" ? "file web" : "file Telegram"), waktu_file: waktuFile,
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
  P("pin", "Buat atau ganti PIN"), P("contohgaji", "Contoh pesan gaji: /contohgaji <ID> <nomor>"),
  P("izin", "Catat izin: /izin <ID> <tanggal> [tanggal selesai]"), P("sakit", "Catat sakit: /sakit <ID> <tanggal> [tanggal selesai]"),
  P("cuti", "Catat cuti: /cuti <ID> <tanggal> [tanggal selesai]"),
  P("kasbon", "Kasbon: /kasbon <ID> <jumlah> <cicilan>; /kasbon <ID> lihat saldo"),
  P("cicilan", "Ganti cicilan kasbon: /cicilan <ID> <jumlah>"), P("lunas", "Pelunasan kasbon tunai: /lunas <ID> <jumlah>"),
  P("setujuilembur", "Setujui lembur: /setujuilembur <ID atau divisi> <tanggal> [tanggal selesai]"),
  P("batalkanlembur", "Batalkan lembur: /batalkanlembur <ID atau divisi> <tanggal> [tanggal selesai]"),
  P("setujuiawal", "Setujui jam datang lebih awal jadi lembur: /setujuiawal <ID atau divisi> <tanggal>"),
  P("batalperintah", "Batalkan izin/sakit/cuti/kasbon/lembur: /batalperintah <nomor perintah>"), P("perintahku", "10 perintah chat terakhir"),
  P("keberatan", "Keberatan karyawan yang belum dijawab"),
  P("bantuan", "Daftar perintah"),
];
export const MENU: Record<string, Perintah[]> = {
  umum: [P("daftar", "Daftar karyawan dengan kode dari HRD"), P("gabung", "Gabung sebagai HRD/bos dengan kode undangan"),
         P("bantuan", "Daftar perintah")],
  karyawan: [P("gaji", "Rincian gaji terakhir (atau /gaji <nomor>)"),
             P("keberatan", "Keberatan atas satu tanggal: /keberatan <tanggal> <alasan>"), P("bantuan", "Daftar perintah")],
  hrd: MENU_HRD,
  bos: [P("lengkap", "Total lengkap termasuk orang rahasia (dengan PIN)"), P("pengajuan", "Pengajuan gaji yang menunggu persetujuan"),
        P("pin", "Buat atau ganti PIN"),
        P("bantuan", "Daftar perintah")],
  pembangun: [...MENU_HRD.slice(0, -1), P("setujui", "Setujui pengajuan: /setujui <nomor>"), P("tolak", "Tolak pengajuan: /tolak <nomor>"),
              P("undang", "Undang akun: /undang hrd atau /undang bos"), P("hapuspin", "Hapus PIN akun yang lupa PIN"),
              P("cabutakun", "Cabut akun HRD, bos, atau karyawan"),
              P("lengkap", "Total lengkap termasuk orang rahasia (dengan PIN)"),
              P("pengajuan", "Pengajuan gaji yang menunggu persetujuan"),
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
    "/izin, /sakit, /cuti <ID> <tanggal> [tanggal selesai] [catatan] catat izin, sakit, atau cuti (boleh susulan), " +
    "misalnya /izin 10001 30-03-2026\n" +
    "/kasbon <ID> <jumlah> <cicilan per periode> [catatan] catat pinjaman, misalnya /kasbon 10001 1.000.000 250rb; " +
    "/kasbon <ID> lihat saldo\n/cicilan <ID> <jumlah> ganti cicilan\n/lunas <ID> <jumlah> [catatan] pelunasan tunai di luar gaji\n" +
    "/setujuilembur, /batalkanlembur <ID atau kode divisi> <tanggal> [tanggal selesai] [catatan] setujui atau batalkan lembur, " +
    "misalnya /setujuilembur PRD 05-12-2026\n" +
    "/setujuiawal <ID atau kode divisi> <tanggal> [tanggal selesai] jam datang lebih awal ikut dihitung lembur\n" +
    "/batalperintah <nomor perintah> batalkan izin, sakit, cuti, kasbon, atau perintah lembur yang salah\n/perintahku 10 perintah chat terakhir\n" +
    "/keberatan keberatan karyawan yang belum dijawab (dijawab dengan tombol Terima/Tolak)\n" +
    "Kirim file mesin sebagai dokumen untuk menghitung gaji.",
  bos: "Pengajuan rilis gaji dikirim ke chat ini dengan tombol Setujui dan Tolak. Bila belum dijawab, bot mengingatkan setiap pagi.\n" +
    "Total lengkap termasuk orang rahasia: tombol Total lengkap (atau /lengkap <nomor>), lalu ketik PIN. " +
    "PIN dibuat dengan tombol PIN (atau /pin <6 angka>).\n" +
    "Pengajuan karyawan baru dan ubah gaji dari web HRD dikirim ke chat ini dengan tombol Setujui dan Tolak, lalu ketik PIN; " +
    "/pengajuan menampilkan yang masih menunggu.",
  pembangun: "",
  karyawan: "Rincian gaji dikirim lewat chat ini setelah gaji dirilis.\nTombol Gaji saya (atau /gaji) mengirim ulang " +
    "rincian gaji terakhir; /gaji <nomor> untuk periode tertentu.\n" +
    "Ada yang tidak sesuai? /keberatan <tanggal> <alasan>, misalnya /keberatan 05-04-2026 saya masuk tapi tercatat alpha. " +
    "Paling lambat 14 hari sesudah tanggal bayar. Tombol Keberatan (atau /keberatan saja) menampilkan keberatan Anda dan jawabannya.",
  umum: "Karyawan: minta kode daftar ke HRD, lalu ketik /daftar KODE.\nHRD atau bos: minta kode undangan ke pembangun, lalu ketik /gabung KODE.",
};
BANTUAN.pembangun = BANTUAN.hrd + "\n\nKhusus pembangun:\n/setujui <nomor> dan /tolak <nomor> (lalu ketik PIN)\n" +
  "/undang hrd atau /undang bos kode undangan akun\n/hapuspin hapus PIN akun yang lupa PIN\n" +
  "/cabutakun cabut akun HRD, bos, atau karyawan (bisa bergabung lagi dengan kode baru)\n" +
  "/lengkap <nomor> total lengkap termasuk orang rahasia (lalu ketik PIN)\n" +
  "/pengajuan pengajuan karyawan baru dan ubah gaji yang menunggu (tombol Setujui/Tolak lalu PIN)";

// Perintah yang diketik tanpa garis miring tetap dikenali (paket 8b-3, temuan 6).
const KATA_PERINTAH = new Set(["pin", "ajukan", "rilis", "setujui", "tolak", "batal", "hapuspin", "undang", "gabung", "daftar",
  "kode", "unggah", "bantuan", "gaji", "contohgaji", "lengkap", "izin", "sakit", "cuti", "batalperintah", "perintahku", "kasbon",
  "cicilan", "lunas", "setujuilembur", "batalkanlembur",
  "setujuiawal", "cabutakun", "keberatan", "pengajuan"]);
export function rapikanPerintah(teks: string): string {
  const m = /^([a-z]+)(?:\s|$)/i.exec(teks);
  return m && KATA_PERINTAH.has(m[1].toLowerCase()) ? "/" + teks : teks;
}

// Paket 8b-4: tombol tetap di bawah kolom ketik, per peran. Teks tombol diterjemahkan ke perintah.
export const TOMBOL_TETAP: Record<string, string[][]> = {
  hrd: [["Kirim file", "Ajukan", "Rilis"], ["Perintah HRD", "Kode karyawan", "PIN"], ["Bantuan"]],
  pembangun: [["Kirim file", "Ajukan", "Rilis"], ["Perintah HRD", "Kode karyawan", "PIN"], ["Undang", "Hapus PIN", "Total lengkap"],
              ["Bantuan"]],
  bos: [["Total lengkap", "PIN"], ["Bantuan"]],
  karyawan: [["Gaji saya", "Keberatan"], ["Bantuan"]],
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
  "gaji saya": "/gaji", "menu": "/bantuan", "total lengkap": "/lengkap", "perintah hrd": "/tombol_perintah",
  "cabut akun": "/cabutakun", "keberatan": "/keberatan",
};
export function teksTombol(teks: string): string {
  return TEKS_TOMBOL[teks.trim().toLowerCase()] ?? teks;
}
// Pertanyaan bot yang dijawab dengan membalas pesannya (force reply); awal teks dipakai untuk mengenali jawabannya.
export const TANYA_ID = "Ketik ID karyawan yang dibuatkan kode daftar";
export const TANYA_PIN = "Buat PIN: ketik 6 angka. Ganti PIN: ketik PIN lama, spasi, PIN baru";
export const TANYA_PERINTAH = "Ketik perintah HRD sebagai balasan pesan ini";
export const TANYA_TOLAK_KEBERATAN = "Ketik alasan menolak keberatan no.";

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

// Paket 8d: akun bos juga boleh membuat PIN (untuk total lengkap); database yang menentukan.
async function aturPin(alat: Alat, tg: number, _hrd: boolean, a?: string, b?: string): Promise<string> {
  if (!a) return "Cara pakai: /pin <PIN baru 6 angka>. Ganti PIN: /pin <PIN lama> <PIN baru>. Pesan berisi PIN dihapus otomatis.";
  const r = await alat.api("pintu_atur_pin", b ? { telegram_id: tg, pin_lama: a, pin_baru: b } : { telegram_id: tg, pin_baru: a });
  switch (r.hasil) {
    case "dibuat": return "PIN dibuat. Simpan baik-baik; PIN dipakai untuk merilis gaji dan melihat total lengkap.";
    case "diganti": return "PIN diganti.";
    case "lemah": return "PIN harus 6 angka dan tidak boleh angka sama semua atau berurutan (misalnya 111111 atau 123456).";
    case "perlu_pin_lama": return "PIN sudah ada. Untuk mengganti: /pin <PIN lama> <PIN baru>. Lupa PIN: minta akun pembangun menghapusnya (/hapuspin).";
    case "salah": return "PIN lama salah.";
    case "terkunci": return "Terlalu banyak PIN salah. Coba lagi 1 jam lagi.";
    default: return "PIN hanya untuk akun HRD, bos, dan pembangun.";
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
const KATA_AKSI: Record<string, string> = {
  rilis: "merilis gaji", setujui: "menyetujui pengajuan", tolak: "menolak pengajuan", lengkap: "melihat total lengkap",
};
async function mintaPin(alat: Alat, chat: number, tg: number, aksi: "rilis" | "setujui" | "tolak" | "lengkap",
                        periode: number): Promise<void> {
  const r = await alat.api("pintu_minta_pin", { telegram_id: tg, aksi, periode_id: periode });
  switch (r.hasil) {
    case "menunggu":
      // Paket 8b-5: tanpa force reply (6 angka dikenali dari catatan menunggu PIN), supaya tombol tetap tidak tertutup.
      await kirim(alat, chat, `Ketik PIN 6 angka untuk ${KATA_AKSI[aksi]} periode no. ${periode}. Berlaku 5 menit; pesan PIN dihapus otomatis.`);
      return;
    case "bukan_pembangun": await kirim(alat, chat, "Persetujuan dengan PIN hanya untuk akun pembangun; akun bos memakai tombol."); return;
    case "bukan_bos": await kirim(alat, chat, BUKAN_BOS); return;
    case "tidak_ada": await kirim(alat, chat, "Periode tidak ditemukan."); return;
    default: await kirim(alat, chat, BUKAN_HRD_RILIS);
  }
}

// Pesan 6 angka: PIN untuk tombol/perintah yang sedang menunggu. Pesannya selalu dihapus.
async function pakaiPin(alat: Alat, chat: number, tg: number, hrd: boolean, pin: string): Promise<void> {
  const t = await alat.api("pintu_ambil_pin", { telegram_id: tg });
  if (t?.aksi === "rilis") return rilisGaji(alat, chat, tg, hrd, String(t.periode_id), pin);
  if (t?.aksi === "setujui" || t?.aksi === "tolak") return putuskan(alat, chat, tg, Number(t.periode_id), null, t.aksi === "setujui", pin);
  if (t?.aksi === "lengkap") return totalLengkap(alat, chat, tg, Number(t.periode_id), pin);
  if (t?.aksi === "uang_setuju" || t?.aksi === "uang_tolak") {
    return putuskanUang(alat, chat, tg, Number(t.pengajuan_uang), t.aksi === "uang_setuju", pin);
  }
  await kirim(alat, chat, t?.lewat
    ? "Waktu memasukkan PIN sudah lewat (5 menit). Tekan tombolnya lagi."
    : "Pesan berisi 6 angka sudah dihapus. Tidak ada perintah yang sedang menunggu PIN. " +
      "Tekan dulu tombolnya (misalnya Rilis, Setujui, atau salah satu periode di Total lengkap); " +
      "sesudah bot meminta PIN, baru ketik PIN. Untuk membuat atau mengganti PIN, tekan tombol PIN lalu balas pertanyaannya.");
}

// ---------------------------------------------------------------------------
// Paket 9b-2: pengajuan karyawan baru / ubah gaji dari web; bos atau pembangun memutuskan dengan PIN.
// ---------------------------------------------------------------------------
const tombolUang = (id: number) => ({ reply_markup: { inline_keyboard: [[
  { text: "Setujui (PIN)", callback_data: `g|y|${id}` }, { text: "Tolak (PIN)", callback_data: `g|n|${id}` },
]] } });
const STATUS_UANG: Record<string, string> = { disetujui: "sudah disetujui", ditolak: "sudah ditolak", ditarik: "sudah ditarik pengaju",
                                              hangus: "sudah hangus (lewat 7 hari)" };
async function mintaPinUang(alat: Alat, chat: number, tg: number, id: number, setuju: boolean): Promise<void> {
  const r = await alat.api("pintu_uang_minta_pin", { telegram_id: tg, pengajuan_id: id, setuju });
  if (r?.hasil === "menunggu") {
    await kirim(alat, chat, `Ketik PIN 6 angka untuk ${setuju ? "MENYETUJUI" : "MENOLAK"} pengajuan no. ${id}:\n${r.ringkas}\n` +
      "Berlaku 5 menit; pesan PIN dihapus otomatis.");
  } else if (r?.hasil === "tidak_berlaku") {
    await kirim(alat, chat, `Pengajuan no. ${id} ${STATUS_UANG[r.status] ?? "tidak ada"}.`);
  } else {
    await kirim(alat, chat, "Pengajuan gaji hanya diputuskan akun bos atau pembangun.");
  }
}
async function putuskanUang(alat: Alat, chat: number, tg: number, id: number, setuju: boolean, pin: string): Promise<void> {
  const mulai = alat.sekarang();
  const r = await alat.api("pintu_uang_putuskan", { telegram_id: tg, pengajuan_id: id, setuju, pin });
  switch (r?.hasil) {
    case "disetujui": case "ditolak": {
      const kata = r.hasil === "disetujui" ? "DISETUJUI" : "DITOLAK";
      const siapa = r.oleh === "pembangun" ? "pembangun" : "bos";
      await kirim(alat, chat, `Pengajuan no. ${id} ${kata}${r.sendiri ? " (pengajuan sendiri)" : ""}:\n${r.ringkas}` +
        (r.hasil === "disetujui" && (r.periode ?? []).length ? "\nMenghitung ulang..." : ""));
      if (r.pengaju_telegram && Number(r.pengaju_telegram) !== tg) {
        await kirimAman(alat, Number(r.pengaju_telegram), `Pengajuan no. ${id} ${kata.toLowerCase()} oleh ${siapa}:\n${r.ringkas}` +
          (r.hasil === "disetujui" ? `\nTercatat sebagai perintah no. ${r.perintah_id}; bisa dibatalkan di web HRD selama periodenya belum dirilis.` : ""));
      }
      if (r.hasil === "disetujui" && (r.periode ?? []).length) await kerjakanAntrean(alat, chat, mulai, "telegram", "perintah web");
      return;
    }
    case "tidak_berlaku":
      await kirim(alat, chat, r.alasan ? `Pengajuan no. ${id} tidak bisa disetujui: ${r.alasan}`
        : `Pengajuan no. ${id} ${STATUS_UANG[r.status] ?? "tidak ada"}.`);
      return;
    case "belum_ada_pin": await kirim(alat, chat, "Belum ada PIN. Buat dulu dengan /pin <PIN baru 6 angka>."); return;
    case "pin_salah": await kirim(alat, chat, "PIN salah. Tekan tombol Setujui/Tolak lagi."); return;
    case "terkunci": await kirim(alat, chat, "Terlalu banyak PIN salah. Coba lagi 1 jam lagi."); return;
    default: await kirim(alat, chat, "Pengajuan gaji hanya diputuskan akun bos atau pembangun.");
  }
}
async function daftarPengajuanUang(alat: Alat, chat: number, tg: number): Promise<void> {
  const r = await alat.api("pintu_uang_daftar", { telegram_id: tg });
  if (r?.hasil !== "ada") {
    await kirim(alat, chat, "Pengajuan gaji hanya untuk akun bos atau pembangun.");
    return;
  }
  const daftar: any[] = r.pengajuan ?? [];
  if (!daftar.length) {
    await kirim(alat, chat, "Tidak ada pengajuan karyawan baru atau ubah gaji yang menunggu.");
    return;
  }
  for (const a of daftar) await kirim(alat, chat, `Pengajuan no. ${a.id} dari ${a.pengaju}:\n${a.ringkas}`, tombolUang(a.id));
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
      text: `Hapus PIN: ${a.peran === "hrd" ? "HRD" : a.peran} ${a.label}${a.sendiri ? " (akun ini)" : ""}`,
      callback_data: `h|y|${a.id}`,
    }]) },
  });
}

// Paket 8e: keberatan karyawan (docs/rencana-8e.md).
const NAMA_STATUS_HARI: Record<string, string> = {
  hadir: "hadir", alpha: "alpha (tidak hadir tanpa keterangan)", sakit: "sakit", izin: "izin", cuti: "cuti",
  dinas_luar: "dinas luar", libur: "libur", lembur_hari_libur: "lembur di hari libur", menunggu: "menunggu data",
  tanpa_tap_massal: "tanpa tap (mesin tidak mengirim)",
};
const NAMA_ASAL: Record<string, string> = {
  mesin: "dari mesin", manual: "catatan manual", perintah: "perintah HRD", tidak_wajib_tap: "tidak wajib tap", jadwal: "dari jadwal",
};
export function jamTitik(iso: string | null | undefined): string {
  if (!iso) return "-";
  const t = new Date(new Date(iso).getTime() + 7 * 3600 * 1000);
  return `${String(t.getUTCHours()).padStart(2, "0")}.${String(t.getUTCMinutes()).padStart(2, "0")}`;
}
export function tulisBukti(bukti: any): string[] {
  const h = bukti?.hari;
  const baris: string[] = [];
  if (!h) {
    baris.push("• Tidak ada catatan hari ini untuk Anda di hasil hitung terakhir.");
  } else {
    baris.push(`• Status: ${NAMA_STATUS_HARI[h.status] ?? h.status} (${NAMA_ASAL[h.asal] ?? h.asal})`);
    if (h.kode_jadwal) baris.push(`• Jadwal: ${h.kode_jadwal} ${jamTitik(h.jadwal_masuk)}–${jamTitik(h.jadwal_pulang)}`);
    else baris.push(`• Jadwal: tidak ada (${h.jenis_hari === "kerja" ? "hari kerja" : "hari libur"})`);
    baris.push(`• Masuk ${jamTitik(h.masuk)}, pulang ${jamTitik(h.pulang)}`);
    const menit: string[] = [];
    if (Number(h.menit_telat) > 0) menit.push(`telat ${h.menit_telat} menit`);
    if (Number(h.menit_pulang_cepat) > 0) menit.push(`pulang cepat ${h.menit_pulang_cepat} menit`);
    if (Number(h.menit_lebih) > 0) menit.push(`lebih ${h.menit_lebih} menit`);
    if (h.lupa_tap) menit.push(`lupa tap ${h.lupa_tap}`);
    if (menit.length) baris.push(`• ${menit.join(", ")}`);
  }
  const tap = (bukti?.tap ?? []) as any[];
  baris.push(tap.length ? `• Tap hari itu: ${tap.map((t) => `${jamTitik(t.waktu)} (${t.peran})`).join(", ")}` : "• Tap hari itu: tidak ada");
  return baris;
}
function tulisPeriode(p: any): string {
  return `periode no. ${p.id}, ${tulisTanggal(String(p.awal), false)} – ${tulisTanggal(String(p.akhir), false)}`;
}
const CARA_KEBERATAN = "Cara pakai: /keberatan <tanggal> <alasan>, misalnya /keberatan 05-04-2026 saya masuk tapi tercatat alpha.";

async function siapkanKeberatan(alat: Alat, chat: number, tg: number, isi: string): Promise<void> {
  if (!isi) {
    await daftarKeberatan(alat, chat, tg);
    return;
  }
  const [kataTanggal, ...sisa] = isi.split(/\s+/);
  const tanggal = bacaTanggal(kataTanggal, alat.sekarang());
  if (!tanggal) {
    await kirim(alat, chat, `Tanggal "${kataTanggal}" tidak dikenali atau tidak ada. ${CARA_KEBERATAN}`);
    return;
  }
  const r = await alat.api("pintu_keberatan_siapkan", { telegram_id: tg, tanggal, alasan: sisa.join(" ") });
  switch (r.hasil) {
    case "siap":
      await kirim(alat, chat, [
        `Keberatan untuk ${tulisTanggal(String(r.tanggal))} (${tulisPeriode(r.periode)}):`,
        `Alasan: ${r.alasan}`, "", "Catatan sistem untuk hari itu:", ...tulisBukti(r.bukti), "",
        "Kirim keberatan ini ke HRD?",
      ].join("\n"), { reply_markup: { inline_keyboard: [[{ text: "Kirim", callback_data: `e|y|${r.draf_id}` },
                                                         { text: "Batal", callback_data: `e|n|${r.draf_id}` }]] } });
      return;
    default:
      await kirim(alat, chat, alasanTolakKeberatan(r));
  }
}

function alasanTolakKeberatan(r: any): string {
  switch (r?.hasil) {
    case "bukan_karyawan": return "Keberatan hanya untuk akun karyawan. Karyawan: minta kode daftar ke HRD, lalu ketik /daftar KODE.";
    case "alasan_kosong": return `Tulis alasannya. ${CARA_KEBERATAN}`;
    case "alasan_panjang": return "Alasan terlalu panjang (paling banyak 300 huruf).";
    case "tanggal_depan": return "Tanggal itu belum lewat.";
    case "tanpa_periode": return "Tanggal itu tidak termasuk periode gaji mana pun.";
    case "belum_dihitung": return "Hari itu belum dihitung sistem. Coba lagi setelah data mesin masuk.";
    case "lewat_batas": return `Batas keberatan untuk periode itu sudah lewat (paling lambat ${tulisTanggal(String(r.batas))}). Hubungi HRD langsung.`;
    case "sudah_ada": return `Keberatan no. ${r.keberatan_id} untuk tanggal itu masih menunggu jawaban HRD.`;
    case "terlalu_banyak": return "Paling banyak 5 keberatan per hari. Coba lagi besok.";
    default: return "Keberatan ini sudah tidak berlaku (dikirim, dibatalkan, atau lewat 10 menit). Ketik /keberatan lagi.";
  }
}

async function kirimKeberatan(alat: Alat, chat: number, tg: number, draf: number, ya: boolean, pesanId?: number): Promise<void> {
  const r = await alat.api("pintu_keberatan_kirim", { telegram_id: tg, draf_id: draf, ya });
  if (pesanId !== undefined && r?.hasil !== "tidak_ada") {
    try {
      await alat.telegram("editMessageReplyMarkup", { chat_id: chat, message_id: pesanId, reply_markup: { inline_keyboard: [] } });
    } catch {
      // tombol yang tertinggal tidak berlaku lagi (dijaga database)
    }
  }
  if (r.hasil === "dibatalkan") {
    await kirim(alat, chat, "Keberatan tidak jadi dikirim.");
    return;
  }
  if (r.hasil !== "dikirim") {
    await kirim(alat, chat, alasanTolakKeberatan(r));
    return;
  }
  await kirim(alat, chat, `Keberatan no. ${r.keberatan_id} terkirim ke HRD. Jawabannya akan dikirim ke chat ini.`);
  const teks = [
    `Keberatan no. ${r.keberatan_id} dari ${r.id_karyawan} ${r.nama}`,
    `Tanggal: ${tulisTanggal(String(r.tanggal))} (${tulisPeriode(r.periode)}${r.dirilis ? ", gaji sudah dirilis" : ""})`,
    `Alasan: ${r.alasan}`, "", "Catatan sistem saat keberatan dikirim:", ...tulisBukti(r.bukti),
  ].join("\n");
  const tombol = { reply_markup: { inline_keyboard: [[{ text: "Terima", callback_data: `f|y|${r.keberatan_id}` },
                                                      { text: "Tolak", callback_data: `f|n|${r.keberatan_id}` }]] } };
  for (const t of (r.penerima ?? []) as number[]) await kirimAman2(alat, t, teks, tombol);
}

async function tanyaAlasanTolak(alat: Alat, chat: number, tg: number, keberatan: number): Promise<void> {
  const r = await alat.api("pintu_keberatan_daftar", { telegram_id: tg });
  if (r.hasil !== "hrd") {
    await kirim(alat, chat, "Hanya HRD atau pembangun yang bisa menjawab keberatan.");
    return;
  }
  await kirim(alat, chat, `${TANYA_TOLAK_KEBERATAN} ${keberatan} (balas pesan ini). Alasan dikirim ke karyawan.`,
    { reply_markup: { force_reply: true, input_field_placeholder: "alasan penolakan" } });
}

async function putuskanKeberatan(alat: Alat, chat: number, tg: number, keberatan: number, terima: boolean,
                                 catatan: string | null): Promise<void> {
  const r = await alat.api("pintu_keberatan_putuskan", { telegram_id: tg, keberatan_id: keberatan, terima, catatan });
  switch (r.hasil) {
    case "diputuskan": break;
    case "bukan_hrd": await kirim(alat, chat, "Hanya HRD atau pembangun yang bisa menjawab keberatan."); return;
    case "tidak_ada": await kirim(alat, chat, "Keberatan tidak ditemukan."); return;
    case "sudah_diputuskan":
      await kirim(alat, chat, `Keberatan no. ${r.keberatan_id} sudah dijawab (${r.keputusan}) oleh ${r.oleh}.`); return;
    case "alasan_wajib": await kirim(alat, chat, "Alasan penolakan wajib diisi. Tekan Tolak lagi lalu balas dengan alasannya."); return;
    case "catatan_panjang": await kirim(alat, chat, "Alasan terlalu panjang (paling banyak 300 huruf)."); return;
    default: await kirim(alat, chat, "Keberatan tidak bisa dijawab."); return;
  }
  const hari = tulisTanggal(String(r.tanggal));
  const diterima = r.keputusan === "diterima";
  const tindak = diterima
    ? (r.dirilis
      ? "Gaji periode itu sudah dirilis dan tidak bisa dihitung ulang sistem; selisihnya dibayar HRD di luar gaji periode ini."
      : "Perbaiki lewat perintah HRD (misalnya /izin, /sakit, /setujuilembur) supaya gaji dihitung ulang.")
    : "";
  await kirim(alat, chat, `Keberatan no. ${r.keberatan_id} (${r.id_karyawan} ${r.nama}, ${hari}) ${r.keputusan}.` +
    (tindak ? `\n${tindak}` : "") + (r.karyawan_telegram ? "" : "\nKaryawan ini tidak punya akun aktif; jawaban tidak terkirim."));
  for (const t of (r.penerima ?? []) as number[]) {
    await kirimAman2(alat, t, `Keberatan no. ${r.keberatan_id} (${r.id_karyawan}, ${hari}) sudah ${r.keputusan}` +
      (r.catatan ? `: ${r.catatan}` : "."), {});
  }
  if (r.karyawan_telegram) {
    const teks = diterima
      ? `Keberatan no. ${r.keberatan_id} untuk ${hari} DITERIMA HRD.` + (r.catatan ? ` Catatan: ${r.catatan}` : "") +
        (r.dirilis ? "\nGaji periode itu sudah dirilis; selisihnya dibayar HRD di luar gaji periode ini." :
                     "\nHRD akan memperbaiki catatannya; gaji dihitung ulang sebelum dirilis.")
      : `Keberatan no. ${r.keberatan_id} untuk ${hari} DITOLAK HRD.\nAlasan: ${r.catatan}`;
    await kirimAman2(alat, Number(r.karyawan_telegram), teks, {});
  }
}

async function daftarKeberatan(alat: Alat, chat: number, tg: number): Promise<void> {
  const r = await alat.api("pintu_keberatan_daftar", { telegram_id: tg });
  if (r.hasil === "karyawan") {
    const d = (r.daftar ?? []) as any[];
    await kirim(alat, chat, (d.length
      ? ["Keberatan Anda (10 terakhir):", ...d.map((k) => `• No. ${k.keberatan_id}, ${tulisTanggal(String(k.tanggal))}: ` +
          (k.keputusan ? `${k.keputusan}${k.catatan ? ` (${k.catatan})` : ""}` : "menunggu jawaban HRD"))].join("\n") + "\n\n"
      : "Belum ada keberatan.\n\n") + CARA_KEBERATAN);
    return;
  }
  if (r.hasil === "hrd") {
    const d = (r.daftar ?? []) as any[];
    if (!d.length) {
      await kirim(alat, chat, "Tidak ada keberatan yang menunggu jawaban.");
      return;
    }
    await kirim(alat, chat, `Keberatan menunggu jawaban: ${r.jumlah}` + (Number(r.jumlah) > d.length ? ` (${d.length} terlama ditampilkan)` : "") + ".", {
      reply_markup: { inline_keyboard: d.map((k) => [
        { text: `Terima no. ${k.keberatan_id} ${k.id_karyawan} ${tulisTanggal(String(k.tanggal), false)}`, callback_data: `f|y|${k.keberatan_id}` },
        { text: "Tolak", callback_data: `f|n|${k.keberatan_id}` }]) },
    });
    for (const k of d.slice(0, 5)) {
      await kirim(alat, chat, `No. ${k.keberatan_id}: ${k.id_karyawan} ${k.nama}, ${tulisTanggal(String(k.tanggal))}\nAlasan: ${k.alasan}`);
    }
    return;
  }
  await kirim(alat, chat, alasanTolakKeberatan({ hasil: "bukan_karyawan" }));
}

// Paket 8f: pembangun mencabut akun HRD, bos, atau karyawan.
const NAMA_PERAN: Record<string, string> = { hrd: "HRD", bos: "bos", karyawan: "karyawan" };
async function daftarCabut(alat: Alat, chat: number, tg: number): Promise<void> {
  const r = await alat.api("pintu_cabut_daftar", { telegram_id: tg });
  if (r.hasil !== "ada") {
    await kirim(alat, chat, BUKAN_PEMBANGUN);
    return;
  }
  const akun = r.akun as any[];
  if (!akun.length) {
    await kirim(alat, chat, "Tidak ada akun HRD, bos, atau karyawan yang aktif.");
    return;
  }
  await kirim(alat, chat, "Pilih akun yang dicabut. Akun pembangun tidak bisa dicabut.", {
    reply_markup: { inline_keyboard: akun.map((a) => [{
      text: `Cabut: ${NAMA_PERAN[a.peran] ?? a.peran} ${a.label}`, callback_data: `k|p|${a.id}`,
    }]) },
  });
}

async function tombolCabut(alat: Alat, chat: number, tg: number, langkah: string, pengguna: number): Promise<void> {
  if (langkah === "n") {
    await kirim(alat, chat, "Dibatalkan. Tidak ada akun yang dicabut.");
    return;
  }
  if (langkah === "p") {
    const r = await alat.api("pintu_cabut_daftar", { telegram_id: tg });
    if (r.hasil !== "ada") {
      await kirim(alat, chat, BUKAN_PEMBANGUN);
      return;
    }
    const a = (r.akun as any[]).find((x) => Number(x.id) === pengguna);
    if (!a) {
      await kirim(alat, chat, "Akun tidak ditemukan atau sudah dicabut.");
      return;
    }
    await kirim(alat, chat, `Cabut akun ${NAMA_PERAN[a.peran] ?? a.peran} ${a.label}? ` +
      "Akun ini tidak bisa memakai bot lagi sampai bergabung atau mendaftar ulang dengan kode baru. Riwayatnya tetap tersimpan.", {
      reply_markup: { inline_keyboard: [[{ text: "Ya, cabut", callback_data: `k|y|${pengguna}` },
                                         { text: "Tidak", callback_data: `k|n|${pengguna}` }]] },
    });
    return;
  }
  const r = await alat.api("pintu_cabut_akun", { telegram_id: tg, pengguna_id: pengguna });
  switch (r.hasil) {
    case "dicabut": {
      const peran = NAMA_PERAN[r.peran] ?? r.peran;
      await kirim(alat, chat, `Akun ${peran} ${r.label} dicabut. Untuk bergabung lagi: ` +
        (r.peran === "karyawan" ? "buat kode daftar baru dengan /kode." : `buat undangan baru dengan /undang ${r.peran}.`));
      if (r.telegram_id && Number(r.telegram_id) !== tg) {
        await kirimAman2(alat, Number(r.telegram_id), `Akun ${peran} Anda dicabut oleh pembangun. ` + BANTUAN.umum, papanTombol(null));
        await pasangMenu(alat, Number(r.telegram_id), null);
      }
      return;
    }
    case "tidak_ada": await kirim(alat, chat, "Akun tidak ditemukan atau sudah dicabut."); return;
    default: await kirim(alat, chat, BUKAN_PEMBANGUN);
  }
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
// Perintah HRD lewat chat (paket 7a, docs/rencana-tahap-7.md bagian 5; PRD v2 Tahap 7): izin, sakit, cuti, termasuk
// susulan. Draf -> tombol Ya/Batal -> perintah dicatat -> hitung ulang lewat antrean yang sama dengan file -> kabar
// status hari sebelum dan sesudah. Balasan tanpa angka gaji perorangan (F15).
// ---------------------------------------------------------------------------

export const RE_PERINTAH_HRD = /^\/(izin|sakit|cuti)(?:@\w+)?(?:\s+([\s\S]*))?$/i;
export const CONTOH_PERINTAH = "Contoh: izin 10001 30-03-2026, sakit 10001 30-03 31-03, cuti 10001 01-04-2026 03-04-2026 menikah. " +
  "Bentuk: jenis (izin, sakit, cuti), ID karyawan, tanggal, tanggal selesai bila lebih dari sehari, catatan bila perlu.";
export const CARA_PERINTAH = "Cara pakai: /izin <ID> <tanggal> [tanggal selesai] [catatan]; sama untuk /sakit dan /cuti. " +
  "Tanggal dd-mm-yyyy, atau dd-mm untuk tahun ini. " + CONTOH_PERINTAH.split(". Bentuk")[0] + ".";
const BULAN = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
const HARI = ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"];
const NAMA_JENIS: Record<string, string> = {
  izin: "IZIN", sakit: "SAKIT", cuti: "CUTI", kasbon: "KASBON", setujui_lembur: "SETUJUI LEMBUR", batalkan_lembur: "BATALKAN LEMBUR",
  setujui_datang_awal: "SETUJUI DATANG AWAL",
};
// Sasaran perintah: orang ("10067 Vina Pohan") atau divisi ("divisi PRD (Produksi)").
const sasaran = (r: any) => r.id ? `${r.id} ${r.nama}` : `divisi ${r.divisi_kode} (${r.divisi})`;
const NAMA_STATUS: Record<string, string> = {
  alpha: "alpha", hadir: "hadir", izin: "izin", sakit: "sakit", cuti: "cuti", dinas_luar: "dinas luar", libur: "libur",
  lembur_hari_libur: "masuk di hari libur", menunggu: "menunggu data mesin", tanpa_tap_massal: "hari tanpa tap massal",
};
const namaStatus = (x: string | null | undefined) => x ? (NAMA_STATUS[x] ?? x.replace(/_/g, " ")) : "belum dihitung";

// "30-03-2026", "30/03/2026", "30.03.2026", atau "30-03" (tahun ini menurut WIB) -> "2026-03-30"; tanggal tidak ada -> null.
export function bacaTanggal(teks: string, sekarangMs: number): string | null {
  const m = /^(\d{1,2})[-/.](\d{1,2})(?:[-/.](\d{4}))?$/.exec(teks.trim());
  if (!m) return null;
  const tahun = m[3] ? Number(m[3]) : new Date(sekarangMs + 7 * 3600 * 1000).getUTCFullYear();
  const t = new Date(Date.UTC(tahun, Number(m[2]) - 1, Number(m[1])));
  if (t.getUTCFullYear() !== tahun || t.getUTCMonth() !== Number(m[2]) - 1 || t.getUTCDate() !== Number(m[1])) return null;
  return t.toISOString().slice(0, 10);
}
// "2026-03-30" -> "Senin, 30 Mar 2026"
export function tulisTanggal(iso: string, denganHari = true): string {
  const t = new Date(iso + "T00:00:00Z");
  return (denganHari ? HARI[t.getUTCDay()] + ", " : "") + `${t.getUTCDate()} ${BULAN[t.getUTCMonth()]} ${t.getUTCFullYear()}`;
}
// Baca isi perintah: ID, tanggal, tanggal selesai (bila berupa tanggal), catatan.
export function bacaPerintah(isi: string, sekarangMs: number):
  { id: string; mulai: string; selesai: string; catatan: string } | { salah: string } {
  const kata = isi.trim().split(/\s+/).filter(Boolean);
  if (kata.length < 2) return { salah: CARA_PERINTAH };
  const mulai = bacaTanggal(kata[1], sekarangMs);
  if (!mulai) return { salah: `Tanggal "${kata[1]}" tidak dikenali atau tidak ada. ${CARA_PERINTAH}` };
  const kedua = kata[2] !== undefined ? bacaTanggal(kata[2], sekarangMs) : null;
  if (kata[2] !== undefined && !kedua && /^\d{1,2}[-/.]\d{1,2}/.test(kata[2])) {
    return { salah: `Tanggal "${kata[2]}" tidak dikenali atau tidak ada. ${CARA_PERINTAH}` };
  }
  return { id: kata[0], mulai, selesai: kedua ?? mulai, catatan: kata.slice(kedua ? 3 : 2).join(" ") };
}

function teksTolakPerintah(r: any): string {
  switch (r?.hasil) {
    case "bukan_hrd": return BUKAN_HRD_RILIS;
    case "tidak_ada": return `Karyawan dengan ID ${r.id ?? "itu"} tidak ada. Periksa ID-nya.`;
    case "tanggal_salah": return `Tanggal tidak benar (tanggal selesai tidak boleh sebelum tanggal mulai). ${CARA_PERINTAH}`;
    case "terlalu_panjang": return `Rentang ${angka(r.hari)} hari terlalu panjang; paling banyak 31 hari sekali catat.`;
    case "tanpa_periode": return `Tanggal ${tulisTanggal(r.tanggal)} tidak masuk periode gaji mana pun yang tercatat.`;
    case "periode_dirilis": return `Ditolak: ${tulisTanggal(r.tanggal)} masuk periode no. ${r.periode?.id} ` +
      `(${r.periode?.awal} s.d. ${r.periode?.akhir}) yang gajinya sudah ${r.periode?.status}; periode itu tidak dihitung ulang. ` +
      "Tidak ada yang dicatat.";
    case "tidak_aktif": return `Ditolak: ${r.id} ${r.nama} tidak aktif bekerja pada ${tulisTanggal(r.tanggal)} ` +
      "(belum mulai atau sudah berhenti). Tidak ada yang dicatat.";
    case "jenis_salah": return CARA_PERINTAH;
    case "tidak_ada_perintah": return `Perintah no. ${r.perintah_id ?? "itu"} tidak ada. Lihat nomornya di /perintahku.`;
    case "jenis_tidak_bisa": return `Perintah no. ${r.perintah_id} (${String(r.jenis).replace(/_/g, " ")}) tidak bisa dibatalkan lewat chat; ` +
      "yang bisa: izin, sakit, cuti.";
    case "sudah_dibatalkan": return `Perintah no. ${r.perintah_id} sudah dibatalkan oleh perintah no. ${r.oleh_perintah}. Tidak ada yang dicatat.`;
    case "divisi_tidak_ada": return `Divisi atau ID "${r.divisi_kode ?? ""}" tidak ada. Kode divisi misalnya PRD, GDG, QC.`;
    case "jumlah_salah": return `Jumlah tidak dikenali. ${CARA_KASBON}`;
    case "cicilan_wajib": return `Cicilan per periode wajib diisi. ${CARA_KASBON}`;
    case "tanpa_saldo": return `${r.id} ${r.nama} tidak punya saldo kasbon; cicilan tidak perlu diganti.`;
    case "melebihi_saldo": return r.saldo === null || r.saldo === undefined
      ? `Ditolak: pelunasan melebihi saldo kasbon ${r.id} ${r.nama}. Tidak ada yang dicatat.`
      : `Ditolak: pelunasan melebihi saldo kasbon ${r.id} ${r.nama} (${rupiah(r.saldo)}, sesudah potongan yang sudah dihitung). ` +
        "Tidak ada yang dicatat.";
    case "rahasia": return `Kasbon ${r.id} ${r.nama} tidak ditampilkan: gaji orang ini rahasia.`;
    case "tidak_berlaku": return "Tombol ini sudah tidak berlaku (sudah dipakai, dibatalkan, atau lewat 15 menit). Ketik perintahnya lagi.";
    default: return "Perintah tidak bisa diproses.";
  }
}
const barisPeriode = (r: any) => (r.periode_ulang ?? r.periode ?? []).map((p: any) => `no. ${p.id} (${p.awal} s.d. ${p.akhir})`).join(", ");
const libur = (st: string | null) => st === "libur" || st === "lembur_hari_libur";

export function susunKonfirmasi(r: any): string {
  const hari: any[] = r.hari ?? [];
  const jumlah = hari.length;
  const baris = hari.map((h) => {
    let b = `• ${tulisTanggal(h.tanggal)}: ${namaStatus(h.status)}`;
    if (h.perintah_lama) b += ` (perintah ${h.perintah_lama.jenis.replace(/_/g, " ")} no. ${h.perintah_lama.id} diganti)`;
    if (libur(h.status)) b += " — hari libur, perintah tidak mengubah hari ini";
    return b;
  });
  return `Catat ${NAMA_JENIS[r.jenis] ?? r.jenis} untuk ${r.id} ${r.nama} (${r.divisi})?\n` +
    `Tanggal: ${jumlah === 1 ? tulisTanggal(r.mulai) : `${tulisTanggal(r.mulai)} s.d. ${tulisTanggal(r.selesai)} (${angka(jumlah)} hari)`}\n` +
    (r.catatan ? `Catatan: ${r.catatan}\n` : "") +
    `Status sekarang:\n${baris.join("\n")}\n` +
    `Sesudah dicatat, periode ${barisPeriode(r)} dihitung ulang.` +
    (r.pengajuan_batal ? " Pengajuan rilis periode itu batal dan perlu diajukan lagi." : "") +
    (r.jenis === "izin" ? "\nIzin tidak dibayar (pengaturan sekarang)." : "");
}

async function siapkanPerintah(alat: Alat, chat: number, tg: number, hrd: boolean, jenis: string, isi: string): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  const baca = bacaPerintah(isi, alat.sekarang());
  if ("salah" in baca) {
    await kirim(alat, chat, baca.salah, await papanAkun(alat, tg));
    return;
  }
  const r = await alat.api("pintu_perintah_siapkan", {
    telegram_id: tg, jenis, id_karyawan: baca.id, mulai: baca.mulai, selesai: baca.selesai, catatan: baca.catatan || null,
  });
  if (r?.hasil !== "siap") {
    await kirim(alat, chat, teksTolakPerintah(r), await papanAkun(alat, tg));
    return;
  }
  await kirim(alat, chat, susunKonfirmasi(r), { reply_markup: { inline_keyboard: [[
    { text: "Ya, catat", callback_data: `c|y|${r.draf_id}` }, { text: "Batal", callback_data: `c|n|${r.draf_id}` },
  ]] } });
}

// Paket 7b (docs/rencana-tahap-7.md bagian 8): kasbon lewat chat. Angka orang rahasia tidak ditampilkan (F15).
export const RE_KASBON = /^\/(kasbon|cicilan|lunas)(?:@\w+)?(?:\s+([\s\S]*))?$/i;
export const CARA_KASBON = "Cara pakai: /kasbon <ID> <jumlah> <cicilan per periode> [catatan] untuk pinjaman, " +
  "/kasbon <ID> untuk melihat saldo, /cicilan <ID> <jumlah> untuk mengganti cicilan, /lunas <ID> <jumlah> [catatan] untuk " +
  "pelunasan tunai di luar gaji. Jumlah boleh 1500000, 1.500.000, 1,5jt, atau 500rb.";

// "1500000", "1.500.000", "1,5jt", "1.5 juta", "500rb", "500k" -> angka rupiah; selain itu null.
export function bacaUang(teks: string): number | null {
  const t = teks.trim().toLowerCase().replace(/^rp\.?/, "");
  const m = /^(\d+(?:[.,]\d+)?)(jt|juta|rb|ribu|k)$/.exec(t);
  if (m) {
    const n = Number(m[1].replace(",", ".")) * (m[2] === "jt" || m[2] === "juta" ? 1_000_000 : 1_000);
    return Number.isSafeInteger(Math.round(n)) && Math.abs(n - Math.round(n)) < 1e-6 && n > 0 ? Math.round(n) : null;
  }
  if (/^\d{1,3}([.,]\d{3})+$/.test(t) || /^\d+$/.test(t)) {
    const n = Number(t.replace(/[.,]/g, ""));
    return Number.isSafeInteger(n) && n > 0 ? n : null;
  }
  return null;
}
const teksKasbon = (r: any) => r.kasbon_jenis === "pinjam" ? `pinjam ${rupiah(r.jumlah)} (cicilan ${rupiah(r.cicilan)})`
  : r.kasbon_jenis === "cicilan" ? `ganti cicilan jadi ${rupiah(r.jumlah)}` : `pelunasan tunai ${rupiah(r.jumlah)}`;

export function susunKonfirmasiKasbon(r: any): string {
  const k = r.kasbon ?? {};
  const p = r.periode?.[0] ?? {};
  const judul = r.kasbon_jenis === "pinjam" ? "Catat KASBON (pinjam)" : r.kasbon_jenis === "cicilan" ? "Ganti CICILAN kasbon"
    : "Catat PELUNASAN kasbon (tunai, di luar gaji)";
  const baris = [`${judul} untuk ${r.id} ${r.nama} (${r.divisi})?`];
  if (r.kasbon_jenis === "pinjam") baris.push(`Pinjam: ${rupiah(r.jumlah)}`, `Cicilan per periode: ${rupiah(r.cicilan)}`);
  else if (r.kasbon_jenis === "cicilan") baris.push(`Cicilan per periode: ${k.rahasia ? "" : `${k.cicilan ? rupiah(k.cicilan) : "-"} → `}${rupiah(r.jumlah)}`);
  else baris.push(`Dibayar tunai: ${rupiah(r.jumlah)}`);
  if (r.catatan) baris.push(`Catatan: ${r.catatan}`);
  if (k.rahasia) baris.push("Saldo tidak ditampilkan: gaji orang ini rahasia.");
  else {
    const sesudah = r.kasbon_jenis === "pinjam" ? Number(k.saldo) + Number(r.jumlah)
      : r.kasbon_jenis === "pelunasan" ? Number(k.saldo) - Number(r.jumlah) : Number(k.saldo);
    baris.push(`Saldo kasbon (sesudah potongan yang sudah dihitung): ${rupiah(k.saldo)} → ${rupiah(sesudah)}`);
  }
  baris.push(`Berlaku mulai periode no. ${p.id} (${p.awal} s.d. ${p.akhir}). Potongan per periode = cicilan, paling banyak ` +
    "batas potongan perusahaan sesudah denda; sisanya dibawa ke periode berikut.");
  baris.push(`Periode ${barisPeriode(r)} dihitung ulang.` +
    (r.pengajuan_batal ? " Pengajuan rilis periode itu batal dan perlu diajukan lagi." : ""));
  return baris.join("\n");
}

async function siapkanKasbon(alat: Alat, chat: number, tg: number, hrd: boolean, perintah: string, isi: string): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  const kata = isi.trim().split(/\s+/).filter(Boolean);
  if (kata.length === 0) {
    await kirim(alat, chat, CARA_KASBON, await papanAkun(alat, tg));
    return;
  }
  if (perintah === "kasbon" && kata.length === 1) {
    const r = await alat.api("pintu_kasbon_saldo", { telegram_id: tg, id_karyawan: kata[0] });
    if (r?.hasil !== "ada") {
      await kirim(alat, chat, teksTolakPerintah(r), await papanAkun(alat, tg));
      return;
    }
    const k = r.kasbon;
    const riwayat = (r.riwayat ?? []).map((x: any) => `• ${tulisTanggal(x.tanggal, false)}: ${x.jenis} ${rupiah(x.jumlah)}` +
      (x.perintah_id ? ` (perintah no. ${x.perintah_id}${x.oleh ? `, ${x.oleh}` : ""})` : "") + (x.dibatalkan ? " DIBATALKAN" : ""));
    await kirim(alat, chat, `Kasbon ${r.id} ${r.nama} (${r.divisi}):\n` +
      `Saldo sesudah potongan yang sudah dihitung: ${rupiah(k.saldo)}\n` +
      `Pinjam ${rupiah(k.pinjam)}, pelunasan tunai ${rupiah(k.pelunasan)}, terpotong dari gaji ${rupiah(k.terpotong)}\n` +
      `Cicilan per periode: ${k.cicilan ? rupiah(k.cicilan) : "-"}` +
      (k.potongan_periode !== null && k.potongan_periode !== undefined && r.periode
        ? `\nPotongan di periode no. ${r.periode.id}: ${rupiah(k.potongan_periode)}` : "") +
      (riwayat.length ? `\n5 catatan terakhir:\n${riwayat.join("\n")}` : "\nBelum ada catatan kasbon."), await papanAkun(alat, tg));
    return;
  }
  const jumlah = kata[1] !== undefined ? bacaUang(kata[1]) : null;
  if (jumlah === null) {
    await kirim(alat, chat, (kata[1] === undefined ? "" : `Jumlah "${kata[1]}" tidak dikenali. `) + CARA_KASBON, await papanAkun(alat, tg));
    return;
  }
  let cicilan: number | null = null;
  let sisa = kata.slice(2);
  if (perintah === "kasbon") {
    cicilan = kata[2] !== undefined ? bacaUang(kata[2]) : null;
    if (cicilan === null) {
      await kirim(alat, chat, `Cicilan per periode wajib diisi sesudah jumlah pinjaman. ${CARA_KASBON}`, await papanAkun(alat, tg));
      return;
    }
    sisa = kata.slice(3);
  }
  const r = await alat.api("pintu_kasbon_siapkan", {
    telegram_id: tg, kasbon_jenis: perintah === "kasbon" ? "pinjam" : perintah === "cicilan" ? "cicilan" : "pelunasan",
    id_karyawan: kata[0], jumlah, cicilan, catatan: perintah === "cicilan" ? null : sisa.join(" ") || null,
  });
  if (r?.hasil !== "siap") {
    await kirim(alat, chat, teksTolakPerintah(r), await papanAkun(alat, tg));
    return;
  }
  await kirim(alat, chat, susunKonfirmasiKasbon(r), { reply_markup: { inline_keyboard: [[
    { text: "Ya, catat", callback_data: `c|y|${r.draf_id}` }, { text: "Batal", callback_data: `c|n|${r.draf_id}` },
  ]] } });
}

// Paket 7c-1 (docs/rencana-tahap-7.md bagian 9): setujui/batalkan lembur, per orang atau divisi. Mesin hitung tidak
// berubah; efeknya mengikuti pengaturan lembur (otomatis / wajib perintah, aturan D5).
export const RE_LEMBUR = /^\/(setujuilembur|batalkanlembur|setujuiawal)(?:@\w+)?(?:\s+([\s\S]*))?$/i;
export const CARA_LEMBUR = "Cara pakai: /setujuilembur <ID atau kode divisi> <tanggal> [tanggal selesai] [catatan]; sama untuk " +
  "/batalkanlembur dan /setujuiawal (jam datang lebih awal dihitung lembur). Contoh: /setujuilembur PRD 05-12-2026, " +
  "/batalkanlembur 10001 26-11-2026, /setujuiawal 10001 21-11-2026.";
const NAMA_ATUR: Record<string, string> = { otomatis: "otomatis", wajib_perintah: "wajib perintah" };

function barisHariLembur(h: any, divisi: boolean, jenis?: string): string {
  let b = `• ${tulisTanggal(h.tanggal)}: pengaturan ${NAMA_ATUR[h.pengaturan] ?? h.pengaturan}; `;
  if (divisi && jenis === "setujui_datang_awal") {
    b += `${angka(h.awal_divisi?.orang ?? 0)} orang datang lebih awal, total ${angka(h.awal_divisi?.menit ?? 0)} menit`;
  } else if (divisi) b += `${angka(h.orang_lembur ?? 0)} orang pulang 60 menit atau lebih lewat jadwal`;
  else if (h.status === null || h.status === undefined) b += "belum dihitung";
  else if (h.status !== "hadir") b += namaStatus(h.status);
  else if (jenis === "setujui_datang_awal") {
    b += `datang ${angka(h.menit_awal ?? 0)} menit lebih awal, pulang ${angka(h.menit_lebih ?? 0)} menit lewat jadwal` +
      (Number(h.menit_awal ?? 0) === 0 ? " (tidak ada datang awal yang bisa dihitung)" : "");
  } else b += `pulang ${angka(h.menit_lebih ?? 0)} menit lewat jadwal` + (Number(h.menit_lebih ?? 0) < 60 ? " (kurang dari 60 menit, bukan lembur)" : "");
  const ada = (h.perintah ?? []).map((p: any) => `${NAMA_JENIS[p.jenis] ?? p.jenis} no. ${p.id}`);
  if (ada.length) b += `; sudah ada ${ada.join(", ")}`;
  if (jenis === "setujui_lembur" && h.pengaturan === "otomatis") b += " — lembur sudah dibayar otomatis, perintah ini tidak mengubah hari ini";
  if (jenis === "batalkan_lembur" && h.pengaturan === "wajib_perintah" && !(h.perintah ?? []).some((p: any) => p.jenis === "setujui_lembur")) {
    b += " — tanpa persetujuan lembur memang tidak dibayar, perintah ini tidak mengubah hari ini";
  }
  return b;
}

export function susunKonfirmasiLembur(r: any): string {
  const hari: any[] = r.hari ?? [];
  const tanggal = r.mulai === r.selesai ? tulisTanggal(r.mulai) : `${tulisTanggal(r.mulai)} s.d. ${tulisTanggal(r.selesai)} (${angka(hari.length)} hari)`;
  const awal = r.jenis === "setujui_datang_awal";
  const judul = awal ? "Setujui DATANG AWAL (dihitung lembur)" : `${r.jenis === "setujui_lembur" ? "Setujui" : "Batalkan"} LEMBUR`;
  // Celah 2 pemeriksaan 7c-2: persetujuan divisi untuk rentang panjang harus terlihat jumlahnya.
  const jumlahAwal = awal && !r.id ? hari.reduce((a, h) => ({ orang: a.orang + Number(h.awal_divisi?.orang ?? 0),
    menit: a.menit + Number(h.awal_divisi?.menit ?? 0) }), { orang: 0, menit: 0 }) : null;
  return `${judul} untuk ${r.id ? `${r.id} ${r.nama} (${r.divisi})` : sasaran(r)}?\n` +
    `Tanggal: ${tanggal}\n` + (r.catatan ? `Catatan: ${r.catatan}\n` : "") +
    `Keadaan sekarang:\n${hari.map((h) => barisHariLembur(h, !r.id, r.jenis)).join("\n")}\n` +
    (jumlahAwal ? `Jumlah seluruh rentang: ${angka(jumlahAwal.orang)} hari-orang datang lebih awal, total ${angka(jumlahAwal.menit)} menit.\n` : "") +
    (awal ? "Menit datang lebih awal ditambahkan ke menit lewat jam pulang di hari yang sama, lalu dihitung dengan aturan lembur " +
        "(minimal 60 menit, kelipatan 30 menit). Hari dengan data tap tidak lengkap atau meragukan tidak dihitung."
      : r.jenis === "setujui_lembur" ? "Lembur yang disetujui dibayar sesuai aturan lembur (minimal 60 menit, kelipatan 30 menit)."
      : "Lembur di tanggal itu tidak dibayar; kelebihan jam tetap tercatat.") +
    `\nPeriode ${barisPeriode(r)} dihitung ulang.` +
    (r.pengajuan_batal ? " Pengajuan rilis periode itu batal dan perlu diajukan lagi." : "");
}

export function susunHasilLembur(sebelum: any, h: any): string {
  const apa = h.jenis === "batalkan_perintah" ? "PEMBATALAN PERINTAH LEMBUR" : NAMA_JENIS[h.jenis] ?? h.jenis;
  const kepala = `Hasil ${apa} ${sasaran(h)} (perintah no. ${h.perintah_id}):\n`;
  const lama = new Map<string, number>((sebelum?.daftar ?? []).map((x: any) => [`${x.periode}|${x.id}`, Number(x.lembur)] as [string, number]));
  const baru: any[] = h.lembur?.daftar ?? [];
  const rahasia = Number(h.lembur?.rahasia ?? 0);
  if (h.id) {
    if (baru.length === 0) return kepala + (rahasia ? "Angka tidak ditampilkan: gaji orang ini rahasia." : "Belum ada hasil hitung.");
    return kepala + baru.map((x) => `• Lembur periode no. ${x.periode}: ` +
      `${lama.has(`${x.periode}|${x.id}`) ? `${rupiah(lama.get(`${x.periode}|${x.id}`)!)} → ` : ""}${rupiah(x.lembur)}`).join("\n");
  }
  let berubah = 0;
  let totalLama = 0;
  let totalBaru = 0;
  for (const x of baru) {
    const l = lama.get(`${x.periode}|${x.id}`) ?? 0;
    totalLama += l;
    totalBaru += Number(x.lembur);
    if (l !== Number(x.lembur)) berubah++;
  }
  return kepala + `• ${angka(berubah)} orang lemburnya berubah\n• Total lembur orang di divisi ini: ${rupiah(totalLama)} → ${rupiah(totalBaru)}` +
    (rahasia ? ` (tidak termasuk ${angka(rahasia)} orang rahasia)` : "");
}

async function siapkanLembur(alat: Alat, chat: number, tg: number, hrd: boolean, perintah: string, isi: string): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  const baca = bacaPerintah(isi, alat.sekarang());
  if ("salah" in baca) {
    await kirim(alat, chat, baca.salah.replace(CARA_PERINTAH, CARA_LEMBUR), await papanAkun(alat, tg));
    return;
  }
  const r = await alat.api("pintu_lembur_siapkan", {
    telegram_id: tg, jenis: perintah === "setujuilembur" ? "setujui_lembur" : perintah === "setujuiawal" ? "setujui_datang_awal" : "batalkan_lembur",
    sasaran: baca.id,
    mulai: baca.mulai, selesai: baca.selesai, catatan: baca.catatan || null,
  });
  if (r?.hasil !== "siap") {
    await kirim(alat, chat, teksTolakPerintah(r), await papanAkun(alat, tg));
    return;
  }
  await kirim(alat, chat, susunKonfirmasiLembur(r), { reply_markup: { inline_keyboard: [[
    { text: "Ya, catat", callback_data: `c|y|${r.draf_id}` }, { text: "Batal", callback_data: `c|n|${r.draf_id}` },
  ]] } });
}

export function susunKonfirmasiBatal(r: any): string {
  const hari: any[] = r.hari ?? [];
  const d = r.dibatalkan ?? {};
  const tanggal = r.mulai === r.selesai ? tulisTanggal(r.mulai) : `${tulisTanggal(r.mulai)} s.d. ${tulisTanggal(r.selesai)} (${angka(hari.length)} hari)`;
  return `Batalkan perintah no. ${d.id}: ${NAMA_JENIS[d.jenis] ?? d.jenis} ${r.id ? `${r.id} ${r.nama} (${r.divisi})` : sasaran(r)}?\n` +
    `Tanggal: ${tanggal}\nDicatat lewat: ${d.asal === "chat" ? "chat" : "file"}` + (d.alasan ? `, catatan: ${d.alasan}` : "") + "\n" +
    (d.jenis === "setujui_lembur" || d.jenis === "batalkan_lembur" || d.jenis === "setujui_datang_awal"
      ? `Keadaan sekarang:\n${hari.map((h) => barisHariLembur(h, !r.id, d.jenis === "setujui_datang_awal" ? d.jenis : undefined)).join("\n")}\n` +
        "Sesudah dibatalkan, lembur di tanggal itu kembali mengikuti pengaturan (otomatis atau wajib perintah). "
      : d.jenis === "kasbon"
      ? `Isi: ${(d.kasbon ?? []).map((k: any) => `${k.jenis} ${rupiah(k.jumlah)}`).join(", ")}\n` +
        (r.kasbon?.rahasia ? "" : `Saldo kasbon sekarang: ${rupiah(r.kasbon?.saldo ?? 0)}\n`) +
        "Sesudah dibatalkan, catatan kasbon ini tidak dihitung lagi. "
      : `Status sekarang:\n${hari.map((h) => `• ${tulisTanggal(h.tanggal)}: ${namaStatus(h.status)}`).join("\n")}\n` +
        "Sesudah dibatalkan, hari itu kembali mengikuti data mesin (atau perintah lain yang masih berlaku). ") +
    `Periode ${barisPeriode(r)} dihitung ulang.` +
    (r.pengajuan_batal ? " Pengajuan rilis periode itu batal dan perlu diajukan lagi." : "") +
    "\nPembatalan tidak bisa dibatalkan; kalau salah, ketik perintahnya lagi.";
}

async function siapkanBatal(alat: Alat, chat: number, tg: number, hrd: boolean, nomor?: string): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  if (!nomor || !/^\d+$/.test(nomor)) {
    await kirim(alat, chat, "Cara pakai: /batalperintah <nomor perintah>. Nomornya ada di pesan \"Tercatat\" atau di /perintahku.",
      await papanAkun(alat, tg));
    return;
  }
  const r = await alat.api("pintu_batal_siapkan", { telegram_id: tg, perintah_id: Number(nomor) });
  if (r?.hasil !== "siap") {
    await kirim(alat, chat, teksTolakPerintah(r), await papanAkun(alat, tg));
    return;
  }
  await kirim(alat, chat, susunKonfirmasiBatal(r), { reply_markup: { inline_keyboard: [[
    { text: "Ya, batalkan", callback_data: `c|y|${r.draf_id}` }, { text: "Tidak", callback_data: `c|n|${r.draf_id}` },
  ]] } });
}

async function perintahTerakhir(alat: Alat, chat: number, tg: number, hrd: boolean): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  const r = await alat.api("pintu_perintah_terakhir", { telegram_id: tg });
  const daftar: any[] = r?.daftar ?? [];
  if (daftar.length === 0) {
    await kirim(alat, chat, "Belum ada perintah lewat chat.", await papanAkun(alat, tg));
    return;
  }
  const baris = daftar.map((x) => {
    const tgl = x.mulai === x.selesai ? tulisTanggal(x.mulai, false) : `${tulisTanggal(x.mulai, false)} s.d. ${tulisTanggal(x.selesai, false)}`;
    const apa = x.jenis === "batalkan_perintah" ? `batalkan no. ${x.membatalkan}` : NAMA_JENIS[x.jenis] ?? x.jenis;
    return `no. ${x.id} · ${apa} · ${x.id_karyawan ? `${x.id_karyawan} ${x.nama ?? ""}` : `divisi ${x.divisi}`} · ${tgl} · ${x.oleh ?? "?"} ${x.dibuat}` +
      (x.dibatalkan_oleh ? ` · DIBATALKAN (no. ${x.dibatalkan_oleh})` : "");
  });
  await kirim(alat, chat, `10 perintah chat terakhir (terbaru di atas):\n${baris.join("\n")}`, await papanAkun(alat, tg));
}

export function susunHasilPerintah(sebelum: any[], r: any, kasbonSebelum?: any): string {
  if (r.kasbon) {
    const apa = r.jenis === "batalkan_perintah" ? "PEMBATALAN KASBON" : "KASBON";
    const k = r.kasbon;
    const kepala = `Hasil ${apa} ${r.id} ${r.nama} (perintah no. ${r.perintah_id}):\n`;
    if (k.rahasia) return kepala + "Angka tidak ditampilkan: gaji orang ini rahasia.";
    const lama = kasbonSebelum && !kasbonSebelum.rahasia ? kasbonSebelum.potongan_periode : undefined;
    const potong = (x: any) => x === null || x === undefined ? "belum dihitung" : rupiah(x);
    return kepala +
      `• Potongan kasbon periode no. ${r.periode_kasbon}: ${lama === undefined ? "" : `${potong(lama)} → `}${potong(k.potongan_periode)}\n` +
      `• Sisa saldo sesudah potongan yang sudah dihitung: ${rupiah(k.saldo)}\n` +
      `• Cicilan per periode: ${k.cicilan ? rupiah(k.cicilan) : "-"}`;
  }
  const lama = new Map<string, string | null>((sebelum ?? []).map((h: any) => [h.tanggal, h.status] as [string, string | null]));
  const baris = (r.hari ?? []).map((h: any) => {
    const a = lama.get(h.tanggal) ?? null;
    return `• ${tulisTanggal(h.tanggal)}: ${a === h.status ? `${namaStatus(h.status)} (tidak berubah)` : `${namaStatus(a)} → ${namaStatus(h.status)}`}`;
  });
  const apa = r.jenis === "batalkan_perintah" ? "PEMBATALAN" : NAMA_JENIS[r.jenis] ?? r.jenis;
  return `Hasil ${apa} ${r.id} ${r.nama} (perintah no. ${r.perintah_id}):\n${baris.join("\n")}`;
}

async function jawabPerintah(alat: Alat, chat: number, tg: number, draf: number, ya: boolean, pesanId?: number): Promise<void> {
  const mulai = alat.sekarang();
  const r = await alat.api("pintu_perintah_simpan", { telegram_id: tg, draf_id: draf, ya });
  if (r?.hasil === "disimpan" || r?.hasil === "dibatalkan") {
    try {
      if (pesanId !== undefined) {
        await alat.telegram("editMessageReplyMarkup", { chat_id: chat, message_id: pesanId, reply_markup: { inline_keyboard: [] } });
      }
    } catch {
      // tombol yang tertinggal tidak berlaku lagi (dijaga database)
    }
  }
  if (r?.hasil === "dibatalkan") {
    await kirim(alat, chat, "Tidak jadi dicatat.", await papanAkun(alat, tg));
    return;
  }
  if (r?.hasil !== "disimpan") {
    await kirim(alat, chat, teksTolakPerintah(r), await papanAkun(alat, tg));
    return;
  }
  const tanggal = r.mulai === r.selesai ? tulisTanggal(r.mulai) : `${tulisTanggal(r.mulai)} s.d. ${tulisTanggal(r.selesai)}`;
  const apa = r.jenis === "batalkan_perintah" ? `pembatalan perintah no. ${r.membatalkan}`
    : r.jenis === "kasbon" ? `KASBON ${teksKasbon(r)},` : NAMA_JENIS[r.jenis] ?? r.jenis;
  await kirim(alat, chat, `Tercatat: perintah no. ${r.perintah_id}, ${apa} ${sasaran(r)}, ${tanggal}. ` +
    `Menghitung ulang periode ${barisPeriode(r)}...` +
    (r.jenis === "batalkan_perintah" ? "" : `\nSalah catat? Ketik /batalperintah ${r.perintah_id}`), await papanAkun(alat, tg));
  await kerjakanAntrean(alat, chat, mulai, "telegram", "perintah HRD");
  const h = await alat.api("pintu_perintah_hasil", { telegram_id: tg, perintah_id: r.perintah_id });
  if (h?.hasil !== "ada") return;
  if (h.gagal) {
    await kirimAman(alat, chat, `Perintah no. ${r.perintah_id} tersimpan, tetapi hitung ulang gagal; pembangun perlu memeriksa.`);
  } else if (!h.selesai_dihitung) {
    await kirimAman(alat, chat, `Perintah no. ${r.perintah_id} tersimpan; hitung ulang belum selesai (antrean). ` +
      "Hasilnya terlihat sesudah hitungan berikutnya.");
  } else {
    await kirimAman(alat, chat, h.lembur ? susunHasilLembur(r.lembur_sebelum, h) : susunHasilPerintah(r.hari_sebelum, h, r.kasbon_sebelum));
  }
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
  baris.push("", "Ada yang tidak sesuai? Ketik /keberatan <tanggal> <alasan>, misalnya /keberatan 05-04-2026 saya masuk tapi tercatat alpha.");
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
  await kirimHasilGaji(alat, chat, tg, r, nomor, dariDaftar);
}

async function kirimHasilGaji(alat: Alat, chat: number, tg: number, r: any, nomor?: string, dariDaftar = false): Promise<void> {
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

// Total lengkap termasuk orang rahasia (paket 8d, F15/F15b): hanya bos dan pembangun, dengan PIN; setiap lihat tercatat.
const BUKAN_BOS = "Total lengkap hanya untuk akun bos dan pembangun.";
async function pilihPeriodeLengkap(alat: Alat, chat: number, tg: number): Promise<void> {
  const r = await alat.api("pintu_periode_gaji", { telegram_id: tg });
  if (r.hasil !== "ada") {
    await kirim(alat, chat, BUKAN_BOS);
    return;
  }
  const daftar: any[] = r.periode ?? [];
  if (!daftar.length) {
    await kirim(alat, chat, "Belum ada periode yang dihitung.");
    return;
  }
  // Paket 8d-2: uji nyata 20 Nov 2026 -> PIN dua kali diketik sebelum tombol periode ditekan; kalimat diperjelas.
  await kirim(alat, chat, "Total lengkap periode mana? Tekan salah satu tombol periode di bawah dulu; bot akan meminta PIN sesudahnya.", {
    reply_markup: { inline_keyboard: daftar.map((x) => [{
      text: `No. ${x.periode_id}: ${x.awal} s.d. ${x.akhir} (${x.status})`, callback_data: `l|y|${x.periode_id}`,
    }]) },
  });
}

export function susunTotalLengkap(r: any): string[] {
  const l = r.lengkap ?? {};
  const t = r.terlihat ?? {};
  const daftar: any[] = r.daftar_rahasia ?? [];
  const selisih = Number(l.bersih ?? 0) - Number(t.bersih ?? 0);
  const baris = [
    "TOTAL LENGKAP (termasuk orang rahasia; hanya untuk bos dan pembangun)",
    `Periode no. ${r.periode_id}: ${r.awal} s.d. ${r.akhir}, dibayar ${r.bayar}. Status: ${r.status}.`,
    `${angka(l.orang ?? 0)} orang, gaji bersih ${rupiah(l.bersih ?? 0)}, dibayar ${rupiah(l.dibayar ?? 0)} ` +
      `(transfer ${rupiah(l.transfer ?? 0)}, tunai ${rupiah(l.tunai ?? 0)}).`,
    `Yang terlihat HRD: ${angka(t.orang ?? 0)} orang, gaji bersih ${rupiah(t.bersih ?? 0)}.`,
    `Selisih: ${angka(daftar.length)} orang rahasia, gaji bersih ${rupiah(selisih)}.`,
  ];
  if (daftar.length) {
    baris.push("", "Orang rahasia:");
    for (const x of daftar) {
      baris.push(`- ${x.nama} (ID ${x.id}): bersih ${rupiah(x.bersih)}, dibayar ${rupiah(x.dibayar)} (${x.cara_bayar ?? "-"})`);
    }
  }
  baris.push("", "Pesan ini berisi gaji rahasia; jangan diteruskan. Hapus dari chat bila sudah tidak perlu.");
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
  return pesan;
}

async function totalLengkap(alat: Alat, chat: number, tg: number, periode: number, pin: string): Promise<void> {
  const r = await alat.api("pintu_total_lengkap", { telegram_id: tg, periode_id: periode, pin });
  switch (r.hasil) {
    case "ada": await kirimBagian(alat, chat, susunTotalLengkap(r)); return;
    case "belum_ada_pin": await kirim(alat, chat, "Belum ada PIN. Buat dulu dengan tombol PIN atau /pin <PIN baru 6 angka>."); return;
    case "pin_salah": await kirim(alat, chat, "PIN salah."); return;
    case "terkunci": await kirim(alat, chat, "Terlalu banyak PIN salah. Coba lagi 1 jam lagi."); return;
    case "tidak_ada": await kirim(alat, chat, "Periode itu belum dihitung."); return;
    default: await kirim(alat, chat, BUKAN_BOS);
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

export const KALIMAT_TUNGGU_RILIS = "Rincian gaji akan dikirim lewat chat ini setelah gaji dirilis.";
export const KALIMAT_SUDAH_RILIS = "Rincian gaji terakhir ada di bawah ini; tombol Gaji saya untuk meminta ulang.";

async function jawabDaftar(alat: Alat, tg: number, kodeId: number, ya: boolean): Promise<string> {
  const r = await alat.api("pintu_daftar_jawab", { telegram_id: tg, kode_id: kodeId, jawab: ya ? "ya" : "bukan" });
  switch (r.hasil) {
    case "terdaftar":
      return `Terdaftar: ${r.nama} (ID ${r.id}). ${KALIMAT_TUNGGU_RILIS}`;
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
    periode_baru: r.periode_baru ?? [],
  };
  const latar = r.hasil === "diterima"
    ? (async () => {
      await kirimAman(alat, chat, `File ${nama} diunggah lewat web (mesin ${mesin}): ${angka(r.jumlah_tap)} tap, ` +
        `${r.tanggal_awal} s.d. ${r.tanggal_akhir}. Menghitung ulang...` + teksPeriodeBaru(r.periode_baru));
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

export async function webMintaKode(alat: Alat, emailMasuk: string, tujuan: "unggah" | "hrd" = "unggah"): Promise<JawabanWeb> {
  if (!alat.email) return { status: 503, isi: { alasan: "Masuk lewat email belum disiapkan." }, latar: null };
  const email = String(emailMasuk ?? "").trim().toLowerCase();
  if (!emailSah(email)) return { status: 400, isi: { alasan: "Tulis alamat email yang benar." }, latar: null };
  const kode = kodeEnamAngka();
  const r = await alat.api("pintu_minta_kode_email", { email, sidik: await sidikTeks(`${email}:${kode}`) });
  if (r.kirim) {
    try {
      // Paket 9a (C12): judul email mengikuti halaman yang meminta kode.
      const halaman = tujuan === "hrd" ? "web HRD" : "unggah file";
      await alat.email(email, `Kode masuk ${halaman}: ${kode}`,
        `Kode masuk ${tujuan === "hrd" ? "web HRD" : "halaman unggah file mesin"}: ${kode}\n\nBerlaku 10 menit. ` +
          `Jangan berikan kode ini kepada siapa pun.\nBila Anda tidak meminta kode ini, abaikan email ini.`);
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

// ---------------------------------------------------------------------------
// Paket 9a: web HRD lihat saja (docs/rencana-9a.md). Sesi 2 jam (30 menit diam), hanya sidiknya di database.
// ---------------------------------------------------------------------------
export async function webMasukHrd(alat: Alat, emailMasuk: string, kodeMasuk: string): Promise<JawabanWeb> {
  const email = String(emailMasuk ?? "").trim().toLowerCase();
  const kodeEmail = String(kodeMasuk ?? "").replace(/\s+/g, "");
  if (!emailSah(email) || !/^\d{6}$/.test(kodeEmail)) {
    return { status: 400, isi: { alasan: "Kode terdiri dari 6 angka." }, latar: null };
  }
  const kodeSesi = kodeAcak();
  const r = await alat.api("web_sesi_buat", {
    email,
    sidik_kode: await sidikTeks(`${email}:${kodeEmail}`),
    sidik_sesi: await sidikTeks(kodeSesi),
  });
  if (r.hasil === "masuk") {
    return { status: 200, isi: { sesi: kodeSesi, berlaku_sampai: r.berlaku_sampai, peran: r.peran, label: r.label }, latar: null };
  }
  if (r.hasil === "salah") return { status: 401, isi: { alasan: `Kode salah. Sisa ${r.sisa} kali percobaan.` }, latar: null };
  return { status: 401, isi: { alasan: "Kode tidak berlaku (salah 5 kali, lewat 10 menit, atau sudah dipakai). Minta kode baru." }, latar: null };
}

export const KUNCI_COBA = ["telat_menit", "lembur_minimal", "lembur_kelipatan", "lembur_bulat", "uang_makan", "premi_hadir", "shift_malam"];
// Paket 9b-1: isian perintah web; hanya kunci yang dikenal, teks pendek (diperiksa lagi oleh database).
export const KUNCI_PERINTAH = ["jenis", "id_karyawan", "mulai", "selesai", "divisi", "regu", "jabatan", "id_mesin", "alasan", "nomor",
  // Paket 9b-2: karyawan baru dan ubah gaji (tanpa rekening).
  "nama", "wajib_tap", "gaji_pokok", "tunjangan", "ptkp", "cara_bayar", "bpjs_kesehatan", "bpjs_ketenagakerjaan", "rahasia"];
export const SESI_HABIS = "Sesi berakhir (lewat 2 jam, 30 menit tidak dipakai, keluar, atau akun dicabut). Masuk lagi.";
export async function webHrd(alat: Alat, badan: any): Promise<JawabanWeb> {
  const sesi = String(badan?.sesi ?? "");
  if (!/^[0-9a-f]{64}$/.test(sesi)) return { status: 401, isi: { hasil: "sesi_tidak_berlaku", alasan: SESI_HABIS }, latar: null };
  const aksi = String(badan?.aksi ?? "");
  const masukan: Record<string, unknown> = { sidik_sesi: await sidikTeks(sesi), aksi };
  if (badan?.periode_id !== undefined) masukan.periode_id = String(badan.periode_id);
  if (badan?.id_karyawan !== undefined) masukan.id_karyawan = String(badan.id_karyawan).slice(0, 40);
  // Paket 9c: isian coba aturan; hanya kunci yang dikenal dan nilai sederhana (diperiksa lagi oleh database).
  if (badan?.aturan && typeof badan.aturan === "object" && !Array.isArray(badan.aturan)) {
    const aturan: Record<string, string | number> = {};
    for (const k of KUNCI_COBA) {
      const v = (badan.aturan as any)[k];
      if (typeof v === "number" || typeof v === "string") aturan[k] = typeof v === "string" ? v.slice(0, 20) : v;
    }
    masukan.aturan = aturan;
  }
  if (badan?.perintah && typeof badan.perintah === "object" && !Array.isArray(badan.perintah)) {
    const perintah: Record<string, string> = {};
    for (const k of KUNCI_PERINTAH) {
      const v = (badan.perintah as any)[k];
      if (typeof v === "number" || typeof v === "string") perintah[k] = String(v).slice(0, 200);
    }
    masukan.perintah = perintah;
  }
  const mulai = alat.sekarang();
  const r = await alat.api("web_hrd", masukan);
  switch (r?.hasil) {
    case "ok": return { status: 200, isi: { hasil: "ok", data: r.data }, latar: null };
    // Paket 9b-1: perintah tersimpan atau dibatalkan -> hitung ulang lewat antrean yang sama dengan file dan chat,
    // lalu Sheets dipicu (kerjakanAntrean). Kabar ke Telegram akun itu bila akunnya punya ID Telegram.
    case "disimpan": case "dibatalkan": {
      const chat: number | null = r.telegram_id === null || r.telegram_id === undefined ? null : Number(r.telegram_id);
      const ada = Array.isArray(r.data?.periode) && r.data.periode.length > 0;
      const latar = ada
        ? (async () => {
          await kirimAman(alat, chat, `Perintah web no. ${r.data.perintah_id}: ${r.data.ringkas}. Menghitung ulang...`);
          await kerjakanAntrean(alat, chat, mulai, "web", "perintah web");
        })()
        : null;
      return { status: 200, isi: { hasil: r.hasil, data: r.data }, latar };
    }
    // Paket 9b-2: pengajuan uang -> pesan ke bos dan pembangun dengan tombol Setujui/Tolak (lalu PIN).
    case "diajukan": {
      const penerima: number[] = (r.data?.penerima ?? []).map(Number);
      const latar = penerima.length
        ? (async () => {
          for (const t of penerima) {
            await kirimAman2(alat, t, `Pengajuan no. ${r.data.pengajuan_id} dari ${r.data.pengaju} (web HRD):\n${r.data.ringkas}\n` +
              "Setujui atau tolak, lalu ketik PIN. Hangus bila tidak diputuskan dalam 7 hari.", tombolUang(r.data.pengajuan_id));
          }
        })()
        : null;
      const isi = { ...r.data };
      delete isi.penerima;
      delete isi.ringkas; // tabel web memakai ringkas_hrd (tanpa angka orang rahasia)
      return { status: 200, isi: { hasil: "diajukan", data: { ...isi, jumlah_penerima: penerima.length } }, latar };
    }
    case "ditarik": return { status: 200, isi: { hasil: "ditarik", data: r.data }, latar: null };
    case "ditolak": return { status: 409, isi: { hasil: "ditolak", alasan: r.alasan }, latar: null };
    case "keluar": return { status: 200, isi: { hasil: "keluar" }, latar: null };
    case "terlalu_banyak":
      return { status: 429, isi: { hasil: "terlalu_banyak", alasan: "Terlalu banyak permintaan dalam 1 jam; coba lagi nanti." }, latar: null };
    case "tidak_ada": return { status: 404, isi: { hasil: "tidak_ada", alasan: "Periode atau karyawan tidak ditemukan." }, latar: null };
    case "aksi_salah": return { status: 400, isi: { hasil: "aksi_salah", alasan: "Permintaan tidak dikenal." }, latar: null };
    // Paket 9c: penolakan coba aturan membawa alasan dari database.
    case "tidak_boleh": case "antrean": case "sibuk": case "gagal":
      return { status: 409, isi: { hasil: r.hasil, alasan: r.alasan }, latar: null };
    case "isian_salah": case "tanpa_perubahan": return { status: 400, isi: { hasil: r.hasil, alasan: r.alasan }, latar: null };
    case "batas_harian": return { status: 429, isi: { hasil: r.hasil, alasan: r.alasan }, latar: null };
    default: return { status: 401, isi: { hasil: "sesi_tidak_berlaku", alasan: SESI_HABIS }, latar: null };
  }
}
