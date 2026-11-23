"""Header keamanan halaman demo dan unggah (paket 6f, celah S3; docs/halaman-demo.md versi 4).

Menulis <folder>/_headers (format Cloudflare Pages). Skrip yang tertulis langsung di halaman diizinkan lewat sidik
SHA-256 masing-masing (bukan 'unsafe-inline'); gaya boleh langsung (atribut style="..." tidak bisa diberi sidik, dan
CSS tidak menjalankan kode). Sambungan hanya ke halaman sendiri dan alamat Edge Function.

Pemakaian: python3 web/buat_headers.py <folder halaman> <asal Edge Function, mis. https://xxx.supabase.co>
           python3 web/buat_headers.py --periksa <folder> <asal>   (keluar 1 bila _headers tidak sesuai halaman)
"""
import base64
import hashlib
import os
import re
import sys

HALAMAN = ["index.html", "unggah/index.html", "hrd/index.html"]


punya_src = set()


def sidik_skrip(folder):
    hasil = []
    for h in HALAMAN:
        teks = open(os.path.join(folder, h), encoding="utf-8").read()
        if re.search(r"\son[a-z]+\s*=", teks, re.I) or "javascript:" in teks:
            raise SystemExit(f"GAGAL: {h} memuat penangan kejadian langsung (on...=) atau javascript:, diblok CSP")
        for src in re.findall(r"<script[^>]*\ssrc=[\"']([^\"']*)[\"']", teks, re.I):
            # Paket G1: skrip dari halaman sendiri (alamat relatif) boleh; dari situs lain tidak.
            if re.match(r"^([a-z][a-z0-9+.-]*:|//)", src, re.I) or ".." in src:
                raise SystemExit(f"GAGAL: {h} memuat skrip dari luar ({src}); tidak diizinkan")
            punya_src.add(src)
        for isi in re.findall(r"<script>(.*?)</script>", teks, re.S):
            hasil.append("'sha256-" + base64.b64encode(hashlib.sha256(isi.encode("utf-8")).digest()).decode() + "'")
    return sorted(set(hasil))


def susun(folder, asal_fungsi):
    if not re.fullmatch(r"https://[a-z0-9]+\.supabase\.co", asal_fungsi):
        raise SystemExit(f"GAGAL: asal Edge Function tidak sah: {asal_fungsi!r}")
    csp = "; ".join([
        "default-src 'none'",
        "script-src " + " ".join(sidik := sidik_skrip(folder)) + (" 'self'" if punya_src else ""),
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data:",
        f"connect-src 'self' {asal_fungsi}",
        "base-uri 'none'",
        "form-action 'self'",
        "frame-ancestors 'none'",
    ])
    return ("# Dibuat web/buat_headers.py (paket 6f); jangan diedit tangan.\n"
            "/*\n"
            f"  Content-Security-Policy: {csp}\n"
            "  X-Content-Type-Options: nosniff\n"
            "  Referrer-Policy: no-referrer\n"
            "  X-Frame-Options: DENY\n")


def main():
    arg = sys.argv[1:]
    periksa = bool(arg) and arg[0] == "--periksa"
    if periksa:
        arg = arg[1:]
    if len(arg) != 2:
        print(__doc__)
        sys.exit(2)
    folder, asal = arg
    isi = susun(folder, asal)
    jalur = os.path.join(folder, "_headers")
    if periksa:
        lama = open(jalur, encoding="utf-8").read() if os.path.exists(jalur) else ""
        if lama != isi:
            print("GAGAL: _headers tidak sesuai halaman sekarang (sidik skrip berubah?)")
            sys.exit(1)
        print("_headers sesuai halaman")
        return
    with open(jalur, "w", encoding="utf-8") as f:
        f.write(isi)
    print(f"_headers ditulis: {len(sidik_skrip(folder))} sidik skrip, sambungan ke {asal}")


if __name__ == "__main__":
    main()
