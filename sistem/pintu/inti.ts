// Inti pintu Telegram (paket 5b, docs/pintu-telegram.md; pemberitahuan segera dan pengingat paket 5c,
// docs/pemberitahuan-segera.md; unggah lewat web paket 5d, docs/unggah-web.md).
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
}

export const BATAS_UKURAN = 20 * 1024 * 1024; // batas unduh file lewat bot Telegram
export const BATAS_KERJA_MS = 110_000; // Edge Function gratis hidup paling lama 150 detik
export const BATAS_UKURAN_WEB = 50 * 1024 * 1024; // batas unggah lewat web (paket 5d)

const API_BOLEH = new Set([
  "pintu_pesan", "pintu_tunda", "pintu_ambil_tunda", "pintu_terima_file", "pintu_kerjakan",
  "pintu_pemberitahuan_ambil", "pintu_pengingat", "pintu_pemberitahuan_hasil",
  "pintu_buat_tautan", "pintu_periksa_tautan", "pintu_terima_web", "pintu_status_kiriman",
]);
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
    if (/^\/unggah(@\w+)?\s*$/i.test(String(pesan.text).trim())) {
      await kirim(alat, pesan.chat.id, await buatTautan(alat, pesan.from?.id, info.hrd), {
        link_preview_options: { is_disabled: true },
      });
      return null;
    }
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
      await kirimPemberitahuan(alat, chat); // file rusak Excel atau format tidak dikenal: tingkat segera (U14)
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

export async function kerjakanAntrean(alat: Alat, chat: number | null, mulai: number): Promise<void> {
  while (alat.sekarang() - mulai < BATAS_KERJA_MS) {
    const r = await alat.api("pintu_kerjakan");
    if (r.kosong) return;
    if (r.sibuk) {
      await kirimAman(alat, chat, "Hitungan lain sedang berjalan; periode ini akan dihitung sesudahnya.");
      return;
    }
    const p = r.periode;
    if (r.hasil?.galat) {
      await kirimAman(alat, chat, `Periode ${p.awal} s.d. ${p.akhir} gagal dihitung: ${r.hasil.galat}`);
    } else {
      const x = r.hasil;
      await kirimAman(
        alat,
        chat,
        `Periode ${p.awal} s.d. ${p.akhir}: ${angka(x.orang)} orang, gaji bersih ${rp(x.bersih)}. ` +
          (x.bisa_diajukan ? "Bisa diajukan." : "Belum bisa diajukan.") +
          (x.segera > 0 ? ` ${angka(x.segera)} pemberitahuan penting perlu diperiksa.` : ""),
      );
    }
    await kirimPemberitahuan(alat, chat); // sesudah setiap periode, bukan menunggu seluruh antrean (U14)
    if (r.sisa === 0) return;
  }
  await kirimAman(alat, chat, "Sebagian periode masih di antrean; dihitung saat pesan berikutnya masuk.");
}

// ---------------------------------------------------------------------------
// Pemberitahuan tingkat segera (paket 5c, U14)
// ---------------------------------------------------------------------------

export const BATAS_PESAN = 3800; // Telegram menerima paling banyak 4096 karakter per pesan

// Judul dan langkah yang perlu dilakukan HRD, per jenis kejadian (PRD bagian 9).
export const JENIS_SEGERA: Record<string, { judul: string; langkah: string }> = {
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
  const chat: number = Number(r.telegram_id);
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
      await kerjakanAntrean(alat, chat, mulai);
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
  return { status: 200, isi: r, latar: null };
}
