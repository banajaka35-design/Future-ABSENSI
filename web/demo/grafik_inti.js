// Penghitung ukuran grafik halaman demo (paket G1, docs/halaman-demo.md versi 5).
// Fungsi murni (tanpa DOM), diuji node --test (sistem/uji/uji_grafik.ts). Dimuat halaman dari asal sendiri.
"use strict";
(function (g) {
  // Batang mendatar: panjang tiap batang terhadap lebar tersedia. Nilai minus/kosong -> 0 (ditandai).
  function batangMendatar(daftar, lebar) {
    const maks = Math.max(0, ...daftar.map((d) => Number(d.nilai) || 0));
    return daftar.map((d) => {
      const n = Number(d.nilai) || 0;
      const panjang = maks > 0 && n > 0 ? Math.max(1, Math.round((n / maks) * lebar)) : 0;
      return { label: d.label, nilai: n, panjang, minus: n < 0 };
    });
  }
  // Kolom per tanggal: tinggi tiap kolom terhadap tinggi tersedia; indeks nilai tertinggi (untuk satu label).
  function kolom(nilai, tinggi) {
    const maks = Math.max(0, ...nilai.map((n) => Number(n) || 0));
    const t = nilai.map((n) => (maks > 0 && n > 0 ? Math.max(1, Math.round((n / maks) * tinggi)) : 0));
    return { tinggi: t, maks, puncak: maks > 0 ? nilai.indexOf(maks) : -1 };
  }
  // Selang label sumbu: tampilkan tiap k label supaya tiap label punya ruang paling sedikit minPx.
  function selangLabel(jumlah, lebarPx, minPx) {
    if (jumlah <= 0) return 1;
    const ruang = lebarPx / jumlah;
    return Math.max(1, Math.ceil((minPx || 28) / ruang));
  }
  // Persen satu desimal dengan koma (gaya Indonesia); total 0 -> "0,0".
  function persen(bagian, total) {
    if (!total) return "0,0";
    return ((bagian / total) * 100).toFixed(1).replace(".", ",");
  }
  g.GrafikInti = { batangMendatar, kolom, selangLabel, persen };
})(typeof window !== "undefined" ? window : globalThis);
