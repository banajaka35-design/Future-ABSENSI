// Uji pintu Telegram (paket 5b, kasus T1-T8 di docs/pintu-telegram.md; paket 5c, kasus N1-N9 dan P1-P7 di
// docs/pemberitahuan-segera.md; paket 5d, kasus W1-W11 di docs/unggah-web.md; paket 5e, kasus E di
// docs/login-email.md) dengan pesan Telegram tiruan,
// file simulasi Pabrik A, dan Postgres sementara. Database dipanggil sebagai peran `pintu`, seperti Edge Function.
// Pemakaian: DB_URL=... node --test sistem/pintu/uji_pintu.ts  (database sudah berisi struktur dan karyawan Pabrik A,
// periode, tanpa tap; disiapkan oleh sistem/uji/uji_pintu.sh)
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import { PESAN, urai } from "../urai/urai.ts";
import {
  apiBoleh, BATAS_PESAN, JENIS_SEGERA, susunPesanSegera, tanganiPengingat, tanganiPermintaan, webMintaKode, webPeriksa,
  webStatus, webTukarKode, webUnggah, type Alat,
} from "./inti.ts";

const DB = process.env.DB_URL!;
const RAHASIA = "rahasia-uji";
const HRD = 111;
const BUKAN = 222;
const PEMBANGUN = 444; // penerima pemberitahuan (paket 5c)
const NONAKTIF = 555;

function psql(sql: string, sebagaiPintu = false): string {
  const r = spawnSync("psql", [DB, "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1"], {
    input: (sebagaiPintu ? "set role pintu;\n" : "") + sql,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout.trim();
}
const nilai = (sql: string) => psql(sql);

const fileSim = (nama: string) => gunzipSync(readFileSync(`data/simulasi/A/mesin/${nama}.gz`));
const BERKAS: Record<string, Uint8Array> = {
  F_MA1: fileSim("A_p1_MA1.csv"),
  F_MA2: fileSim("A_p1_MA2.csv"),
  // T4: file yang dibuka lalu disimpan di Excel; No.ID panjang menjadi notasi ilmiah.
  F_EXCEL: new TextEncoder().encode(
    fileSim("A_p1_MA2.csv").toString("utf8").split("\r\n").map((b, i) => {
      if (i === 0 || !b) return b;
      const k = b.split(",");
      k[1] = "\"1,98E+17\"";
      return k.join(",");
    }).join("\r\n"),
  ),
  F_TEKS: new TextEncoder().encode("halo, ini bukan file mesin\nbaris kedua\n"),
};

const terkirim: { metode: string; isi: any }[] = [];
const diunduh: string[] = [];
const alat: Alat = {
  async api(nama, isi) {
    assert.ok(apiBoleh(nama));
    const arg = isi === undefined ? "" : `$j$${JSON.stringify(isi)}$j$::jsonb`;
    const keluar = psql(`select api.${nama}(${arg});`, true);
    return keluar === "" ? null : JSON.parse(keluar);
  },
  async telegram(metode, isi) {
    terkirim.push({ metode, isi });
    if (metode === "getFile") return { file_path: isi.file_id };
    return {};
  },
  async unduh(jalur) {
    diunduh.push(jalur);
    return BERKAS[jalur];
  },
  urai,
  sekarang: () => Date.now(),
  tidur: async () => {},
};

function dokumen(updateId: number, dari: number, fileId: string, nama: string, caption?: string) {
  return JSON.stringify({
    update_id: updateId,
    message: { message_id: updateId, date: 1771635600, chat: { id: dari }, from: { id: dari },
               document: { file_id: fileId, file_name: nama, file_size: BERKAS[fileId].length }, caption },
  });
}
async function kirimUpdate(badan: string, rahasia = RAHASIA) {
  const awal = terkirim.length;
  const r = await tanganiPermintaan("POST", rahasia, badan, RAHASIA, alat);
  if (r.latar) await r.latar;
  return { status: r.status, pesan: terkirim.slice(awal).filter((t) => t.metode === "sendMessage").map((t) => t.isi) };
}

test("persiapan: HRD 111 terdaftar, 222 bukan HRD, 444 pembangun, 555 HRD nonaktif", () => {
  psql(`insert into induk.pengguna (telegram_id, peran, aktif) values (${HRD}, 'hrd', true), (${BUKAN}, 'karyawan', true),
        (${PEMBANGUN}, 'pembangun', true), (${NONAKTIF}, 'hrd', false);`);
});

// Pesan pemberitahuan segera untuk satu akun, dari daftar pesan satu proses.
const segera = (pesan: any[], tg: number) =>
  pesan.filter((p) => p.chat_id === tg && /^PEMBERITAHUAN SEGERA/.test(p.text)).map((p) => p.text as string);
// U14: setiap kejadian segera yang ada sekarang sudah tercatat terkirim.
const belumTerkirim = () =>
  nilai(`select count(*) from fakta.kejadian_segera() k
         where not exists (select 1 from fakta.pemberitahuan b where b.kunci = k.kunci and b.status = 'terkirim')`);
const sudahDikirim = new Set<string>();
function catatBaris(teks: string[]) {
  const baru = teks.flatMap((t) => t.split("\n").filter((b) => b.startsWith("• ")));
  for (const b of baru) assert.ok(!sudahDikirim.has(b), `dikirim dua kali: ${b}`);
  for (const b of baru) sudahDikirim.add(b);
  return baru.length;
}

test("T8: kode rahasia salah ditolak tanpa menyimpan apa pun", async () => {
  const r = await kirimUpdate(dokumen(1, HRD, "F_MA1", "A_p1_MA1.csv", "MA1"), "salah");
  assert.equal(r.status, 401);
  assert.equal(nilai("select count(*) from fakta.pesan_telegram"), "0");
});

test("T1: file sah diterima, disimpan, dan periode terkena dihitung", async () => {
  const mulai = Date.now();
  const r = await kirimUpdate(dokumen(1, HRD, "F_MA1", "A_p1_MA1.csv", "mesin ma1"));
  assert.equal(r.status, 200);
  assert.match(r.pesan[0].text, /diterima \(mesin MA1\), sedang diproses/);
  const harap = urai(new TextDecoder().decode(BERKAS.F_MA1), { tanggal_kirim: "2026-02-21" }).tap.length;
  assert.equal(nilai("select hasil || '/' || nomor_pesan || '/' || mesin from fakta.kiriman_file where nama_file = 'A_p1_MA1.csv'"),
               "diterima/1/MA1");
  assert.equal(nilai("select count(*) from fakta.tap_mentah"), String(harap));
  assert.equal(nilai("select count(*) from fakta.antrean_kerja where status <> 'selesai'"), "0");
  assert.ok(Number(nilai("select count(*) from fakta.antrean_kerja where status = 'selesai'")) >= 1);
  assert.equal(nilai(`select count(*) from hitung.versi_terakhir v join fakta.periode p on p.id = v.periode_id
                      where p.tanggal_awal = '2026-01-21' and v.jenis in ('baca_tap', 'hitung_gaji')`), "2");
  assert.ok(r.pesan.some((p) => /Periode 2026-01-21 s\.d\. 2026-02-20: [\d.]+ orang, gaji bersih Rp/.test(p.text)), JSON.stringify(r.pesan));
  console.log(`  T1 selesai dalam ${Date.now() - mulai} ms; ${r.pesan.length} pesan: ${r.pesan.map((p) => p.text.slice(0, 80)).join(" | ")}`);
  // N6 / U14: anomali segera dari file ini terkirim ke HRD dan pembangun dalam proses yang sama.
  const keHrd = segera(r.pesan, HRD);
  assert.ok(keHrd.length >= 1, "tidak ada pemberitahuan segera");
  assert.deepEqual(segera(r.pesan, PEMBANGUN), keHrd);
  assert.equal(r.pesan.filter((p) => p.chat_id === BUKAN || p.chat_id === NONAKTIF).length, 0);
  assert.equal(belumTerkirim(), "0");
  console.log(`  N6: ${catatBaris(keHrd)} kejadian segera terkirim ke 2 akun`);
});

test("T3: update_id yang sama diabaikan tanpa balasan", async () => {
  const r = await kirimUpdate(dokumen(1, HRD, "F_MA1", "A_p1_MA1.csv", "MA1"));
  assert.deepEqual(r.pesan, []);
  assert.equal(nilai("select count(*) from fakta.kiriman_file"), "1");
});

test("T2: file yang sama dikirim lagi ditolak sebagai dobel", async () => {
  const tap = nilai("select count(*) from fakta.tap_mentah");
  const r = await kirimUpdate(dokumen(2, HRD, "F_MA1", "salinan.csv", "MA1"));
  assert.match(r.pesan.at(-1).text, /ditolak: File yang sama sudah diterima sebelumnya/);
  assert.equal(nilai("select count(*) from fakta.tap_mentah"), tap);
  assert.deepEqual(segera(r.pesan, HRD), [], "N9: file dobel bukan tingkat segera");
});

test("T4: file rusak karena Excel ditolak dengan alasan", async () => {
  const tap = nilai("select count(*) from fakta.tap_mentah");
  const r = await kirimUpdate(dokumen(3, HRD, "F_EXCEL", "rusak.csv", "MA2"));
  assert.match(r.pesan.find((p) => p.chat_id === HRD && /ditolak:/.test(p.text)).text, /ditolak: .*Excel/);
  assert.equal(nilai("select hasil from fakta.kiriman_file where nama_file = 'rusak.csv'"), "ditolak");
  assert.equal(nilai("select count(*) from fakta.tap_mentah"), tap);
  // N4: pengirim dapat balasan, semua penerima dapat pemberitahuan segera dalam proses yang sama.
  for (const tg of [HRD, PEMBANGUN]) {
    const t = segera(r.pesan, tg);
    assert.equal(t.length, 1);
    assert.match(t[0], /Excel/);
    assert.match(t[0], /rusak\.csv \(mesin MA2/);
  }
  catatBaris(segera(r.pesan, HRD));
  assert.equal(belumTerkirim(), "0");
});

test("T5: file bukan file mesin ditolak", async () => {
  const r = await kirimUpdate(dokumen(4, HRD, "F_TEKS", "catatan.txt", "MA1"));
  assert.match(r.pesan.find((p) => /ditolak:/.test(p.text)).text, /ditolak: Format file tidak dikenal/);
  // N5: format tidak dikenal juga tingkat segera.
  assert.match(segera(r.pesan, PEMBANGUN)[0], /format file tidak dikenal[\s\S]*catatan\.txt/);
  catatBaris(segera(r.pesan, HRD));
  assert.equal(belumTerkirim(), "0");
});

test("T6: pengirim bukan HRD ditolak; file tidak diunduh dan tidak dicatat", async () => {
  const unduhSebelum = diunduh.length;
  const r = await kirimUpdate(dokumen(5, BUKAN, "F_MA2", "dari_orang_lain.csv", "MA2"));
  assert.match(r.pesan[0].text, /belum terdaftar untuk mengirim file/);
  assert.equal(diunduh.length, unduhSebelum);
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'dari_orang_lain.csv'"), "0");
});

test("T7: tanpa kode mesin -> tombol pilihan; tombol ditekan -> diproses; tekan lagi -> tidak diproses dua kali", async () => {
  const r = await kirimUpdate(dokumen(6, HRD, "F_MA2", "A_p1_MA2.csv"));
  assert.match(r.pesan[0].text, /dari mesin mana/);
  assert.deepEqual(r.pesan[0].reply_markup.inline_keyboard[0].map((t: any) => t.text), ["MA1", "MA2"]);
  const tekan = (u: number) => JSON.stringify({
    update_id: u, callback_query: { id: `cb${u}`, data: "m|6|MA2", from: { id: HRD }, message: { chat: { id: HRD } } },
  });
  const r2 = await kirimUpdate(tekan(7));
  assert.match(r2.pesan[0].text, /A_p1_MA2.csv diterima \(mesin MA2\)/);
  assert.equal(nilai("select hasil || '/' || mesin || '/' || nomor_pesan from fakta.kiriman_file where nama_file = 'A_p1_MA2.csv'"),
               "diterima/MA2/6");
  // N2: periode 1 dihitung ulang dengan file MA2; kejadian yang sudah dikirim tidak dikirim lagi.
  catatBaris(segera(r2.pesan, HRD));
  assert.equal(belumTerkirim(), "0");
  assert.equal(nilai("select count(*) from fakta.pemberitahuan group by kunci having count(*) > 1"), "");
  const r3 = await kirimUpdate(tekan(8));
  assert.match(r3.pesan[0].text, /sudah diproses sebelumnya/);
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'A_p1_MA2.csv'"), "1");
});

test("akun pembangun boleh mengirim file seperti HRD (keputusan pemilik)", async () => {
  psql(`insert into induk.pengguna (telegram_id, peran) values (333, 'pembangun');`);
  const r = await kirimUpdate(dokumen(10, 333, "F_TEKS", "dari_pembangun.txt", "MA1"));
  assert.match(r.pesan[0].text, /diterima \(mesin MA1\), sedang diproses/);
  assert.equal(nilai("select hasil from fakta.kiriman_file where nama_file = 'dari_pembangun.txt'"), "ditolak");
});

test("pesan teks dari HRD dijawab petunjuk", async () => {
  const r = await kirimUpdate(JSON.stringify({ update_id: 9, message: { message_id: 9, chat: { id: HRD }, from: { id: HRD }, text: "halo" } }));
  assert.match(r.pesan[0].text, /Kirim file ekspor/);
});

// ---------------------------------------------------------------------------
// Paket 5c: isi pesan dan pengingat
// ---------------------------------------------------------------------------

test("teks penolakan di pembaca file cocok dengan awalan yang dikenali database", () => {
  assert.equal(nilai(`select fakta.jenis_tolak_segera($t$${PESAN.idRusakExcel}$t$)`), "file_rusak_excel");
  assert.equal(nilai(`select fakta.jenis_tolak_segera($t$${PESAN.formatTidakDikenal}$t$)`), "format_tidak_dikenal");
  assert.equal(nilai(`select fakta.jenis_tolak_segera($t$${PESAN.tanggalCampur}$t$) is null`), "t");
});

test("N1: ketujuh jenis kejadian punya judul dan langkah di pesan; pesan panjang dipecah", () => {
  const jenis = ["file_rusak_excel", "format_tidak_dikenal", "file_terpotong", "tap_terakhir_lama",
                 "jam_mesin_melenceng", "tanpa_tap_massal", "belum_terdaftar_mesin"];
  const kejadian = jenis.map((j, i) => ({ id: i, jenis: j, isi: { keterangan: `ket ${j}`, nama_file: "f.csv", mesin: "MA1", kiriman_id: i } }));
  const [teks] = susunPesanSegera(kejadian);
  assert.match(teks, /^PEMBERITAHUAN SEGERA \(7 kejadian\)/);
  for (const j of jenis) {
    assert.ok(teks.includes(JENIS_SEGERA[j].judul), j);
    assert.ok(teks.includes(JENIS_SEGERA[j].langkah), j);
  }
  const banyak = Array.from({ length: 300 }, (_, i) => ({ id: i, jenis: "belum_terdaftar_mesin",
    isi: { keterangan: `Karyawan baru ${10000 + i} tanpa tap di 2 hari kerja pertamanya; belum didaftar di mesin?` } }));
  const pecahan = susunPesanSegera(banyak);
  assert.ok(pecahan.length > 1);
  for (const p of pecahan) assert.ok(p.length <= BATAS_PESAN, String(p.length));
  assert.equal(pecahan.join("\n").split("\n").filter((b) => b.startsWith("• ")).length, 300);
});

const RAHASIA_PENGINGAT = "rahasia-pengingat";
async function picuPengingat(isi: unknown, rahasia = RAHASIA_PENGINGAT) {
  const awal = terkirim.length;
  const r = await tanganiPengingat("POST", rahasia, JSON.stringify(isi), RAHASIA_PENGINGAT, alat);
  return { ...r, pesan: terkirim.slice(awal).filter((t) => t.metode === "sendMessage").map((t) => t.isi) };
}

test("P7: kode rahasia pengingat salah ditolak tanpa catatan", async () => {
  const sebelum = nilai("select count(*) from fakta.pemberitahuan where tingkat = 'pengingat'");
  assert.equal((await picuPengingat({ tanggal: "2026-03-21" }, "salah")).status, 401);
  assert.equal((await picuPengingat({ tanggal: "21-03-2026" })).status, 400);
  assert.equal(nilai("select count(*) from fakta.pemberitahuan where tingkat = 'pengingat'"), sebelum);
});

test("P1, P2: pengingat hari ke-1 ke HRD dan pembangun untuk mesin yang belum mengirim; sekali saja", async () => {
  // Semua file uji hanya sampai 20 Feb, jadi untuk tutup buku 20 Mar kedua mesin belum mengirim.
  const r = await picuPengingat({ tanggal: "2026-03-21" });
  assert.equal(r.status, 200);
  assert.equal(r.hasil.hari_ke, 1);
  assert.deepEqual(r.pesan.map((p) => p.chat_id).sort(), [HRD, 333, PEMBANGUN]);
  assert.match(r.pesan[0].text, /^PENGINGAT \(hari ke-1 sesudah tutup buku 20-03-2026\): file mesin MA1, MA2 untuk periode 21-02-2026 s\.d\. 20-03-2026 belum masuk/);
  assert.equal(nilai("select string_agg(distinct status, ',') from fakta.pemberitahuan where tingkat = 'pengingat'"), "terkirim");
  const lagi = await picuPengingat({ tanggal: "2026-03-21" });
  assert.deepEqual(lagi.pesan, []);
});

test("P3: hari ke-2 tanpa akun bos: HRD diingatkan, bos dicatat dilewati", async () => {
  const r = await picuPengingat({ tanggal: "2026-03-22" });
  assert.deepEqual(r.pesan.map((p) => p.chat_id).sort(), [HRD, 333, PEMBANGUN]);
  assert.match(r.pesan[0].text, /hari ke-2.*bos juga diberi tahu/);
  assert.deepEqual(r.hasil.dilewati, [{ kepada: "bos", status: "dilewati_tanpa_akun_bos", mesin: ["MA1", "MA2"] }]);
});

// ---------------------------------------------------------------------------
// Paket 5d: unggah lewat web (kasus W1-W9, W11 di docs/unggah-web.md)
// ---------------------------------------------------------------------------

alat.alamatUnggah = "https://halaman.uji/unggah/";
const sha256 = (t: string) => createHash("sha256").update(t).digest("hex");
const kodeDari = (teks: string) => /#kode=([0-9a-f]{64})$/.exec(teks)?.[1] ?? "";
let KODE = "";

test("W2: /unggah dari akun bukan HRD ditolak tanpa tautan", async () => {
  const r = await kirimUpdate(JSON.stringify({ update_id: 801, message: { message_id: 801, chat: { id: BUKAN }, from: { id: BUKAN }, text: "/unggah" } }));
  assert.match(r.pesan[0].text, /belum terdaftar/);
  assert.equal(nilai("select count(*) from fakta.tautan_unggah"), "0");
});

test("W1: /unggah dari HRD -> tautan 15 menit; database hanya menyimpan sidik kode", async () => {
  const r = await kirimUpdate(JSON.stringify({ update_id: 802, message: { message_id: 802, chat: { id: HRD }, from: { id: HRD }, text: "/unggah" } }));
  KODE = kodeDari(r.pesan[0].text);
  assert.match(r.pesan[0].text, /^Tautan unggah file mesin \(berlaku 15 menit/);
  assert.ok(r.pesan[0].text.includes("https://halaman.uji/unggah/#kode="));
  assert.equal(r.pesan[0].link_preview_options.is_disabled, true);
  assert.equal(KODE.length, 64);
  assert.equal(nilai(`select count(*) from fakta.tautan_unggah where sidik = '${sha256(KODE)}'`), "1");
  assert.equal(nilai(`select count(*) from fakta.tautan_unggah where sidik = '${KODE}'`), "0");
  const p = await webPeriksa(alat, KODE);
  assert.equal(p.status, 200);
  assert.deepEqual(p.isi.mesin, ["MA1", "MA2"]);
});

test("W3: kode palsu ditolak; file tidak diproses", async () => {
  assert.equal((await webPeriksa(alat, "0".repeat(64))).status, 401);
  assert.equal((await webPeriksa(alat, "bukan-kode")).status, 401);
  const r = await webUnggah(alat, "0".repeat(64), "palsu.csv", fileSim("A_p2_MA1.csv"), "MA1");
  assert.equal(r.status, 401);
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'palsu.csv'"), "0");
});

async function unggah(nama: string, isi: Uint8Array, mesin: string, kode = KODE, a: Alat = alat) {
  const awal = terkirim.length;
  const r = await webUnggah(a, kode, nama, isi, mesin);
  if (r.latar) await r.latar;
  return { ...r, pesan: terkirim.slice(awal).filter((t) => t.metode === "sendMessage").map((t) => t.isi) };
}

test("W8: file rusak Excel lewat web ditolak; pemberitahuan segera ke semua penerima", async () => {
  const r = await unggah("excel_web.csv", BERKAS.F_EXCEL, "MA2");
  assert.equal(r.status, 200);
  assert.equal(r.isi.hasil, "ditolak");
  assert.match(r.isi.alasan, /Excel/);
  for (const tg of [HRD, 333, PEMBANGUN]) assert.match(segera(r.pesan, tg)[0] ?? "", /excel_web\.csv/, String(tg));
  assert.equal(nilai("select asal from fakta.kiriman_file where nama_file = 'excel_web.csv'"), "web");
  assert.equal(belumTerkirim(), "0");
});

test("W7: file yang sudah diterima lewat bot, diunggah lagi lewat web -> ditolak dobel", async () => {
  const r = await unggah("A_p1_MA1_lagi.csv", BERKAS.F_MA1, "MA1");
  assert.equal(r.isi.hasil, "ditolak");
  assert.match(r.isi.alasan, /sudah diterima sebelumnya/);
});

test("W6, W9: file sah lewat web (tautan yang sama) diterima, dihitung, status terbaca; ringkasan ke Telegram", async () => {
  const r = await unggah("A_p2_MA1.csv", fileSim("A_p2_MA1.csv"), "MA1");
  assert.equal(r.isi.hasil, "diterima", JSON.stringify(r.isi));
  assert.ok(r.isi.jumlah_tap > 0);
  assert.equal(nilai(`select asal || '/' || (pengirim = (select id from induk.pengguna where telegram_id = ${HRD}))
                      from fakta.kiriman_file where id = ${r.isi.kiriman_id}`), "web/true");
  const s = await webStatus(alat, KODE, r.isi.kiriman_id);
  assert.equal(s.status, 200);
  assert.equal(s.isi.selesai, true);
  assert.ok(s.isi.periode.length >= 1 && s.isi.periode.every((p: any) => p.status === "selesai" && p.hasil.orang > 0));
  assert.ok(r.pesan.some((p) => p.chat_id === HRD && /diunggah lewat web \(mesin MA1\)/.test(p.text)));
  assert.ok(r.pesan.some((p) => p.chat_id === HRD && /^Periode .*gaji bersih Rp/.test(p.text)));
  assert.equal(belumTerkirim(), "0");
});

test("cadangan: Telegram gagal total -> file web tetap diterima dan dihitung", async () => {
  const mati: Alat = { ...alat, async telegram() { throw new Error("Telegram tidak bisa dihubungi"); } };
  const r = await unggah("A_p2_MA2.csv", fileSim("A_p2_MA2.csv"), "MA2", KODE, mati);
  assert.equal(r.isi.hasil, "diterima");
  const s = await webStatus(alat, KODE, r.isi.kiriman_id);
  assert.equal(s.isi.selesai, true);
  assert.ok(s.isi.periode.every((p: any) => p.status === "selesai"));
  // pemberitahuan yang gagal terkirim tercatat gagal, tidak hilang diam-diam
  assert.equal(nilai("select count(*) from fakta.pemberitahuan where status = 'akan_dikirim'"), "0");
});

test("W11: status kiriman dengan tautan akun lain ditolak", async () => {
  const r = await kirimUpdate(JSON.stringify({ update_id: 803, message: { message_id: 803, chat: { id: 333 }, from: { id: 333 }, text: "/unggah" } }));
  const lain = kodeDari(r.pesan[0].text);
  const id = Number(nilai("select max(id) from fakta.kiriman_file where asal = 'web'"));
  assert.equal((await webStatus(alat, lain, id)).status, 404);
});

test("W4: tautan lewat 15 menit ditolak", async () => {
  psql(`update fakta.tautan_unggah set berlaku_sampai = now() - interval '1 minute' where sidik = '${sha256(KODE)}'`);
  assert.equal((await webPeriksa(alat, KODE)).status, 401);
  const r = await webUnggah(alat, KODE, "telat.csv", fileSim("A_p3_MA1.csv"), "MA1");
  assert.equal(r.status, 401);
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'telat.csv'"), "0");
});

// ---------------------------------------------------------------------------
// Paket 5e: masuk lewat kode email (kasus E1-E8, E11 di docs/login-email.md); pengirim email tiruan
// ---------------------------------------------------------------------------

const surat: { ke: string; judul: string; isi: string }[] = [];
const alatEmail: Alat = { ...alat, async email(ke, judul, isi) { surat.push({ ke, judul, isi }); } };
const kodeSurat = () => /\b(\d{6})\b/.exec(surat.at(-1)?.isi ?? "")?.[1] ?? "";

test("E (persiapan): email untuk HRD 111 dan akun HRD tanpa Telegram", () => {
  psql(`update induk.pengguna set email = 'hrd111@contoh.id' where telegram_id = ${HRD};
        insert into induk.pengguna (peran, email) values ('hrd', 'tanpa.tg@contoh.id');`);
});

test("jalur email belum disiapkan (tanpa pengirim) -> 503", async () => {
  assert.equal((await webMintaKode(alat, "hrd111@contoh.id")).status, 503);
});

test("E1, E2: jawaban halaman sama untuk email terdaftar dan tidak; hanya yang terdaftar dikirimi kode", async () => {
  const a = await webMintaKode(alatEmail, "HRD111@contoh.id");
  const b = await webMintaKode(alatEmail, "orang.luar@contoh.id");
  assert.equal(a.status, 200);
  assert.deepEqual(b, a);
  assert.equal(surat.length, 1);
  assert.equal(surat[0].ke, "hrd111@contoh.id");
  assert.match(kodeSurat(), /^\d{6}$/);
  assert.ok(surat[0].judul.includes(kodeSurat()));
  assert.equal(nilai(`select count(*) from fakta.kode_email where sidik = '${sha256(`hrd111@contoh.id:${kodeSurat()}`)}'`), "1");
});

test("E3: kode benar -> kode tautan; tautan itu dipakai untuk unggah seperti 5d", async () => {
  const salah = await webTukarKode(alatEmail, "hrd111@contoh.id", kodeSurat() === "000000" ? "111111" : "000000");
  assert.equal(salah.status, 401);
  assert.match(salah.isi.alasan, /Sisa 4/);
  const r = await webTukarKode(alatEmail, "hrd111@contoh.id", kodeSurat());
  assert.equal(r.status, 200);
  assert.match(r.isi.kode, /^[0-9a-f]{64}$/);
  assert.equal((await webPeriksa(alat, r.isi.kode)).status, 200);
  const u = await unggah("excel_email.csv", BERKAS.F_EXCEL, "MA2", r.isi.kode);
  assert.equal(u.isi.hasil, "ditolak");
  assert.match(u.isi.alasan, /Excel/);
  // E6: kode email dipakai lagi
  assert.equal((await webTukarKode(alatEmail, "hrd111@contoh.id", kodeSurat())).status, 401);
});

test("E4: salah 5 kali -> terkunci, kode benar ditolak", async () => {
  await webMintaKode(alatEmail, "hrd111@contoh.id");
  const benar = kodeSurat();
  const keliru = benar === "000000" ? "111111" : "000000";
  for (let i = 0; i < 4; i++) assert.match((await webTukarKode(alatEmail, "hrd111@contoh.id", keliru)).isi.alasan, /Kode salah/);
  assert.match((await webTukarKode(alatEmail, "hrd111@contoh.id", keliru)).isi.alasan, /tidak berlaku/);
  assert.equal((await webTukarKode(alatEmail, "hrd111@contoh.id", benar)).status, 401);
});

test("E8: permintaan ke-4 dalam 15 menit tidak mengirim email; jawaban halaman tetap sama", async () => {
  const sebelum = surat.length; // sudah 2 kode untuk email ini
  const r3 = await webMintaKode(alatEmail, "hrd111@contoh.id");
  const r4 = await webMintaKode(alatEmail, "hrd111@contoh.id");
  assert.equal(surat.length, sebelum + 1);
  assert.deepEqual(r4, r3);
});

test("E11: akun tanpa ID Telegram masuk lewat email dan mengunggah file sah; tidak ada pesan Telegram ke akun itu", async () => {
  await webMintaKode(alatEmail, "tanpa.tg@contoh.id");
  const t = await webTukarKode(alatEmail, "tanpa.tg@contoh.id", kodeSurat());
  assert.equal(t.status, 200);
  const u = await unggah("A_p3_MA2.csv", fileSim("A_p3_MA2.csv"), "MA2", t.isi.kode);
  assert.equal(u.isi.hasil, "diterima", JSON.stringify(u.isi));
  assert.equal(nilai(`select asal || '/' || (select email from induk.pengguna where id = pengirim)
                      from fakta.kiriman_file where id = ${u.isi.kiriman_id}`), "web/tanpa.tg@contoh.id");
  const s = await webStatus(alat, t.isi.kode, u.isi.kiriman_id);
  assert.equal(s.isi.selesai, true);
  assert.ok(!u.pesan.some((p) => p.chat_id === null || p.chat_id === 0 || Number.isNaN(p.chat_id)));
  assert.ok(!u.pesan.some((p) => /diunggah lewat web/.test(p.text)), "ringkasan tidak dikirim ke akun tanpa Telegram");
});

test("masukan rusak: kode bukan 6 angka, email tidak sah -> 400", async () => {
  assert.equal((await webTukarKode(alatEmail, "hrd111@contoh.id", "12ab56")).status, 400);
  assert.equal((await webMintaKode(alatEmail, "bukan-email")).status, 400);
});
