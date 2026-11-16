-- Uji isian aturan resmi dari migrasi 0008 (tarif TER PPh 21 dan PTKP).
-- Sumber dan tanggal pengecekan: docs/cek-aturan-hukum.md.
begin;

-- Jumlah lapisan sesuai Lampiran PP 58/2023: A 44, B 40, C 41.
select uji.sama('TER: kategori A punya 44 lapisan',
  (select count(*) from aturan.tarif_ter where kategori = 'A')::int, 44);
select uji.sama('TER: kategori B punya 40 lapisan',
  (select count(*) from aturan.tarif_ter where kategori = 'B')::int, 40);
select uji.sama('TER: kategori C punya 41 lapisan',
  (select count(*) from aturan.tarif_ter where kategori = 'C')::int, 41);

-- Tidak ada celah: setiap lapisan mulai tepat di akhir lapisan sebelumnya, mulai dari 0, satu lapisan terbuka di atas.
select uji.sama('TER: lapisan bersambung tanpa celah',
  (select count(*) from (
     select bruto_dari, lag(bruto_sampai) over (partition by kategori order by bruto_dari) as sebelumnya
     from aturan.tarif_ter) t
   where sebelumnya is not null and sebelumnya <> bruto_dari)::int, 0);
select uji.sama('TER: tiap kategori mulai dari 0 dan punya satu lapisan teratas terbuka',
  (select count(*) from aturan.tarif_ter where bruto_dari = 0)::int * 10
  + (select count(*) from aturan.tarif_ter where bruto_sampai is null)::int, 33);
select uji.sama('TER: tarif naik bersama penghasilan',
  (select count(*) from (
     select persen, lag(persen) over (partition by kategori order by bruto_dari) as sebelumnya
     from aturan.tarif_ter) t
   where persen < sebelumnya)::int, 0);

-- Batas lapisan: "sampai dengan" ikut lapisan bawah.
select uji.sama('TER A: bruto 5.400.000 kena 0%',
  (select persen from aturan.tarif_ter where kategori = 'A' and 5400000 >= bruto_dari and (bruto_sampai is null or 5400000 < bruto_sampai)), 0);
select uji.sama('TER A: bruto 5.400.001 kena 0,25%',
  (select persen from aturan.tarif_ter where kategori = 'A' and 5400001 >= bruto_dari and (bruto_sampai is null or 5400001 < bruto_sampai)), 25);

-- Kasus jebakan E04: TK/0, bruto pajak 10.454.000 -> kategori A, 2,5%, PPh 21 = 261.350.
select uji.sama('E04: TK/0 memakai kategori A',
  (select kategori_ter from aturan.ptkp where status = 'TK/0' and berlaku_sampai is null), 'A');
select uji.sama('E04: bruto 10.454.000 kena 2,5%',
  (select t.persen from aturan.tarif_ter t join aturan.ptkp p on p.kategori_ter = t.kategori
   where p.status = 'TK/0' and 10454000 >= t.bruto_dari and (t.bruto_sampai is null or 10454000 < t.bruto_sampai)
     and '2026-03-31' >= t.berlaku_dari and (t.berlaku_sampai is null or '2026-03-31' < t.berlaku_sampai)), 250);
select uji.sama('E04: PPh 21 = Rp261.350',
  (select 10454000::bigint * persen / 10000 from aturan.tarif_ter
   where kategori = 'A' and 10454000 >= bruto_dari and (bruto_sampai is null or 10454000 < bruto_sampai)), 261350::bigint);

-- PTKP: 8 status, nilai sesuai PMK 101/2016.
select uji.sama('PTKP: 8 status terisi',
  (select count(*) from aturan.ptkp)::int, 8);
select uji.sama('PTKP: jumlah semua nilai sesuai PMK 101/2016',
  (select sum(nilai_setahun) from aturan.ptkp)::bigint,
  (54000000 + 58500000 + 58500000 + 63000000 + 67500000 + 63000000 + 67500000 + 72000000)::bigint);
select uji.sama('PTKP: K/3 satu-satunya kategori C',
  (select string_agg(status, ',') from aturan.ptkp where kategori_ter = 'C'), 'K/3');

-- Tarif baru yang tumpang tindih dengan tarif resmi ditolak (perubahan harus menutup baris lama dulu).
select uji.harus_ditolak('TER: tarif baru yang menimpa tarif resmi ditolak',
  $$insert into aturan.tarif_ter (kategori, bruto_dari, bruto_sampai, persen, berlaku_dari) values ('B', 7000000, 7100000, 80, '2027-01-01')$$);

rollback;
