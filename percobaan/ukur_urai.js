// Percobaan Tahap 1,5: ukur waktu prosesor (CPU) untuk mengurai file mesin.
// Pembanding: Cloudflare Workers gratis 10 ms CPU per permintaan, berbayar 30 detik.
// Kode percobaan, boleh dibuang. Pemakaian: node ukur_urai.js <file.xls> <file.csv.gz>
const fs = require("fs");
const zlib = require("zlib");
const XLSX = require("xlsx");

function cpuMs(fn, ulang = 5) {
  const hasil = [];
  let out;
  for (let i = 0; i < ulang; i++) {
    const a = process.cpuUsage();
    out = fn();
    const b = process.cpuUsage(a);
    hasil.push((b.user + b.system) / 1000);
  }
  hasil.sort((x, y) => x - y);
  return { median: hasil[Math.floor(ulang / 2)], out };
}

const [xlsPath, csvPath] = process.argv.slice(2);
const xlsBuf = fs.readFileSync(xlsPath);
const csvTxt = zlib.gunzipSync(fs.readFileSync(csvPath)).toString("utf8");

const xls = cpuMs(() => {
  const wb = XLSX.read(xlsBuf, { type: "buffer" });
  return XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1 }).length;
});
const csv = cpuMs(() => {
  let n = 0;
  for (const baris of csvTxt.split("\n")) {
    if (!baris) continue;
    const kol = baris.split(",");
    if (kol.length >= 5) n++;
  }
  return n;
});
console.log(JSON.stringify({
  ukuran_xls_mb: +(xlsBuf.length / 1048576).toFixed(2),
  ukuran_csv_mb: +(Buffer.byteLength(csvTxt) / 1048576).toFixed(2),
  baris_xls: xls.out, cpu_urai_xls_ms: +xls.median.toFixed(0),
  baris_csv: csv.out, cpu_urai_csv_ms: +csv.median.toFixed(0),
}, null, 1));
