-- Uji paket 8e (docs/rencana-8e.md): keberatan karyawan lewat bot.
begin;
set local app.pengguna = 'uji-otomatis';
insert into induk.karyawan (id, nama) values ('E8A', 'Uji Keberatan'), ('E8B', 'Uji Lain');
insert into induk.pengguna (telegram_id, peran) values (9801, 'hrd'), (9811, 'pembangun'), (9803, 'bos');
insert into induk.pengguna (telegram_id, peran, id_karyawan) values (9802, 'karyawan', 'E8A'), (9804, 'karyawan', 'E8B');
-- Periode berjalan (batas belum lewat) dan periode lama (lewat 14 hari sesudah tanggal bayar), relatif terhadap hari ini WIB.
create temp table t as select (now() at time zone 'Asia/Jakarta')::date as hari;
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar)
select hari - 20, hari + 10, hari + 15 from t union all select hari - 90, hari - 60, hari - 55 from t;
create temp table h (nama text primary key, isi jsonb);
grant all on h, t to pintu;
create function pg_temp.k(x text) returns jsonb language sql as $$ select isi from h where nama = x $$;
create function pg_temp.tgl(n integer) returns text language sql as $$ select (hari + n)::text from t $$;
grant execute on function pg_temp.k(text), pg_temp.tgl(integer) to pintu;
do $$
declare
  v_baru bigint := (select id from fakta.periode where tanggal_awal = (select hari - 20 from t));
  v_lama bigint := (select id from fakta.periode where tanggal_awal = (select hari - 90 from t));
  v1 bigint;
  v2 bigint;
  v_hari date := (select hari from t);
begin
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (v_baru, 'baca_tap', 1, 'uji-8e', 'a', 'a') returning id into v1;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (v_baru, 'baca_tap', 2, 'uji-8e', 'b', 'b') returning id into v2;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (v_lama, 'baca_tap', 1, 'uji-8e', 'c', 'c');
  -- Versi 1 (lama) dan versi 2 (terakhir) berbeda: bukti harus dari versi terakhir.
  insert into hitung.hasil_harian (versi_id, id_karyawan, tanggal, divisi, regu, kode_jadwal, jenis_hari, jadwal_masuk, jadwal_pulang,
                                   status, asal, masuk, pulang, menit_telat)
  values (v1, 'E8A', v_hari - 5, 'TL', 0, 'P', 'kerja', null, null, 'hadir', 'mesin', null, null, 0),
         (v2, 'E8A', v_hari - 5, 'TL', 0, 'P', 'kerja', (v_hari - 5) + time '07:00', (v_hari - 5) + time '15:00',
          'alpha', 'mesin', null, null, 0),
         (v2, 'E8A', v_hari - 4, 'TL', 0, 'P', 'kerja', null, null, 'hadir', 'mesin', (v_hari - 4) + time '07:10', (v_hari - 4) + time '15:00', 10);
  insert into hitung.tap_bersih (versi_id, tap_id, id_karyawan, waktu_baku, tanggal_kerja, peran)
  values (v2, 1, 'E8A', (v_hari - 5) + time '06:58', v_hari - 5, 'tunggal'),
         (v2, 2, 'E8A', (v_hari - 5) + time '06:59', v_hari - 5, 'dobel'),
         (v1, 3, 'E8A', (v_hari - 5) + time '07:00', v_hari - 5, 'masuk');
end $$;

set local role pintu;
insert into h values ('bukan_karyawan', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9801, 'tanggal', pg_temp.tgl(-5), 'alasan', 'x')));
insert into h values ('alasan_kosong', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-5), 'alasan', '  ')));
insert into h values ('alasan_panjang', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-5), 'alasan', repeat('a', 301))));
insert into h values ('depan', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(1), 'alasan', 'x')));
insert into h values ('tanpa_periode', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-200), 'alasan', 'x')));
insert into h values ('lewat', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-70), 'alasan', 'x')));
insert into h values ('siap', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-5), 'alasan', ' saya masuk ')));
insert into h values ('kirim_orang_lain', api.pintu_keberatan_kirim(jsonb_build_object('telegram_id', 9804, 'draf_id', (pg_temp.k('siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('kirim', api.pintu_keberatan_kirim(jsonb_build_object('telegram_id', 9802, 'draf_id', (pg_temp.k('siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('kirim_lagi', api.pintu_keberatan_kirim(jsonb_build_object('telegram_id', 9802, 'draf_id', (pg_temp.k('siap') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('dobel', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-5), 'alasan', 'lagi')));
insert into h values ('siap_batal', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-4), 'alasan', 'telat salah')));
insert into h values ('batal', api.pintu_keberatan_kirim(jsonb_build_object('telegram_id', 9802, 'draf_id', (pg_temp.k('siap_batal') ->> 'draf_id')::bigint, 'ya', false)));
insert into h values ('putus_karyawan', api.pintu_keberatan_putuskan(jsonb_build_object('telegram_id', 9802, 'keberatan_id', (pg_temp.k('kirim') ->> 'keberatan_id')::bigint, 'terima', true)));
insert into h values ('putus_bos', api.pintu_keberatan_putuskan(jsonb_build_object('telegram_id', 9803, 'keberatan_id', (pg_temp.k('kirim') ->> 'keberatan_id')::bigint, 'terima', true)));
insert into h values ('daftar_hrd', api.pintu_keberatan_daftar(jsonb_build_object('telegram_id', 9801)));
insert into h values ('tolak_tanpa_alasan', api.pintu_keberatan_putuskan(jsonb_build_object('telegram_id', 9801, 'keberatan_id', (pg_temp.k('kirim') ->> 'keberatan_id')::bigint, 'terima', false, 'catatan', ' ')));
insert into h values ('tolak', api.pintu_keberatan_putuskan(jsonb_build_object('telegram_id', 9801, 'keberatan_id', (pg_temp.k('kirim') ->> 'keberatan_id')::bigint, 'terima', false, 'catatan', 'tap tidak ada di mesin')));
insert into h values ('putus_lagi', api.pintu_keberatan_putuskan(jsonb_build_object('telegram_id', 9811, 'keberatan_id', (pg_temp.k('kirim') ->> 'keberatan_id')::bigint, 'terima', true)));
insert into h values ('daftar_karyawan', api.pintu_keberatan_daftar(jsonb_build_object('telegram_id', 9802)));
insert into h values ('daftar_bos', api.pintu_keberatan_daftar(jsonb_build_object('telegram_id', 9803)));
-- Sesudah ditolak, tanggal yang sama boleh diajukan lagi; lalu diterima pembangun tanpa catatan.
insert into h values ('siap2', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-5), 'alasan', 'ini buktinya')));
insert into h values ('kirim2', api.pintu_keberatan_kirim(jsonb_build_object('telegram_id', 9802, 'draf_id', (pg_temp.k('siap2') ->> 'draf_id')::bigint, 'ya', true)));
insert into h values ('terima', api.pintu_keberatan_putuskan(jsonb_build_object('telegram_id', 9811, 'keberatan_id', (pg_temp.k('kirim2') ->> 'keberatan_id')::bigint, 'terima', true)));
-- Batas 5 keberatan per orang per hari (sudah 2 hari ini).
insert into h select 'banyak' || i, api.pintu_keberatan_kirim(jsonb_build_object('telegram_id', 9802, 'ya', true,
  'draf_id', (api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-10 - i), 'alasan', 'uji ' || i)) ->> 'draf_id')::bigint))
from generate_series(1, 3) i;
insert into h values ('banyak4', api.pintu_keberatan_siapkan(jsonb_build_object('telegram_id', 9802, 'tanggal', pg_temp.tgl(-15), 'alasan', 'uji 4')));
reset role;

select uji.sama('8e: hanya akun karyawan yang bisa mengajukan', pg_temp.k('bukan_karyawan') ->> 'hasil', 'bukan_karyawan');
select uji.sama('8e: alasan kosong / lebih dari 300 huruf ditolak',
  concat_ws('/', pg_temp.k('alasan_kosong') ->> 'hasil', pg_temp.k('alasan_panjang') ->> 'hasil'), 'alasan_kosong/alasan_panjang');
select uji.sama('8e: tanggal depan, tanpa periode, lewat 14 hari sesudah bayar ditolak',
  concat_ws('/', pg_temp.k('depan') ->> 'hasil', pg_temp.k('tanpa_periode') ->> 'hasil', pg_temp.k('lewat') ->> 'hasil',
            (pg_temp.k('lewat') ->> 'batas' = (select (hari - 55 + 14)::text from t))::text),
  'tanggal_depan/tanpa_periode/lewat_batas/true');
select uji.sama('8e: siap -> bukti dari baca tap TERAKHIR (status, jadwal, tap dan perannya)',
  concat_ws('/', pg_temp.k('siap') ->> 'hasil', pg_temp.k('siap') ->> 'alasan', pg_temp.k('siap') #>> '{bukti,hari,status}',
            jsonb_array_length(pg_temp.k('siap') #> '{bukti,tap}'), pg_temp.k('siap') #>> '{bukti,tap,1,peran}',
            pg_temp.k('siap') #>> '{bukti,hari,kode_jadwal}'),
  'siap/saya masuk/alpha/2/dobel/P');
select uji.sama('8e: bukti tanpa angka rupiah', (pg_temp.k('siap') -> 'bukti')::text ~* 'gaji|rp|upah|bersih', false);
select uji.sama('8e: draf orang lain tidak bisa dikirim', pg_temp.k('kirim_orang_lain') ->> 'hasil', 'tidak_ada');
select uji.sama('8e: kirim -> tercatat, penerima = HRD dan pembangun (bukan bos)',
  concat_ws('/', pg_temp.k('kirim') ->> 'hasil', pg_temp.k('kirim') ->> 'nama',
            (select string_agg(x, ',' order by x) from jsonb_array_elements_text(pg_temp.k('kirim') -> 'penerima') x where x in ('9801', '9803', '9811'))),
  'dikirim/Uji Keberatan/9801,9811');
select uji.sama('8e: draf yang sudah dikirim tidak bisa dikirim lagi', pg_temp.k('kirim_lagi') ->> 'hasil', 'tidak_ada');
select uji.sama('8e: tanggal yang masih terbuka tidak bisa diajukan lagi',
  concat_ws('/', pg_temp.k('dobel') ->> 'hasil', (pg_temp.k('dobel') ->> 'keberatan_id' = pg_temp.k('kirim') ->> 'keberatan_id')::text), 'sudah_ada/true');
select uji.sama('8e: Batal -> tidak tercatat', concat_ws('/', pg_temp.k('batal') ->> 'hasil',
  (select count(*) from fakta.keberatan where id_karyawan = 'E8A' and alasan = 'telat salah')), 'dibatalkan/0');
select uji.sama('8e: karyawan dan bos tidak bisa memutuskan',
  concat_ws('/', pg_temp.k('putus_karyawan') ->> 'hasil', pg_temp.k('putus_bos') ->> 'hasil'), 'bukan_hrd/bukan_hrd');
select uji.sama('8e: HRD melihat keberatan terbuka', concat_ws('/', pg_temp.k('daftar_hrd') ->> 'hasil',
  (select count(*) from jsonb_array_elements(pg_temp.k('daftar_hrd') -> 'daftar') x where x ->> 'id_karyawan' = 'E8A')), 'hrd/1');
select uji.sama('8e: tolak wajib beralasan', pg_temp.k('tolak_tanpa_alasan') ->> 'hasil', 'alasan_wajib');
select uji.sama('8e: tolak -> karyawan dikabari, HRD lain (pembangun) ikut tahu',
  concat_ws('/', pg_temp.k('tolak') ->> 'hasil', pg_temp.k('tolak') ->> 'keputusan', pg_temp.k('tolak') ->> 'catatan',
            pg_temp.k('tolak') ->> 'karyawan_telegram',
            (select string_agg(x, ',') from jsonb_array_elements_text(pg_temp.k('tolak') -> 'penerima') x where x in ('9801', '9811')),
            pg_temp.k('tolak') ->> 'dirilis'),
  'diputuskan/ditolak/tap tidak ada di mesin/9802/9811/false');
select uji.sama('8e: keputusan kedua ditolak', concat_ws('/', pg_temp.k('putus_lagi') ->> 'hasil', pg_temp.k('putus_lagi') ->> 'keputusan'),
  'sudah_diputuskan/ditolak');
select uji.sama('8e: karyawan melihat keberatannya beserta keputusan',
  concat_ws('/', pg_temp.k('daftar_karyawan') ->> 'hasil', pg_temp.k('daftar_karyawan') #>> '{daftar,0,keputusan}',
            pg_temp.k('daftar_karyawan') #>> '{daftar,0,catatan}'), 'karyawan/ditolak/tap tidak ada di mesin');
select uji.sama('8e: bos tidak punya daftar keberatan', pg_temp.k('daftar_bos') ->> 'hasil', 'bukan_akun');
select uji.sama('8e: sesudah ditolak boleh diajukan lagi; diterima tanpa catatan',
  concat_ws('/', pg_temp.k('kirim2') ->> 'hasil', pg_temp.k('terima') ->> 'keputusan', coalesce(pg_temp.k('terima') ->> 'catatan', '-')),
  'dikirim/diterima/-');
select uji.sama('8e: batas 5 keberatan per orang per hari',
  (select string_agg(isi ->> 'hasil', ',' order by nama) from h where nama like 'banyak%'), 'dikirim,dikirim,dikirim,terlalu_banyak');
select uji.sama('8e: gaji dan hasil hitung tidak disentuh (keberatan hanya catatan)',
  (select count(*) from hitung.versi_hitung where versi_kode = 'uji-8e'), 3::bigint);
select uji.harus_ditolak('8e: keberatan hanya bertambah', 'delete from fakta.keberatan');
select uji.harus_ditolak('8e: keputusan hanya bertambah', 'update fakta.keputusan_keberatan set hasil = ''diterima''');
select uji.harus_ditolak('8e: pintu tidak bisa membaca keberatan langsung', 'select count(*) from fakta.keberatan', 'pintu');
select uji.sama('8e: anon dan authenticated tidak bisa memanggil fungsi baru',
  (select count(*) from pg_roles r cross join (values ('api.pintu_keberatan_siapkan(jsonb)'), ('api.pintu_keberatan_kirim(jsonb)'),
     ('api.pintu_keberatan_putuskan(jsonb)'), ('api.pintu_keberatan_daftar(jsonb)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);
rollback;
