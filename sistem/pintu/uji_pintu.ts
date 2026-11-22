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
  apiBoleh, BATAS_PESAN, JENIS_SEGERA, MENU, PESAN_HANYA_PRIBADI, rapikanPerintah, susunPesanSegera, TANYA_ID, TANYA_PIN,
  TOMBOL_TETAP, TANYA_PERINTAH, CARA_PERINTAH, bacaTanggal, bacaPerintah, tulisTanggal, susunPesanGaji, susunTotalLengkap, rupiah as rupiahBot, BATAS_PESAN as BATAS, tanganiPengingat, tanganiPermintaan, webMintaKode, webPeriksa,
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
  urai,
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
