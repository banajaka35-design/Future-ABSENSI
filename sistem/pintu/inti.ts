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
      else await kirim(alat, chat, await putuskan(alat, tg, Number(mesin), Number(keempat), asal === "y"));
      return null;
    }
    if (jenis === "d" && (asal === "y" || asal === "n") && /^\d+$/.test(mesin ?? "")) {
      await kirim(alat, chat, await jawabDaftar(alat, tg, Number(mesin), asal === "y"));
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
    const teks = String(pesan.text).trim();
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
      else await kirim(alat, pesan.chat.id, await rilisGaji(alat, pesan.from?.id, info.hrd, rilis[1], rilis[2]));
      return null;
    }
    const putus = /^\/(setujui|tolak)(?:@\w+)?(?:\s+(\S+))?(?:\s+(\S+))?\s*$/i.exec(teks);
    if (putus) {
      if (putus[3]) await hapusPesan(alat, pesan.chat.id, pesan.message_id);
      await kirim(alat, pesan.chat.id, !/^\d+$/.test(putus[2] ?? "") || !putus[3]
        ? "Cara pakai: /setujui <nomor periode> <PIN> atau /tolak <nomor periode> <PIN>. Nomor periode terlihat di /rilis."
        : await putuskan(alat, pesan.from?.id, Number(putus[2]), null, putus[1].toLowerCase() === "setujui", putus[3]));
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
export async function picuSheets(alat: Alat, chat: number | null, mulai: number, asal: "telegram" | "web"): Promise<void> {
  const waktuFile = new Date(mulai).toISOString();
  let hasil: "terkirim" | "gagal" | "belum_disiapkan";
  let alasan: string | undefined;
  if (!alat.picuSheets) {
    hasil = "belum_disiapkan";
  } else {
    try {
      const r = await alat.picuSheets({ pemicu: asal === "web" ? "file web" : "file Telegram", waktu_file: waktuFile });
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
    await alat.api("pintu_catat_picu", { asal, hasil, alasan: alasan ?? null, waktu_file: waktuFile });
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
  return {
    status: 200,
    hasil: { tanggal: r.tanggal, tutup_buku: r.tutup_buku, hari_ke: r.hari_ke, terkirim, dilewati: r.dilewati ?? [] },
  };
}

// ---------------------------------------------------------------------------
// Unggah cadangan lewat web (paket 5d, docs/unggah-web.md)
// ---------------------------------------------------------------------------

// Perintah /unggah: kode acak, database menyimpan sidiknya saja, tautan berlaku 15 menit.
// ---------------------------------------------------------------------------
// Rilis gaji (paket 8b, docs/rencana-8b.md; PRD v2 celah K5): /pin, /ajukan, persetujuan bos, /rilis dengan PIN
// ---------------------------------------------------------------------------

const BUKAN_HRD_RILIS = "Perintah ini hanya untuk HRD.";

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
    case "perlu_pin_lama": return "PIN sudah ada. Untuk mengganti: /pin <PIN lama> <PIN baru>.";
    case "salah": return "PIN lama salah.";
    case "terkunci": return "Terlalu banyak PIN salah. Coba lagi 1 jam lagi.";
    default: return BUKAN_HRD_RILIS;
  }
}

async function daftarPeriode(alat: Alat, chat: number, tg: number, hrd: boolean, untuk: "ajukan" | "rilis"): Promise<void> {
  if (!hrd) {
    await kirim(alat, chat, BUKAN_HRD_RILIS);
    return;
  }
  const r = await alat.api("pintu_daftar_periode", { telegram_id: tg, untuk });
  const daftar: any[] = r.periode ?? [];
  if (r.hasil !== "ada" || daftar.length === 0) {
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
      await kirim(alat, chat, `${teksRingkasan(x)}\nStatus: ${x.status}. ` + (tunggu
        ? "Menunggu persetujuan bos." + (r.pembangun && x.status === "diajukan" ? `\n${caraPembangun(x.periode_id)}` : "")
        : `Untuk merilis, ketik: /rilis ${x.periode_id} <PIN> (pesan berisi PIN dihapus otomatis).`));
    }
  }
}

async function jawabAjukan(alat: Alat, chat: number, tg: number, periode: number, versi: number, ya: boolean): Promise<void> {
  if (!ya) {
    await kirim(alat, chat, "Tidak jadi diajukan.");
    return;
  }
  const r = await alat.api("pintu_ajukan", { telegram_id: tg, periode_id: periode, versi_gaji: versi });
  switch (r.hasil) {
    case "diajukan": {
      if (!r.perlu_bos) {
        await kirim(alat, chat, `Diajukan.\n${teksRingkasan(r)}\nUntuk merilis, ketik: /rilis ${r.periode_id} <PIN>.`);
        return;
      }
      const bos: number[] = r.bos ?? [];
      const pembangun: number[] = r.pembangun ?? [];
      await kirim(alat, chat, `Diajukan.\n${teksRingkasan(r)}\n` + (bos.length
        ? "Menunggu persetujuan bos."
        : pembangun.length
          ? "Belum ada akun bos yang terdaftar; akun pembangun bisa menyetujui."
          : "Belum ada akun bos yang terdaftar, jadi pengajuan ini belum bisa disetujui.") +
        (pembangun.includes(tg) ? `\n${caraPembangun(r.periode_id)}` : ""));
      for (const b of bos) {
        await kirimAman2(alat, b, `Pengajuan rilis gaji:\n${teksRingkasan(r)}`, {
          reply_markup: { inline_keyboard: [[
            { text: "Setujui", callback_data: `s|y|${r.periode_id}|${r.pengajuan_id}` },
            { text: "Tolak", callback_data: `s|n|${r.periode_id}|${r.pengajuan_id}` },
          ]] },
        });
      }
      // Pembangun (paket 8b-2): teks perintah, bukan tombol, karena persetujuan pembangun wajib PIN.
      for (const b of pembangun) {
        if (b !== tg) await kirimAman2(alat, b, `Pengajuan rilis gaji:\n${teksRingkasan(r)}\n${caraPembangun(r.periode_id)}`, {});
      }
      return;
    }
    case "versi_berubah":
      await kirim(alat, chat, "Angka periode ini sudah dihitung ulang sejak daftar ditampilkan. Ketik /ajukan lagi.");
      return;
    case "tidak_bisa":
      await kirim(alat, chat, `Periode ini tidak bisa diajukan (status: ${r.status ?? "-"}).`);
      return;
    default:
      await kirim(alat, chat, BUKAN_HRD_RILIS);
  }
}

async function kirimAman2(alat: Alat, chat: number, teks: string, tambahan: Record<string, unknown>): Promise<void> {
  try {
    await kirim(alat, chat, teks, tambahan);
  } catch {
    // akun bos yang tidak bisa dihubungi tidak menggagalkan pengajuan
  }
}

// Paket 8b-2 (docs/rencana-8b-2.md): pembangun menyetujui atau menolak dengan PIN lewat perintah.
export function caraPembangun(periode: number): string {
  return `Sebagai pembangun: /setujui ${periode} <PIN> untuk menyetujui, /tolak ${periode} <PIN> untuk menolak ` +
    "(pesan berisi PIN dihapus otomatis).";
}

// Persetujuan rilis: tombol bos (dengan nomor pengajuan, tanpa PIN) atau perintah pembangun (tanpa nomor pengajuan, dengan PIN).
async function putuskan(alat: Alat, tg: number, periode: number, pengajuan: number | null, setuju: boolean,
                        pin?: string): Promise<string> {
  const isi: Record<string, unknown> = { telegram_id: tg, periode_id: periode, setuju };
  if (pengajuan !== null) isi.pengajuan_id = pengajuan;
  if (pin !== undefined) isi.pin = pin;
  const r = await alat.api("pintu_setujui", isi);
  switch (r.hasil) {
    case "disetujui":
    case "ditolak": {
      const kata = r.hasil === "disetujui" ? "disetujui" : "ditolak (kembali ke dihitung)";
      const siapa = r.oleh === "pembangun" ? "Pembangun" : "Bos";
      const lanjut = r.hasil === "disetujui" ? `\nUntuk merilis, ketik: /rilis ${r.periode_id} <PIN>.` : "";
      if (r.pengaju && r.pengaju !== tg) {
        await kirimAman(alat, r.pengaju, `${siapa} ${r.hasil === "disetujui" ? "menyetujui" : "menolak"} pengajuan rilis:\n` +
          teksRingkasan(r) + lanjut);
        return `Pengajuan ${kata}.\n${teksRingkasan(r)}`;
      }
      return `Pengajuan ${kata}.\n${teksRingkasan(r)}` + (r.pengaju === tg ? lanjut : "");
    }
    case "tidak_berlaku":
      return "Pengajuan ini tidak berlaku lagi (sudah diputuskan, dihitung ulang, ada pengajuan baru, atau periode belum diajukan).";
    case "belum_ada_pin": return "Belum ada PIN. Buat dulu dengan /pin <PIN baru 6 angka>.";
    case "pin_salah": return "PIN salah.";
    case "terkunci": return "Terlalu banyak PIN salah. Coba lagi 1 jam lagi.";
    case "pakai_tombol": return "Akun bos menyetujui lewat tombol Setujui/Tolak di pesan pengajuan.";
    default: return "Persetujuan rilis hanya untuk akun bos atau pembangun.";
  }
}

async function rilisGaji(alat: Alat, tg: number, hrd: boolean, nomor: string, pin?: string): Promise<string> {
  if (!hrd) return BUKAN_HRD_RILIS;
  if (!/^\d+$/.test(nomor) || !pin) return "Cara pakai: /rilis untuk melihat periode; /rilis <nomor periode> <PIN> untuk merilis.";
  const r = await alat.api("pintu_rilis", { telegram_id: tg, periode_id: Number(nomor), pin });
  switch (r.hasil) {
    case "dirilis": return `Gaji DIRILIS.\n${teksRingkasan(r)}\nPeriode ini tidak dihitung ulang lagi.`;
    case "belum_ada_pin": return "Belum ada PIN. Buat dulu dengan /pin <PIN baru 6 angka>.";
    case "pin_salah": return "PIN salah.";
    case "terkunci": return "Terlalu banyak PIN salah. Coba lagi 1 jam lagi.";
    case "belum_disetujui": return "Periode ini belum disetujui bos.";
    case "versi_berubah": return "Angka periode ini sudah dihitung ulang sejak diajukan. Ajukan lagi dengan /ajukan.";
    case "tidak_bisa": return `Periode ini tidak bisa dirilis (status: ${r.status ?? "tidak ada"}).`;
    default: return BUKAN_HRD_RILIS;
  }
}

// ---------------------------------------------------------------------------
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
