-- Pemeriksaan setelah data awal Pabrik A dimuat. Dipakai di uji otomatis dan setelah pemasangan ke Supabase.
select uji.sama('data awal: 2 mesin', (select count(*) from induk.mesin)::int, 2);
select uji.sama('data awal: 5 divisi', (select count(*) from induk.divisi)::int, 5);
select uji.sama('data awal: setiap karyawan punya riwayat yang berlaku saat mulai kerja',
  (select count(*) from induk.karyawan k
   where not exists (select 1 from induk.karyawan_riwayat r where r.id_karyawan = k.id))::int, 0);
select uji.sama('data awal: setiap karyawan punya regu sejak mulai kerja',
  (select count(*) from induk.karyawan k
   join induk.status_kerja s on s.id_karyawan = k.id and s.jenis = 'mulai'
   where not exists (select 1 from induk.penugasan_regu p
                     where p.id_karyawan = k.id and daterange(p.berlaku_dari, p.berlaku_sampai, '[)') @> s.tanggal))::int, 0);
select uji.sama('data awal: setiap karyawan punya ID mesin',
  (select count(*) from induk.karyawan k
   where not exists (select 1 from induk.pemetaan_id_mesin p where p.id_karyawan = k.id))::int, 0);
select uji.sama('data awal: karyawan dengan dua ID mesin (kasus F07)',
  (select count(*) from (select id_karyawan from induk.pemetaan_id_mesin group by 1 having count(*) > 1) x)::int, 1);
select uji.sama('data awal: kalender 2026 berisi 22 tanggal', (select count(*) from induk.kalender)::int, 22);
select uji.sama('data awal: pengali lembur lengkap 44 baris', (select count(*) from aturan.pengali_lembur)::int, 44);
select uji.sama('data awal: jadwal kantor Ramadan 19 Feb memakai KR',
  (select kode from induk.jadwal_hari where divisi = 'KTR' and hari_ke = 4
   and daterange(berlaku_dari, berlaku_sampai, '[)') @> date '2026-02-19'), 'KR'::text);
