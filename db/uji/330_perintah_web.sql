-- Uji paket 9b-1 (docs/rencana-9b-1.md): perintah lewat web HRD (tambah libur, absen manual divisi, berhenti,
-- aktif kembali, mutasi), pratinjau tanpa perubahan, simpan -> hitung ulang lewat antrean, dan pembatalan dengan
-- pengecualian sempit pada penjaga data induk. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

-- Data dasar seperti uji 240/320.
insert into aturan.jendela_tap (menit_sebelum_masuk, menit_sesudah_pulang, jarak_minimal_menit, berlaku_dari) values (120, 360, 60, '2026-01-01');
insert into aturan.toleransi (telat_menit, pulang_cepat_menit, berlaku_dari) values (5, 0, '2026-01-01');
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select j, k, case when k = 1 then 15 else 20 end, date '2021-02-02' from unnest(array['kerja', 'libur_6_hari', 'libur_6_hari_terpendek', 'libur_5_hari']) j, generate_series(1, 12) k;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang'), ('MA2', 'Kantor');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values
  ('TL', 'Uji Lantai', 'mingguan', 1, 'MA1'), ('TM', 'Uji Kantor', 'mingguan', 1, 'MA2'), ('TR', 'Uji Rotasi', 'rotasi', 2, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select d, 0, h, case when h = 7 then null else 'P' end, '2026-01-01' from unnest(array['TL', 'TM']) d, generate_series(1, 7) h;
-- K1, K2, K3 aktif; K4 berhenti 10 Apr 2026; K5 rahasia; K6 pernah ganti data (baris tertutup, untuk uji penjaga).
insert into induk.karyawan (id, nama) values ('K1', 'Uji Satu'), ('K2', 'Uji Dua'), ('K3', 'Uji Tiga'), ('K4', 'Uji Berhenti'),
  ('K5', 'Uji Rahasia'), ('K6', 'Uji Enam');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, jabatan, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                    rekening_terenkripsi, bpjs_kesehatan, bpjs_ketenagakerjaan, gaji_rahasia)
select i, '2025-01-01', 'TL', 'Operator', 3500000 + n * 1000, 500000, 'TK/' || (n % 4), case when n = 2 then 'tunai' else 'transfer' end,
       case when n = 2 then null else convert_to('rek-' || i, 'UTF8') end, n % 2 = 0, n % 3 = 0, i = 'K5'
from unnest(array['K1', 'K2', 'K3', 'K4', 'K5']) with ordinality x(i, n);
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, berlaku_sampai, divisi, gaji_pokok, ptkp, cara_bayar)
values ('K6', '2025-01-01', '2025-06-01', 'TL', 3500000, 'TK/0', 'tunai');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar)
values ('K6', '2025-06-01', 'TL', 3600000, 'TK/0', 'tunai');
insert into induk.status_kerja (id_karyawan, jenis, tanggal)
select i, 'mulai', '2025-01-01' from unnest(array['K1', 'K2', 'K3', 'K4', 'K5', 'K6']) i;
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('K4', 'berhenti', '2026-04-10');
insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari)
select i, 0, '2025-01-01' from unnest(array['K1', 'K2', 'K3', 'K4', 'K5', 'K6']) i;
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari)
select 'MA1', n::text, 'K' || n, '2025-01-01' from generate_series(1, 6) n;
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA2', '92', 'K2', '2025-01-01');
-- Tiga periode: dirilis (Feb-Mar), terbuka (Mar-Apr), terbuka (Apr-Mei).
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-02-21', '2026-03-20', '2026-03-25'), ('2026-03-21', '2026-04-20', '2026-04-25'), ('2026-04-21', '2026-05-20', '2026-05-25');
create function pg_temp.jadi(p_awal date, p_status text) returns void language sql as $$
  select set_config('app.ubah_status_periode', 'ya', true);
  update fakta.periode set status = p_status where tanggal_awal = p_awal;
  select set_config('app.ubah_status_periode', '', true) $$;
select pg_temp.jadi('2026-02-21', 'dirilis');
insert into induk.pengguna (telegram_id, peran, email) values (8801, 'hrd', 'hrd-9b@contoh.test'), (8802, 'hrd', 'hrd2-9b@contoh.test'),
  (8803, 'pembangun', 'bangun-9b@contoh.test');
-- Tap 7-14 Apr (Senin-Selasa); 10 Apr (Jumat) tidak ada tap sama sekali (untuk absen manual).
create temp table tap_uji (n int, t text, s text);
insert into tap_uji select n, d || ' 06:55:00', 'Masuk' from generate_series(1, 5) n,
  unnest(array['2026-04-07', '2026-04-08', '2026-04-09', '2026-04-11', '2026-04-13', '2026-04-14']) d where not (n = 4 and d > '2026-04-10');
insert into tap_uji select n, d || ' 15:05:00', 'Keluar' from generate_series(1, 5) n,
  unnest(array['2026-04-07', '2026-04-08', '2026-04-09', '2026-04-11', '2026-04-13', '2026-04-14']) d where not (n = 4 and d > '2026-04-10');
select fakta.terima_kiriman('uji9b.csv', repeat('b', 64), 'MA1',
  (select jsonb_agg(jsonb_build_array(n::text, t, s, r) order by r) from (select n, t, s, row_number() over (order by t, n) as r from tap_uji) y),
  null, '2026-04-15 08:00+07');
-- Mesin MA2 juga mengirim (supaya divisi TM tidak "menunggu data"); tap K2 yang sama persis dihitung sekali.
select fakta.terima_kiriman('uji9b-ma2.csv', repeat('a', 64), 'MA2', '[["92", "2026-04-07 06:55:00", "Masuk", 1]]'::jsonb, null, '2026-04-15 08:00+07');
update fakta.antrean_kerja set status = 'selesai', selesai = now() where status = 'menunggu';
select count(hitung.baca_tap(id)), count(hitung.hitung_gaji(id)) from fakta.periode where tanggal_awal = '2026-03-21';

create temp table h (nama text primary key, isi jsonb);
create temp table v as select id as periode from fakta.periode where tanggal_awal = '2026-03-21';
create function pg_temp.k(x text) returns jsonb language sql as $$ select isi from h where nama = x $$;
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select repeat('c', 64), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 8801;
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select repeat('e', 64), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 8802;
insert into fakta.sesi_web (sidik, pengguna, berlaku_sampai) select repeat('f', 64), id, now() + interval '1 hour' from induk.pengguna where telegram_id = 8803;
create function pg_temp.w(p_aksi text, p_perintah jsonb, p_sesi text default repeat('c', 64)) returns jsonb language sql as $$
  select api.web_hrd(jsonb_build_object('sidik_sesi', p_sesi, 'aksi', p_aksi, 'perintah', p_perintah)) $$;
-- Pratinjau lalu simpan (sesi yang sama).
create function pg_temp.simpan(p_perintah jsonb, p_sesi text default repeat('c', 64)) returns jsonb language plpgsql as $$
declare v jsonb := pg_temp.w('perintah_pratinjau', p_perintah, p_sesi);
begin
  if v ->> 'hasil' <> 'ok' then return v; end if;
  return pg_temp.w('perintah_simpan', jsonb_build_object('nomor', v #>> '{data,draf_id}'), p_sesi);
end $$;
create function pg_temp.batal(p_nomor bigint) returns jsonb language sql as $$
  select pg_temp.w('perintah_batal', jsonb_build_object('nomor', p_nomor)) $$;
-- Antrean dikerjakan seperti Edge Function (api.pintu_kerjakan sampai kosong).
create function pg_temp.kerja() returns integer language plpgsql as $$
declare r jsonb; n integer := 0;
begin
  loop
    r := api.pintu_kerjakan();
    exit when coalesce((r ->> 'kosong')::boolean, false) or n > 10;
    n := n + 1;
  end loop;
  return n;
end $$;
create function pg_temp.harian(p_id text) returns text language sql as $$
  select coalesce(string_agg(to_char(h.tanggal, 'MMDD') || ':' || h.status || ':' || h.asal || ':' || h.divisi, ',' order by h.tanggal), '-')
  from hitung.hasil_harian h, v
  where h.id_karyawan = p_id and h.tanggal between '2026-04-07' and '2026-04-14'
    and h.versi_id = (select x.id from hitung.versi_terakhir x where x.periode_id = v.periode and x.jenis = 'baca_tap') $$;
create function pg_temp.induk(p_id text) returns text language sql as $$
  select concat_ws('|',
    (select string_agg(to_jsonb(s)::text, ',' order by s.id) from induk.status_kerja s where s.id_karyawan = p_id),
    (select string_agg(to_jsonb(r)::text, ',' order by r.id) from induk.karyawan_riwayat r where r.id_karyawan = p_id),
    (select string_agg(to_jsonb(g)::text, ',' order by g.id) from induk.penugasan_regu g where g.id_karyawan = p_id),
    (select string_agg(to_jsonb(m)::text, ',' order by m.id) from induk.pemetaan_id_mesin m where m.id_karyawan = p_id)) $$;
create function pg_temp.potret() returns text language sql as $$
  select concat_ws('|', (select count(*) from fakta.perintah_hrd), (select count(*) from induk.status_kerja),
    (select count(*) from induk.karyawan_riwayat), (select count(*) from induk.penugasan_regu), (select count(*) from induk.pemetaan_id_mesin),
    (select count(*) from hitung.versi_hitung), (select count(*) from fakta.antrean_kerja), (select count(*) from jejak.perubahan)) $$;
create function pg_temp.satu(p_id text, p_hari text) returns text language sql as $$
  select coalesce((select x from unnest(string_to_array(pg_temp.harian(p_id), ',')) x where x like p_hari || ':%'), '-') $$;
create temp table awal as select pg_temp.harian('K1') k1, pg_temp.harian('K2') k2, pg_temp.harian('K3') k3,
  pg_temp.induk('K1') i1, pg_temp.induk('K3') i3, pg_temp.induk('K5') i5;

-- ===== Akses =====
insert into h values ('daftar', pg_temp.w('perintah_daftar', null));
select uji.sama('9b: daftar perintah berisi pilihan divisi', jsonb_array_length(pg_temp.k('daftar') #> '{data,divisi}'), 3);
insert into h values ('palsu', pg_temp.w('perintah_pratinjau', '{"jenis": "tambah_libur"}', repeat('d', 64)));
select uji.sama('9b: sesi palsu ditolak', pg_temp.k('palsu') ->> 'hasil', 'sesi_tidak_berlaku');
select uji.harus_ditolak('9b: pintu tidak bisa memanggil fungsi simpan langsung', $q$select fakta.web_perintah_simpan(1, 1)$q$, 'pintu');
select uji.harus_ditolak('9b: pintu tidak bisa memanggil fungsi batal langsung', $q$select fakta.web_perintah_batal(1, 1)$q$, 'pintu');

-- ===== Tambah libur =====
create temp table p0 as select pg_temp.potret() as x;
insert into h values ('libur_pra', pg_temp.w('perintah_pratinjau', '{"jenis": "tambah_libur", "mulai": "2026-04-14", "divisi": "TL", "alasan": "listrik padam"}'));
select uji.sama('9b: pratinjau tambah libur: orang aktif, periode, catatan tap',
  concat_ws('/', pg_temp.k('libur_pra') ->> 'hasil', pg_temp.k('libur_pra') #>> '{data,orang}',
            jsonb_array_length(pg_temp.k('libur_pra') #> '{data,periode}'),
            (pg_temp.k('libur_pra') #>> '{data,catatan,0}' like '4 orang sudah tap%')::text), 'ok/5/1/true');
select uji.sama('9b (C5/C12): pratinjau tidak mengubah apa pun (perintah, induk, versi, antrean, jejak)', pg_temp.potret(), (select x from p0));
insert into h values ('libur_simpan', pg_temp.w('perintah_simpan', jsonb_build_object('nomor', pg_temp.k('libur_pra') #>> '{data,draf_id}')));
insert into h values ('libur_ulang', pg_temp.w('perintah_simpan', jsonb_build_object('nomor', pg_temp.k('libur_pra') #>> '{data,draf_id}')));
select uji.sama('9b: simpan tambah libur -> perintah asal web oleh akun itu, antrean periode',
  (select concat_ws('/', x.asal, x.jenis, x.divisi, x.tanggal_mulai, u.telegram_id,
          (select count(*) from fakta.antrean_kerja a where a.perintah_id = x.id and a.status = 'menunggu'))
   from fakta.perintah_hrd x join induk.pengguna u on u.id = x.oleh where x.id = (pg_temp.k('libur_simpan') #>> '{data,perintah_id}')::bigint),
  'web/tambah_libur/TL/2026-04-14/8801/1');
select uji.sama('9b (C11): pratinjau yang sama tidak bisa disimpan dua kali', pg_temp.k('libur_ulang') ->> 'hasil', 'ditolak');
insert into h values ('libur_dobel', pg_temp.w('perintah_pratinjau', '{"jenis": "tambah_libur", "mulai": "2026-04-13", "selesai": "2026-04-14", "divisi": "TL", "alasan": "x"}'));
select uji.sama('9b: tambah libur yang bertumpuk dengan perintah sama ditolak',
  (pg_temp.k('libur_dobel') ->> 'alasan') like 'Sudah ada perintah no.%', true);
select pg_temp.kerja();
select uji.sama('9b: sesudah hitung ulang, 14 Apr libur; yang tap menjadi masuk di hari libur',
  pg_temp.satu('K2', '0414'), '0414:lembur_hari_libur:mesin:TL');
insert into h values ('daftar2', pg_temp.w('perintah_daftar', null));
select uji.sama('9b: daftar perintah web: ringkas, keadaan hitung selesai',
  concat_ws('/', pg_temp.k('daftar2') #>> '{data,perintah,0,ringkas}', pg_temp.k('daftar2') #>> '{data,perintah,0,hitung}'),
  'Tambah libur divisi Uji Lantai, 14 Apr 2026/selesai');
insert into h values ('libur_batal', pg_temp.batal((pg_temp.k('libur_simpan') #>> '{data,perintah_id}')::bigint));
select pg_temp.kerja();
select uji.sama('9b: batal tambah libur -> hasil harian kembali seperti semula',
  concat_ws('/', pg_temp.k('libur_batal') ->> 'hasil', pg_temp.harian('K2') = (select k2 from awal)), 'dibatalkan/t');
insert into h values ('libur_batal2', pg_temp.batal((pg_temp.k('libur_simpan') #>> '{data,perintah_id}')::bigint));
select uji.sama('9b: perintah yang sudah dibatalkan tidak bisa dibatalkan lagi', (pg_temp.k('libur_batal2') ->> 'alasan') like '%sudah dibatalkan%', true);
insert into h values ('libur_rilis', pg_temp.w('perintah_pratinjau', '{"jenis": "tambah_libur", "mulai": "2026-03-02", "alasan": "x"}'));
select uji.sama('9b (C3): tanggal di periode dirilis ditolak', (pg_temp.k('libur_rilis') ->> 'alasan') like '%sudah dirilis%', true);
insert into h values ('libur_31', pg_temp.w('perintah_pratinjau', '{"jenis": "tambah_libur", "mulai": "2026-03-21", "selesai": "2026-04-30", "alasan": "x"}'));
select uji.sama('9b: lebih dari 31 hari ditolak', (pg_temp.k('libur_31') ->> 'alasan') like 'Paling banyak 31%', true);
insert into h values ('libur_kosong', pg_temp.w('perintah_pratinjau', '{"jenis": "tambah_libur", "mulai": "2026-04-14"}'));
select uji.sama('9b: keterangan wajib', pg_temp.k('libur_kosong') ->> 'hasil', 'ditolak');

-- ===== Absen manual divisi (10 Apr tanpa tap sama sekali) =====
insert into h values ('absen_tanpa_divisi', pg_temp.w('perintah_pratinjau', '{"jenis": "absen_manual", "mulai": "2026-04-10", "alasan": "mesin mati"}'));
select uji.sama('9b: absen manual tanpa divisi ditolak', (pg_temp.k('absen_tanpa_divisi') ->> 'alasan') like '%wajib memilih satu divisi%', true);
insert into h values ('absen', pg_temp.simpan('{"jenis": "absen_manual", "mulai": "2026-04-10", "divisi": "tl", "alasan": "mesin mati"}'));
select pg_temp.kerja();
select uji.sama('9b (F08): absen manual divisi -> yang tidak tap hadir, asal manual',
  concat_ws('/', pg_temp.k('absen') ->> 'hasil', pg_temp.satu('K1', '0410')), 'disimpan/0410:hadir:manual:TL');
insert into h values ('absen_batal', pg_temp.batal((pg_temp.k('absen') #>> '{data,perintah_id}')::bigint));
select pg_temp.kerja();
select uji.sama('9b: batal absen manual -> kembali seperti semula', pg_temp.harian('K1') = (select k1 from awal), true);

-- ===== Berhenti dan aktif kembali (K3) =====
insert into h values ('henti_pra', pg_temp.w('perintah_pratinjau', '{"jenis": "berhenti", "id_karyawan": "k3", "mulai": "2026-04-08", "alasan": "mengundurkan diri"}'));
select uji.sama('9b (C5/C6): pratinjau berhenti memperingatkan tap sesudah tanggal itu dan masa pajak terakhir',
  concat_ws('/', pg_temp.k('henti_pra') #>> '{data,nama}', (pg_temp.k('henti_pra') #>> '{data,catatan,0}' like 'PERHATIAN: ada 8 tap sesudah 8 Apr 2026 (terakhir 14 Apr 2026)%')::text,
            (pg_temp.k('henti_pra') #>> '{data,catatan,1}' like 'Periode no. % menjadi masa pajak terakhir%')::text), 'Uji Tiga/true/true');
insert into h values ('henti', pg_temp.w('perintah_simpan', jsonb_build_object('nomor', pg_temp.k('henti_pra') #>> '{data,draf_id}')));
select pg_temp.kerja();
select uji.sama('9b (2a): berhenti 8 Apr = hari kerja terakhir: 8 Apr tetap ada, sesudahnya tidak dihitung',
  pg_temp.harian('K3'), '0407:hadir:mesin:TL,0408:hadir:mesin:TL');
insert into h values ('henti2', pg_temp.w('perintah_pratinjau', '{"jenis": "berhenti", "id_karyawan": "K3", "mulai": "2026-04-12", "alasan": "x"}'));
select uji.sama('9b: orang yang sudah berhenti tidak bisa diberhentikan lagi', (pg_temp.k('henti2') ->> 'alasan') like '%tidak aktif%', true);
insert into h values ('aktif_awal', pg_temp.w('perintah_pratinjau', '{"jenis": "aktif_kembali", "id_karyawan": "K3", "mulai": "2026-04-08", "alasan": "x"}'));
select uji.sama('9b: aktif kembali harus sesudah hari kerja terakhir', (pg_temp.k('aktif_awal') ->> 'alasan') like 'Tanggal mulai lagi harus sesudah%', true);
insert into h values ('aktif_k1', pg_temp.w('perintah_pratinjau', '{"jenis": "aktif_kembali", "id_karyawan": "K1", "mulai": "2026-04-12", "alasan": "x"}'));
select uji.sama('9b: aktif kembali untuk orang yang tidak berhenti ditolak', (pg_temp.k('aktif_k1') ->> 'alasan') like '%tidak sedang berhenti%', true);
insert into h values ('aktif', pg_temp.simpan('{"jenis": "aktif_kembali", "id_karyawan": "K3", "mulai": "2026-04-11", "alasan": "kembali bekerja"}'));
select pg_temp.kerja();
select uji.sama('9b: aktif kembali 11 Apr -> tap 11-14 Apr dihitung lagi',
  pg_temp.harian('K3'), '0407:hadir:mesin:TL,0408:hadir:mesin:TL,0411:hadir:mesin:TL,0412:libur:jadwal:TL,0413:hadir:mesin:TL,0414:hadir:mesin:TL');
insert into h values ('henti_batal_dulu', pg_temp.batal((pg_temp.k('henti') #>> '{data,perintah_id}')::bigint));
select uji.sama('9b (C10): berhenti tidak bisa dibatalkan selama ada perubahan lebih baru (aktif kembali)',
  (pg_temp.k('henti_batal_dulu') ->> 'alasan') like '%perubahan lain pada data K3%', true);
insert into h values ('aktif_batal', pg_temp.batal((pg_temp.k('aktif') #>> '{data,perintah_id}')::bigint));
insert into h values ('henti_batal', pg_temp.batal((pg_temp.k('henti') #>> '{data,perintah_id}')::bigint));
select pg_temp.kerja();
select uji.sama('9b: aktif kembali lalu berhenti dibatalkan berurutan -> data induk dan hasil harian K3 persis semula',
  concat_ws('/', pg_temp.k('aktif_batal') ->> 'hasil', pg_temp.k('henti_batal') ->> 'hasil',
            pg_temp.induk('K3') = (select i3 from awal), pg_temp.harian('K3') = (select k3 from awal)), 'dibatalkan/dibatalkan/t/t');
select uji.sama('9b (C2): penghapusan saat batal tercatat di jejak dengan nama akun web',
  (select count(*) from jejak.perubahan where tabel = 'induk.status_kerja' and aksi = 'DELETE' and oleh like 'web:%' and data_lama ->> 'id_karyawan' = 'K3'), 2::bigint);
-- Batas ke depan (C4).
insert into h select 'depan', pg_temp.w('perintah_pratinjau', jsonb_build_object('jenis', 'berhenti', 'id_karyawan', 'K1', 'mulai', fakta.web_hari_ini() + 30, 'alasan', 'x'));
insert into h select 'depan_jauh', pg_temp.w('perintah_pratinjau', jsonb_build_object('jenis', 'berhenti', 'id_karyawan', 'K1', 'mulai', fakta.web_hari_ini() + 63, 'alasan', 'x'));
select uji.sama('9b (C4): berhenti 30 hari ke depan tanpa periode boleh (tanpa hitung ulang); 63 hari ditolak',
  concat_ws('/', pg_temp.k('depan') ->> 'hasil', jsonb_array_length(pg_temp.k('depan') #> '{data,periode}'),
            (pg_temp.k('depan_jauh') ->> 'alasan') like '%lebih dari 62 hari%'), 'ok/0/t');
insert into h values ('henti_rilis', pg_temp.w('perintah_pratinjau', '{"jenis": "berhenti", "id_karyawan": "K1", "mulai": "2026-03-01", "alasan": "x"}'));
select uji.sama('9b (C3): berhenti di periode dirilis ditolak', (pg_temp.k('henti_rilis') ->> 'alasan') like '%sudah dirilis%', true);

-- ===== Mutasi =====
insert into h values ('mut_tanpa_mesin', pg_temp.w('perintah_pratinjau', '{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-13", "divisi": "TM", "alasan": "pindah"}'));
select uji.sama('9b (C7): mutasi ke divisi bermesin lain tanpa ID mesin ditolak',
  (pg_temp.k('mut_tanpa_mesin') ->> 'alasan') like 'Divisi Uji Kantor memakai mesin MA2%', true);
insert into h values ('mut_mesin_dipakai', pg_temp.w('perintah_pratinjau', '{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-13", "divisi": "TM", "id_mesin": "92", "alasan": "pindah"}'));
select uji.sama('9b (C7): ID mesin yang dipakai orang lain ditolak', (pg_temp.k('mut_mesin_dipakai') ->> 'alasan') like 'ID 92 di mesin MA2 sudah dipakai%', true);
insert into h values ('mut_sama', pg_temp.w('perintah_pratinjau', '{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-13", "divisi": "TL", "jabatan": "Operator", "alasan": "x"}'));
select uji.sama('9b: mutasi tanpa perubahan ditolak', (pg_temp.k('mut_sama') ->> 'alasan') like 'Tidak ada yang berubah%', true);
insert into h values ('mut_regu', pg_temp.w('perintah_pratinjau', '{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-13", "divisi": "TR", "alasan": "x"}'));
insert into h values ('mut_regu3', pg_temp.w('perintah_pratinjau', '{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-13", "divisi": "TR", "regu": 3, "alasan": "x"}'));
insert into h values ('mut_regu_mingguan', pg_temp.w('perintah_pratinjau', '{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-13", "divisi": "TM", "regu": 1, "id_mesin": "91", "alasan": "x"}'));
select uji.sama('9b (C8): regu wajib dan dalam batas untuk divisi rotasi; divisi mingguan tanpa regu',
  concat_ws('/', (pg_temp.k('mut_regu') ->> 'alasan') like 'Pilih regu%', (pg_temp.k('mut_regu3') ->> 'alasan') like 'Regu di divisi Uji Rotasi harus 1–2%',
            (pg_temp.k('mut_regu_mingguan') ->> 'alasan') like '%tidak memakai regu%'), 't/t/t');
insert into h values ('mut', pg_temp.simpan('{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-13", "divisi": "TM", "jabatan": "Staf", "id_mesin": "91", "alasan": "pindah ke kantor"}'));
select pg_temp.kerja();
select uji.sama('9b: mutasi K1 ke TM 13 Apr -> jadwal mengikuti divisi baru mulai 13 Apr',
  concat_ws('/', pg_temp.k('mut') ->> 'hasil', pg_temp.satu('K1', '0413'), pg_temp.satu('K1', '0414'), pg_temp.satu('K1', '0411')),
  'disimpan/0413:hadir:mesin:TM/0414:hadir:mesin:TM/0411:hadir:mesin:TL');
select uji.sama('9b (C9): riwayat baru menyalin semua isian uang, rekening, BPJS, dan tanda rahasia apa adanya',
  (select (to_jsonb(b) - array['id', 'berlaku_dari', 'berlaku_sampai', 'divisi', 'jabatan']) = (to_jsonb(a) - array['id', 'berlaku_dari', 'berlaku_sampai', 'divisi', 'jabatan'])
          and a.berlaku_sampai = '2026-04-13' and b.berlaku_dari = '2026-04-13' and b.divisi = 'TM' and b.jabatan = 'Staf'
   from induk.karyawan_riwayat a join induk.karyawan_riwayat b on b.id_karyawan = a.id_karyawan and b.id > a.id where a.id_karyawan = 'K1'), true);
select uji.sama('9b: ID mesin baru tercatat; ID lama tetap', (select string_agg(mesin || ':' || id_mesin || ':' || berlaku_dari, ',' order by id)
  from induk.pemetaan_id_mesin where id_karyawan = 'K1'), 'MA1:1:2025-01-01,MA2:91:2026-04-13');
insert into h values ('mut_sebelum', pg_temp.w('perintah_pratinjau', '{"jenis": "mutasi", "id_karyawan": "K1", "mulai": "2026-04-12", "jabatan": "Kepala", "alasan": "x"}'));
select uji.sama('9b: mutasi sebelum perubahan terakhir ditolak', (pg_temp.k('mut_sebelum') ->> 'alasan') like 'Sudah ada perubahan data K1%', true);
-- Perubahan dari luar web (mis. file data karyawan) sesudah mutasi -> pembatalan ditolak.
savepoint luar;
update induk.penugasan_regu set berlaku_sampai = '2026-04-20' where id_karyawan = 'K1' and berlaku_sampai is null;
-- Hasil diperiksa sebelum kembali ke savepoint (catatan LULUS/GAGAL sudah tercetak).
select uji.sama('9b (C10): perubahan dari luar web sesudah perintah -> pembatalan ditolak',
  (pg_temp.batal((pg_temp.k('mut') #>> '{data,perintah_id}')::bigint) ->> 'alasan') like '%perubahan lain pada data K1%', true);
rollback to savepoint luar;
insert into h values ('mut_batal', pg_temp.batal((pg_temp.k('mut') #>> '{data,perintah_id}')::bigint));
select pg_temp.kerja();
select uji.sama('9b: batal mutasi -> riwayat, regu, ID mesin, dan hasil harian K1 persis semula',
  concat_ws('/', pg_temp.k('mut_batal') ->> 'hasil', pg_temp.induk('K1') = (select i1 from awal), pg_temp.harian('K1') = (select k1 from awal)), 'dibatalkan/t/t');
-- Mutasi bertumpuk: A lalu B, B dibatalkan, A tetap bisa dibatalkan (perubahan B dan pembatalannya saling meniadakan).
insert into h values ('mut_a', pg_temp.simpan('{"jenis": "mutasi", "id_karyawan": "K5", "mulai": "2026-04-09", "jabatan": "Pengawas", "alasan": "naik jabatan"}'));
insert into h values ('mut_b', pg_temp.simpan('{"jenis": "mutasi", "id_karyawan": "K5", "mulai": "2026-04-13", "jabatan": "Kepala", "alasan": "naik lagi"}'));
select uji.sama('9b (C9): tanda rahasia ikut tersalin pada mutasi orang rahasia',
  (select string_agg(gaji_rahasia::text || ':' || coalesce(jabatan, '-'), ',' order by id) from induk.karyawan_riwayat where id_karyawan = 'K5'),
  'true:Operator,true:Pengawas,true:Kepala');
insert into h values ('mut_a_dulu', pg_temp.batal((pg_temp.k('mut_a') #>> '{data,perintah_id}')::bigint));
insert into h values ('mut_b_batal', pg_temp.batal((pg_temp.k('mut_b') #>> '{data,perintah_id}')::bigint));
insert into h values ('mut_a_batal', pg_temp.batal((pg_temp.k('mut_a') #>> '{data,perintah_id}')::bigint));
select pg_temp.kerja();
select uji.sama('9b: mutasi bertumpuk dibatalkan dari yang terbaru -> data K5 persis semula',
  concat_ws('/', pg_temp.k('mut_a_dulu') ->> 'hasil', pg_temp.k('mut_b_batal') ->> 'hasil', pg_temp.k('mut_a_batal') ->> 'hasil',
            pg_temp.induk('K5') = (select i5 from awal)), 'ditolak/dibatalkan/dibatalkan/t');

-- ===== Draf milik akun lain, kedaluwarsa, pembangun =====
insert into h values ('draf_lain', pg_temp.w('perintah_pratinjau', '{"jenis": "tambah_libur", "mulai": "2026-04-20", "alasan": "x"}'));
insert into h values ('draf_lain_simpan', pg_temp.w('perintah_simpan', jsonb_build_object('nomor', pg_temp.k('draf_lain') #>> '{data,draf_id}'), repeat('e', 64)));
update fakta.draf_perintah_web set kedaluwarsa = now() - interval '1 second' where id = (pg_temp.k('draf_lain') #>> '{data,draf_id}')::bigint;
insert into h values ('draf_lewat', pg_temp.w('perintah_simpan', jsonb_build_object('nomor', pg_temp.k('draf_lain') #>> '{data,draf_id}')));
select uji.sama('9b: draf hanya untuk akun pembuatnya dan hanya 15 menit',
  concat_ws('/', pg_temp.k('draf_lain_simpan') ->> 'hasil', pg_temp.k('draf_lewat') ->> 'hasil'), 'ditolak/ditolak');
insert into h values ('pembangun', pg_temp.simpan('{"jenis": "tambah_libur", "mulai": "2026-04-20", "alasan": "uji pembangun"}', repeat('f', 64)));
select uji.sama('9b: akun pembangun bisa membuat perintah web seperti HRD (keputusan tetap pemilik)', pg_temp.k('pembangun') ->> 'hasil', 'disimpan');

-- ===== Penjaga tetap berlaku di luar pembatalan web =====
select uji.harus_ditolak('9b: status kerja tetap tidak bisa dihapus langsung', $q$delete from induk.status_kerja where id_karyawan = 'K4'$q$);
select uji.harus_ditolak('9b: riwayat tetap tidak bisa dihapus langsung', $q$delete from induk.karyawan_riwayat where id_karyawan = 'K6' and berlaku_sampai is null$q$);
select uji.harus_ditolak('9b: riwayat tertutup tetap tidak bisa dibuka lagi', $q$update induk.karyawan_riwayat set berlaku_sampai = null where id_karyawan = 'K6' and berlaku_sampai is not null$q$);
select uji.harus_ditolak('9b: menyalakan pengecualian tanpa pembatalan yang tercatat tetap ditolak',
  format($q$select set_config('app.batal_perintah_web', '%s', true); delete from induk.pemetaan_id_mesin where id_karyawan = 'K1'$q$,
         (pg_temp.k('mut') #>> '{data,perintah_id}')));
select uji.harus_ditolak('9b: pengecualian tidak berlaku untuk baris yang bukan milik perintah itu',
  format($q$insert into fakta.perintah_hrd (asal, jenis, membatalkan) values ('web', 'batalkan_perintah', %s);
            select set_config('app.batal_perintah_web', '%s', true); delete from induk.status_kerja where id_karyawan = 'K4'$q$,
         (pg_temp.k('henti') #>> '{data,perintah_id}'), (pg_temp.k('henti') #>> '{data,perintah_id}')));
select uji.harus_ditolak('9b: tabel fakta lain tetap hanya bertambah', $q$delete from fakta.perintah_hrd where asal = 'web'$q$);
select uji.harus_ditolak('9b: catatan perubahan perintah web hanya bertambah', $q$delete from fakta.perintah_web_ubah$q$);
select uji.harus_ditolak('9b: daftar perintah web hanya bertambah', $q$update fakta.perintah_web set ringkas = 'x'$q$);
select uji.harus_ditolak('9b: aturan bertanggal (schema aturan) tetap terjaga', $q$delete from aturan.toleransi$q$);
-- Lewat peran pintu (seperti Edge Function).
grant all on h to pintu;
set local role pintu;
insert into h values ('pintu_pra', api.web_hrd(jsonb_build_object('sidik_sesi', repeat('c', 64), 'aksi', 'perintah_pratinjau',
  'perintah', jsonb_build_object('jenis', 'tambah_libur', 'mulai', '2026-04-21', 'alasan', 'x'))));
reset role;
select uji.sama('9b: pratinjau lewat peran pintu', (select isi ->> 'hasil' from h where nama = 'pintu_pra'), 'ok');
rollback;
