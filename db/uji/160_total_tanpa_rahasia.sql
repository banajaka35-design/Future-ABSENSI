-- Uji paket G1-3 (docs/rencana-g1-3.md): total gaji untuk bot dan halaman unggah tanpa orang rahasia, aturan F15c.
-- Angka harapan dihitung tangan di komentar, bukan dengan rumus yang sama. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.mesin (kode, nama) values ('MZ1', 'Uji G1-3');
insert into induk.divisi (kode, nama, pola) values ('ZG13', 'Uji G1-3', 'mingguan');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2031-01-21', '2031-02-20', '2031-02-25'),   -- P1
  ('2031-02-21', '2031-03-20', '2031-03-25'),   -- P2
  ('2031-03-21', '2031-04-20', '2031-04-25');   -- P3

-- Lima orang. Gaji bersih tiap periode: A 1.000, B 2.000, C 3.000, D 4.000, E 5.000.
--   A, E: tidak pernah rahasia.
--   B: rahasia sejak awal.
--   C: rahasia sampai 28 Feb 2031, sesudahnya dicabut (F15c: tetap tersembunyi di P1 dan P2, terbuka di P3).
--   D: dijadikan rahasia mulai 10 Apr 2031 ("rahasia sekarang": tersembunyi di semua periode).
insert into induk.karyawan (id, nama) values ('Z1A', 'Uji A'), ('Z1B', 'Uji B'), ('Z1C', 'Uji C'), ('Z1D', 'Uji D'), ('Z1E', 'Uji E');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, berlaku_sampai, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('Z1A', '2030-01-01', null, 'ZG13', 1, 'TK/0', 'transfer', false),
  ('Z1B', '2030-01-01', null, 'ZG13', 1, 'TK/0', 'transfer', true),
  ('Z1C', '2030-01-01', '2031-03-01', 'ZG13', 1, 'TK/0', 'transfer', true),
  ('Z1C', '2031-03-01', null, 'ZG13', 1, 'TK/0', 'transfer', false),
  ('Z1D', '2030-01-01', '2031-04-10', 'ZG13', 1, 'TK/0', 'transfer', false),
  ('Z1D', '2031-04-10', null, 'ZG13', 1, 'TK/0', 'transfer', true),
  ('Z1E', '2030-01-01', null, 'ZG13', 1, 'TK/0', 'transfer', false);

create temp table v (nama text primary key, id bigint);
with baru as (
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan)
  select p.id, 'hitung_gaji', 1, 'uji-g1-3', 'uji-g1-3-' || p.tanggal_awal from fakta.periode p
  where p.tanggal_awal in ('2031-01-21', '2031-02-21', '2031-03-21')
  returning id, periode_id
)
insert into v select 'P' || row_number() over (order by p.tanggal_awal), b.id from baru b join fakta.periode p on p.id = b.periode_id;
insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, dibayar)
select v.id, k.id, x.b, x.b, 0, x.b, x.b
from v cross join (values ('Z1A', 1000), ('Z1B', 2000), ('Z1C', 3000), ('Z1D', 4000), ('Z1E', 5000)) as x(i, b)
join induk.karyawan k on k.id = x.i;
-- Versi baca tap (bukan hitung gaji) untuk uji "bukan versi gaji -> null".
insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan)
select p.id, 'baca_tap', 1, 'uji-g1-3', 'uji-g1-3-baca' from fakta.periode p where p.tanggal_awal = '2031-01-21';

-- P1: terlihat A, E -> 2 orang, 6.000; rahasia B, C, D -> 3.
-- Aturan lama "semua orang": 15.000. Aturan lama "status terakhir saja": A, C, E -> 9.000.
select uji.sama('G1-3 P1: total tanpa orang rahasia (A + E = 6.000; semua orang 15.000 dan status terakhir 9.000 salah)',
  hitung.ringkasan_terlihat((select id from v where nama = 'P1')), '{"orang": 2, "bersih": 6000, "rahasia": 3}'::jsonb);
-- P2: C masih rahasia 21-28 Feb (F15c) -> sama dengan P1.
select uji.sama('G1-3 P2 (F15c): C dicabut rahasianya 1 Mar tetap tersembunyi karena rahasia pada hari mana pun di periode',
  hitung.ringkasan_terlihat((select id from v where nama = 'P2')), '{"orang": 2, "bersih": 6000, "rahasia": 3}'::jsonb);
-- P3: C tidak rahasia sepanjang periode -> A + C + E = 9.000; D tetap tersembunyi (rahasia di 10-20 Apr dan sekarang).
select uji.sama('G1-3 P3 (F15c): C terbuka di periode sesudah dicabut; D tersembunyi',
  hitung.ringkasan_terlihat((select id from v where nama = 'P3')), '{"orang": 3, "bersih": 9000, "rahasia": 2}'::jsonb);
select uji.sama('G1-3: total - jumlah per orang yang terlihat = 0 di semua periode',
  (select count(*) from v where (hitung.ringkasan_terlihat(v.id) ->> 'bersih')::bigint
     <> (select sum(g.gaji_bersih) from hitung.ringkasan_gaji g where g.versi_id = v.id
         and g.id_karyawan in (select 'Z1A' union select 'Z1E' union select 'Z1C' where v.nama = 'P3'))), 0::bigint);
select uji.sama('G1-3: versi yang bukan hitung gaji -> null',
  hitung.ringkasan_terlihat((select id from hitung.versi_hitung where sidik_masukan = 'uji-g1-3-baca')), null::jsonb);

-- C1: hasil antrean menyimpan nomor versi; total dihitung saat dibaca.
select uji.sama('G1-3 (C1): hasil antrean tampil = hitungan saat dibaca',
  fakta.hasil_antrean_tampil(jsonb_build_object('versi_gaji', (select id from v where nama = 'P3'), 'bisa_diajukan', true, 'segera', 2)),
  '{"orang": 3, "bersih": 9000, "rahasia": 2, "bisa_diajukan": true, "segera": 2}'::jsonb);
-- E dijadikan rahasia "sekarang" (sesudah hasil disimpan): P3 menjadi A + C = 4.000.
update induk.karyawan_riwayat set berlaku_sampai = '2031-05-01' where id_karyawan = 'Z1E' and berlaku_sampai is null;
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia)
values ('Z1E', '2031-05-01', 'ZG13', 1, 'TK/0', 'transfer', true);
select uji.sama('G1-3 (C1): orang yang dijadikan rahasia sesudah hasil disimpan ikut disembunyikan (P3: A + C = 4.000)',
  fakta.hasil_antrean_tampil(jsonb_build_object('versi_gaji', (select id from v where nama = 'P3'))),
  '{"orang": 2, "bersih": 4000, "rahasia": 3}'::jsonb);
-- C1b: baris lama (sebelum paket ini) berisi rupiah -> tanpa angka.
select uji.sama('G1-3 (C1b): baris lama berisi rupiah tampil tanpa angka',
  fakta.hasil_antrean_tampil('{"orang": 1010, "bersih": 4999870485, "bisa_diajukan": false, "segera": 0}'::jsonb),
  '{"bisa_diajukan": false, "segera": 0, "angka_dihapus": true}'::jsonb);
select uji.sama('G1-3 (C1b): versi yang tidak dikenal -> tanpa angka',
  fakta.hasil_antrean_tampil('{"versi_gaji": -1}'::jsonb), '{"angka_dihapus": true}'::jsonb);
select uji.sama('G1-3 (C1b): tidak ada baris antrean berisi rupiah sesudah migrasi 0024',
  (select count(*) from fakta.antrean_kerja where hasil ? 'bersih' or hasil ? 'orang'), 0::bigint);

-- C3: peran pintu tidak bisa memanggil fungsi yang menghitung rahasia.
select uji.harus_ditolak('G1-3 (C3): pintu ditolak memanggil hitung.ringkasan_terlihat',
  'select hitung.ringkasan_terlihat(1)', 'pintu');
select uji.harus_ditolak('G1-3 (C3): pintu ditolak memanggil fakta.hasil_antrean_tampil',
  $$select fakta.hasil_antrean_tampil('{}'::jsonb)$$, 'pintu');
select uji.sama('G1-3 (C3): kedua fungsi tanpa izin jalankan untuk anon, authenticated, pintu',
  (select count(*) from pg_proc f cross join pg_roles r
   where f.oid in ('hitung.ringkasan_terlihat(bigint)'::regprocedure, 'fakta.hasil_antrean_tampil(jsonb)'::regprocedure)
     and r.rolname in ('anon', 'authenticated', 'pintu')
     and has_function_privilege(r.oid, f.oid, 'execute')), 0::bigint);
select uji.sama('G1-3 (C3): ada 3 peran yang diperiksa', (select count(*) from pg_roles where rolname in ('anon', 'authenticated', 'pintu')), 3::bigint);

rollback;
