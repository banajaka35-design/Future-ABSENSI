-- Uji paket 8c-2 (docs/rencana-8c-2.md): isi pesan gaji membawa sisa pembulatan periode lalu (kasus E09).
begin;
set local app.pengguna = 'uji-otomatis';
insert into induk.divisi (kode, nama, pola) values ('ZS2', 'Uji Sisa', 'mingguan');
insert into induk.karyawan (id, nama) values ('S2A', 'Uji Sisa'), ('S2B', 'Uji Tanpa Sisa');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('S2A', '2030-01-01', 'ZS2', 1, 'TK/0', 'tunai', false), ('S2B', '2030-01-01', 'ZS2', 1, 'TK/0', 'tunai', false);
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values ('2037-01-21', '2037-02-20', '2037-02-25');
create temp table p as select id from fakta.periode where tanggal_awal = '2037-01-21';
do $$
declare
  v_baca bigint;
  v_gaji bigint;
  v_p bigint := (select id from p);
begin
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (v_p, 'baca_tap', 1, 'uji-8c2', 'b', 'b') returning id into v_baca;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil, versi_sumber)
  values (v_p, 'hitung_gaji', 1, 'uji-8c2', 'g', 'g', v_baca) returning id into v_gaji;
  -- E09: bersih 3.847.263 + sisa lalu 400 = dibayar 3.847.000 + sisa 663
  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, sisa_lalu,
                                     dibayar, sisa_pembulatan, peringatan)
  values (v_gaji, 'S2A', 3847263, 3847263, 0, 3847263, 400, 3847000, 663, '{}'),
         (v_gaji, 'S2B', 3847000, 3847000, 0, 3847000, 0, 3847000, 0, '{}');
end $$;
select uji.sama('8c-2: isi pesan membawa sisa pembulatan lalu',
  (fakta.isi_gaji((select id from p), 'S2A') ->> 'sisa_lalu') || '/' || (fakta.isi_gaji((select id from p), 'S2B') ->> 'sisa_lalu'), '400/0');
select uji.sama('8c-2: bersih + sisa lalu = dibayar + sisa baru, dari isi pesan',
  (select (x ->> 'bersih')::bigint + (x ->> 'sisa_lalu')::bigint - (x ->> 'dibayar')::bigint - (x ->> 'sisa')::bigint
   from (select fakta.isi_gaji((select id from p), 'S2A') x) z), 0::bigint);
rollback;
