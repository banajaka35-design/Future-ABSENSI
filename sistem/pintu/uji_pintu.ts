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
import { PESAN, urai, uraiBerkas } from "../urai/urai.ts";
import {
  apiBoleh, BATAS_PESAN, JENIS_SEGERA, MENU, PESAN_HANYA_PRIBADI, rapikanPerintah, susunPesanSegera, TANYA_ID, TANYA_PIN,
  TOMBOL_TETAP, TANYA_PERINTAH, TANYA_TOLAK_KEBERATAN, tulisBukti, webHrd, webMasukHrd, CARA_PERINTAH, CARA_KASBON, bacaUang, bacaTanggal, bacaPerintah, tulisTanggal, susunPesanGaji, susunTotalLengkap, rupiah as rupiahBot, BATAS_PESAN as BATAS, tanganiPengingat, tanganiPermintaan, webMintaKode, webPeriksa,
  webStatus, webTukarKode, webUnggah, type Alat, teksPeriodeBaru,
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
  // Paket F1: data MA2 periode 1 yang sama dalam file Excel .xls (sistem/urai/contoh/, dibuat dari data simulasi).
  F_MA2_XLS: new Uint8Array(readFileSync("sistem/urai/contoh/A_p1_MA2.xls")),
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
  // Paket 6e: file MA1 periode 1 dengan satu baris dibuang (sidik berbeda, semua tap sudah ada di gudang).
  F_KURANG_1: kurangiBaris(fileSim("A_p1_MA1.csv"), 2),
  F_KURANG_2: kurangiBaris(fileSim("A_p1_MA1.csv"), 3),
  // Paket 8b: file MA1 periode 1 lain lagi (sidik berbeda) untuk periode yang sudah dirilis.
  F_KURANG_3: kurangiBaris(fileSim("A_p1_MA1.csv"), 4),
};
function kurangiBaris(isi: Uint8Array, ke: number): Uint8Array {
  const baris = new TextDecoder().decode(isi).split("\r\n");
  baris.splice(ke, 1);
  return new TextEncoder().encode(baris.join("\r\n"));
}

const terkirim: { metode: string; isi: any }[] = [];
const diunduh: string[] = [];
const dipicu: { pemicu: string; waktu_file: string }[] = []; // panggilan pemicu Isi Sheets (paket 6e)
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
  urai: uraiBerkas,
  sekarang: () => Date.now(),
  tidur: async () => {},
  async picuSheets(m) {
    dipicu.push(m);
    return { ok: true };
  },
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
  assert.ok(r.pesan.some((p) => /Periode 2026-01-21 s\.d\. 2026-02-20: [\d.]+ orang, gaji bersih Rp[\d.]+ \(tidak termasuk 3 orang rahasia\)\./.test(p.text)), JSON.stringify(r.pesan));
  pesanT1 = r.pesan;
  console.log(`  T1 selesai dalam ${Date.now() - mulai} ms; ${r.pesan.length} pesan: ${r.pesan.map((p) => p.text.slice(0, 80)).join(" | ")}`);
  // N6 / U14: anomali segera dari file ini terkirim ke HRD dan pembangun dalam proses yang sama.
  const keHrd = segera(r.pesan, HRD);
  assert.ok(keHrd.length >= 1, "tidak ada pemberitahuan segera");
  assert.deepEqual(segera(r.pesan, PEMBANGUN), keHrd);
  assert.equal(r.pesan.filter((p) => p.chat_id === BUKAN || p.chat_id === NONAKTIF).length, 0);
  assert.equal(belumTerkirim(), "0");
  console.log(`  N6: ${catatBaris(keHrd)} kejadian segera terkirim ke 2 akun`);
});

// ---------------------------------------------------------------------------
// Paket G1-3 (docs/rencana-g1-3.md): total di bot dan halaman unggah tanpa orang rahasia (F15b, F15c), chat pribadi (C2)
// ---------------------------------------------------------------------------

let pesanT1: any[] = [];
// Daftar rahasia dibaca dari file induk simulasi, bukan dari database, supaya pembandingnya tidak memakai rumus yang diuji.
const RAHASIA_CSV = new Set(
  readFileSync("data/simulasi/A/induk/karyawan.csv", "utf8").split("\n").slice(1).filter(Boolean)
    .map((b) => b.split(",")).filter((k) => k[12] === "ya").map((k) => k[0]),
);
const rupiah = (t: string) => Number(t.replace(/\./g, ""));
// Gaji bersih per orang dari versi gaji terakhir satu periode (dibaca sebagai pemilik database, seperti Sheets).
function gajiPeriode(awal: string): Map<string, number> {
  const keluar = nilai(`select string_agg(g.id_karyawan || ':' || g.gaji_bersih, ',')
                        from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id and v.jenis = 'hitung_gaji'
                        join fakta.periode p on p.id = v.periode_id where p.tanggal_awal = '${awal}'`);
  return new Map(keluar.split(",").map((x) => x.split(":")).map(([i, b]) => [i, Number(b)]));
}

test("G1-3 (T1): total bot - jumlah gaji yang terlihat = 0; orang rahasia tidak ikut; antrean tanpa rupiah", () => {
  assert.equal(RAHASIA_CSV.size, 3);
  const teks = pesanT1.map((p) => p.text).find((t: string) => t.startsWith("Periode 2026-01-21 s.d. 2026-02-20:"));
  const m = /: ([\d.]+) orang, gaji bersih Rp([\d.]+) \(tidak termasuk (\d+) orang rahasia\)/.exec(teks);
  assert.ok(m, teks);
  const gaji = gajiPeriode("2026-01-21");
  const terlihat = [...gaji].filter(([i]) => !RAHASIA_CSV.has(i));
  const jumlahTerlihat = terlihat.reduce((a, [, b]) => a + b, 0);
  const semua = [...gaji.values()].reduce((a, b) => a + b, 0);
  assert.equal(rupiah(m[2]) - jumlahTerlihat, 0, "total bot - jumlah yang terlihat harus 0");
  assert.equal(rupiah(m[1]), terlihat.length);
  assert.equal(Number(m[3]), gaji.size - terlihat.length);
  assert.notEqual(rupiah(m[2]), semua, "aturan lama (semua orang) tidak boleh dipakai");
  // C1: kolom hasil antrean hanya menyimpan nomor versi, tanpa rupiah dan jumlah orang.
  assert.equal(nilai(`select count(*) from fakta.antrean_kerja where hasil ? 'bersih' or hasil ? 'orang' or hasil ? 'rahasia'`), "0");
  assert.equal(nilai(`select count(*) from fakta.antrean_kerja where status = 'selesai' and not hasil ? 'versi_gaji'`), "0");
  console.log(`  G1-3: bot ${m[2]} = terlihat ${jumlahTerlihat}; semua orang ${semua}; rahasia ${m[3]}`);
});

test("G1-3 (C3): peran pintu tidak bisa memanggil fungsi hitungan rahasia", () => {
  for (const f of ["hitung.ringkasan_terlihat(1)", "fakta.hasil_antrean_tampil('{}'::jsonb)"]) {
    assert.throws(() => psql(`select ${f};`, true), /permission denied/, f);
  }
});

const grup = -1001234567890;
test("G1-3 (C2): file di grup tidak diproses dan tidak diunduh; dijawab satu kalimat", async () => {
  const unduhSebelum = diunduh.length;
  const kiriman = nilai("select count(*) from fakta.kiriman_file");
  const r = await kirimUpdate(JSON.stringify({
    update_id: 9701,
    message: { message_id: 9701, date: 1771635600, chat: { id: grup, type: "supergroup" }, from: { id: HRD },
               document: { file_id: "F_MA2", file_name: "di_grup.csv", file_size: BERKAS.F_MA2.length }, caption: "MA2" },
  }));
  assert.deepEqual(r.pesan.map((p) => [p.chat_id, p.text]), [[grup, PESAN_HANYA_PRIBADI]]);
  assert.equal(diunduh.length, unduhSebelum);
  assert.equal(nilai("select count(*) from fakta.kiriman_file"), kiriman);
});

test("G1-3 (C2): /unggah di grup tidak membuat tautan", async () => {
  const tautan = nilai("select count(*) from fakta.tautan_unggah");
  const r = await kirimUpdate(JSON.stringify({
    update_id: 9702, message: { message_id: 9702, chat: { id: grup, type: "group" }, from: { id: HRD }, text: "/unggah" },
  }));
  assert.deepEqual(r.pesan.map((p) => [p.chat_id, p.text]), [[grup, PESAN_HANYA_PRIBADI]]);
  assert.equal(nilai("select count(*) from fakta.tautan_unggah"), tautan);
});

test("G1-3 (C2): tombol di grup dan chat yang bukan milik pengirim tidak diproses", async () => {
  const kiriman = nilai("select count(*) from fakta.kiriman_file");
  const r = await kirimUpdate(JSON.stringify({
    update_id: 9703, callback_query: { id: "cb9703", data: "m|6|MA2", from: { id: HRD }, message: { chat: { id: grup, type: "group" } } },
  }));
  assert.deepEqual(r.pesan.map((p) => p.text), [PESAN_HANYA_PRIBADI]);
  const r2 = await kirimUpdate(JSON.stringify({
    update_id: 9704, message: { message_id: 9704, chat: { id: PEMBANGUN, type: "private" }, from: { id: HRD }, text: "/unggah" },
  }));
  assert.deepEqual(r2.pesan.map((p) => p.text), [PESAN_HANYA_PRIBADI]);
  assert.equal(nilai("select count(*) from fakta.kiriman_file"), kiriman);
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

test("6e: T1 memicu Isi Sheets sekali (file Telegram, waktu file sah); T2-T5 ditolak/dobel tidak memicu", () => {
  assert.equal(dipicu.length, 1, JSON.stringify(dipicu));
  assert.equal(dipicu[0].pemicu, "file Telegram");
  assert.ok(!Number.isNaN(Date.parse(dipicu[0].waktu_file)) && dipicu[0].waktu_file.endsWith("Z"), dipicu[0].waktu_file);
  assert.ok(terkirim.some((t) => t.metode === "sendMessage" && t.isi.chat_id === HRD &&
                               /^Sheets sedang diperbarui otomatis/.test(t.isi.text)));
  assert.equal(nilai("select string_agg(asal || '/' || hasil, ',') from fakta.picu_sheets"), "telegram/terkirim");
  assert.equal(nilai("select count(*) from fakta.kejadian_segera() where jenis = 'sheets_tidak_terpicu'"), "0");
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

test("G1-3: tombol pilihan mesin milik HRD ditekan akun lain (pembangun) -> file tidak diproses", async () => {
  const r = await kirimUpdate(dokumen(9705, HRD, "F_TEKS", "tunda_hrd.txt"));
  assert.match(r.pesan[0].text, /dari mesin mana/);
  const r2 = await kirimUpdate(JSON.stringify({
    update_id: 9706, callback_query: { id: "cb9706", data: "m|9705|MA1", from: { id: PEMBANGUN },
                                       message: { chat: { id: PEMBANGUN, type: "private" } } },
  }));
  assert.match(r2.pesan[0].text, /sudah diproses sebelumnya/);
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'tunda_hrd.txt'"), "0");
  assert.equal(nilai("select count(*) from fakta.file_tertunda where update_id = 9705"), "1");
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
  assert.ok(r.pesan.some((p) => p.chat_id === HRD && /^Periode .*gaji bersih Rp.*\(tidak termasuk 3 orang rahasia\)/.test(p.text)));
  assert.equal(belumTerkirim(), "0");
  // G1-3: halaman unggah memakai kalimat yang sama dengan bot.
  for (const p of s.isi.periode) {
    assert.ok(r.pesan.some((x) => x.text === `Periode ${p.awal} s.d. ${p.akhir}: ${p.ringkasan}`), p.ringkasan);
  }
  kirimanW6 = r.isi.kiriman_id;
});

let kirimanW6 = 0;
test("G1-3 (C1): orang yang dijadikan rahasia SESUDAH file diproses ikut disembunyikan di halaman unggah", async () => {
  const sebelum = (await webStatus(alat, KODE, kirimanW6)).isi.periode;
  const p2 = sebelum.find((p: any) => p.awal === "2026-02-21");
  const gaji = gajiPeriode("2026-02-21");
  const target = "10001";
  assert.ok(!RAHASIA_CSV.has(target) && gaji.has(target));
  psql(`update induk.karyawan_riwayat set berlaku_sampai = current_date where id_karyawan = '${target}' and berlaku_sampai is null;
        insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap,
          ptkp, cara_bayar, rekening_terenkripsi, wajib_tap, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan)
        select id_karyawan, current_date, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
               rekening_terenkripsi, wajib_tap, true, bpjs_kesehatan, bpjs_ketenagakerjaan
        from induk.karyawan_riwayat where id_karyawan = '${target}' and berlaku_sampai = current_date;`);
  const sesudah = (await webStatus(alat, KODE, kirimanW6)).isi.periode.find((p: any) => p.awal === "2026-02-21");
  assert.equal(p2.hasil.bersih - sesudah.hasil.bersih, gaji.get(target), "gaji orang itu harus keluar dari total");
  assert.equal(p2.hasil.orang - sesudah.hasil.orang, 1);
  assert.equal(sesudah.hasil.rahasia, p2.hasil.rahasia + 1);
  assert.match(sesudah.ringkasan, /tidak termasuk 4 orang rahasia/);
  const terlihat = [...gaji].filter(([i]) => !RAHASIA_CSV.has(i) && i !== target).reduce((a, [, b]) => a + b, 0);
  assert.equal(sesudah.hasil.bersih - terlihat, 0);
});

test("G1-3 (C1b): baris antrean lama yang menyimpan rupiah tampil tanpa angka", async () => {
  const a = nilai(`select id from fakta.antrean_kerja where kiriman_id = ${kirimanW6} order by id limit 1`);
  psql(`update fakta.antrean_kerja set hasil = '{"orang": 1010, "bersih": 123456789, "bisa_diajukan": false, "segera": 0}' where id = ${a}`);
  const s = await webStatus(alat, KODE, kirimanW6);
  const teks = JSON.stringify(s.isi);
  assert.ok(!teks.includes("123456789") && !teks.includes(`"orang":1010`), teks);
  assert.ok(s.isi.periode.some((p: any) => p.hasil.angka_dihapus && /^angka gaji tidak ditampilkan\./.test(p.ringkasan)));
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

test("5e-2: Brevo gagal 3 kali lalu pulih -> kode keempat langsung terkirim dan bisa dipakai", async () => {
  psql("update induk.pengguna set email = 'pulih@contoh.id' where telegram_id = 333");
  let gagal = 3;
  const kotak: string[] = [];
  const alatRewel: Alat = {
    ...alat,
    async email(_ke, _judul, isi) {
      if (gagal-- > 0) throw new Error("Brevo 401: unrecognised IP address");
      kotak.push(isi);
    },
  };
  for (let i = 0; i < 3; i++) assert.equal((await webMintaKode(alatRewel, "pulih@contoh.id")).status, 502);
  assert.equal(nilai("select count(*) from fakta.kode_email where email = 'pulih@contoh.id' and gagal_kirim is not null"), "3");
  assert.equal((await webMintaKode(alatRewel, "pulih@contoh.id")).status, 200);
  assert.equal(kotak.length, 1);
  const kode = /\b(\d{6})\b/.exec(kotak[0])?.[1] ?? "";
  assert.equal((await webTukarKode(alatRewel, "pulih@contoh.id", kode)).status, 200);
});

// ---------------------------------------------------------------------------
// Paket 6e: pemicu Isi Sheets gagal atau belum disiapkan (docs/pintu-telegram.md bagian "Pemicu Sheets")
// ---------------------------------------------------------------------------

async function kirimDengan(a: Alat, badan: string) {
  const awal = terkirim.length;
  const r = await tanganiPermintaan("POST", RAHASIA, badan, RAHASIA, a);
  if (r.latar) await r.latar;
  return terkirim.slice(awal).filter((x) => x.metode === "sendMessage").map((x) => x.isi);
}

test("6e: GitHub menolak -> HRD diberi tahu Sheets BELUM diperbarui; pemberitahuan segera ke HRD dan pembangun", async () => {
  const sebelum = dipicu.length;
  const alatGagal: Alat = { ...alat, async picuSheets() { return { ok: false, alasan: "GitHub 401: Bad credentials" }; } };
  const pesan = await kirimDengan(alatGagal, dokumen(9601, HRD, "F_KURANG_1", "A_p1_MA1_kurang1.csv", "MA1"));
  assert.equal(dipicu.length, sebelum, "pemicu tiruan default tidak dipanggil");
  assert.ok(pesan.some((p) => p.chat_id === HRD && /^Sheets BELUM diperbarui \(GitHub 401: Bad credentials\)/.test(p.text)),
            JSON.stringify(pesan.map((p) => p.text)));
  for (const tg of [HRD, PEMBANGUN]) {
    const s = segera(pesan, tg).join("\n");
    assert.match(s, /Sheets TIDAK diperbarui otomatis/);
    assert.match(s, /pemicu gagal \(GitHub 401: Bad credentials\)/);
  }
  assert.equal(nilai("select hasil || '/' || alasan from fakta.picu_sheets order by id desc limit 1"),
               "gagal/GitHub 401: Bad credentials");
  // Gaji periode itu tetap terhitung walau Sheets tidak terpicu.
  assert.equal(nilai("select count(*) from fakta.antrean_kerja where status <> 'selesai'"), "0");
  // Kejadian "Sheets tidak terpicu" terkirim (kejadian lain yang sengaja gagal di uji "Telegram gagal total" tidak dihitung).
  assert.equal(nilai(`select count(*) from fakta.kejadian_segera() k where k.jenis = 'sheets_tidak_terpicu'
                      and not exists (select 1 from fakta.pemberitahuan b where b.kunci = k.kunci and b.status = 'terkirim')`), "0");
});

test("6e: pemicu belum disiapkan (token kosong) -> pesan jelas dan pemberitahuan segera", async () => {
  const { picuSheets: _tanpa, ...sisa } = alat;
  const alatTanpa: Alat = sisa;
  const pesan = await kirimDengan(alatTanpa, dokumen(9602, HRD, "F_KURANG_2", "A_p1_MA1_kurang2.csv", "MA1"));
  assert.ok(pesan.some((p) => p.chat_id === HRD && /^Sheets belum diperbarui otomatis \(pemicu belum disiapkan\)/.test(p.text)));
  assert.match(segera(pesan, PEMBANGUN).join("\n"), /pemicu belum disiapkan/);
  assert.equal(nilai("select hasil from fakta.picu_sheets order by id desc limit 1"), "belum_disiapkan");
  // Kejadian "Sheets tidak terpicu" terkirim (kejadian lain yang sengaja gagal di uji "Telegram gagal total" tidak dihitung).
  assert.equal(nilai(`select count(*) from fakta.kejadian_segera() k where k.jenis = 'sheets_tidak_terpicu'
                      and not exists (select 1 from fakta.pemberitahuan b where b.kunci = k.kunci and b.status = 'terkirim')`), "0");
});

test("6e: pemicu melempar galat -> dicatat gagal, hitung tetap tersimpan", async () => {
  const alatLempar: Alat = { ...alat, async picuSheets() { throw new Error("jaringan putus"); } };
  // Tidak ada file baru yang sah tersisa; picu langsung lewat fungsi yang sama dengan satu periode berhasil.
  const { picuSheets } = await import("./inti.ts");
  const awal = terkirim.length;
  await picuSheets(alatLempar, HRD, Date.now(), "web");
  const pesan = terkirim.slice(awal).filter((x) => x.metode === "sendMessage").map((x) => x.isi);
  assert.ok(pesan.some((p) => /^Sheets BELUM diperbarui \(jaringan putus\)/.test(p.text)));
  assert.equal(nilai("select asal || '/' || hasil from fakta.picu_sheets order by id desc limit 1"), "web/gagal");
});

test("6f (E8b): 10 kode untuk satu email dalam 24 jam -> berikutnya tidak dikirim; jawaban sama dengan email tak terdaftar", async () => {
  const kotak: string[] = [];
  const alatHitung: Alat = { ...alat, async email(_ke, _judul, isi) { kotak.push(isi); } };
  const id = nilai("select id from induk.pengguna where email = 'pulih@contoh.id'");
  // 10 kode terkirim 1-20 jam lalu (di luar jendela 15 menit, di dalam 24 jam).
  psql(`insert into fakta.kode_email (pengguna, email, sidik, dibuat, berlaku_sampai)
        select ${id}, 'pulih@contoh.id', repeat('a', 64), now() - (g || ' hours')::interval, now() - (g || ' hours')::interval
        from generate_series(1, 10) g`);
  const r = await webMintaKode(alatHitung, "pulih@contoh.id");
  const tak = await webMintaKode(alatHitung, "tidak.terdaftar@contoh.id");
  assert.equal(kotak.length, 0, "kode ke-11 tidak boleh dikirim");
  assert.deepEqual(r, tak, "jawaban halaman sama dengan email tidak terdaftar");
  psql("delete from fakta.kode_email where email = 'pulih@contoh.id' and dibuat < now() - interval '30 minutes'");
  await webMintaKode(alatHitung, "pulih@contoh.id");
  assert.equal(kotak.length, 1, "sesudah jatah harian kosong lagi, kode terkirim");
});

test("6f (E8b): 100 kode semua email dalam 24 jam -> email lain pun tidak dikirimi", async () => {
  const kotak: string[] = [];
  const alatHitung: Alat = { ...alat, async email(_ke, _judul, isi) { kotak.push(isi); } };
  const id = nilai("select id from induk.pengguna where email = 'hrd111@contoh.id'");
  const ada = Number(nilai("select count(*) from fakta.kode_email where dibuat > now() - interval '24 hours'"));
  psql(`insert into fakta.kode_email (pengguna, email, sidik, dibuat, berlaku_sampai, gagal_kirim)
        select ${id}, 'banjir' || g || '@contoh.id', repeat('b', 64), now() - interval '2 hours', now() - interval '2 hours',
               now() - interval '2 hours'
        from generate_series(1, ${Math.max(100 - ada, 0)}) g`);
  const r = await webMintaKode(alatHitung, "pulih@contoh.id");
  assert.equal(kotak.length, 0, "batas 100 sehari untuk semua email (termasuk yang gagal dikirim)");
  assert.deepEqual(r, await webMintaKode(alatHitung, "tidak.terdaftar@contoh.id"));
  psql("delete from fakta.kode_email where email like 'banjir%@contoh.id'");
});

// ---------------------------------------------------------------------------
// Paket 8a: pendaftaran karyawan lewat bot (docs/rencana-8a.md; PRD v2 celah K1, K8)
// ---------------------------------------------------------------------------

const teksPribadi = (u: number, dari: number, text: string) =>
  JSON.stringify({ update_id: u, message: { message_id: u, chat: { id: dari, type: "private" }, from: { id: dari }, text } });
const KARYAWAN_BARU = 7001;
let kodeDaftar = "";
let kodeIdDaftar = 0;

test("8a: HRD /kode 10001 -> kode 10 huruf, nama dan divisi, tanpa angka gaji; database hanya menyimpan sidik", async () => {
  const r = await kirimUpdate(teksPribadi(9801, HRD, "/kode 10001"));
  assert.equal(r.pesan.length, 1);
  const m = /^Kode daftar untuk 10001 Eka Susanto \((.+)\): ([A-HJKMNP-Z2-9]{10})\n/.exec(r.pesan[0].text);
  assert.ok(m, r.pesan[0].text);
  kodeDaftar = m[2];
  assert.ok(!/Rp/.test(r.pesan[0].text));
  assert.equal(nilai(`select count(*) from fakta.kode_daftar where sidik = '${sha256(kodeDaftar)}'`), "1");
  assert.equal(nilai(`select count(*) from fakta.kode_daftar where sidik = '${kodeDaftar}'`), "0");
});

test("8a: /kode tanpa ID, ID tak ada, dan dari akun bukan HRD", async () => {
  assert.match((await kirimUpdate(teksPribadi(9802, HRD, "/kode"))).pesan[0].text, /^Cara pakai: \/kode/);
  assert.match((await kirimUpdate(teksPribadi(9803, HRD, "/kode 99999"))).pesan[0].text, /^ID 99999 tidak ditemukan/);
  assert.match((await kirimUpdate(teksPribadi(9804, BUKAN, "/kode 10002"))).pesan[0].text, /hanya untuk HRD/);
});

test("8a (K8): /daftar kode (huruf kecil, tanda hubung) -> nama dan divisi + tombol Ya/Bukan", async () => {
  const ketik = `${kodeDaftar.slice(0, 5).toLowerCase()}-${kodeDaftar.slice(5)}`;
  const r = await kirimUpdate(teksPribadi(9805, KARYAWAN_BARU, `/daftar ${ketik}`));
  assert.match(r.pesan[0].text, /^Kode cocok untuk:\nEka Susanto, divisi .+ \(ID 10001\)\.\nApakah ini Anda\?$/);
  const tombol = r.pesan[0].reply_markup.inline_keyboard[0];
  assert.deepEqual(tombol.map((t: any) => t.text), ["Ya, ini saya", "Bukan"]);
  kodeIdDaftar = Number(/^d\|y\|(\d+)$/.exec(tombol[0].callback_data)![1]);
  assert.equal(nilai(`select count(*) from induk.pengguna where telegram_id = ${KARYAWAN_BARU}`), "0", "belum terdaftar sebelum Ya");
});

test("8a: tombol Ya -> terdaftar sebagai karyawan 10001; ditekan lagi -> tidak berlaku", async () => {
  const tekan = (u: number) => JSON.stringify({ update_id: u, callback_query: { id: `cb${u}`, data: `d|y|${kodeIdDaftar}`,
    from: { id: KARYAWAN_BARU }, message: { chat: { id: KARYAWAN_BARU, type: "private" } } } });
  const r = await kirimUpdate(tekan(9806));
  assert.match(r.pesan[0].text, /^Terdaftar: Eka Susanto \(ID 10001\)/);
  // Paket 8c-3: belum ada gaji yang dirilis -> kalimat "akan dikirim setelah gaji dirilis" tetap, tanpa rincian.
  assert.ok(r.pesan[0].text.endsWith("Rincian gaji akan dikirim lewat chat ini setelah gaji dirilis."), r.pesan[0].text);
  assert.equal(r.pesan.length, 1);
  assert.equal(nilai(`select peran || '/' || id_karyawan || '/' || aktif from induk.pengguna where telegram_id = ${KARYAWAN_BARU}`),
               "karyawan/10001/true");
  assert.match((await kirimUpdate(tekan(9807))).pesan[0].text, /tidak berlaku lagi/);
});

test("8a: akun karyawan tidak bisa /unggah, /kode, atau mengirim file; teks dijawab sebagai karyawan", async () => {
  assert.match((await kirimUpdate(teksPribadi(9808, KARYAWAN_BARU, "halo"))).pesan[0].text,
               /^Akun ini terdaftar sebagai karyawan Eka Susanto\./);
  const t = await kirimUpdate(teksPribadi(9809, KARYAWAN_BARU, "/unggah"));
  assert.ok(!/unggah\/#kode=/.test(t.pesan[0].text) && /belum terdaftar untuk mengirim file/.test(t.pesan[0].text), t.pesan[0].text);
  assert.match((await kirimUpdate(teksPribadi(9810, KARYAWAN_BARU, "/kode 10002"))).pesan[0].text, /hanya untuk HRD/);
  const unduh = diunduh.length;
  const f = await kirimUpdate(dokumen(9811, KARYAWAN_BARU, "F_MA2", "dari_karyawan.csv", "MA2"));
  assert.match(f.pesan[0].text, /belum terdaftar untuk mengirim file/);
  assert.equal(diunduh.length, unduh);
});

test("8a (K1): /kode untuk ID yang sudah punya akun ditolak tanpa 'ganti'; akun Telegram yang terdaftar tidak bisa /daftar", async () => {
  assert.match((await kirimUpdate(teksPribadi(9812, HRD, "/kode 10001"))).pesan[0].text, /sudah punya akun aktif.*\/kode 10001 ganti/);
  assert.match((await kirimUpdate(teksPribadi(9813, HRD, "/daftar ABCDE23456"))).pesan[0].text, /sudah terdaftar/);
});

test("8a: kode salah ditolak (gerbang Tahap 8); 5 kali salah dalam 1 jam -> terkunci", async () => {
  for (let i = 0; i < 5; i++) {
    const r = await kirimUpdate(teksPribadi(9820 + i, 7002, "/daftar SALAH23456"));
    assert.match(r.pesan[0].text, new RegExp(`^Kode tidak berlaku .*Sisa percobaan dalam 1 jam: ${4 - i}\\.$`));
  }
  assert.match((await kirimUpdate(teksPribadi(9825, 7002, "/daftar SALAH23456"))).pesan[0].text, /^Terlalu banyak kode salah/);
  assert.equal(nilai("select count(*) from induk.pengguna where telegram_id = 7002"), "0");
  assert.match((await kirimUpdate(teksPribadi(9826, 7003, "/daftar"))).pesan[0].text, /^Cara pakai: \/daftar KODE/);
  assert.match((await kirimUpdate(teksPribadi(9827, 7003, "halo"))).pesan[0].text, /minta kode daftar ke HRD, lalu ketik \/daftar KODE/);
});

test("8a: /daftar di grup tidak diproses (aturan G1-3)", async () => {
  const r = await kirimUpdate(JSON.stringify({ update_id: 9828, message: { message_id: 9828,
    chat: { id: -100777, type: "group" }, from: { id: 7004 }, text: "/daftar ABCDE23456" } }));
  assert.deepEqual(r.pesan.map((p) => p.text), [PESAN_HANYA_PRIBADI]);
  assert.equal(nilai("select count(*) from fakta.percobaan_daftar where telegram_id = 7004"), "0");
});

// ---------------------------------------------------------------------------
// Paket 8b: rilis gaji dengan PIN (docs/rencana-8b.md; PRD v2 celah K5). Pengaturan demo Pabrik A: HRD lalu bos.
// ---------------------------------------------------------------------------

const BOS = 6001;
const PIN_UJI = "530817";
let periodeRilis = 0;
const tekanTombol = (u: number, dari: number, data: string) => JSON.stringify({ update_id: u, callback_query: {
  id: `cb${u}`, data, from: { id: dari }, message: { chat: { id: dari, type: "private" } } } });
const dihapus = (awal: number) => terkirim.slice(awal).filter((t) => t.metode === "deleteMessage").map((t) => t.isi.message_id);

test("8b (persiapan): isian pajak Januari karangan dimuat, periode 1 dihitung ulang dan bisa diajukan; akun bos", () => {
  psql(`insert into induk.pengguna (telegram_id, peran) values (${BOS}, 'bos');`);
  const r = spawnSync("psql", [DB, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", "db/data_awal/pajak_awal_tahun_simulasi.sql"], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  periodeRilis = Number(nilai("select id from fakta.periode where tanggal_awal = '2026-01-21'"));
  psql(`select hitung.hitung_gaji(${periodeRilis});`);
  assert.equal(nilai(`select status || '/' || hitung.periode_bisa_diajukan(id) from fakta.periode where id = ${periodeRilis}`), "dihitung/true");
  assert.equal(nilai("select aturan.pengaturan_pada('persetujuan_rilis', null, current_date)"), "hrd_lalu_bos");
});

test("8b: /pin dari karyawan ditolak; /pin lemah ditolak; /pin dibuat; pesan berisi PIN dihapus; PIN tidak tersimpan", async () => {
  // Paket 8d: bos juga boleh punya PIN, jadi teks penolakan menyebut HRD, bos, dan pembangun.
  assert.match((await kirimUpdate(teksPribadi(9901, KARYAWAN_BARU, "/pin 482913"))).pesan[0].text, /PIN hanya untuk akun HRD, bos, dan pembangun/);
  const awal = terkirim.length;
  assert.match((await kirimUpdate(teksPribadi(9902, HRD, "/pin 123456"))).pesan[0].text, /tidak boleh angka sama semua atau berurutan/);
  const r = await kirimUpdate(teksPribadi(9903, HRD, `/pin ${PIN_UJI}`));
  assert.match(r.pesan[0].text, /^PIN dibuat/);
  assert.ok(!r.pesan.some((p) => p.text.includes(PIN_UJI)));
  assert.deepEqual(dihapus(awal), [9902, 9903]);
  assert.equal(nilai(`select pin_tersamar like '$2a$10$%' and position('${PIN_UJI}' in pin_tersamar) = 0
                      from induk.pengguna where telegram_id = ${HRD}`), "t");
  assert.match((await kirimUpdate(teksPribadi(9904, HRD, "/pin"))).pesan[0].text, /^Cara pakai: \/pin/);
});

let versiAjukan = 0;
test("8b (K5): /ajukan -> ringkasan tanpa orang rahasia + tombol Ajukan/Batal; karyawan dan grup ditolak", async () => {
  assert.match((await kirimUpdate(teksPribadi(9905, KARYAWAN_BARU, "/ajukan"))).pesan[0].text, /hanya untuk HRD/);
  const r = await kirimUpdate(teksPribadi(9906, HRD, "/ajukan"));
  const m = r.pesan.find((p) => p.text.startsWith(`Periode no. ${periodeRilis}: 2026-01-21 s.d. 2026-02-20`));
  assert.ok(m, JSON.stringify(r.pesan.map((p) => p.text)));
  assert.match(m.text, /orang, gaji bersih Rp[\d.]+ \(tidak termasuk \d+ orang rahasia\)\.\nTransfer Rp[\d.]+, tunai Rp[\d.]+\.\nAjukan/);
  const tombol = m.reply_markup.inline_keyboard[0];
  assert.deepEqual(tombol.map((t: any) => t.text), ["Ajukan", "Batal"]);
  versiAjukan = Number(tombol[0].callback_data.split("|")[3]);
  const g = await kirimUpdate(JSON.stringify({ update_id: 9907, message: { message_id: 9907, chat: { id: -100555, type: "group" },
    from: { id: HRD }, text: "/ajukan" } }));
  assert.deepEqual(g.pesan.map((p) => p.text), [PESAN_HANYA_PRIBADI]);
  assert.match((await kirimUpdate(tekanTombol(9908, HRD, `a|n|${periodeRilis}|${versiAjukan}`))).pesan[0].text, /Tidak jadi diajukan/);
  assert.equal(nilai(`select status from fakta.periode where id = ${periodeRilis}`), "dihitung");
});

test("8b: Ajukan -> bos menerima ringkasan + Setujui/Tolak; rilis sebelum disetujui ditolak", async () => {
  const r = await kirimUpdate(tekanTombol(9909, HRD, `a|y|${periodeRilis}|${versiAjukan}`));
  assert.match(r.pesan.find((p) => p.chat_id === HRD).text, /^Diajukan\.[\s\S]*Menunggu persetujuan bos\./);
  const keBos = r.pesan.find((p) => p.chat_id === BOS);
  assert.match(keBos.text, /^Pengajuan rilis gaji:\nPeriode no\./);
  assert.deepEqual(keBos.reply_markup.inline_keyboard[0].map((t: any) => t.text), ["Setujui", "Tolak"]);
  assert.equal(nilai(`select status from fakta.periode where id = ${periodeRilis}`), "diajukan");
  const awal = terkirim.length;
  const x = await kirimUpdate(teksPribadi(9910, HRD, `/rilis ${periodeRilis} ${PIN_UJI}`));
  assert.match(x.pesan[0].text, /belum disetujui bos/);
  assert.deepEqual(dihapus(awal), [9910]);
  const d = await kirimUpdate(teksPribadi(9911, HRD, "/rilis"));
  assert.match(d.pesan.find((p) => p.text.startsWith(`Periode no. ${periodeRilis}`)).text, /Status: diajukan\. Menunggu persetujuan bos\./);
  // tombol bos ditekan akun HRD -> ditolak
  const sd = keBos.reply_markup.inline_keyboard[0][0].callback_data;
  assert.match((await kirimUpdate(tekanTombol(9912, HRD, sd))).pesan[0].text, /hanya untuk akun bos/);
  bosSetujui = sd;
});
let bosSetujui = "";

test("8b: bos menyetujui -> HRD diberi tahu; PIN salah ditolak (pesan dihapus); PIN benar -> dirilis", async () => {
  const r = await kirimUpdate(tekanTombol(9913, BOS, bosSetujui));
  assert.match(r.pesan.find((p) => p.chat_id === BOS).text, /^Pengajuan disetujui\./);
  assert.match(r.pesan.find((p) => p.chat_id === HRD).text, /^Bos menyetujui pengajuan rilis:[\s\S]*\/rilis \d+ <PIN>/);
  assert.equal(nilai(`select status from fakta.periode where id = ${periodeRilis}`), "disetujui");
  const awal = terkirim.length;
  assert.match((await kirimUpdate(teksPribadi(9914, HRD, `/rilis ${periodeRilis} 000001`))).pesan[0].text, /^PIN salah/);
  const ok = await kirimUpdate(teksPribadi(9915, HRD, `/rilis ${periodeRilis} ${PIN_UJI}`));
  assert.match(ok.pesan[0].text, /^Gaji DIRILIS\.\nPeriode no\./);
  assert.deepEqual(dihapus(awal), [9914, 9915]);
  assert.equal(nilai(`select status from fakta.periode where id = ${periodeRilis}`), "dirilis");
  assert.equal(nilai(`select string_agg(status_baru || '/' || oleh, ',' order by id) from fakta.riwayat_status_periode
                      where periode_id = ${periodeRilis} and status_baru in ('diajukan', 'disetujui', 'dirilis')`),
               `diajukan/pengguna ${nilai(`select id from induk.pengguna where telegram_id = ${HRD}`)},` +
               `disetujui/pengguna ${nilai(`select id from induk.pengguna where telegram_id = ${BOS}`)},` +
               `dirilis/pengguna ${nilai(`select id from induk.pengguna where telegram_id = ${HRD}`)}`);
  // tombol bos ditekan lagi -> tidak berlaku
  assert.match((await kirimUpdate(tekanTombol(9916, BOS, bosSetujui))).pesan[0].text, /tidak berlaku lagi/);
});

test("8b: file baru untuk periode yang sudah dirilis -> tap disimpan, periode tidak dihitung ulang, pemberitahuan segera", async () => {
  const versi = nilai(`select count(*) from hitung.versi_hitung where periode_id = ${periodeRilis}`);
  const r = await kirimUpdate(dokumen(9917, HRD, "F_KURANG_3", "A_p1_MA1_kurang3.csv", "MA1"));
  assert.ok(r.pesan.some((p) => p.chat_id === HRD &&
    p.text === "Periode 2026-01-21 s.d. 2026-02-20: sudah dirilis; tidak dihitung ulang. Tap baru tetap tersimpan."),
    JSON.stringify(r.pesan.map((p) => p.text)));
  assert.equal(nilai(`select count(*) from hitung.versi_hitung where periode_id = ${periodeRilis}`), versi);
  assert.equal(nilai(`select status from fakta.periode where id = ${periodeRilis}`), "dirilis");
  for (const tg of [HRD, PEMBANGUN]) {
    assert.ok(segera(r.pesan, tg).some((t) => /SUDAH DIRILIS[\s\S]*Periode 2026-01-21 s\.d\. 2026-02-20: file A_p1_MA1_kurang3\.csv/.test(t)), tg.toString());
  }
  // Hanya kejadian dari file ini (uji "Telegram gagal total" di atas sengaja meninggalkan pemberitahuan gagal).
  assert.equal(nilai(`select count(*) from fakta.kejadian_segera() k where k.jenis = 'periode_dirilis_kena_file'
                      and not exists (select 1 from fakta.pemberitahuan b where b.kunci = k.kunci and b.status = 'terkirim')`), "0");
});

// ---------------------------------------------------------------------------
// Paket 8b-2: akun pembangun menyetujui atau menolak dengan PIN (docs/rencana-8b-2.md; keputusan pemilik 19 Nov 2026).
// ---------------------------------------------------------------------------

const PIN_PEMBANGUN = "640295";
// Paket 8b-5: pesan kabar "Sheets sedang diperbarui" sesudah status periode berubah tidak dihitung di uji jumlah pesan.
const KABAR_SHEETS = /^Sheets sedang diperbarui otomatis/;
const tanpaSheets = (ps: any[]) => ps.filter((p) => !KABAR_SHEETS.test(String(p.text)));
let periode2 = 0;
const pembangunId = () => nilai(`select id from induk.pengguna where telegram_id = ${PEMBANGUN}`);
async function ajukanLewatTombol(u: number, dari: number) {
  const daftar = await kirimUpdate(teksPribadi(u, dari, "/ajukan"));
  const m = daftar.pesan.find((p) => p.text.startsWith(`Periode no. ${periode2}:`));
  assert.ok(m, JSON.stringify(daftar.pesan.map((p) => p.text)));
  return kirimUpdate(tekanTombol(u + 1, dari, m.reply_markup.inline_keyboard[0][0].callback_data));
}

test("8b-2 (persiapan): periode 21 Feb-20 Mar dihitung dan bisa diajukan; pembangun membuat PIN", async () => {
  periode2 = Number(nilai("select id from fakta.periode where tanggal_awal = '2026-02-21'"));
  psql(`select hitung.hitung_gaji(${periode2});`);
  assert.equal(nilai(`select status || '/' || hitung.periode_bisa_diajukan(id) from fakta.periode where id = ${periode2}`), "dihitung/true");
  assert.match((await kirimUpdate(teksPribadi(9930, PEMBANGUN, `/pin ${PIN_PEMBANGUN}`))).pesan[0].text, /^PIN dibuat/);
});

test("8b-2/8b-3: HRD mengajukan -> bos dapat tombol; pembangun dapat cara /setujui dan /tolak + tombol yang meminta PIN", async () => {
  const r = await ajukanLewatTombol(9931, HRD);
  assert.match(r.pesan.find((p) => p.chat_id === HRD).text, /Menunggu persetujuan bos\.$/);
  assert.ok(r.pesan.find((p) => p.chat_id === BOS).reply_markup);
  const ke = r.pesan.filter((p) => p.chat_id === PEMBANGUN);
  assert.equal(ke.length, 1);
  assert.match(ke[0].text, new RegExp(`^Pengajuan rilis gaji:\\nPeriode no\\. ${periode2}:[\\s\\S]*\\/setujui ${periode2} <PIN>[\\s\\S]*\\/tolak ${periode2} <PIN>`));
  // Paket 8b-3: pembangun juga mendapat tombol (tombol meminta PIN sesudah ditekan).
  assert.deepEqual(ke[0].reply_markup.inline_keyboard[0].map((t: any) => t.callback_data), [`p|y|${periode2}`, `p|n|${periode2}`]);
});

test("8b-2: PIN salah dan cara pakai salah ditolak; bos diminta pakai tombol; HRD ditolak; pesan berisi PIN dihapus", async () => {
  const awal = terkirim.length;
  assert.match((await kirimUpdate(teksPribadi(9933, PEMBANGUN, `/setujui ${periode2} 000001`))).pesan[0].text, /^PIN salah/);
  // Paket 8b-3: perintah tanpa PIN meminta PIN (bukan "Cara pakai").
  assert.match((await kirimUpdate(teksPribadi(9934, PEMBANGUN, `/setujui ${periode2}`))).pesan[0].text, /^Ketik PIN 6 angka untuk menyetujui/);
  assert.match((await kirimUpdate(teksPribadi(9929, PEMBANGUN, "/setujui"))).pesan[0].text, /^Cara pakai: \/setujui/);
  assert.match((await kirimUpdate(teksPribadi(9935, BOS, `/setujui ${periode2} ${PIN_PEMBANGUN}`))).pesan[0].text, /lewat tombol/);
  assert.match((await kirimUpdate(teksPribadi(9936, HRD, `/tolak ${periode2} ${PIN_UJI}`))).pesan[0].text, /hanya untuk akun bos atau pembangun/);
  assert.deepEqual(dihapus(awal), [9933, 9935, 9936]);
  assert.equal(nilai(`select status from fakta.periode where id = ${periode2}`), "diajukan");
});

test("8b-2: pembangun menolak dengan PIN -> kembali dihitung; HRD diberi tahu 'Pembangun menolak'", async () => {
  const r = await kirimUpdate(teksPribadi(9937, PEMBANGUN, `/tolak ${periode2} ${PIN_PEMBANGUN}`));
  assert.match(r.pesan.find((p) => p.chat_id === PEMBANGUN).text, /^Pengajuan ditolak \(kembali ke dihitung\)\./);
  assert.match(r.pesan.find((p) => p.chat_id === HRD).text, /^Pembangun menolak pengajuan rilis:/);
  assert.equal(nilai(`select status from fakta.periode where id = ${periode2}`), "dihitung");
});

test("8b-2: pembangun mengajukan, menyetujui, dan merilis sendiri; tercatat 'oleh pembangun'", async () => {
  const a = await ajukanLewatTombol(9938, PEMBANGUN);
  const sendiri = tanpaSheets(a.pesan.filter((p) => p.chat_id === PEMBANGUN));
  assert.equal(sendiri.length, 1, JSON.stringify(sendiri.map((p) => p.text)));
  assert.match(sendiri[0].text, new RegExp(`^Diajukan\\.[\\s\\S]*Menunggu persetujuan bos\\.\\nSebagai pembangun: [\\s\\S]*\\/setujui ${periode2} <PIN>`));
  const d = await kirimUpdate(teksPribadi(9940, PEMBANGUN, "/rilis"));
  assert.match(d.pesan.find((p) => p.text.startsWith(`Periode no. ${periode2}`)).text, /Menunggu persetujuan bos\.\nSebagai pembangun: /);
  const s = await kirimUpdate(teksPribadi(9941, PEMBANGUN, `/setujui ${periode2} ${PIN_PEMBANGUN}`));
  assert.equal(tanpaSheets(s.pesan).length, 1);
  assert.match(s.pesan[0].text, new RegExp(`^Pengajuan disetujui\\.[\\s\\S]*\\/rilis ${periode2} <PIN>\\.$`));
  assert.equal(s.pesan[0].reply_markup.inline_keyboard[0][0].callback_data, `r|y|${periode2}`);
  const rl = await kirimUpdate(teksPribadi(9942, PEMBANGUN, `/rilis ${periode2} ${PIN_PEMBANGUN}`));
  assert.match(rl.pesan[0].text, /^Gaji DIRILIS\./);
  assert.equal(nilai(`select status from fakta.periode where id = ${periode2}`), "dirilis");
  assert.equal(nilai(`select string_agg(r.status_baru || '/' || r.oleh || '/' || coalesce(r.alasan, '-'), ',' order by r.id)
                      from fakta.riwayat_status_periode r where r.periode_id = ${periode2} and r.id > (select max(id) from
                      fakta.riwayat_status_periode where periode_id = ${periode2} and alasan = 'ditolak pembangun')`),
    `diajukan/pengguna ${pembangunId()}/diajukan lewat Telegram,disetujui/pengguna ${pembangunId()}/disetujui pembangun,` +
    `dirilis/pengguna ${pembangunId()}/dirilis lewat Telegram dengan PIN`);
  assert.equal(nilai(`select string_agg(keputusan || ':' || coalesce(catatan, '-'), ',' order by id) from fakta.persetujuan
                      where perihal = 'rilis' and penyetuju = ${pembangunId()}`), "tolak:oleh pembangun,setuju:oleh pembangun");
});

// ---------------------------------------------------------------------------
// Paket 8b-3: urutan, tombol yang meminta PIN, /batal, /hapuspin, /undang, /gabung, kabar rilis, pengingat ke bos.
// ---------------------------------------------------------------------------

let periode3 = 0;
let tombolAjukan3 = "";
const pesanKe = (r: { pesan: any[] }, tg: number) => r.pesan.filter((p) => p.chat_id === tg);
const disetel = (awal: number) => terkirim.slice(awal).filter((t) => t.metode === "setMyCommands").map((t) => t.isi);

test("8b-3: perintah tanpa garis miring dikenali; kata lain tidak diubah", () => {
  assert.equal(rapikanPerintah("pin 482913"), "/pin 482913");
  assert.equal(rapikanPerintah("Ajukan"), "/Ajukan");
  assert.equal(rapikanPerintah("pinjam uang"), "pinjam uang");
  assert.equal(rapikanPerintah("/rilis"), "/rilis");
});

test("8b-3: menu perintah sah untuk Telegram (huruf kecil, maks 32 huruf, keterangan maks 256)", () => {
  for (const [peran, daftar] of Object.entries(MENU)) {
    assert.ok(daftar.length > 0 && daftar.length <= 100, peran);
    for (const p of daftar) {
      assert.match(p.command, /^[a-z0-9_]{1,32}$/, `${peran} ${p.command}`);
      assert.ok(p.description.length >= 1 && p.description.length <= 256, `${peran} ${p.command}`);
    }
  }
  assert.ok(MENU.pembangun.some((p) => p.command === "hapuspin") && !MENU.hrd.some((p) => p.command === "hapuspin"));
});

test("8b-3 (persiapan): periode 21 Mar-20 Apr dihitung dan bisa diajukan", () => {
  periode3 = Number(nilai("select id from fakta.periode where tanggal_awal = '2026-03-21'"));
  psql(`select hitung.hitung_gaji(${periode3});`);
  assert.equal(nilai(`select status || '/' || hitung.periode_bisa_diajukan(id) || '/' || coalesce(fakta.periode_menunggu(id)::text, '-')
                      from fakta.periode where id = ${periode3}`), "dihitung/true/-");
});

test("8b-3: 'ajukan' tanpa garis miring -> Ajukan -> bos dapat tombol, pembangun dapat tombol yang meminta PIN", async () => {
  const daftar = await kirimUpdate(teksPribadi(9950, HRD, "ajukan"));
  const m = daftar.pesan.find((p) => p.text.startsWith(`Periode no. ${periode3}:`));
  assert.ok(m, JSON.stringify(daftar.pesan.map((p) => p.text)));
  tombolAjukan3 = m.reply_markup.inline_keyboard[0][0].callback_data;
  const r = await kirimUpdate(tekanTombol(9951, HRD, tombolAjukan3));
  assert.match(pesanKe(r, HRD)[0].text, /^Diajukan\./);
  assert.equal(pesanKe(r, BOS)[0].reply_markup.inline_keyboard[0][0].callback_data.split("|")[0], "s");
  assert.equal(pesanKe(r, PEMBANGUN)[0].reply_markup.inline_keyboard[0][0].callback_data, `p|y|${periode3}`);
});

test("8b-3: pengingat harian -> bos diingatkan dengan tombol Setujui/Tolak (sekali per hari)", async () => {
  const besok = new Date(Date.now() + 7 * 3600 * 1000 + 86400 * 1000).toISOString().slice(0, 10);
  const r = await picuPengingat({ tanggal: besok });
  assert.equal(r.hasil.pengingat_rilis, 1);
  const ke = pesanKe(r, BOS).filter((p) => p.text.startsWith("PENGINGAT: pengajuan rilis gaji"));
  assert.equal(ke.length, 1);
  assert.match(ke[0].text, new RegExp(`Periode no\\. ${periode3}:`));
  assert.equal(ke[0].reply_markup.inline_keyboard[0][0].callback_data.split("|").slice(0, 3).join("|"), `s|y|${periode3}`);
  assert.equal(nilai(`select status from fakta.pemberitahuan where jenis = 'pengingat_rilis' order by id desc limit 1`), "terkirim");
  assert.equal((await picuPengingat({ tanggal: besok })).hasil.pengingat_rilis, 0);
});

test("8b-3: /batal -> kembali dihitung; bos dan pembangun diberi kabar; karyawan ditolak", async () => {
  assert.match((await kirimUpdate(teksPribadi(9952, KARYAWAN_BARU, `/batal ${periode3}`))).pesan[0].text, /hanya untuk HRD/);
  const r = await kirimUpdate(teksPribadi(9953, HRD, `batal ${periode3}`));
  assert.match(pesanKe(r, HRD)[0].text, /^Pengajuan dibatalkan; periode kembali ke dihitung\./);
  for (const tg of [BOS, PEMBANGUN]) {
    assert.match(pesanKe(r, tg)[0].text, new RegExp(`^Pengajuan rilis periode no\\. ${periode3} dibatalkan oleh HRD\\.`));
  }
  assert.equal(nilai(`select status from fakta.periode where id = ${periode3}`), "dihitung");
  assert.match((await kirimUpdate(teksPribadi(9954, HRD, `/batal ${periode3}`))).pesan[0].text, /tidak sedang diajukan/);
});

test("8b-3: bos setuju -> HRD dapat tombol Rilis -> PIN salah lalu PIN benar (pesan dihapus) -> dirilis; akun lain dikabari", async () => {
  const a = await kirimUpdate(tekanTombol(9955, HRD, tombolAjukan3));
  const sb = pesanKe(a, BOS)[0].reply_markup.inline_keyboard[0][0].callback_data;
  const s = await kirimUpdate(tekanTombol(9956, BOS, sb));
  const keHrd = pesanKe(s, HRD)[0];
  assert.match(keHrd.text, /^Bos menyetujui pengajuan rilis:/);
  assert.equal(keHrd.reply_markup.inline_keyboard[0][0].callback_data, `r|y|${periode3}`);
  const minta = await kirimUpdate(tekanTombol(9957, HRD, `r|y|${periode3}`));
  assert.match(minta.pesan[0].text, new RegExp(`^Ketik PIN 6 angka untuk merilis gaji periode no\\. ${periode3}\\.`));
  // Paket 8b-5: tanpa force reply supaya tombol tetap tidak tertutup.
  assert.equal(minta.pesan[0].reply_markup, undefined);
  const awal = terkirim.length;
  assert.match((await kirimUpdate(teksPribadi(9958, HRD, "000001"))).pesan[0].text, /^PIN salah/);
  await kirimUpdate(tekanTombol(9959, HRD, `r|y|${periode3}`));
  const ok = await kirimUpdate(teksPribadi(9960, HRD, PIN_UJI));
  assert.deepEqual(dihapus(awal), [9958, 9960]);
  assert.match(pesanKe(ok, HRD)[0].text, /^Gaji DIRILIS\./);
  // Paket 8b-5: sesudah balasan rilis, Isi Sheets dipicu dan dikabarkan (urutan: hasil dulu, lalu kabar Sheets).
  assert.match(pesanKe(ok, HRD)[1].text, KABAR_SHEETS);
  assert.deepEqual(dipicu[dipicu.length - 1], { pemicu: "status periode", waktu_file: "" });
  for (const tg of [BOS, PEMBANGUN]) {
    assert.match(pesanKe(ok, tg)[0].text, new RegExp(`^Gaji periode no\\. ${periode3} DIRILIS\\.`));
  }
  assert.equal(pesanKe(ok, NONAKTIF).length, 0);
  assert.equal(nilai(`select status from fakta.periode where id = ${periode3}`), "dirilis");
});

test("8b-3: 6 angka tanpa perintah yang menunggu -> dihapus; 'pin' tanpa garis miring dari karyawan -> dihapus dan ditolak", async () => {
  const awal = terkirim.length;
  const enam = (await kirimUpdate(teksPribadi(9961, HRD, "123123"))).pesan[0].text;
  assert.match(enam, /Tidak ada perintah yang sedang menunggu PIN/);
  // Paket 8d-2: pesan menunjuk langkah yang terlewat (tekan tombol dulu, baru PIN).
  assert.match(enam, /Tekan dulu tombolnya \(misalnya Rilis, Setujui, atau salah satu periode di Total lengkap\)/);
  assert.match((await kirimUpdate(teksPribadi(9962, KARYAWAN_BARU, "pin 482913"))).pesan[0].text, /PIN hanya untuk akun HRD, bos, dan pembangun/);
  assert.deepEqual(dihapus(awal), [9961, 9962]);
});

test("8b-3: /hapuspin hanya pembangun; PIN HRD dihapus lewat tombol; HRD diberi tahu lalu membuat PIN baru", async () => {
  assert.match((await kirimUpdate(teksPribadi(9963, HRD, "/hapuspin"))).pesan[0].text, /hanya untuk akun pembangun/);
  const d = await kirimUpdate(teksPribadi(9964, PEMBANGUN, "/hapuspin"));
  const idHrd = nilai(`select id from induk.pengguna where telegram_id = ${HRD}`);
  const tombol = d.pesan[0].reply_markup.inline_keyboard.flat();
  assert.ok(tombol.some((t: any) => t.callback_data === `h|y|${idHrd}`), JSON.stringify(tombol));
  const h = await kirimUpdate(tekanTombol(9965, PEMBANGUN, `h|y|${idHrd}`));
  assert.match(pesanKe(h, PEMBANGUN)[0].text, /dihapus\. Pemilik akun membuat PIN baru/);
  assert.match(pesanKe(h, HRD)[0].text, /^PIN Anda dihapus oleh pembangun\./);
  assert.equal(nilai(`select pin_tersamar is null from induk.pengguna where telegram_id = ${HRD}`), "t");
  assert.match((await kirimUpdate(teksPribadi(9966, HRD, "/pin 905172"))).pesan[0].text, /^PIN dibuat/);
  assert.equal(nilai(`select count(*) from fakta.hapus_pin`), "1");
});

test("8b-3: /undang bos hanya pembangun; 'gabung KODE' -> akun bos terdaftar, menu dipasang, pembangun diberi tahu", async () => {
  assert.match((await kirimUpdate(teksPribadi(9967, HRD, "/undang bos"))).pesan[0].text, /hanya untuk akun pembangun/);
  assert.match((await kirimUpdate(teksPribadi(9968, PEMBANGUN, "/undang"))).pesan[0].text, /^Cara pakai: \/undang hrd/);
  const u = await kirimUpdate(teksPribadi(9969, PEMBANGUN, "/undang bos"));
  const kode = /Kode undangan bos: ([A-Z0-9]{10})/.exec(u.pesan[0].text)?.[1];
  assert.ok(kode, u.pesan[0].text);
  assert.equal(nilai(`select count(*) from fakta.undangan_akun where position('${kode}' in sidik) > 0`), "0");
  const BOS_BARU = 6002;
  const awal = terkirim.length;
  const g = await kirimUpdate(teksPribadi(9970, BOS_BARU, `gabung ${kode.toLowerCase()}`));
  assert.match(pesanKe(g, BOS_BARU)[0].text, /^Terdaftar sebagai bos\./);
  assert.match(pesanKe(g, PEMBANGUN)[0].text, /Kode undangan bos sudah dipakai/);
  const menu = disetel(awal);
  assert.equal(menu.length, 1);
  assert.deepEqual(menu[0].scope, { type: "chat", chat_id: BOS_BARU });
  assert.deepEqual(menu[0].commands, MENU.bos);
  assert.equal(nilai(`select peran from induk.pengguna where telegram_id = ${BOS_BARU}`), "bos");
  assert.match((await kirimUpdate(teksPribadi(9971, BOS_BARU, `/gabung ${kode}`))).pesan[0].text, /sudah terdaftar sebagai bos/);
  assert.match((await kirimUpdate(teksPribadi(9972, BOS_BARU, "/bantuan"))).pesan[0].text, /tombol Setujui dan Tolak/);
});

// ---------------------------------------------------------------------------
// Paket 8b-4: tombol tetap di bawah kolom ketik.
// ---------------------------------------------------------------------------

const balas = (u: number, dari: number, text: string, tanya: string) => JSON.stringify({ update_id: u, message: {
  message_id: u, chat: { id: dari, type: "private" }, from: { id: dari }, text,
  reply_to_message: { message_id: u - 1, from: { id: 1, is_bot: true }, text: tanya } } });
const papan = (p: any) => p.reply_markup.keyboard.map((b: any[]) => b.map((t) => t.text));

test("8b-4: /bantuan memasang tombol tetap sesuai peran (HRD, pembangun, bos)", async () => {
  assert.deepEqual(papan((await kirimUpdate(teksPribadi(9980, HRD, "/bantuan"))).pesan[0]), TOMBOL_TETAP.hrd);
  assert.deepEqual(papan((await kirimUpdate(teksPribadi(9981, PEMBANGUN, "Bantuan"))).pesan[0]), TOMBOL_TETAP.pembangun);
  assert.deepEqual(papan((await kirimUpdate(teksPribadi(9982, BOS, "/start"))).pesan[0]), TOMBOL_TETAP.bos);
  // Paket 8c: karyawan kini punya tombol tetap (Gaji saya, Bantuan); akun tak dikenal tanpa tombol.
  const k = await kirimUpdate(teksPribadi(9983, KARYAWAN_BARU, "/bantuan"));
  assert.deepEqual(papan(k.pesan[0]), TOMBOL_TETAP.karyawan);
  assert.equal((await kirimUpdate(teksPribadi(9979, 4242, "/bantuan"))).pesan[0].reply_markup.remove_keyboard, true);
});

test("8b-4: tombol 'Kirim file', 'Ajukan', 'Rilis', 'Hapus PIN' sama dengan perintahnya", async () => {
  const tanpaKode = (r: { pesan: any[] }) => r.pesan.map((p) => String(p.text).replace(/#kode=[0-9a-f]{64}/, "#kode=X"));
  assert.deepEqual(tanpaKode(await kirimUpdate(teksPribadi(9984, HRD, "Kirim file"))),
    tanpaKode(await kirimUpdate(teksPribadi(9985, HRD, "/unggah"))));
  assert.deepEqual((await kirimUpdate(teksPribadi(9986, HRD, "Rilis"))).pesan.map((p) => p.text),
    (await kirimUpdate(teksPribadi(9987, HRD, "/rilis"))).pesan.map((p) => p.text));
  assert.match((await kirimUpdate(teksPribadi(9988, PEMBANGUN, "Hapus PIN"))).pesan[0].text, /^Pilih akun yang PIN-nya dihapus/);
  assert.match((await kirimUpdate(teksPribadi(9989, KARYAWAN_BARU, "Kode karyawan"))).pesan[0].text, /hanya untuk HRD/);
});

test("8b-4: tombol 'Kode karyawan' bertanya ID -> balasan ID membuat kode daftar", async () => {
  const t = await kirimUpdate(teksPribadi(9990, HRD, "Kode karyawan"));
  assert.ok(t.pesan[0].text.startsWith(TANYA_ID));
  assert.equal(t.pesan[0].reply_markup.force_reply, true);
  const id = nilai(`select k.id from induk.karyawan k where fakta.karyawan_aktif(k.id)
                    and not exists (select 1 from induk.pengguna u where u.id_karyawan = k.id) order by k.id limit 1`);
  const r = await kirimUpdate(balas(9991, HRD, id, t.pesan[0].text));
  assert.match(r.pesan[0].text, new RegExp(`^Kode daftar untuk ${id} `));
});

test("8b-4: tombol 'PIN' bertanya -> balasan 'PIN lama PIN baru' mengganti PIN; pesan dihapus; format salah ditolak", async () => {
  const t = await kirimUpdate(teksPribadi(9992, HRD, "PIN"));
  assert.ok(t.pesan[0].text.startsWith(TANYA_PIN));
  const awal = terkirim.length;
  assert.match((await kirimUpdate(balas(9993, HRD, "905172 640913 1", t.pesan[0].text))).pesan[0].text, /^Format salah/);
  assert.match((await kirimUpdate(balas(9994, HRD, "905172 640913", t.pesan[0].text))).pesan[0].text, /^PIN diganti/);
  assert.deepEqual(dihapus(awal), [9993, 9994]);
  assert.match((await kirimUpdate(balas(9995, HRD, "640913", t.pesan[0].text))).pesan[0].text, /^PIN sudah ada/);
});

test("8b-4: tombol 'Undang' -> pilihan HRD/Bos -> kode undangan; tombol 'Batalkan pengajuan' memanggil /batal", async () => {
  const u = await kirimUpdate(teksPribadi(9996, PEMBANGUN, "Undang"));
  assert.deepEqual(u.pesan[0].reply_markup.inline_keyboard[0].map((t: any) => t.callback_data), ["u|hrd", "u|bos"]);
  assert.match((await kirimUpdate(tekanTombol(9997, PEMBANGUN, "u|hrd"))).pesan[0].text, /^Kode undangan HRD: [A-Z0-9]{10}/);
  assert.match((await kirimUpdate(tekanTombol(9998, HRD, "u|bos"))).pesan[0].text, /hanya untuk akun pembangun/);
  assert.match((await kirimUpdate(tekanTombol(9999, HRD, `b|y|${periode3}`))).pesan[0].text, /tidak sedang diajukan atau disetujui \(status: dirilis\)/);
});

// ---------------------------------------------------------------------------
// Paket 8b-5: Sheets diisi ulang sesudah status periode berubah; tombol tetap kembali sesudah pertanyaan dijawab.
// ---------------------------------------------------------------------------

test("8b-5: ajukan dan batal yang ditolak (status tidak berubah) tidak memicu Isi Sheets", async () => {
  const periode4 = Number(nilai("select id from fakta.periode where tanggal_awal = '2026-11-21'"));
  const awal = dipicu.length;
  await kirimUpdate(tekanTombol(10001, HRD, `a|y|${periode4}|0`));
  await kirimUpdate(teksPribadi(10002, HRD, `/batal ${periode4}`));
  assert.equal(dipicu.length, awal, "status tidak berubah -> Sheets tidak dipicu");
});

test("8b-5: setiap perubahan status (ajukan, batal, ajukan, setuju, rilis di uji 8b-3) memicu Isi Sheets dan tercatat", async () => {
  const terakhir = dipicu.filter((d) => d.pemicu === "status periode");
  assert.ok(terakhir.length >= 4, JSON.stringify(dipicu.slice(-6)));
  assert.ok(terakhir.every((d) => d.waktu_file === ""));
  assert.equal(nilai(`select count(*) from fakta.picu_sheets where waktu_file is null and hasil = 'terkirim'`), String(terakhir.length));
});

test("8b-5: jawaban pertanyaan PIN mengembalikan tombol tetap", async () => {
  const t = await kirimUpdate(teksPribadi(10003, HRD, "PIN"));
  const r = await kirimUpdate(balas(10004, HRD, "640913 715208", t.pesan[0].text));
  assert.match(r.pesan[0].text, /^PIN diganti/);
  assert.deepEqual(papan(r.pesan[0]), TOMBOL_TETAP.hrd);
});

// ---------------------------------------------------------------------------
// Paket 8c: pesan rincian gaji ke karyawan.
// ---------------------------------------------------------------------------

const contohIsi = (bukti = "hadir 20 hari") => ({
  periode_id: 7, awal: "2026-01-21", akhir: "2026-02-20", bayar: "2026-02-25", id: "10001", nama: "Eka", divisi: "Jahit",
  cara_bayar: "tunai", pendapatan: 3000, potongan: -150, bersih: 2850, dibayar: 2000, sisa: 850,
  komponen: [
    { komponen: "gaji_pokok", kelompok: "pendapatan", nominal: 3000, bukti },
    { komponen: "pph21", kelompok: "potongan", nominal: -150, bukti: "TER" },
    { komponen: "bpjs_jht_perusahaan", kelompok: "perusahaan", nominal: 111, bukti: "3,7%" },
  ],
});

test("8c: susun pesan gaji: komponen, potongan bertanda minus, dibayar tunai, sisa pembulatan (E09), bagian perusahaan", () => {
  const [p, ...lain] = susunPesanGaji(contohIsi());
  assert.equal(lain.length, 0);
  assert.equal(rupiahBot(-150), "-Rp150");
  for (const bagian of ["RINCIAN GAJI\nPeriode no. 7: 2026-01-21 s.d. 2026-02-20, dibayar 2026-02-25.\nEka (ID 10001), Jahit.",
    "- Gaji pokok: Rp3.000\n  (hadir 20 hari)", "- PPh 21: -Rp150", "GAJI BERSIH: Rp2.850", "Dibayar tunai: Rp2.000",
    "Sisa pembulatan Rp850 dibawa ke periode berikutnya.", "Dibayar perusahaan untuk Anda (tidak memotong gaji):\n- BPJS JHT: Rp111"]) {
    assert.ok(p.includes(bagian), bagian);
  }
});

test("8c: pesan gaji panjang dipecah di antara baris, tiap bagian <= batas Telegram, bernomor (1/n)", () => {
  const isi = contohIsi();
  isi.komponen = Array.from({ length: 30 }, (_, i) => ({ komponen: `tunjangan_${i}`, kelompok: "pendapatan", nominal: 1000 + i,
    bukti: "x".repeat(500) }));
  const bagian = susunPesanGaji(isi);
  assert.ok(bagian.length >= 3, String(bagian.length));
  for (const [i, b] of bagian.entries()) {
    assert.ok(b.length <= BATAS + 20, String(b.length));
    assert.ok(b.startsWith(`(${i + 1}/${bagian.length})\n`));
  }
  assert.ok(bagian.join("\n").includes("- Tunjangan 29: Rp1.029"));
});

test("8c: penjadwal mengirim antrean: karyawan terdaftar menerima rincian + tombol Gaji saya; periode dikunci; ringkasan ke HRD/pembangun", async () => {
  const menunggu = Number(nilai("select count(*) from fakta.kirim_gaji where status = 'menunggu'"));
  assert.ok(menunggu >= 3, String(menunggu));
  const r = await picuPengingat({ tugas: "kirim_gaji" });
  assert.equal(r.status, 200);
  assert.equal(r.hasil.terkirim, menunggu);
  const ke = r.pesan.filter((p) => p.chat_id === KARYAWAN_BARU);
  assert.equal(ke.filter((p) => p.text.startsWith("RINCIAN GAJI")).length, 3, JSON.stringify(ke.map((p) => p.text.slice(0, 40))));
  assert.match(ke[0].text, /\(ID 10001\)/);
  assert.deepEqual(papan(ke[0]), TOMBOL_TETAP.karyawan);
  assert.equal(nilai("select count(*) from fakta.kirim_gaji where status in ('menunggu', 'sedang')"), "0");
  assert.equal(nilai(`select string_agg(status, ',' order by id) from fakta.periode where status in ('dirilis', 'dikunci')`),
    "dikunci,dikunci,dikunci");
  for (const tg of [HRD, PEMBANGUN]) {
    assert.equal(r.pesan.filter((p) => p.chat_id === tg && /^Pesan gaji periode no\. \d+ selesai dikirim: /.test(p.text)).length, 3);
  }
  assert.equal(r.pesan.filter((p) => p.chat_id === NONAKTIF).length, 0);
  const lagi = await picuPengingat({ tugas: "kirim_gaji" });
  assert.equal(lagi.hasil.terkirim + lagi.pesan.length, 0);
});

test("8c: 'Gaji saya' -> rincian periode terakhir; /gaji <nomor> -> periode itu; salah ketik dan HRD ditolak", async () => {
  const g = await kirimUpdate(teksPribadi(10101, KARYAWAN_BARU, "Gaji saya"));
  assert.match(g.pesan[0].text, new RegExp(`^RINCIAN GAJI\nPeriode no\\. ${periode3}:`));
  const n = Number(nilai("select id from fakta.periode where tanggal_awal = '2026-01-21'"));
  assert.match((await kirimUpdate(teksPribadi(10102, KARYAWAN_BARU, `gaji ${n}`))).pesan[0].text, new RegExp(`Periode no\\. ${n}:`));
  assert.match((await kirimUpdate(teksPribadi(10103, KARYAWAN_BARU, "/gaji abc"))).pesan[0].text, /^Cara pakai: \/gaji/);
  assert.match((await kirimUpdate(teksPribadi(10104, HRD, "/gaji"))).pesan[0].text, /untuk karyawan yang sudah terdaftar/);
});

// Contoh untuk periode yang belum dirilis (versi berlaku) diuji di db/uji/210_pesan_gaji.sql.
test("8c: /contohgaji: HRD ya; orang rahasia hanya pembangun; karyawan ditolak", async () => {
  const p4 = periode3;
  const biasa = nilai(`select g.id_karyawan from hitung.ringkasan_gaji g where g.versi_id = fakta.versi_gaji_berlaku(${p4})
                       and not fakta.rahasia_di_periode(g.id_karyawan, ${p4}) order by 1 limit 1`);
  const c = await kirimUpdate(teksPribadi(10105, HRD, `/contohgaji ${biasa} ${p4}`));
  assert.match(c.pesan[0].text, new RegExp(`^CONTOH RINCIAN GAJI \\(pesan yang diterima karyawan\\)\nPeriode no\\. ${p4}:`));
  const rahasia = nilai(`select g.id_karyawan from hitung.ringkasan_gaji g
                         where g.versi_id = fakta.versi_gaji_berlaku(${p4}) and fakta.rahasia_di_periode(g.id_karyawan, ${p4})
                         order by 1 limit 1`);
  const bukanRahasiaTapiRahasiaKini = nilai(`select g.id_karyawan from hitung.ringkasan_gaji g join induk.karyawan_riwayat r
                         on r.id_karyawan = g.id_karyawan and r.gaji_rahasia
                         where g.versi_id = fakta.versi_gaji_berlaku(${p4}) order by 1 limit 1`);
  // Celah yang tertangkap saat membuat 8c: orang yang rahasia di riwayat mana pun tetap tertutup dari HRD (F15c).
  assert.match((await kirimUpdate(teksPribadi(10114, HRD, `/contohgaji ${bukanRahasiaTapiRahasiaKini} ${p4}`))).pesan[0].text,
    /hanya untuk akun pembangun/);
  assert.match((await kirimUpdate(teksPribadi(10106, HRD, `/contohgaji ${rahasia} ${p4}`))).pesan[0].text, /hanya untuk akun pembangun/);
  assert.match((await kirimUpdate(teksPribadi(10107, PEMBANGUN, `/contohgaji ${rahasia} ${p4}`))).pesan[0].text, /^CONTOH RINCIAN GAJI/);
  assert.match((await kirimUpdate(teksPribadi(10108, KARYAWAN_BARU, `/contohgaji 10001 ${p4}`))).pesan[0].text, /hanya untuk HRD/);
  assert.match((await kirimUpdate(teksPribadi(10109, HRD, "/contohgaji 10001"))).pesan[0].text, /^Cara pakai: \/contohgaji/);
});

test("8c: karyawan yang baru daftar sesudah rilis langsung menerima rincian gaji terakhir + tombol Gaji saya", async () => {
  const id = nilai(`select k.id from induk.karyawan k where fakta.karyawan_aktif(k.id)
                    and exists (select 1 from fakta.kirim_gaji g where g.id_karyawan = k.id and g.periode_id = ${periode3})
                    and not exists (select 1 from induk.pengguna u where u.id_karyawan = k.id) order by k.id limit 1`);
  const kode = /: ([A-HJKMNP-Z2-9]{10})\n/.exec((await kirimUpdate(teksPribadi(10110, HRD, `/kode ${id}`))).pesan[0].text)![1];
  const BARU = 7005;
  const d = await kirimUpdate(teksPribadi(10111, BARU, `/daftar ${kode}`));
  const r = await kirimUpdate(tekanTombol(10112, BARU, d.pesan[0].reply_markup.inline_keyboard[0][0].callback_data));
  assert.match(r.pesan[0].text, /^Terdaftar: /);
  // Paket 8c-3: rincian terakhir sudah ada -> kalimat "akan dikirim setelah gaji dirilis" diganti.
  assert.ok(r.pesan[0].text.endsWith("Rincian gaji terakhir ada di bawah ini; tombol Gaji saya untuk meminta ulang."), r.pesan[0].text);
  assert.deepEqual(papan(r.pesan[0]), TOMBOL_TETAP.karyawan);
  assert.match(r.pesan[1].text, new RegExp(`^RINCIAN GAJI\nPeriode no\\. ${periode3}:[\\s\\S]*\\(ID ${id}\\)`));
  assert.equal(nilai(`select status from fakta.kirim_gaji where id_karyawan = '${id}' and periode_id = ${periode3}`), "terkirim");
});

test("8c: tombol 'menu' dikenali sebagai /bantuan", async () => {
  assert.match((await kirimUpdate(teksPribadi(10113, HRD, "menu"))).pesan[0].text, /^Perintah HRD:/);
});

// Paket 8c-2: sisa pembulatan periode lalu ditulis bila bukan nol (bersih + sisa lalu = dibayar + sisa baru).
test("8c-2: pesan gaji menulis sisa pembulatan lalu bila ada; angka di pesan bisa dicocokkan", () => {
  const isi = { ...contohIsi(), bersih: 3847263, sisa_lalu: 400, dibayar: 3847000, sisa: 663 };
  const p = susunPesanGaji(isi)[0];
  assert.ok(p.includes("GAJI BERSIH: Rp3.847.263\nSisa pembulatan periode lalu (ditambahkan): Rp400\nDibayar tunai: Rp3.847.000"), p);
  assert.ok(p.includes("Sisa pembulatan Rp663 dibawa ke periode berikutnya."));
  assert.equal(isi.bersih + isi.sisa_lalu - isi.dibayar - isi.sisa, 0);
  assert.ok(!susunPesanGaji(contohIsi())[0].includes("periode lalu"));
});

// ---------------------------------------------------------------------------
// Paket 8d: total lengkap untuk bos dan pembangun (dengan PIN), orang rahasia wajib transfer.
// ---------------------------------------------------------------------------

test("8d: susun total lengkap: total, yang terlihat HRD, selisih = jumlah gaji orang rahasia, daftar orang rahasia", () => {
  const [p] = susunTotalLengkap({ periode_id: 2, awal: "2026-02-21", akhir: "2026-03-20", bayar: "2026-03-25", status: "dikunci",
    lengkap: { orang: 1010, bersih: 8216972265, dibayar: 8216958000, transfer: 7085500000, tunai: 1131458000 },
    terlihat: { orang: 1007, bersih: 8191433902 },
    daftar_rahasia: [{ id: "R1", nama: "Rahasia Satu", bersih: 25538363, dibayar: 25538363, cara_bayar: "transfer" }] });
  for (const bagian of ["1.010 orang, gaji bersih Rp8.216.972.265", "Yang terlihat HRD: 1.007 orang, gaji bersih Rp8.191.433.902.",
    "Selisih: 1 orang rahasia, gaji bersih Rp25.538.363.", "- Rahasia Satu (ID R1): bersih Rp25.538.363, dibayar Rp25.538.363 (transfer)"]) {
    assert.ok(p.includes(bagian), bagian);
  }
});

test("8d: HRD dan karyawan tidak bisa melihat total lengkap; bos tidak punya tombol HRD", async () => {
  assert.match((await kirimUpdate(teksPribadi(10201, HRD, "/lengkap"))).pesan[0].text, /hanya untuk akun bos dan pembangun/);
  assert.match((await kirimUpdate(teksPribadi(10202, KARYAWAN_BARU, `/lengkap ${periode3}`))).pesan[0].text, /hanya untuk akun bos dan pembangun/);
  assert.deepEqual(TOMBOL_TETAP.bos, [["Total lengkap", "PIN"], ["Bantuan"]]);
});

test("8d: bos membuat PIN, tombol Total lengkap -> pilih periode -> PIN -> total lengkap (selisih = orang rahasia); tercatat", async () => {
  assert.match((await kirimUpdate(teksPribadi(10203, BOS, "/pin 581374"))).pesan[0].text, /^PIN dibuat/);
  const pilih = await kirimUpdate(teksPribadi(10204, BOS, "Total lengkap"));
  // Paket 8d-2: kalimat menyuruh menekan tombol periode dulu, PIN sesudahnya.
  assert.match(pilih.pesan[0].text, /Tekan salah satu tombol periode di bawah dulu; bot akan meminta PIN sesudahnya\.$/);
  const tombol = pilih.pesan[0].reply_markup.inline_keyboard.flat().map((t: any) => t.callback_data);
  assert.ok(tombol.includes(`l|y|${periode3}`), JSON.stringify(tombol));
  const minta = await kirimUpdate(tekanTombol(10205, BOS, `l|y|${periode3}`));
  assert.match(minta.pesan[0].text, new RegExp(`^Ketik PIN 6 angka untuk melihat total lengkap periode no\\. ${periode3}\\.`));
  const awal = terkirim.length;
  const r = await kirimUpdate(teksPribadi(10206, BOS, "581374"));
  assert.deepEqual(dihapus(awal), [10206]);
  const teks = r.pesan.map((p) => p.text).join("\n");
  assert.match(teks, /^TOTAL LENGKAP \(termasuk orang rahasia/);
  const versi = nilai(`select versi_gaji from fakta.rilis_gaji where periode_id = ${periode3}`);
  const rahasia = Number(nilai(`select count(*) from hitung.ringkasan_gaji g where g.versi_id = ${versi}
                                and fakta.rahasia_di_periode(g.id_karyawan, ${periode3})`));
  const selisih = nilai(`select coalesce(sum(g.gaji_bersih), 0) from hitung.ringkasan_gaji g where g.versi_id = ${versi}
                         and fakta.rahasia_di_periode(g.id_karyawan, ${periode3})`);
  assert.ok(rahasia > 0);
  assert.ok(teks.includes(`Selisih: ${rahasia.toLocaleString("id-ID")} orang rahasia, gaji bersih Rp${Number(selisih).toLocaleString("id-ID")}.`), teks);
  assert.equal(nilai(`select count(*) from fakta.lihat_rahasia l join induk.pengguna u on u.id = l.pengguna where u.telegram_id = ${BOS}`), "1");
});

test("8d: /lengkap <nomor> <PIN> salah -> ditolak; pembangun bisa; /bantuan bos memasang tombol Total lengkap", async () => {
  assert.match((await kirimUpdate(teksPribadi(10207, BOS, `/lengkap ${periode3} 000001`))).pesan[0].text, /^PIN salah/);
  assert.match((await kirimUpdate(teksPribadi(10208, PEMBANGUN, `/lengkap ${periode3} ${PIN_PEMBANGUN}`))).pesan[0].text, /^TOTAL LENGKAP/);
  assert.deepEqual(papan((await kirimUpdate(teksPribadi(10209, BOS, "/bantuan"))).pesan[0]), TOMBOL_TETAP.bos);
});

test("8d (i): orang rahasia tidak bisa dicatat dibayar tunai", () => {
  assert.throws(() => psql(`set app.pengguna = 'uji'; insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok,
    ptkp, cara_bayar, gaji_rahasia) select '10001', '2031-01-01', divisi, 1, 'TK/0', 'tunai', true from induk.karyawan_riwayat
    where id_karyawan = '10001' limit 1;`), /rahasia_wajib_transfer/);
});

// ---------------------------------------------------------------------------
// Paket 7a: izin, sakit, cuti lewat chat (docs/rencana-tahap-7.md bagian 5)
// ---------------------------------------------------------------------------

test("7a: membaca tanggal dd-mm-yyyy, dd/mm/yyyy, dd-mm (tahun ini WIB); tanggal tidak ada ditolak", () => {
  const nov2026 = Date.UTC(2026, 10, 21, 3); // 21 Nov 2026 10.00 WIB
  assert.equal(bacaTanggal("30-03-2026", nov2026), "2026-03-30");
  assert.equal(bacaTanggal("30/3/2026", nov2026), "2026-03-30");
  assert.equal(bacaTanggal("30.03", nov2026), "2026-03-30");
  assert.equal(bacaTanggal("01-01", Date.UTC(2026, 11, 31, 18)), "2027-01-01"); // 1 Jan 2027 01.00 WIB
  assert.equal(bacaTanggal("30-02-2026", nov2026), null);
  assert.equal(bacaTanggal("2026-03-30", nov2026), null);
  assert.equal(tulisTanggal("2026-03-30"), "Senin, 30 Mar 2026");
});

test("7a: membaca isi perintah: ID, tanggal, tanggal selesai, catatan", () => {
  const t = Date.UTC(2026, 10, 21, 3);
  assert.deepEqual(bacaPerintah("10067 30-03-2026", t), { id: "10067", mulai: "2026-03-30", selesai: "2026-03-30", catatan: "" });
  assert.deepEqual(bacaPerintah("10067 30-03 31-03 urusan keluarga", t),
    { id: "10067", mulai: "2026-03-30", selesai: "2026-03-31", catatan: "urusan keluarga" });
  assert.deepEqual(bacaPerintah("10067 30-03-2026 2 hari", t), { id: "10067", mulai: "2026-03-30", selesai: "2026-03-30", catatan: "2 hari" });
  assert.match((bacaPerintah("10067", t) as any).salah, /^Cara pakai/);
  assert.match((bacaPerintah("10067 31-04-2026", t) as any).salah, /^Tanggal "31-04-2026" tidak dikenali/);
  assert.match((bacaPerintah("10067 30-03 31-13", t) as any).salah, /^Tanggal "31-13" tidak dikenali/);
});

const jumlahPerintahChat = () => nilai("select count(*) from fakta.perintah_hrd where asal = 'chat'");
const statusHari = (id: string, hari: string) => nilai(`select hh.status from hitung.hasil_harian hh
  join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
  join fakta.periode p on p.id = v.periode_id and '${hari}'::date between p.tanggal_awal and p.tanggal_akhir
  where hh.id_karyawan = '${id}' and hh.tanggal = '${hari}'`);
let tombolYa7a = "";

test("7a: karyawan ditolak; periode dirilis ditolak; ID tidak ada ditolak; tidak ada yang dicatat", async () => {
  assert.equal((await kirimUpdate(teksPribadi(10301, KARYAWAN_BARU, "/izin 10067 25-11-2026"))).pesan[0].text, "Perintah ini hanya untuk HRD.");
  const dirilis = await kirimUpdate(teksPribadi(10302, HRD, "/izin 10067 30-03-2026"));
  assert.match(dirilis.pesan[0].text, /^Ditolak: Senin, 30 Mar 2026 masuk periode no\. \d+ \(2026-03-21 s\.d\. 2026-04-20\) yang gajinya sudah (dirilis|dikunci)/);
  assert.match((await kirimUpdate(teksPribadi(10303, HRD, "/izin 99999 25-11-2026"))).pesan[0].text, /^Karyawan dengan ID 99999 tidak ada/);
  assert.match((await kirimUpdate(teksPribadi(10304, HRD, "/izin 10067 31-11-2026"))).pesan[0].text, /^Tanggal "31-11-2026" tidak dikenali/);
  assert.equal(jumlahPerintahChat(), "0");
});

test("7a: /izin (susulan) -> konfirmasi berisi nama, status sekarang, periode; tombol Ya/Batal; belum dicatat", async () => {
  const r = await kirimUpdate(teksPribadi(10305, HRD, "/izin 10067 25-11-2026 urusan keluarga"));
  const k = r.pesan[0];
  assert.match(k.text, /^Catat IZIN untuk 10067 .+ \(.+\)\?\nTanggal: Rabu, 25 Nov 2026\nCatatan: urusan keluarga\nStatus sekarang:\n• Rabu, 25 Nov 2026: /);
  assert.match(k.text, /periode no\. \d+ \(2026-11-21 s\.d\. 2026-12-20\) dihitung ulang/);
  assert.doesNotMatch(k.text, /Rp|gaji bersih/);
  const [ya, batal] = k.reply_markup.inline_keyboard[0];
  assert.match(ya.callback_data, /^c\|y\|\d+$/);
  assert.match(batal.callback_data, /^c\|n\|\d+$/);
  tombolYa7a = ya.callback_data;
  assert.equal(jumlahPerintahChat(), "0");
});

test("7a GERBANG: Ya -> tercatat oleh HRD, periode dihitung ulang, Sheets dipicu, hasil 'sebelum -> izin'", async () => {
  const sebelumPicu = dipicu.length;
  const r = await kirimUpdate(tekanTombol(10306, HRD, tombolYa7a));
  const teks = r.pesan.map((p) => p.text as string);
  assert.match(teks[0], /^Tercatat: perintah no\. \d+, IZIN 10067 .+, Rabu, 25 Nov 2026\. Menghitung ulang periode no\. \d+/);
  assert.ok(teks.some((t) => t.startsWith("Periode 2026-11-21 s.d. 2026-12-20: ")), JSON.stringify(teks));
  const hasil = teks.find((t) => t.startsWith("Hasil IZIN 10067"));
  assert.ok(hasil, JSON.stringify(teks));
  assert.match(hasil!, /• Rabu, 25 Nov 2026: .+ → izin$/);
  assert.equal(statusHari("10067", "2026-11-25"), "izin");
  assert.equal(nilai(`select x.asal || '/' || x.jenis || '/' || u.telegram_id || '/' || x.alasan from fakta.perintah_hrd x
                      join induk.pengguna u on u.id = x.oleh where x.asal = 'chat'`), `chat/izin/${HRD}/urusan keluarga`);
  assert.equal(dipicu.length, sebelumPicu + 1);
  assert.equal(dipicu[dipicu.length - 1].pemicu, "perintah HRD");
  assert.ok(r.pesan.every((p) => !/Rp\d/.test(p.text) || p.text.startsWith("Periode ")), "hanya kabar periode yang memuat total");
  const lagi = await kirimUpdate(tekanTombol(10307, HRD, tombolYa7a));
  assert.match(lagi.pesan[0].text, /^Tombol ini sudah tidak berlaku/);
  assert.equal(jumlahPerintahChat(), "1");
});

test("7a: tombol 'Perintah HRD' bertanya -> balasan tanpa garis miring -> konfirmasi; balasan salah -> cara pakai", async () => {
  const t = await kirimUpdate(teksPribadi(10308, PEMBANGUN, "Perintah HRD"));
  assert.ok(t.pesan[0].text.startsWith(TANYA_PERINTAH));
  assert.equal(t.pesan[0].reply_markup.force_reply, true);
  const salah = await kirimUpdate(balas(10309, PEMBANGUN, "halo", t.pesan[0].text));
  assert.equal(salah.pesan[0].text, CARA_PERINTAH);
  const r = await kirimUpdate(balas(10310, PEMBANGUN, "sakit 10067 25-11-2026 26-11-2026", t.pesan[0].text));
  assert.match(r.pesan[0].text, /^Catat SAKIT untuk 10067 .+\nTanggal: Rabu, 25 Nov 2026 s\.d\. Kamis, 26 Nov 2026 \(2 hari\)/);
  assert.match(r.pesan[0].text, /• Rabu, 25 Nov 2026: izin \(perintah izin no\. \d+ diganti\)/);
  const batal = await kirimUpdate(tekanTombol(10311, PEMBANGUN, r.pesan[0].reply_markup.inline_keyboard[0][1].callback_data));
  assert.equal(batal.pesan[0].text, "Tidak jadi dicatat.");
  assert.equal(jumlahPerintahChat(), "1");
  assert.equal(statusHari("10067", "2026-11-25"), "izin");
  assert.match((await kirimUpdate(teksPribadi(10312, KARYAWAN_BARU, "Perintah HRD"))).pesan[0].text, /hanya untuk HRD/);
});

test("7a: tombol tetap HRD dan pembangun memuat 'Perintah HRD'; menu memuat izin, sakit, cuti", () => {
  for (const peran of ["hrd", "pembangun"]) {
    assert.ok(TOMBOL_TETAP[peran].flat().includes("Perintah HRD"));
    for (const c of ["izin", "sakit", "cuti"]) assert.ok(MENU[peran].some((m) => m.command === c), `${peran} ${c}`);
  }
  assert.ok(!TOMBOL_TETAP.karyawan.flat().includes("Perintah HRD"));
});

// ---------------------------------------------------------------------------
// Paket 7d: membatalkan perintah lewat chat, /perintahku (docs/rencana-tahap-7.md bagian 7)
// ---------------------------------------------------------------------------

test("7d: /perintahku dan /batalperintah hanya HRD/pembangun; nomor salah dijawab cara pakai", async () => {
  assert.match((await kirimUpdate(teksPribadi(10401, KARYAWAN_BARU, "/perintahku"))).pesan[0].text, /hanya untuk HRD/);
  assert.match((await kirimUpdate(teksPribadi(10402, KARYAWAN_BARU, "/batalperintah 1"))).pesan[0].text, /hanya untuk HRD/);
  assert.match((await kirimUpdate(teksPribadi(10403, HRD, "/batalperintah abc"))).pesan[0].text, /^Cara pakai: \/batalperintah <nomor perintah>/);
  assert.match((await kirimUpdate(teksPribadi(10404, HRD, "/batalperintah 99999999"))).pesan[0].text, /^Perintah no\. 99999999 tidak ada/);
  const izin = nilai("select id from fakta.perintah_hrd where asal = 'chat' and jenis = 'izin'");
  const daftar = (await kirimUpdate(teksPribadi(10405, HRD, "/perintahku"))).pesan[0].text as string;
  assert.match(daftar, new RegExp(`^10 perintah chat terakhir \\(terbaru di atas\\):\\nno\\. ${izin} · IZIN · 10067 .+ · 25 Nov 2026 · hrd `));
  assert.doesNotMatch(daftar, /DIBATALKAN/);
});

test("7d: /batalperintah -> konfirmasi -> Ya -> izin dibatalkan, hari kembali dari data mesin; kedua kali ditolak", async () => {
  const izin = nilai("select id from fakta.perintah_hrd where asal = 'chat' and jenis = 'izin'");
  const k = (await kirimUpdate(teksPribadi(10406, HRD, `/batalperintah ${izin}`))).pesan[0];
  assert.match(k.text, new RegExp(`^Batalkan perintah no\\. ${izin}: IZIN 10067 .+\\?\\nTanggal: Rabu, 25 Nov 2026\\nDicatat lewat: chat, catatan: urusan keluarga\\n` +
    "Status sekarang:\\n• Rabu, 25 Nov 2026: izin\\n"));
  assert.match(k.text, /Periode no\. \d+ \(2026-11-21 s\.d\. 2026-12-20\) dihitung ulang\./);
  assert.doesNotMatch(k.text, /Rp/);
  const ya = k.reply_markup.inline_keyboard[0][0];
  assert.equal(ya.text, "Ya, batalkan");
  const r = await kirimUpdate(tekanTombol(10407, HRD, ya.callback_data));
  const teks = r.pesan.map((p) => p.text as string);
  assert.match(teks[0], new RegExp(`^Tercatat: perintah no\\. \\d+, pembatalan perintah no\\. ${izin} 10067 `));
  assert.doesNotMatch(teks[0], /Salah catat\?/);
  const hasil = teks.find((t) => t.startsWith("Hasil PEMBATALAN 10067"));
  assert.ok(hasil, JSON.stringify(teks));
  assert.match(hasil!, /• Rabu, 25 Nov 2026: izin → /);
  assert.notEqual(statusHari("10067", "2026-11-25"), "izin");
  assert.equal(nilai(`select count(*) from fakta.perintah_hrd where jenis = 'batalkan_perintah' and membatalkan = ${izin}`), "1");
  assert.match((await kirimUpdate(teksPribadi(10408, HRD, `/batalperintah ${izin}`))).pesan[0].text,
    new RegExp(`^Perintah no\\. ${izin} sudah dibatalkan oleh perintah no\\. \\d+`));
  const daftar = (await kirimUpdate(teksPribadi(10409, PEMBANGUN, "perintahku"))).pesan[0].text as string;
  assert.match(daftar, /\nno\. \d+ · batalkan no\. \d+ · 10067 /);
  assert.match(daftar, new RegExp(`no\\. ${izin} · IZIN · .+ · DIBATALKAN \\(no\\. \\d+\\)`));
});

test("7d: pesan Tercatat 7a memberi petunjuk /batalperintah; menu memuat batalperintah dan perintahku", async () => {
  const k = (await kirimUpdate(teksPribadi(10410, HRD, "/cuti 10067 26-11-2026"))).pesan[0];
  const r = await kirimUpdate(tekanTombol(10411, HRD, k.reply_markup.inline_keyboard[0][0].callback_data));
  assert.match(r.pesan[0].text, /\nSalah catat\? Ketik \/batalperintah \d+$/);
  for (const peran of ["hrd", "pembangun"]) {
    for (const c of ["batalperintah", "perintahku"]) assert.ok(MENU[peran].some((m) => m.command === c), `${peran} ${c}`);
  }
});

// ---------------------------------------------------------------------------
// Paket 7b: kasbon lewat chat (docs/rencana-tahap-7.md bagian 8)
// ---------------------------------------------------------------------------

test("7b: membaca jumlah uang", () => {
  for (const [t, n] of [["1000000", 1000000], ["1.000.000", 1000000], ["1,000,000", 1000000], ["1jt", 1000000], ["1,5jt", 1500000],
    ["1.5 juta".replace(" ", ""), 1500000], ["250rb", 250000], ["250ribu", 250000], ["500k", 500000], ["Rp250.000", 250000]] as const) {
    assert.equal(bacaUang(t), n, t);
  }
  for (const t of ["0", "-5", "abc", "1.00.000", "1,2345678jt", "", "1.5"]) assert.equal(bacaUang(t), null, t);
});

// Kasbon berlaku menurut tanggal hari ini (WIB): pastikan ada periode yang memuat hari ini.
const hariIni = () => nilai("select (now() at time zone 'Asia/Jakarta')::date");
let periodeKasbon = "";
let perintahKasbon = "";

test("7b: /kasbon <ID> menampilkan saldo; cicilan wajib; pelunasan melebihi saldo ditolak; karyawan ditolak", async () => {
  if (nilai(`select count(*) from fakta.periode where '${hariIni()}'::date between tanggal_awal and tanggal_akhir`) === "0") {
    nilai(`insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar)
           select greatest(max(tanggal_akhir) + 1, '${hariIni()}'::date - 20), '${hariIni()}'::date + 20, '${hariIni()}'::date + 25
           from fakta.periode returning id`);
  }
  periodeKasbon = nilai(`select id from fakta.periode where '${hariIni()}'::date between tanggal_awal and tanggal_akhir`);
  assert.match((await kirimUpdate(teksPribadi(10501, KARYAWAN_BARU, "/kasbon 10067 1jt 250rb"))).pesan[0].text, /hanya untuk HRD/);
  const saldo = (await kirimUpdate(teksPribadi(10502, HRD, "/kasbon 10067"))).pesan[0].text as string;
  assert.match(saldo, /^Kasbon 10067 .+:\nSaldo sesudah potongan yang sudah dihitung: Rp0\n/);
  assert.match(saldo, /Belum ada catatan kasbon\.$/);
  assert.match((await kirimUpdate(teksPribadi(10503, HRD, "/kasbon 10067 1.000.000"))).pesan[0].text, /^Cicilan per periode wajib diisi/);
  assert.match((await kirimUpdate(teksPribadi(10504, HRD, "/kasbon 10067 sejuta 1"))).pesan[0].text, /^Jumlah "sejuta" tidak dikenali\. Cara pakai/);
  assert.match((await kirimUpdate(teksPribadi(10505, HRD, "/lunas 10067 5jt"))).pesan[0].text,
    /^Ditolak: pelunasan melebihi saldo kasbon 10067 .+ \(Rp0, sesudah potongan yang sudah dihitung\)/);
  assert.equal((await kirimUpdate(teksPribadi(10506, HRD, "/cicilan"))).pesan[0].text, CARA_KASBON);
  assert.equal(nilai("select count(*) from fakta.buku_kasbon"), "0");
});

test("7b: /kasbon pinjam -> konfirmasi -> Ya -> tercatat dengan pencatat, potongan muncul di periode berjalan", async () => {
  const k = (await kirimUpdate(teksPribadi(10507, HRD, "/kasbon 10067 1jt 250rb biaya sekolah"))).pesan[0];
  assert.match(k.text, /^Catat KASBON \(pinjam\) untuk 10067 .+ \(.+\)\?\nPinjam: Rp1\.000\.000\nCicilan per periode: Rp250\.000\nCatatan: biaya sekolah\n/);
  assert.match(k.text, /\nSaldo kasbon \(sesudah potongan yang sudah dihitung\): Rp0 → Rp1\.000\.000\n/);
  assert.match(k.text, new RegExp(`\\nBerlaku mulai periode no\\. ${periodeKasbon} `));
  const r = await kirimUpdate(tekanTombol(10508, HRD, k.reply_markup.inline_keyboard[0][0].callback_data));
  const teks = r.pesan.map((p) => p.text as string);
  assert.match(teks[0], /^Tercatat: perintah no\. \d+, KASBON pinjam Rp1\.000\.000 \(cicilan Rp250\.000\), 10067 /);
  assert.match(teks[0], /\nSalah catat\? Ketik \/batalperintah \d+$/);
  perintahKasbon = /perintah no\. (\d+)/.exec(teks[0])![1];
  const hasil = teks.find((t) => t.startsWith("Hasil KASBON 10067"));
  assert.ok(hasil, JSON.stringify(teks));
  assert.match(hasil!, new RegExp(`• Potongan kasbon periode no\\. ${periodeKasbon}: Rp0 → Rp[\\d.]+\\n• Sisa saldo sesudah potongan yang sudah dihitung: Rp[\\d.]+\\n• Cicilan per periode: Rp250\\.000$`));
  assert.equal(nilai(`select string_agg(k.jenis || ':' || k.jumlah || ':' || u.telegram_id, ',' order by k.id) from fakta.buku_kasbon k
                      join fakta.perintah_hrd x on x.id = k.perintah_id join induk.pengguna u on u.id = x.oleh`),
    `pinjam:1000000:${HRD},cicilan:250000:${HRD}`);
  const potong = nilai(`select coalesce(-sum(r.nominal), 0) from hitung.rincian_gaji r join hitung.versi_terakhir v on v.id = r.versi_id
                        and v.jenis = 'hitung_gaji' where v.periode_id = ${periodeKasbon} and r.id_karyawan = '10067' and r.komponen = 'kasbon'`);
  assert.ok(Number(potong) > 0 && Number(potong) <= 250000, potong);
  assert.match(hasil!, new RegExp(`→ ${("Rp" + Number(potong).toLocaleString("id-ID")).replace(/\./g, "\\.")}\\n`));
});

test("7b: /batalperintah kasbon -> konfirmasi berisi isi kasbon -> Ya -> potongan hilang", async () => {
  const k = (await kirimUpdate(teksPribadi(10509, PEMBANGUN, `/batalperintah ${perintahKasbon}`))).pesan[0];
  assert.match(k.text, new RegExp(`^Batalkan perintah no\\. ${perintahKasbon}: KASBON 10067 `));
  assert.match(k.text, /\nIsi: pinjam Rp1\.000\.000, cicilan Rp250\.000\nSaldo kasbon sekarang: Rp[\d.]+\nSesudah dibatalkan, catatan kasbon ini tidak dihitung lagi\. /);
  const r = await kirimUpdate(tekanTombol(10510, PEMBANGUN, k.reply_markup.inline_keyboard[0][0].callback_data));
  const hasil = r.pesan.map((p) => p.text as string).find((t) => t.startsWith("Hasil PEMBATALAN KASBON 10067"));
  assert.ok(hasil, JSON.stringify(r.pesan.map((p) => p.text)));
  assert.match(hasil!, new RegExp(`• Potongan kasbon periode no\\. ${periodeKasbon}: Rp[\\d.]+ → Rp0\\n• Sisa saldo sesudah potongan yang sudah dihitung: Rp0\\n`));
  const saldo = (await kirimUpdate(teksPribadi(10511, HRD, "kasbon 10067"))).pesan[0].text as string;
  assert.match(saldo, /Saldo sesudah potongan yang sudah dihitung: Rp0\n/);
  assert.match(saldo, /pinjam Rp1\.000\.000 \(perintah no\. \d+, hrd\) DIBATALKAN/);
  for (const peran of ["hrd", "pembangun"]) for (const c of ["kasbon", "cicilan", "lunas"]) assert.ok(MENU[peran].some((m) => m.command === c));
});

// ---------------------------------------------------------------------------
// Paket 7c-1: setujui/batalkan lembur lewat chat (docs/rencana-tahap-7.md bagian 9)
// ---------------------------------------------------------------------------

test("7c: /setujuilembur divisi di pengaturan otomatis -> konfirmasi memberi tahu tidak mengubah; divisi salah ditolak", async () => {
  assert.match((await kirimUpdate(teksPribadi(10601, KARYAWAN_BARU, "/setujuilembur PRD 26-11-2026"))).pesan[0].text, /hanya untuk HRD/);
  assert.match((await kirimUpdate(teksPribadi(10602, HRD, "/setujuilembur XYZ 26-11-2026"))).pesan[0].text, /^Divisi atau ID "XYZ" tidak ada/);
  assert.match((await kirimUpdate(teksPribadi(10603, HRD, "/batalkanlembur PRD"))).pesan[0].text, /^Cara pakai: \/setujuilembur/);
  const k = (await kirimUpdate(teksPribadi(10604, HRD, "/setujuilembur prd 26-11-2026"))).pesan[0];
  assert.match(k.text, /^Setujui LEMBUR untuk divisi PRD \(Produksi\)\?\nTanggal: Kamis, 26 Nov 2026\nKeadaan sekarang:\n• Kamis, 26 Nov 2026: pengaturan otomatis; \d+ orang pulang 60 menit atau lebih lewat jadwal — lembur sudah dibayar otomatis/);
  assert.equal((await kirimUpdate(tekanTombol(10605, HRD, k.reply_markup.inline_keyboard[0][1].callback_data))).pesan[0].text, "Tidak jadi dicatat.");
  assert.equal(nilai("select count(*) from fakta.perintah_hrd where jenis in ('setujui_lembur', 'batalkan_lembur')"), "0");
});

let perintahLembur7c = "";
let calonLembur: { id: string; tanggal: string } = { id: "", tanggal: "" };

test("7c: /batalkanlembur orang (D05) -> lembur periode itu turun; /batalperintah -> kembali", async () => {
  // Siapkan satu hari lembur di periode terbuka: tap satu orang lima menit sebelum masuk dan 130 menit sesudah jadwal pulang.
  // Mesinnya dipilih yang sudah punya kiriman sampai tutup buku 20-04-2026, supaya uji pengingat (uji_sambung, P7) tidak terganggu.
  const tap = nilai(`select m.mesin || '|' || m.id_mesin || '|' || to_char(hh.jadwal_masuk at time zone 'Asia/Jakarta' - interval '5 minutes', 'YYYY-MM-DD HH24:MI:SS')
      || '|' || to_char(hh.jadwal_pulang at time zone 'Asia/Jakarta' + interval '130 minutes', 'YYYY-MM-DD HH24:MI:SS') || '|' || p.id
    from hitung.hasil_harian hh join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
    join fakta.periode p on p.id = v.periode_id join induk.pemetaan_id_mesin m on m.id_karyawan = hh.id_karyawan
    where hh.id_karyawan <> '10067' and p.status not in ('dirilis', 'dikunci') and hh.kode_jadwal is not null
      and hh.jenis_hari = 'kerja' and not fakta.rahasia_di_periode(hh.id_karyawan, p.id) and fakta.karyawan_aktif(hh.id_karyawan, hh.tanggal)
      and exists (select 1 from fakta.kiriman_file k where k.mesin = m.mesin and k.hasil = 'diterima' and k.tanggal_akhir >= '2026-04-20')
      and hh.tanggal between m.berlaku_dari and coalesce(m.berlaku_sampai - 1, hh.tanggal)
    order by hh.tanggal, hh.id_karyawan limit 1`);
  assert.ok(tap, "ada hari kerja di periode terbuka dengan mesin yang sudah mengirim");
  const [mesin, idMesin, masuk, pulang, periode] = tap.split("|");
  nilai(`select fakta.terima_kiriman('uji7c.csv', md5('uji7c') || md5('uji7c'), '${mesin}',
    '[["${idMesin}", "${masuk}", "Masuk", 1], ["${idMesin}", "${pulang}", "Keluar", 2]]'::jsonb, null, now())`);
  nilai(`select hitung.baca_tap(${periode}) + hitung.hitung_gaji(${periode})`);
  const baris = nilai(`select hh.id_karyawan || '|' || to_char(hh.tanggal, 'DD-MM-YYYY') from hitung.hasil_harian hh
    join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap' join fakta.periode p on p.id = v.periode_id
    where p.status not in ('dirilis', 'dikunci') and hh.status = 'hadir' and hh.menit_lebih >= 120
      and not fakta.rahasia_di_periode(hh.id_karyawan, p.id)
      and fakta.karyawan_aktif(hh.id_karyawan, hh.tanggal) order by hh.tanggal, hh.id_karyawan limit 1`);
  assert.ok(baris, "ada calon hari lembur di periode terbuka");
  const [id, tgl] = baris.split("|");
  calonLembur = { id, tanggal: tgl };
  const k = (await kirimUpdate(teksPribadi(10606, HRD, `/batalkanlembur ${id} ${tgl} salah input`))).pesan[0];
  assert.match(k.text, new RegExp(`^Batalkan LEMBUR untuk ${id} .+\\?\\nTanggal: .+\\nCatatan: salah input\\nKeadaan sekarang:\\n• .+: pengaturan otomatis; pulang \\d+ menit lewat jadwal\\n`));
  assert.doesNotMatch(k.text, /tidak mengubah/);
  const r = await kirimUpdate(tekanTombol(10607, HRD, k.reply_markup.inline_keyboard[0][0].callback_data));
  const teks = r.pesan.map((p) => p.text as string);
  assert.match(teks[0], new RegExp(`^Tercatat: perintah no\\. \\d+, BATALKAN LEMBUR ${id} `));
  perintahLembur7c = /perintah no\. (\d+)/.exec(teks[0])![1];
  const hasil = teks.find((t) => t.startsWith(`Hasil BATALKAN LEMBUR ${id}`));
  assert.ok(hasil, JSON.stringify(teks));
  const m = /• Lembur periode no\. \d+: Rp([\d.]+) → Rp([\d.]+)$/.exec(hasil!);
  assert.ok(m, hasil);
  assert.ok(Number(m![2].replace(/\./g, "")) < Number(m![1].replace(/\./g, "")), hasil);
  assert.equal(nilai(`select x.jenis || ':' || x.id_karyawan || ':' || x.alasan from fakta.perintah_hrd x where x.id = ${perintahLembur7c}`),
    `batalkan_lembur:${id}:salah input`);

  const kb = (await kirimUpdate(teksPribadi(10608, HRD, `/batalperintah ${perintahLembur7c}`))).pesan[0];
  assert.match(kb.text, new RegExp(`^Batalkan perintah no\\. ${perintahLembur7c}: BATALKAN LEMBUR ${id} .+\\?\\n`));
  assert.match(kb.text, /\nKeadaan sekarang:\n• .+; sudah ada BATALKAN LEMBUR no\. \d+\n/);
  const rb = await kirimUpdate(tekanTombol(10609, HRD, kb.reply_markup.inline_keyboard[0][0].callback_data));
  const hb = rb.pesan.map((p) => p.text as string).find((t) => t.startsWith(`Hasil PEMBATALAN PERINTAH LEMBUR ${id}`));
  assert.ok(hb, JSON.stringify(rb.pesan.map((p) => p.text)));
  assert.match(hb!, new RegExp(`Rp${m![2].replace(/\./g, "\\.")} → Rp${m![1].replace(/\./g, "\\.")}$`));
});

test("7c: /perintahku dan menu memuat perintah lembur", async () => {
  const daftar = (await kirimUpdate(teksPribadi(10610, HRD, "/perintahku"))).pesan[0].text as string;
  assert.match(daftar, new RegExp(`no\\. ${perintahLembur7c} · BATALKAN LEMBUR · ${calonLembur.id} .+ DIBATALKAN`));
  for (const peran of ["hrd", "pembangun"]) for (const c of ["setujuilembur", "batalkanlembur"]) assert.ok(MENU[peran].some((m) => m.command === c));
});

// ---------------------------------------------------------------------------
// Paket 7c-2: jam datang awal yang disetujui (docs/rencana-tahap-7.md bagian 11; permintaan perubahan 06)
// ---------------------------------------------------------------------------

test("7c-2: /setujuiawal orang -> konfirmasi menit datang awal -> Ya -> lembur naik; divisi menyebut jumlah seluruh rentang", async () => {
  // Tap uji: 40 menit sebelum masuk, 45 menit sesudah jadwal pulang (tanpa persetujuan 45 menit -> 0; disetujui 85 -> 60).
  // Mesin dipilih yang sudah mengirim sampai tutup buku 20-04-2026 (uji pengingat P7 di uji_sambung tidak terganggu).
  const tap = nilai(`select m.mesin || '|' || m.id_mesin || '|' || to_char(hh.jadwal_masuk at time zone 'Asia/Jakarta' - interval '40 minutes', 'YYYY-MM-DD HH24:MI:SS')
      || '|' || to_char(hh.jadwal_pulang at time zone 'Asia/Jakarta' + interval '45 minutes', 'YYYY-MM-DD HH24:MI:SS') || '|' || p.id
      || '|' || hh.id_karyawan || '|' || to_char(hh.tanggal, 'DD-MM-YYYY') || '|' || hh.divisi
    from hitung.hasil_harian hh join hitung.versi_terakhir v on v.id = hh.versi_id and v.jenis = 'baca_tap'
    join fakta.periode p on p.id = v.periode_id join induk.pemetaan_id_mesin m on m.id_karyawan = hh.id_karyawan
    where hh.id_karyawan not in ('10067', '${calonLembur.id}') and p.status not in ('dirilis', 'dikunci') and hh.kode_jadwal is not null
      and hh.jenis_hari = 'kerja' and hh.status <> 'hadir' and not fakta.rahasia_di_periode(hh.id_karyawan, p.id)
      and fakta.karyawan_aktif(hh.id_karyawan, hh.tanggal)
      and exists (select 1 from fakta.kiriman_file k where k.mesin = m.mesin and k.hasil = 'diterima' and k.tanggal_akhir >= '2026-04-20')
      and hh.tanggal between m.berlaku_dari and coalesce(m.berlaku_sampai - 1, hh.tanggal)
    order by hh.tanggal, hh.id_karyawan limit 1`);
  assert.ok(tap, "ada hari kerja di periode terbuka dengan mesin yang sudah mengirim");
  const [mesin, idMesin, masuk, pulang, periode, id, tgl, divisi] = tap.split("|");
  nilai(`select fakta.terima_kiriman('uji7c2.csv', md5('uji7c2') || md5('uji7c2'), '${mesin}',
    '[["${idMesin}", "${masuk}", "Masuk", 1], ["${idMesin}", "${pulang}", "Keluar", 2]]'::jsonb, null, now())`);
  nilai(`select hitung.baca_tap(${periode}) + hitung.hitung_gaji(${periode})`);

  const kd = (await kirimUpdate(teksPribadi(10701, HRD, `/setujuiawal ${divisi} ${tgl}`))).pesan[0];
  assert.match(kd.text, /^Setujui DATANG AWAL \(dihitung lembur\) untuk divisi .+\?\n/);
  assert.match(kd.text, /orang datang lebih awal, total \d+ menit\n/);
  assert.match(kd.text, /\nJumlah seluruh rentang: [\d.]+ hari-orang datang lebih awal, total [\d.]+ menit\.\n/);
  assert.equal((await kirimUpdate(tekanTombol(10702, HRD, kd.reply_markup.inline_keyboard[0][1].callback_data))).pesan[0].text, "Tidak jadi dicatat.");

  const k = (await kirimUpdate(teksPribadi(10703, HRD, `setujuiawal ${id} ${tgl}`))).pesan[0];
  assert.match(k.text, new RegExp(`^Setujui DATANG AWAL \\(dihitung lembur\\) untuk ${id} .+\\?\\n`));
  assert.match(k.text, /: pengaturan otomatis; datang 40 menit lebih awal, pulang 45 menit lewat jadwal\n/);
  assert.match(k.text, /Menit datang lebih awal ditambahkan ke menit lewat jam pulang/);
  const r = await kirimUpdate(tekanTombol(10704, HRD, k.reply_markup.inline_keyboard[0][0].callback_data));
  const teks = r.pesan.map((p) => p.text as string);
  assert.match(teks[0], new RegExp(`^Tercatat: perintah no\\. \\d+, SETUJUI DATANG AWAL ${id} `));
  const hasil = teks.find((t) => t.startsWith(`Hasil SETUJUI DATANG AWAL ${id}`));
  assert.ok(hasil, JSON.stringify(teks));
  const m = /• Lembur periode no\. \d+: Rp([\d.]+) → Rp([\d.]+)$/.exec(hasil!);
  assert.ok(m, hasil);
  assert.ok(Number(m![2].replace(/\./g, "")) > Number(m![1].replace(/\./g, "")), hasil);
  assert.match(nilai(`select array_to_string(g.peringatan, ',') from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id
                      and v.jenis = 'hitung_gaji' where v.periode_id = ${periode} and g.id_karyawan = '${id}'`), /lembur_datang_awal_disetujui/);
  for (const peran of ["hrd", "pembangun"]) assert.ok(MENU[peran].some((x) => x.command === "setujuiawal"));
});

// ---------------------------------------------------------------------------
// Paket 8f: pembangun mencabut akun (docs/rencana-8f.md).
// ---------------------------------------------------------------------------
test("8f: /cabutakun hanya pembangun; bos dicabut lewat tombol (pilih -> Ya), diberi tahu, menu umum, bisa bergabung lagi", async () => {
  const BOS_CABUT = 6050;
  const undang = async (n: number) => /Kode undangan bos: ([A-Z0-9]{10})/.exec(
    (await kirimUpdate(teksPribadi(n, PEMBANGUN, "/undang bos"))).pesan[0].text)![1];
  assert.match((await kirimUpdate(teksPribadi(10801, BOS_CABUT, `/gabung ${await undang(10800)}`))).pesan[0].text, /^Terdaftar sebagai bos\./);
  const idBos = nilai(`select id from induk.pengguna where telegram_id = ${BOS_CABUT}`);

  assert.match((await kirimUpdate(teksPribadi(10802, HRD, "/cabutakun"))).pesan[0].text, /hanya untuk akun pembangun/);
  assert.match((await kirimUpdate(tekanTombol(10803, HRD, `k|y|${idBos}`))).pesan[0].text, /hanya untuk akun pembangun/);
  const d = (await kirimUpdate(teksPribadi(10804, PEMBANGUN, "cabut akun"))).pesan[0];
  const tombol = d.reply_markup.inline_keyboard.flat();
  assert.ok(tombol.some((t: any) => t.callback_data === `k|p|${idBos}`), JSON.stringify(tombol));
  assert.ok(!tombol.some((t: any) => /pembangun/i.test(t.text)), JSON.stringify(tombol));

  const tanya = (await kirimUpdate(tekanTombol(10805, PEMBANGUN, `k|p|${idBos}`))).pesan[0];
  assert.match(tanya.text, /^Cabut akun bos Telegram \.\.\.6050\?/);
  assert.equal((await kirimUpdate(tekanTombol(10806, PEMBANGUN, `k|n|${idBos}`))).pesan[0].text, "Dibatalkan. Tidak ada akun yang dicabut.");
  assert.equal(nilai(`select aktif from induk.pengguna where id = ${idBos}`), "t");

  const awal = terkirim.length;
  const c = await kirimUpdate(tekanTombol(10807, PEMBANGUN, tanya.reply_markup.inline_keyboard[0][0].callback_data));
  assert.match(pesanKe(c, PEMBANGUN)[0].text, /^Akun bos Telegram \.\.\.6050 dicabut\. Untuk bergabung lagi: buat undangan baru dengan \/undang bos\./);
  const kabar = pesanKe(c, BOS_CABUT)[0];
  assert.match(kabar.text, /^Akun bos Anda dicabut oleh pembangun\./);
  assert.deepEqual(kabar.reply_markup, { remove_keyboard: true });
  const menu = disetel(awal);
  assert.equal(menu.length, 1);
  assert.deepEqual(menu[0], { commands: MENU.umum, scope: { type: "chat", chat_id: BOS_CABUT } });
  assert.equal(nilai(`select concat_ws('/', aktif, telegram_id is null) from induk.pengguna where id = ${idBos}`), "f/t");
  assert.match((await kirimUpdate(tekanTombol(10808, PEMBANGUN, `k|y|${idBos}`))).pesan[0].text, /sudah dicabut/);
  assert.doesNotMatch((await kirimUpdate(teksPribadi(10809, BOS_CABUT, "/lengkap"))).pesan[0].text, /PIN/);

  assert.match((await kirimUpdate(teksPribadi(10811, BOS_CABUT, `/gabung ${await undang(10810)}`))).pesan[0].text, /^Terdaftar sebagai bos\./);
  assert.equal(nilai(`select count(*) from induk.pengguna where telegram_id = ${BOS_CABUT} and aktif and id <> ${idBos}`), "1");
  assert.ok(MENU.pembangun.some((x) => x.command === "cabutakun") && !MENU.hrd.some((x) => x.command === "cabutakun"));
});

// ---------------------------------------------------------------------------
// Paket 8e: keberatan karyawan (docs/rencana-8e.md).
// ---------------------------------------------------------------------------
test("8e: karyawan /keberatan -> bukti -> Kirim; HRD dan pembangun menerima Terima/Tolak; tolak beralasan; karyawan dikabari", async () => {
  const hari = hariIni();
  if (nilai(`select count(*) from fakta.periode where '${hari}'::date between tanggal_awal and tanggal_akhir`) === "0") {
    nilai(`insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar)
           select greatest(max(tanggal_akhir) + 1, '${hari}'::date - 20), '${hari}'::date + 20, '${hari}'::date + 25 from fakta.periode`);
  }
  const periode = nilai(`select id from fakta.periode where '${hari}'::date between tanggal_awal and tanggal_akhir`);
  nilai(`select hitung.baca_tap(${periode})`);
  const [kTg, kId] = nilai(`select telegram_id || '|' || id_karyawan from induk.pengguna where peran = 'karyawan' and aktif
                            and telegram_id is not null and id_karyawan is not null order by id limit 1`).split("|");
  const K = Number(kTg);
  const [y, m, d] = hari.split("-");
  const tgl = `${d}-${m}-${y}`;

  assert.match((await kirimUpdate(teksPribadi(10901, K, "/keberatan"))).pesan[0].text, /^Belum ada keberatan\.\n\nCara pakai: \/keberatan/);
  assert.match((await kirimUpdate(teksPribadi(10902, K, "/keberatan 31-02-2026 salah"))).pesan[0].text, /^Tanggal "31-02-2026" tidak dikenali/);
  assert.match((await kirimUpdate(teksPribadi(10903, K, `/keberatan ${tgl}`))).pesan[0].text, /^Tulis alasannya\./);
  assert.match((await kirimUpdate(teksPribadi(10904, HRD, `/keberatan ${tgl} coba`))).pesan[0].text, /^Keberatan hanya untuk akun karyawan/);

  const draf = (await kirimUpdate(teksPribadi(10905, K, `keberatan ${tgl} saya masuk tapi tercatat alpha`))).pesan[0];
  assert.match(draf.text, new RegExp(`^Keberatan untuk .+ \\(periode no\\. ${periode}, .+\\):\\nAlasan: saya masuk tapi tercatat alpha\\n\\nCatatan sistem untuk hari itu:\\n• `));
  assert.match(draf.text, /• Tap hari itu: /);
  assert.match(draf.text, /\n\nKirim keberatan ini ke HRD\?$/);
  assert.doesNotMatch(draf.text, /Rp/);
  const [kirimTombol] = draf.reply_markup.inline_keyboard[0];
  assert.match((await kirimUpdate(tekanTombol(10906, HRD, kirimTombol.callback_data))).pesan[0].text, /sudah tidak berlaku/);

  const k = await kirimUpdate(tekanTombol(10907, K, kirimTombol.callback_data));
  const no = /^Keberatan no\. (\d+) terkirim ke HRD\./.exec(pesanKe(k, K)[0].text)?.[1];
  assert.ok(no, JSON.stringify(k.pesan));
  for (const tg of [HRD, PEMBANGUN]) {
    const p = pesanKe(k, tg)[0];
    assert.match(p.text, new RegExp(`^Keberatan no\\. ${no} dari ${kId} .+\\nTanggal: `), JSON.stringify(k.pesan));
    assert.doesNotMatch(p.text, /Rp/);
    assert.deepEqual(p.reply_markup.inline_keyboard[0].map((t: any) => t.callback_data), [`f|y|${no}`, `f|n|${no}`]);
  }
  assert.equal(pesanKe(k, BOS).length, 0);
  assert.match((await kirimUpdate(teksPribadi(10908, K, `/keberatan ${tgl} lagi`))).pesan[0].text, new RegExp(`^Keberatan no\\. ${no} untuk tanggal itu masih menunggu`));
  assert.match((await kirimUpdate(tekanTombol(10909, K, `f|y|${no}`))).pesan[0].text, /^Hanya HRD atau pembangun/);
  assert.match((await kirimUpdate(teksPribadi(10910, HRD, "/keberatan"))).pesan[0].text, /^Keberatan menunggu jawaban: \d+/);

  const tanya = (await kirimUpdate(tekanTombol(10911, HRD, `f|n|${no}`))).pesan[0];
  assert.ok(tanya.text.startsWith(`${TANYA_TOLAK_KEBERATAN} ${no} `), tanya.text);
  assert.equal(tanya.reply_markup.force_reply, true);
  const t = await kirimUpdate(balas(10912, HRD, "tidak ada tap di mesin hari itu", tanya.text));
  assert.match(pesanKe(t, HRD)[0].text, new RegExp(`^Keberatan no\\. ${no} \\(${kId} .+\\) ditolak\\.`));
  assert.match(pesanKe(t, K)[0].text, new RegExp(`^Keberatan no\\. ${no} untuk .+ DITOLAK HRD\\.\\nAlasan: tidak ada tap di mesin hari itu$`));
  assert.match(pesanKe(t, PEMBANGUN)[0].text, new RegExp(`^Keberatan no\\. ${no} \\(${kId}, .+\\) sudah ditolak: tidak ada tap di mesin hari itu$`));
  assert.match((await kirimUpdate(tekanTombol(10913, PEMBANGUN, `f|y|${no}`))).pesan[0].text, new RegExp(`^Keberatan no\\. ${no} sudah dijawab \\(ditolak\\)`));
  assert.equal(nilai(`select hasil || '|' || catatan from fakta.keputusan_keberatan where keberatan_id = ${no}`), "ditolak|tidak ada tap di mesin hari itu");
  assert.match((await kirimUpdate(teksPribadi(10914, K, "Keberatan"))).pesan[0].text, new RegExp(`• No\\. ${no}, .+: ditolak \\(tidak ada tap di mesin hari itu\\)`));

  // Diajukan lagi lalu diterima pembangun: periode belum dirilis -> HRD diingatkan memperbaiki lewat perintah.
  const draf2 = (await kirimUpdate(teksPribadi(10915, K, `/keberatan ${tgl} ini fotonya ada`))).pesan[0];
  const no2 = /^Keberatan no\. (\d+)/.exec(pesanKe(await kirimUpdate(tekanTombol(10916, K, draf2.reply_markup.inline_keyboard[0][0].callback_data)), K)[0].text)![1];
  const terima = await kirimUpdate(tekanTombol(10917, PEMBANGUN, `f|y|${no2}`));
  assert.match(pesanKe(terima, PEMBANGUN)[0].text, /diterima\.\nPerbaiki lewat perintah HRD/);
  assert.match(pesanKe(terima, K)[0].text, /DITERIMA HRD\.\nHRD akan memperbaiki catatannya/);

  assert.deepEqual(TOMBOL_TETAP.karyawan, [["Gaji saya", "Keberatan"], ["Bantuan"]]);
  for (const peran of ["karyawan", "hrd", "pembangun"]) assert.ok(MENU[peran].some((x) => x.command === "keberatan"), peran);
  assert.ok(!MENU.bos.some((x) => x.command === "keberatan"));
});

test("8e: bukti keberatan ditulis dengan jam WIB dan nama status", () => {
  const baris = tulisBukti({ hari: { status: "alpha", asal: "mesin", jenis_hari: "kerja", kode_jadwal: "P",
    jadwal_masuk: "2026-04-05T00:00:00Z", jadwal_pulang: "2026-04-05T08:00:00Z", masuk: null, pulang: null,
    menit_telat: 0, menit_pulang_cepat: 0, menit_lebih: 0, lupa_tap: null }, tap: [{ waktu: "2026-04-04T23:58:00Z", peran: "tunggal" }] });
  assert.deepEqual(baris, ["• Status: alpha (tidak hadir tanpa keterangan) (dari mesin)", "• Jadwal: P 07.00–15.00",
                           "• Masuk -, pulang -", "• Tap hari itu: 06.58 (tunggal)"]);
  assert.deepEqual(tulisBukti({ hari: null, tap: [] }), ["• Tidak ada catatan hari ini untuk Anda di hasil hitung terakhir.", "• Tap hari itu: tidak ada"]);
});

// ---------------------------------------------------------------------------
// Paket 9a: web HRD (fungsi halaman, tanpa jaringan). Uji lewat penyambung ada di uji_sambung.ts.
// ---------------------------------------------------------------------------
test("9a: masuk web HRD dengan kode email -> sesi; ringkasan = Ringkasan Sheets; orang rahasia tanpa angka; keluar", async () => {
  const email = "web9a-pintu@contoh.id";
  nilai(`update induk.pengguna set email = '${email}' where telegram_id = ${HRD}`);
  const idHrd = nilai(`select id from induk.pengguna where telegram_id = ${HRD}`);
  nilai(`insert into fakta.kode_email (pengguna, email, sidik, berlaku_sampai)
         values (${idHrd}, '${email}', '${sha256(`${email}:246810`)}', now() + interval '10 minutes')`);
  assert.equal((await webMasukHrd(alat, email, "12 34")).status, 400);
  const salah = await webMasukHrd(alat, email, "111111");
  assert.equal(salah.status, 401);
  assert.match(salah.isi.alasan, /^Kode salah\. Sisa 4 kali/);
  const m = await webMasukHrd(alat, email, "246 810");
  assert.equal(m.status, 200, JSON.stringify(m.isi));
  const sesi = m.isi.sesi as string;
  assert.equal(nilai(`select count(*) from fakta.sesi_web where sidik = '${sha256(sesi)}'`), "1");

  const r = await webHrd(alat, { sesi, aksi: "ringkasan" });
  assert.equal(r.status, 200);
  // Sama dengan cara hitung Ringkasan Sheets (web/isi_sheets.py): tanpa orang rahasia (F15b/F15c).
  for (const p of (r.isi.data as any[]).filter((x) => x.ada_gaji)) {
    const harap = nilai(`select count(*) || '/' || sum(g.gaji_bersih) || '/' || count(*) filter (where false)
      from hitung.ringkasan_gaji g join hitung.versi_terakhir v on v.id = g.versi_id and v.jenis = 'hitung_gaji' and v.periode_id = ${p.id}
      where not fakta.rahasia_di_periode(g.id_karyawan, ${p.id})`);
    assert.equal(`${p.orang}/${p.bersih}/0`, harap, `periode ${p.id}`);
    assert.equal(Number(p.transfer) + Number(p.tunai), Number(p.dibayar), `periode ${p.id}`);
  }
  const p = (r.isi.data as any[]).find((x) => x.ada_gaji && x.rahasia > 0);
  assert.ok(p, "ada periode dengan orang rahasia");
  const g = await webHrd(alat, { sesi, aksi: "gaji", periode_id: p.id });
  const rahasia = (g.isi.data as any[]).find((x) => x.rahasia);
  assert.equal(rahasia.bersih, null);
  const o = await webHrd(alat, { sesi, aksi: "orang", periode_id: p.id, id_karyawan: rahasia.id });
  assert.equal(o.isi.data.gaji, null);
  assert.equal(o.isi.data.komponen, null);
  assert.ok(o.isi.data.harian.length > 0);
  const biasa = (g.isi.data as any[]).find((x) => !x.rahasia);
  const ob = await webHrd(alat, { sesi, aksi: "orang", periode_id: p.id, id_karyawan: biasa.id });
  assert.equal(ob.isi.data.gaji.bersih, biasa.bersih);
  assert.ok(ob.isi.data.komponen.length > 0);
  assert.equal((await webHrd(alat, { sesi, aksi: "perlu_dicek", periode_id: p.id })).status, 200);
  assert.equal((await webHrd(alat, { sesi, aksi: "keberatan" })).status, 200);
  assert.equal((await webHrd(alat, { sesi, aksi: "hapus" })).status, 400);
  assert.equal((await webHrd(alat, { sesi: "x", aksi: "ringkasan" })).status, 401);
  assert.equal((await webHrd(alat, { sesi, aksi: "keluar" })).status, 200);
  assert.equal((await webHrd(alat, { sesi, aksi: "ringkasan" })).status, 401);
});

// ---------------------------------------------------------------------------
// Paket 9c: coba aturan lewat fungsi web (data Pabrik A lengkap; tidak ada yang tersimpan).
// ---------------------------------------------------------------------------
test("9c: coba aturan lewat web: nilai sekarang, percobaan tanpa menyimpan, isian salah 400, antrean ditolak", async () => {
  const sesi = "9c".repeat(32);
  nilai(`insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai)
         select '${sha256(sesi)}', id, now() + interval '1 hour' from induk.pengguna where telegram_id = ${PEMBANGUN}`);
  nilai("update fakta.antrean_kerja set status = 'selesai', selesai = now() where status = 'menunggu'");
  const periode = nilai(`select p.id from fakta.periode p where p.status not in ('dirilis', 'dikunci')
    and exists (select 1 from hitung.versi_terakhir g where g.periode_id = p.id and g.jenis = 'hitung_gaji') order by p.tanggal_awal limit 1`);
  const awal = await webHrd(alat, { sesi, aksi: "aturan_sekarang", periode_id: periode });
  assert.equal(awal.status, 200, JSON.stringify(awal.isi));
  assert.equal(awal.isi.data.boleh, true);
  const potret = () => nilai(`select (select count(*) from hitung.versi_hitung) || '|' || (select string_agg(id || ':' || telat_menit, ',' order by id)
    from aturan.toleransi) || '|' || (select string_agg(id || ':' || status, ',' order by id) from fakta.periode)`);
  const sebelum = potret();
  const telat = Number(awal.isi.data.telat_menit) + 10;
  const r = await webHrd(alat, { sesi, aksi: "coba_aturan", periode_id: periode, aturan: { telat_menit: telat, bukan_aturan: 1 } });
  assert.equal(r.status, 200, JSON.stringify(r.isi));
  assert.equal(r.isi.data.aturan.telat_menit, telat);
  assert.ok(Number(r.isi.data.ringkasan.orang) > 900, JSON.stringify(r.isi.data.ringkasan));
  // Data uji pintu hampir tanpa tap; yang dibuktikan di sini jalurnya. Kebenaran angka dibuktikan uji database 320 (gerbang 2).
  assert.equal(Number(r.isi.data.ringkasan.turun), 0, "toleransi telat lebih longgar tidak menurunkan gaji siapa pun");
  assert.equal(Number(r.isi.data.ringkasan.naik) + Number(r.isi.data.ringkasan.turun) + Number(r.isi.data.ringkasan.sama),
               Number(r.isi.data.ringkasan.orang));
  assert.equal(potret(), sebelum, "gudang tidak berubah");
  assert.equal(nilai(`select hasil || '/' || (aturan ->> 'telat_menit') from fakta.coba_aturan order by id desc limit 1`), `selesai/${telat}`);
  assert.equal((await webHrd(alat, { sesi, aksi: "coba_aturan", periode_id: periode, aturan: { lembur_kelipatan: 0 } })).status, 400);
  assert.equal((await webHrd(alat, { sesi, aksi: "coba_aturan", periode_id: periode, aturan: {} })).status, 400);
  nilai(`insert into fakta.antrean_kerja (periode_id) values (${periode})`);
  const q = await webHrd(alat, { sesi, aksi: "coba_aturan", periode_id: periode, aturan: { telat_menit: telat } });
  assert.equal(q.status, 409);
  assert.match(q.isi.alasan, /menunggu hitung ulang/);
  nilai("update fakta.antrean_kerja set status = 'selesai', selesai = now() where status = 'menunggu'");
});

// ---------------------------------------------------------------------------
// Paket 9b-1: perintah lewat web (data Pabrik A lengkap): berhenti -> hitung ulang lewat antrean + Sheets dipicu ->
// batal -> hasil kembali. Kebenaran tiap jenis perintah dibuktikan uji database 330.
// ---------------------------------------------------------------------------
test("9b-1: perintah web berhenti lalu dibatalkan: antrean, Sheets, kabar Telegram, hasil kembali semula", async () => {
  const sesi = "9b".repeat(32);
  nilai(`insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai)
         select '${sha256(sesi)}', id, now() + interval '1 hour' from induk.pengguna where telegram_id = ${HRD}`);
  nilai("update fakta.antrean_kerja set status = 'selesai', selesai = now() where status = 'menunggu'");
  const [periode, hari] = nilai(`select p.id || ',' || (p.tanggal_awal + 9) from fakta.periode p where p.status not in ('dirilis', 'dikunci')
    and exists (select 1 from hitung.versi_terakhir g where g.periode_id = p.id and g.jenis = 'hitung_gaji') order by p.tanggal_awal limit 1`).split(",");
  const orang = nilai(`select r.id_karyawan from induk.karyawan_riwayat r
    where daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> '${hari}'::date and r.berlaku_sampai is null and not r.gaji_rahasia
      and fakta.karyawan_aktif(r.id_karyawan, '${hari}')
      and not exists (select 1 from induk.status_kerja s where s.id_karyawan = r.id_karyawan and s.tanggal >= '${hari}')
    order by r.id_karyawan limit 1`);
  const hasil = () => nilai(`select count(*) || '/' || coalesce(max(h.tanggal)::text, '-') from hitung.hasil_harian h
    where h.id_karyawan = '${orang}' and h.versi_id = (select v.id from hitung.versi_terakhir v where v.periode_id = ${periode} and v.jenis = 'baca_tap')`);
  const sebelum = hasil();
  const salah = await webHrd(alat, { sesi, aksi: "perintah_pratinjau", perintah: { jenis: "berhenti", id_karyawan: orang, mulai: hari } });
  assert.equal(salah.status, 409);
  assert.match(salah.isi.alasan, /alasan wajib/);
  const pra = await webHrd(alat, { sesi, aksi: "perintah_pratinjau",
    perintah: { jenis: "berhenti", id_karyawan: orang, mulai: hari, alasan: "uji 9b-1", bukan_isian: "x", gaji_pokok: 1 } });
  assert.equal(pra.status, 200, JSON.stringify(pra.isi));
  assert.deepEqual(Object.keys(pra.isi.data.isian).sort(), ["alasan", "id_karyawan", "mulai"]);
  assert.ok(pra.isi.data.periode.some((p: any) => String(p.id) === periode));
  const awalPicu = dipicu.length;
  const awalKirim = terkirim.length;
  const t0 = Date.now();
  const simpan = await webHrd(alat, { sesi, aksi: "perintah_simpan", perintah: { nomor: pra.isi.data.draf_id } });
  assert.equal(simpan.status, 200, JSON.stringify(simpan.isi));
  assert.ok(simpan.latar, "hitung ulang berjalan di latar");
  await simpan.latar;
  console.log(`  9b-1: simpan + hitung ulang ${pra.isi.data.periode.length} periode: ${Date.now() - t0} ms`);
  const sesudah = hasil();
  assert.notEqual(sesudah, sebelum);
  assert.equal(sesudah.split("/")[1], hari, "hari kerja terakhir = tanggal berhenti (keputusan 2a)");
  assert.ok(dipicu.slice(awalPicu).some((m) => m.pemicu === "perintah web"), "Isi Sheets dipicu");
  const kabar = terkirim.slice(awalKirim).filter((t) => t.metode === "sendMessage" && t.isi.chat_id === HRD).map((t) => t.isi.text);
  assert.ok(kabar.some((x) => x.startsWith(`Perintah web no. ${simpan.isi.data.perintah_id}: Berhenti ${orang}`)), kabar.join("\n"));
  const ulang = await webHrd(alat, { sesi, aksi: "perintah_simpan", perintah: { nomor: pra.isi.data.draf_id } });
  assert.equal(ulang.status, 409);
  const daftar = await webHrd(alat, { sesi, aksi: "perintah_daftar" });
  assert.equal(daftar.isi.data.perintah[0].id, simpan.isi.data.perintah_id);
  assert.equal(daftar.isi.data.perintah[0].hitung, "selesai");
  const batal = await webHrd(alat, { sesi, aksi: "perintah_batal", perintah: { nomor: simpan.isi.data.perintah_id } });
  assert.equal(batal.status, 200, JSON.stringify(batal.isi));
  await batal.latar;
  assert.equal(hasil(), sebelum, "hasil harian kembali seperti sebelum perintah");
  assert.equal(nilai(`select count(*) from induk.status_kerja where id_karyawan = '${orang}' and jenis = 'berhenti' and tanggal = '${hari}'`), "0");
  assert.equal((await webHrd(alat, { sesi, aksi: "perintah_batal", perintah: { nomor: "abc" } })).status, 409);
});

// ---------------------------------------------------------------------------
// Paket 9b-2: pengajuan ubah gaji dari web -> pesan ke pembangun -> tombol Setujui -> PIN -> hitung ulang -> kabar HRD
// -> batal di web. Kebenaran tiap aturan dibuktikan uji database 340.
// ---------------------------------------------------------------------------
test("9b-2: ubah gaji lewat web disetujui pembangun dengan tombol + PIN, lalu dibatalkan", async () => {
  const sesi = "9d".repeat(32);
  const pin = "731942";
  nilai(`insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai)
         select '${sha256(sesi)}', id, now() + interval '1 hour' from induk.pengguna where telegram_id = ${HRD}`);
  nilai(`update induk.pengguna set pin_tersamar = extensions.crypt('${pin}', extensions.gen_salt('bf')) where telegram_id = ${PEMBANGUN}`);
  nilai("update fakta.antrean_kerja set status = 'selesai', selesai = now() where status = 'menunggu'");
  const [periode, hari] = nilai(`select p.id || ',' || (p.tanggal_awal + 9) from fakta.periode p where p.status not in ('dirilis', 'dikunci')
    and exists (select 1 from hitung.versi_terakhir g where g.periode_id = p.id and g.jenis = 'hitung_gaji') order by p.tanggal_awal limit 1`).split(",");
  const orang = nilai(`select r.id_karyawan from induk.karyawan_riwayat r
    where daterange(r.berlaku_dari, r.berlaku_sampai, '[)') @> '${hari}'::date and r.berlaku_sampai is null and r.berlaku_dari < '${hari}'
      and not exists (select 1 from induk.karyawan_riwayat x where x.id_karyawan = r.id_karyawan and x.gaji_rahasia)
      and fakta.karyawan_aktif(r.id_karyawan, '${hari}') order by r.id_karyawan desc limit 1`);
  const gaji = () => nilai(`select g.gaji_bersih from hitung.ringkasan_gaji g where g.id_karyawan = '${orang}'
    and g.versi_id = (select v.id from hitung.versi_terakhir v where v.periode_id = ${periode} and v.jenis = 'hitung_gaji')`);
  const riwayat = () => nilai(`select string_agg(id || ':' || gaji_pokok || ':' || coalesce(berlaku_sampai::text, '-'), ',' order by id)
    from induk.karyawan_riwayat where id_karyawan = '${orang}'`);
  const sebelum = [gaji(), riwayat()];
  const pokok = Number(nilai(`select gaji_pokok from induk.karyawan_riwayat where id_karyawan = '${orang}' and berlaku_sampai is null`)) + 250000;
  const pra = await webHrd(alat, { sesi, aksi: "perintah_pratinjau",
    perintah: { jenis: "ubah_gaji", id_karyawan: orang, mulai: hari, gaji_pokok: String(pokok), alasan: "uji 9b-2", rekening: "123" } });
  assert.equal(pra.status, 200, JSON.stringify(pra.isi));
  assert.ok(!("rekening" in pra.isi.data.isian));
  const awalKirim = terkirim.length;
  const aju = await webHrd(alat, { sesi, aksi: "perintah_simpan", perintah: { nomor: pra.isi.data.draf_id } });
  assert.equal(aju.status, 200, JSON.stringify(aju.isi));
  assert.equal(aju.isi.hasil, "diajukan");
  assert.ok(!("penerima" in aju.isi.data), "daftar ID Telegram penerima tidak dikirim ke halaman");
  await aju.latar;
  assert.deepEqual([gaji(), riwayat()], sebelum, "pengajuan belum mengubah apa pun");
  const ke = terkirim.slice(awalKirim).filter((t) => t.metode === "sendMessage" && t.isi.chat_id === PEMBANGUN);
  const id = aju.isi.data.pengajuan_id;
  assert.ok(ke.some((t) => t.isi.text.startsWith(`Pengajuan no. ${id} dari`) &&
    JSON.stringify(t.isi.reply_markup).includes(`g|y|${id}`)), JSON.stringify(ke.map((t) => t.isi.text)));
  const r1 = await kirimUpdate(tekanTombol(20001, PEMBANGUN, `g|y|${id}`));
  assert.match(r1.pesan.at(-1).text, new RegExp(`^Ketik PIN 6 angka untuk MENYETUJUI pengajuan no. ${id}`));
  const awalHrd = terkirim.length;
  const r2 = await kirimUpdate(teksPribadi(20002, PEMBANGUN, pin));
  assert.ok(r2.pesan.some((p: any) => p.text.startsWith(`Pengajuan no. ${id} DISETUJUI`)), JSON.stringify(r2.pesan.map((p: any) => p.text)));
  const kabar = terkirim.slice(awalHrd).filter((t) => t.metode === "sendMessage" && t.isi.chat_id === HRD).map((t) => t.isi.text);
  assert.ok(kabar.some((x) => x.startsWith(`Pengajuan no. ${id} disetujui oleh pembangun`)), kabar.join("\n"));
  assert.notEqual(gaji(), sebelum[0], "gaji periode itu dihitung ulang dengan gaji baru");
  assert.match(riwayat(), new RegExp(`:${pokok}:-$`));
  const r3 = await kirimUpdate(tekanTombol(20003, PEMBANGUN, `g|y|${id}`));
  assert.match(r3.pesan.at(-1).text, /sudah disetujui/);
  const perintah = Number(nilai(`select perintah_id from fakta.keputusan_uang where pengajuan_id = ${id}`));
  const batal = await webHrd(alat, { sesi, aksi: "perintah_batal", perintah: { nomor: perintah } });
  assert.equal(batal.status, 200, JSON.stringify(batal.isi));
  await batal.latar;
  assert.deepEqual([gaji(), riwayat()], sebelum, "batal mengembalikan gaji dan riwayat persis");
  const r4 = await kirimUpdate(teksPribadi(20004, PEMBANGUN, "/pengajuan"));
  assert.match(r4.pesan.at(-1).text, /Tidak ada pengajuan/);
});

test("P1: kabar periode baru dibuat otomatis (teks bot dan unggah web)", () => {
  assert.equal(teksPeriodeBaru([]), "");
  assert.equal(teksPeriodeBaru(undefined), "");
  assert.equal(teksPeriodeBaru([{ id: 5, awal: "2026-12-21", akhir: "2027-01-20", bayar: "2027-01-25" }]),
    "\nPeriode baru no. 5 dibuat: 21 Des 2026 – 20 Jan 2027, gajian 25 Jan 2027.");
  assert.equal(teksPeriodeBaru([{ id: 5, awal: "2026-12-21", akhir: "2027-01-20", bayar: "2027-01-25" },
                                { id: 6, awal: "2027-01-21", akhir: "2027-02-20", bayar: "2027-02-25" }]).split("\n").length, 3);
});

test("F1: file Excel .xls dikirim ke bot sebagai dokumen diterima dengan jumlah tap sama dengan CSV-nya", async () => {
  const r = await kirimUpdate(dokumen(30001, HRD, "F_MA2_XLS", "A_p1_MA2.xls", "MA2"));
  assert.equal(r.status, 200);
  const harap = urai(new TextDecoder().decode(BERKAS.F_MA2), { tanggal_kirim: "2026-02-21" }).tap.length;
  assert.ok(r.pesan.some((p) => p.text.includes(`File A_p1_MA2.xls tersimpan: ${harap.toLocaleString("id-ID")} tap`)), JSON.stringify(r.pesan.map((p) => p.text.slice(0, 90))));
  assert.equal(nilai("select hasil || '/' || jumlah_baris from fakta.kiriman_file where nama_file = 'A_p1_MA2.xls'"), `diterima/${harap}`);
});

// ---------------------------------------------------------------------------
// Paket F2: HRD mengonfirmasi format file baru sekali lewat bot (docs/rencana-f2-konfirmasi-format.md, PP07, kasus F09)
// ---------------------------------------------------------------------------
import { PESAN_FORMAT_BARU_WEB, TANYA_KOLOM, duaArti, susunanKolom } from "./inti.ts";

// File F09 dari data simulasi MA2 periode 1: judul "Tgl/Waktu" diganti "Waktu" (judul belum dikenal), 40 baris per file.
function fileF09(dari: number, sampai: number, judul = "Nama,No.ID,Waktu,,Status"): Uint8Array {
  const baris = fileSim("A_p1_MA2.csv").toString("utf8").split("\r\n");
  return new TextEncoder().encode([judul, ...baris.slice(dari, sampai)].join("\r\n") + "\r\n");
}
BERKAS.F2_A = fileF09(1, 41);
BERKAS.F2_B = fileF09(41, 81);
BERKAS.F2_LOKASI = fileF09(81, 121, "Nama,No.ID,Waktu,,Status,Lokasi");
BERKAS.F2_C = fileF09(121, 161);
BERKAS.F2_DUA_ARTI = new TextEncoder().encode("ID Kartu,Jam Scan\r\n10881,01/02/2026 07:01\r\n10881,01/02/2026 16:05\r\n10881,02/01/2026 07:02\r\n");
const tombolX = (u: number, dari: number, data: string) => JSON.stringify({
  update_id: u, callback_query: { id: `cb${u}`, data, from: { id: dari }, message: { message_id: u, chat: { id: dari, type: "private" } } },
});
const balasBot = (u: number, dari: number, text: string, ditanya: string) => JSON.stringify({
  update_id: u, message: { message_id: u, chat: { id: dari, type: "private" }, from: { id: dari }, text,
                           reply_to_message: { from: { is_bot: true }, text: ditanya } },
});
const tombolTeks = (p: any) => (p?.reply_markup?.inline_keyboard ?? []).flat().map((t: any) => t.text);
const dataTombol = (p: any, teks: string) => (p?.reply_markup?.inline_keyboard ?? []).flat().find((t: any) => t.text === teks)?.callback_data;
const sidikGaji = () => nilai(`select string_agg(x.periode_id || ':' || left(md5(x.s), 12), ' ' order by x.periode_id) from (
  select v.periode_id, string_agg(g.id_karyawan || '=' || g.gaji_bersih, ',' order by g.id_karyawan) as s
  from hitung.versi_terakhir v join hitung.ringkasan_gaji g on g.versi_id = v.id where v.jenis = 'hitung_gaji' group by v.periode_id) x`);
let konfirmasiF2 = 0;
let profilF2 = 0;

test("F2: file F09 dari HRD ditahan (tidak dicatat), HRD ditanya kolom ID dengan tombol judul kolom; pembangun diberi tahu", async () => {
  const r = await kirimUpdate(dokumen(40001, HRD, "F2_A", "f09_a.csv", "MA2"));
  const hrd = r.pesan.filter((p) => p.chat_id === HRD);
  assert.match(hrd[1].text, /memakai judul kolom yang belum dikenal: "Nama", "No.ID", "Waktu", "", "Status"\. File ditahan dan belum dihitung/);
  konfirmasiF2 = Number(/konfirmasi format no\. (\d+)/.exec(hrd[1].text)![1]);
  assert.match(hrd[2].text, /Kolom mana yang berisi ID karyawan/);
  // Kolom berjudul kosong tidak ditawarkan.
  assert.deepEqual(tombolTeks(hrd[2]), ["Nama", "No.ID", "Waktu", "Status", "Lainnya, ketik sendiri"]);
  for (const pb of [333, PEMBANGUN]) {
    assert.match(r.pesan.find((p) => p.chat_id === pb)?.text ?? "", /^FORMAT FILE BARU DITAHAN \(konfirmasi format no\. \d+\)\nMesin MA2, file f09_a\.csv/);
  }
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'f09_a.csv'"), "0");
  assert.equal(nilai(`select status || '/' || langkah || '/' || mesin from fakta.konfirmasi_format where id = ${konfirmasiF2}`), "menunggu/id/MA2");
});

test("F2: tombol konfirmasi ditekan akun lain (pembangun) tidak berlaku; ketik sendiri: tidak cocok -> ditanya lagi, cocok -> lanjut", async () => {
  const lain = await kirimUpdate(tombolX(40002, PEMBANGUN, `x|${konfirmasiF2}|i|1`));
  assert.match(lain.pesan[0].text, /sudah tidak berlaku/);
  const k = await kirimUpdate(tombolX(40003, HRD, `x|${konfirmasiF2}|k|0`));
  assert.ok(k.pesan[0].text.startsWith(`${TANYA_KOLOM} ${konfirmasiF2}: kolom yang berisi ID karyawan`), k.pesan[0].text);
  assert.equal(k.pesan[0].reply_markup.force_reply, true);
  const salah = await kirimUpdate(balasBot(40004, HRD, "Nomor Absen", k.pesan[0].text));
  assert.match(salah.pesan[0].text, /judul "Nomor Absen" tidak ada di file.*judul yang ada: "Nama", "No.ID", "Waktu", "Status"/);
  assert.equal(nilai(`select langkah from fakta.konfirmasi_format where id = ${konfirmasiF2}`), "id");
  const cocok = await kirimUpdate(balasBot(40005, HRD, "no id", salah.pesan[0].text));
  assert.match(cocok.pesan[0].text, /Kolom mana yang berisi tanggal dan jam tap/);
  assert.deepEqual(tombolTeks(cocok.pesan[0]), ["Nama", "Waktu", "Status", "Tanggal dan jam di dua kolom", "Lainnya, ketik sendiri"]);
  assert.equal(nilai(`select pilihan ->> 'kolom_id' from fakta.konfirmasi_format where id = ${konfirmasiF2}`), "No.ID");
  // Tombol dari pertanyaan ID (langkah lama) tidak berlaku lagi.
  const lama = await kirimUpdate(tombolX(40006, HRD, `x|${konfirmasiF2}|i|0`));
  assert.match(lama.pesan[0].text, /sudah tidak berlaku/);
});

test("F2: pilih kolom Waktu (tanggal pasti hari/bulan, tidak ditanya) -> contoh hasil bacaan 3 tap + ringkasan + Ya/Tidak", async () => {
  const r = await kirimUpdate(tombolX(40007, HRD, `x|${konfirmasiF2}|w|2`));
  const c = r.pesan.at(-1);
  const acuan = urai(new TextDecoder().decode(fileF09(1, 41, "Nama,No.ID,Tgl/Waktu,,Status")), { tanggal_kirim: "2026-02-21" });
  const t0 = acuan.tap[0];
  assert.match(c.text, new RegExp(`^Contoh hasil bacaan, konfirmasi format no\\. ${konfirmasiF2} \\(mesin MA2, file f09_a\\.csv\\):`));
  assert.ok(c.text.includes(`• baris 2: ID ${t0.id_mesin}, ${tulisTanggal(t0.jam_lokal.slice(0, 10))}, jam ${t0.jam_lokal.slice(11, 16).replace(":", ".")}`), c.text);
  assert.ok(c.text.includes(`Ringkasan: ${acuan.tap.length} tap, ${new Set(acuan.tap.map((t) => t.id_mesin)).size} ID,`), c.text);
  assert.match(c.text, /Kolom: ID = "No\.ID", tanggal-jam = "Waktu", tanggal dibaca hari\/bulan\/tahun\./);
  assert.ok(!/RAHMAT|SANTO/.test(c.text), "contoh tanpa nama");
  assert.deepEqual(tombolTeks(c), ["Ya, simpan", "Tidak", "Pilih ulang"]);
  assert.equal(nilai(`select langkah || '/' || (pilihan ->> 'susunan') from fakta.konfirmasi_format where id = ${konfirmasiF2}`), "contoh/dmy");
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'f09_a.csv'"), "0");
});

test("F2: Ya, simpan -> profil tersimpan, pembangun diberi tahu dengan contoh; file dihitung dengan tap sama dengan bentuk dikenal", async () => {
  const r = await kirimUpdate(tombolX(40008, HRD, `x|${konfirmasiF2}|y|0`));
  const hrd = r.pesan.filter((p) => p.chat_id === HRD);
  assert.match(hrd[0].text, /^Profil format no\. \d+ disimpan untuk mesin MA2: ID = "No\.ID", tanggal-jam = "Waktu"/);
  profilF2 = Number(/Profil format no\. (\d+)/.exec(hrd[0].text)![1]);
  const harap = urai(new TextDecoder().decode(fileF09(1, 41, "Nama,No.ID,Tgl/Waktu,,Status")), { tanggal_kirim: "2026-02-21" }).tap.length;
  assert.ok(hrd.some((p) => p.text.startsWith(`File f09_a.csv tersimpan: ${harap} tap`) &&
    p.text.includes(`(dibaca dengan profil format no. ${profilF2} mesin MA2)`)), JSON.stringify(hrd.map((p) => p.text.slice(0, 120))));
  for (const pb of [333, PEMBANGUN]) {
    const t = r.pesan.find((p) => p.chat_id === pb && p.text.startsWith("PROFIL FORMAT BARU"))?.text ?? "";
    assert.match(t, /Contoh hasil bacaan:\n• baris 2: ID /);
    assert.match(t, /\/profilmesin/);
  }
  assert.equal(nilai("select hasil || '/' || jumlah_baris || '/' || nomor_pesan from fakta.kiriman_file where nama_file = 'f09_a.csv'"), `diterima/${harap}/40001`);
  assert.equal(nilai(`select concat_ws('|', mesin, sidik_judul, kolom_id, kolom_waktu, susunan, aktif::text,
                      (select telegram_id from induk.pengguna where id = disetujui_oleh)) from induk.profil_file_mesin where id = ${profilF2}`),
               `MA2|nama|noid|waktu||status|No.ID|Waktu|dmy|true|${HRD}`);
  const lagi = await kirimUpdate(tombolX(40009, HRD, `x|${konfirmasiF2}|y|0`));
  assert.match(lagi.pesan[0].text, /sudah selesai \(profil disimpan\)/);
});

test("F2: file kedua dari mesin yang sama dengan judul sama persis dibaca otomatis memakai profil (tanpa pertanyaan)", async () => {
  const r = await kirimUpdate(dokumen(40010, HRD, "F2_B", "f09_b.csv", "MA2"));
  assert.ok(!r.pesan.some((p) => /belum dikenal|Kolom mana/.test(p.text)));
  assert.ok(r.pesan.some((p) => p.chat_id === HRD && /^File f09_b\.csv tersimpan: \d+ tap.*dibaca dengan profil format no\. \d+ mesin MA2/.test(p.text)));
  assert.equal(nilai("select hasil from fakta.kiriman_file where nama_file = 'f09_b.csv'"), "diterima");
  // C3: mesin lain dengan judul yang sama tetap ditanya.
  const m1 = await kirimUpdate(dokumen(40011, HRD, "F2_C", "f09_c_ma1.csv", "MA1"));
  assert.ok(m1.pesan.some((p) => p.chat_id === HRD && /belum dikenal/.test(p.text)));
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'f09_c_ma1.csv'"), "0");
});

test("F2 (K3): judul kolom berubah -> ditanya lagi; Tidak -> ditolak format tidak dikenal + pemberitahuan segera; profil tidak bertambah", async () => {
  const r = await kirimUpdate(dokumen(40012, HRD, "F2_LOKASI", "f09_lokasi.csv", "MA2"));
  const hrd = r.pesan.filter((p) => p.chat_id === HRD);
  assert.match(hrd[1].text, /"Lokasi"\. File ditahan/);
  const id = Number(/konfirmasi format no\. (\d+)/.exec(hrd[1].text)![1]);
  await kirimUpdate(tombolX(40013, HRD, `x|${id}|i|1`));
  const c = await kirimUpdate(tombolX(40014, HRD, `x|${id}|w|2`));
  assert.match(c.pesan.at(-1).text, /^Contoh hasil bacaan/);
  const t = await kirimUpdate(tombolX(40015, HRD, `x|${id}|n|0`));
  assert.ok(t.pesan.some((p) => p.chat_id === HRD && p.text === `File f09_lokasi.csv ditolak: ${PESAN.formatTidakDikenal}`), JSON.stringify(t.pesan));
  for (const tg of [HRD, PEMBANGUN]) assert.match(segera(t.pesan, tg)[0] ?? "", /f09_lokasi\.csv/, String(tg));
  assert.equal(nilai("select hasil from fakta.kiriman_file where nama_file = 'f09_lokasi.csv'"), "ditolak");
  assert.equal(nilai("select count(*) from induk.profil_file_mesin"), "1");
  assert.equal(nilai(`select b.status from fakta.pemberitahuan b
                      where b.kunci = 'kiriman|' || (select id from fakta.kiriman_file where nama_file = 'f09_lokasi.csv')`), "terkirim");
});

test("F2: tanggal yang bisa dibaca dua cara -> ditanya (pilihan sesuai contoh); dua kolom tanggal+jam; Pilih ulang kembali ke ID", async () => {
  assert.deepEqual(duaArti("03/04/2026"), ["3 April 2026", "4 Maret 2026"]);
  assert.deepEqual(susunanKolom({ ab: 2, a12: 1, b12: 0, contoh: null }), ["dmy"]);
  assert.deepEqual(susunanKolom({ ab: 2, a12: 1, b12: 1, contoh: null }), []);
  const r = await kirimUpdate(dokumen(40016, HRD, "F2_DUA_ARTI", "dua_arti.csv", "MA1"));
  const id = Number(/konfirmasi format no\. (\d+)/.exec(r.pesan.filter((p) => p.chat_id === HRD)[1].text)![1]);
  await kirimUpdate(tombolX(40017, HRD, `x|${id}|i|0`));
  const s = await kirimUpdate(tombolX(40018, HRD, `x|${id}|w|1`));
  assert.match(s.pesan[0].text, /tanggal "01\/02\/2026" di kolom "Jam Scan" maksudnya\?/);
  assert.deepEqual(tombolTeks(s.pesan[0]), ["1 Februari 2026", "2 Januari 2026"]);
  const c = await kirimUpdate(tombolX(40019, HRD, dataTombol(s.pesan[0], "2 Januari 2026")));
  assert.ok(c.pesan.at(-1).text.includes("ID 10881, Jumat, 2 Jan 2026, jam 07.01"), c.pesan.at(-1).text);
  assert.match(c.pesan.at(-1).text, /tanggal dibaca bulan\/hari\/tahun/);
  const u = await kirimUpdate(tombolX(40020, HRD, `x|${id}|u|0`));
  assert.match(u.pesan[0].text, /Kolom mana yang berisi ID karyawan/);
  assert.equal(nilai(`select langkah || '/' || pilihan::text from fakta.konfirmasi_format where id = ${id}`), "id/{}");
  // Bila ditolak HRD lain: belum ada apa pun yang dicatat untuk file ini.
  assert.equal(nilai("select count(*) from fakta.kiriman_file where nama_file = 'dua_arti.csv'"), "0");
});

test("F2: /profilmesin hanya pembangun; Hapus -> file berikutnya dengan judul itu ditanya lagi; file yang sudah dihitung tetap", async () => {
  assert.match((await kirimUpdate(teksPribadi(40021, HRD, "/profilmesin"))).pesan[0].text, /hanya untuk akun pembangun/);
  const d = await kirimUpdate(teksPribadi(40022, PEMBANGUN, "profilmesin"));
  assert.match(d.pesan[0].text, new RegExp(`No\\. ${profilF2}, mesin MA2: ID = "No\\.ID", tanggal-jam = "Waktu"`));
  assert.deepEqual(tombolTeks(d.pesan[0]), [`Hapus no. ${profilF2} (mesin MA2)`]);
  const kiriman = nilai("select string_agg(hasil, ',' order by id) from fakta.kiriman_file where nama_file like 'f09_%'");
  const sebelum = sidikGaji();
  const h = await kirimUpdate(tombolX(40023, PEMBANGUN, dataTombol(d.pesan[0], `Hapus no. ${profilF2} (mesin MA2)`)));
  assert.match(h.pesan[0].text, new RegExp(`Profil format no\\. ${profilF2} \\(mesin MA2\\) dihapus`));
  assert.equal(nilai(`select aktif::text || '/' || alasan_nonaktif from induk.profil_file_mesin where id = ${profilF2}`), "false/dihapus pembangun (/profilmesin)");
  assert.equal(nilai("select string_agg(hasil, ',' order by id) from fakta.kiriman_file where nama_file like 'f09_%'"), kiriman);
  assert.equal(sidikGaji(), sebelum);
  const lagi = await kirimUpdate(tombolX(40024, PEMBANGUN, dataTombol(d.pesan[0], `Hapus no. ${profilF2} (mesin MA2)`)));
  assert.match(lagi.pesan[0].text, /sudah dihapus/);
  const f = await kirimUpdate(dokumen(40025, HRD, "F2_C", "f09_c_lagi.csv", "MA2"));
  assert.ok(f.pesan.some((p) => p.chat_id === HRD && /belum dikenal/.test(p.text)));
  assert.match((await kirimUpdate(teksPribadi(40026, PEMBANGUN, "/profilmesin"))).pesan[0].text, /Belum ada profil/);
});

test("F2 (K1): halaman unggah: format baru tanpa profil ditolak dengan arahan ke bot (pemberitahuan segera); dengan profil diterima", async () => {
  assert.equal(nilai(`select fakta.jenis_tolak_segera($t$${PESAN_FORMAT_BARU_WEB}$t$)`), "format_tidak_dikenal");
  const t = await kirimUpdate(JSON.stringify({ update_id: 40027, message: { message_id: 40027, chat: { id: HRD }, from: { id: HRD }, text: "/unggah" } }));
  const kode = kodeDari(t.pesan[0].text);
  const tolak = await unggah("f09_web.csv", fileF09(161, 201), "MA2", kode);
  assert.equal(tolak.isi.hasil, "ditolak");
  assert.equal(tolak.isi.alasan, PESAN_FORMAT_BARU_WEB);
  assert.match(segera(tolak.pesan, PEMBANGUN)[0] ?? "", /f09_web\.csv/);
  // Profil disimpan lewat bot (pembangun, K2), lalu file lain dengan judul sama lewat web diterima memakai profil itu.
  const r = await kirimUpdate(dokumen(40028, PEMBANGUN, "F2_C", "f09_c_pembangun.csv", "MA2"));
  const id = Number(/konfirmasi format no\. (\d+)/.exec(r.pesan.filter((p) => p.chat_id === PEMBANGUN)[1].text)![1]);
  await kirimUpdate(tombolX(40029, PEMBANGUN, `x|${id}|i|1`));
  await kirimUpdate(tombolX(40030, PEMBANGUN, `x|${id}|w|2`));
  const y = await kirimUpdate(tombolX(40031, PEMBANGUN, `x|${id}|y|0`));
  assert.ok(y.pesan.some((p) => p.chat_id === PEMBANGUN && /^Profil format no\. \d+ disimpan untuk mesin MA2/.test(p.text)));
  assert.ok(!y.pesan.some((p) => p.chat_id === PEMBANGUN && p.text.startsWith("PROFIL FORMAT BARU")), "pembangun tidak diberi tahu dirinya sendiri");
  assert.ok(y.pesan.some((p) => p.chat_id === 333 && p.text.startsWith("PROFIL FORMAT BARU")));
  const terima = await unggah("f09_web2.csv", fileF09(201, 241), "MA2", kode);
  assert.equal(terima.isi.hasil, "diterima", JSON.stringify(terima.isi));
  assert.ok(terima.isi.jumlah_tap > 0);
});
