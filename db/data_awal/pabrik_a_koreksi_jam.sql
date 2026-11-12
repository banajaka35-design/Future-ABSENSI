-- Data awal Tahap 3 untuk pemasangan demo Pabrik A (simulasi): koreksi jam mesin.
-- Jam mesin MA2 lebih cepat 4 menit pada 1-10 Maret 2026, seolah sudah dilaporkan HRD (kasus F04).
-- Keputusan pemilik 13 Nov 2026: demo memakai koreksi; uji otomatis menguji dengan dan tanpa koreksi
-- (tanpa koreksi: file ini tidak dimuat).

begin;
set local app.pengguna = 'data-awal';

insert into induk.koreksi_jam_mesin (mesin, selisih_menit, berlaku_dari, berlaku_sampai)
values ('MA2', 4, '2026-03-01', '2026-03-11');

commit;
