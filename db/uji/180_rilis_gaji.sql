-- Uji paket 8b (docs/rencana-8b.md): status periode sesudah hitung, ajukan, persetujuan bos, rilis dengan PIN,
-- periode dirilis tidak dihitung ulang, daftar sebelum tanggal mulai. PRD v2 celah K5.
-- Fungsi api dipanggil sebagai peran pintu. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.divisi (kode, nama, pola) values ('ZR8', 'Uji Rilis', 'mingguan');
insert into induk.karyawan (id, nama) values ('R8A', 'Uji A'), ('R8B', 'Uji B Rahasia'), ('R8C', 'Uji C Tunai'),
  ('R8D', 'Uji Mulai Nanti'), ('R8E', 'Uji Berhenti');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar, gaji_rahasia) values
  ('R8A', '2030-01-01', 'ZR8', 1, 'TK/0', 'transfer', false), ('R8B', '2030-01-01', 'ZR8', 1, 'TK/0', 'transfer', true),
  ('R8C', '2030-01-01', 'ZR8', 1, 'TK/0', 'tunai', false), ('R8D', '2030-01-01', 'ZR8', 1, 'TK/0', 'tunai', false),
  ('R8E', '2030-01-01', 'ZR8', 1, 'TK/0', 'tunai', false);
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values
  ('R8A', 'mulai', '2020-01-01'), ('R8B', 'mulai', '2020-01-01'), ('R8C', 'mulai', '2020-01-01'),
  ('R8D', 'mulai', current_date + 20), ('R8E', 'mulai', '2020-01-01'), ('R8E', 'berhenti', current_date - 1);
insert into induk.pengguna (telegram_id, peran) values (8801, 'hrd'), (8802, 'karyawan'), (8803, 'bos'), (8804, 'hrd');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2032-01-21', '2032-02-20', '2032-02-25'), ('2032-02-21', '2032-03-20', '2032-03-25'), ('2032-03-21', '2032-04-20', '2032-04-25');

create temp table p as select row_number() over (order by tanggal_awal) as n, id from fakta.periode where tanggal_awal >= '2032-01-01';
create temp table h (nama text primary key, isi jsonb);
grant all on h, p to pintu;
create function pg_temp.pid(x integer) returns bigint language sql as $$ select id from p where n = x $$;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
create function pg_temp.status(x integer) returns text language sql as $$ select status from fakta.periode where id = (select id from p where n = x) $$;
create temp table vb (n integer primary key, versi bigint);
grant all on vb to pintu;
-- Versi gaji berlaku disiapkan sebagai pemilik (pintu tidak boleh memanggil fungsi fakta).
create function pg_temp.segarkan() returns void language sql as $$
  delete from vb; insert into vb select n, fakta.versi_gaji_berlaku(id) from p $$;
create function pg_temp.vb(x integer) returns bigint language sql as $$ select versi from vb where n = x $$;
grant execute on function pg_temp.pid(integer), pg_temp.k(text), pg_temp.status(integer), pg_temp.vb(integer) to pintu;
-- Satu "hitung": versi baca tap + versi hitung gaji dari baca tap itu, ringkasan A 1.000, B 2.000 (rahasia), C 3.000.
create function pg_temp.hitung(x integer, p_tertahan boolean default false) returns bigint language plpgsql as $$
declare
  v_baca bigint;
  v_gaji bigint;
  v_n integer := coalesce((select max(nomor) from hitung.versi_hitung where periode_id = pg_temp.pid(x)), 0) + 1;
begin
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
  values (pg_temp.pid(x), 'baca_tap', v_n, 'uji-8b', 'b' || v_n, 'b' || v_n) returning id into v_baca;
  insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil, versi_sumber)
  values (pg_temp.pid(x), 'hitung_gaji', v_n, 'uji-8b', 'g' || v_n, 'g' || v_n, v_baca) returning id into v_gaji;
  insert into hitung.ringkasan_gaji (versi_id, id_karyawan, bruto_pajak, total_pendapatan, total_potongan, gaji_bersih, dibayar, peringatan)
  select v_gaji, i, b, b, 0, b, b, case when p_tertahan and i = 'R8A' then array['pph_masa_terakhir_tertahan'] else '{}'::text[] end
  from (values ('R8A', 1000), ('R8B', 2000), ('R8C', 3000)) x(i, b);
  return v_gaji;
end $$;

select pg_temp.hitung(1); select pg_temp.hitung(2, true); select pg_temp.hitung(3);
select uji.sama('8b: sesudah hitung gaji, periode terbuka -> dihitung oleh sistem',
  (select string_agg(status_lama || '>' || status_baru || '/' || oleh, ',') from fakta.riwayat_status_periode where periode_id = pg_temp.pid(1)),
  'terbuka>dihitung/sistem');
select uji.sama('8b (K5): ringkasan tanpa orang rahasia, dengan transfer dan tunai',
  hitung.ringkasan_rilis(fakta.versi_gaji_berlaku(pg_temp.pid(1))),
  '{"orang": 2, "bersih": 4000, "rahasia": 1, "transfer": 1000, "tunai": 3000}'::jsonb);
select uji.sama('8b: ringkasan rilis = ringkasan bot (G1-3) untuk orang, bersih, rahasia',
  hitung.ringkasan_rilis(fakta.versi_gaji_berlaku(pg_temp.pid(1))) - 'transfer' - 'tunai',
  hitung.ringkasan_terlihat(fakta.versi_gaji_berlaku(pg_temp.pid(1))));

select pg_temp.segarkan();
set local role pintu;
insert into h values ('daftar_ajukan', api.pintu_daftar_periode('{"telegram_id": 8801, "untuk": "ajukan"}'));
insert into h values ('ajukan_karyawan', api.pintu_ajukan(jsonb_build_object('telegram_id', 8802, 'periode_id', pg_temp.pid(1), 'versi_gaji', 0)));
insert into h values ('ajukan_bos', api.pintu_ajukan(jsonb_build_object('telegram_id', 8803, 'periode_id', pg_temp.pid(1), 'versi_gaji', 0)));
insert into h values ('ajukan_tertahan', api.pintu_ajukan(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(2),
  'versi_gaji', (select fakta_v from (select null::bigint as fakta_v) z))));
insert into h values ('ajukan_versi_salah', api.pintu_ajukan(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'versi_gaji', -1)));
reset role;
-- Paket 8b-3 (urutan rilis): periode 3 menunggu periode 2, jadi hanya periode 1 yang muncul.
select uji.sama('8b: daftar /ajukan hanya periode dihitung yang bisa diajukan (periode tertahan tidak muncul)',
  (select jsonb_agg(x -> 'periode_id') from jsonb_array_elements(pg_temp.k('daftar_ajukan') -> 'periode') x),
  jsonb_build_array(pg_temp.pid(1)));
select uji.sama('8b: akun karyawan dan bos tidak bisa mengajukan',
  pg_temp.k('ajukan_karyawan') ->> 'hasil' || '/' || (pg_temp.k('ajukan_bos') ->> 'hasil'), 'bukan_hrd/bukan_hrd');
select uji.sama('8b: periode dengan orang tertahan tidak bisa diajukan', pg_temp.k('ajukan_tertahan') ->> 'hasil', 'tidak_bisa');
select uji.sama('8b: versi yang tidak sama dengan versi berlaku ditolak', pg_temp.k('ajukan_versi_salah') ->> 'hasil', 'versi_berubah');

-- Ajukan periode 1 (pengaturan bawaan: HRD saja)
select pg_temp.segarkan();
set local role pintu;
insert into h values ('ajukan_1', api.pintu_ajukan(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1),
  'versi_gaji', (pg_temp.k('daftar_ajukan') -> 'periode' -> 0 ->> 'versi_gaji')::bigint)));
insert into h values ('rilis_tanpa_pin', api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'pin', '482913')));
-- PIN
insert into h values ('pin_lemah1', api.pintu_atur_pin('{"telegram_id": 8801, "pin_baru": "123456"}'));
insert into h values ('pin_lemah2', api.pintu_atur_pin('{"telegram_id": 8801, "pin_baru": "777777"}'));
insert into h values ('pin_lemah3', api.pintu_atur_pin('{"telegram_id": 8801, "pin_baru": "98765"}'));
insert into h values ('pin_lemah4', api.pintu_atur_pin('{"telegram_id": 8801, "pin_baru": "654321"}'));
insert into h values ('pin_karyawan', api.pintu_atur_pin('{"telegram_id": 8802, "pin_baru": "482913"}'));
insert into h values ('pin_buat', api.pintu_atur_pin('{"telegram_id": 8801, "pin_baru": "482913"}'));
insert into h values ('pin_tanpa_lama', api.pintu_atur_pin('{"telegram_id": 8801, "pin_baru": "905172"}'));
insert into h values ('pin_lama_salah', api.pintu_atur_pin('{"telegram_id": 8801, "pin_lama": "000001", "pin_baru": "905172"}'));
insert into h values ('pin_ganti', api.pintu_atur_pin('{"telegram_id": 8801, "pin_lama": "482913", "pin_baru": "905172"}'));
reset role;
select uji.sama('8b: diajukan; status diajukan oleh hrd; versi tercatat',
  pg_temp.k('ajukan_1') ->> 'hasil' || '/' || pg_temp.status(1) || '/' ||
  ((select versi_gaji from fakta.pengajuan_rilis where periode_id = pg_temp.pid(1)) = fakta.versi_gaji_berlaku(pg_temp.pid(1)))::text,
  'diajukan/diajukan/true');
select uji.sama('8b: pengaturan bawaan tidak perlu bos', (pg_temp.k('ajukan_1') ->> 'perlu_bos')::boolean, false);
select uji.sama('8b: rilis tanpa PIN terpasang ditolak', pg_temp.k('rilis_tanpa_pin') ->> 'hasil', 'belum_ada_pin');
select uji.sama('8b: PIN lemah ditolak (berurutan naik/turun, sama semua, bukan 6 angka)',
  (select string_agg(isi ->> 'hasil', ',' order by nama) from h where nama like 'pin_lemah%'), 'lemah,lemah,lemah,lemah');
select uji.sama('8b: akun karyawan tidak bisa membuat PIN', pg_temp.k('pin_karyawan') ->> 'hasil', 'bukan_hrd');
select uji.sama('8b: PIN dibuat; ganti PIN butuh PIN lama yang benar',
  concat_ws('/', pg_temp.k('pin_buat') ->> 'hasil', pg_temp.k('pin_tanpa_lama') ->> 'hasil', pg_temp.k('pin_lama_salah') ->> 'hasil',
            pg_temp.k('pin_ganti') ->> 'hasil'), 'dibuat/perlu_pin_lama/salah/diganti');
select uji.sama('8b: PIN disimpan bcrypt, bukan angkanya',
  (select pin_tersamar like '$2a$10$%' and position('905172' in pin_tersamar) = 0 from induk.pengguna where telegram_id = 8801), true);
select uji.sama('8b: PIN tidak tersimpan di jejak perubahan',
  (select count(*) from jejak.perubahan where tabel = 'induk.pengguna'
     and (position('905172' in data_baru::text) > 0 or position('482913' in data_baru::text) > 0)), 0::bigint);

-- Dihitung ulang sesudah diajukan -> pengajuan batal; baca tap baru tanpa hitung gaji -> versi berubah
select pg_temp.hitung(1);
select uji.sama('8b: hitung ulang sesudah diajukan -> kembali dihitung (pengajuan batal)',
  (select status_baru || '/' || oleh || '/' || alasan from fakta.riwayat_status_periode where periode_id = pg_temp.pid(1) order by id desc limit 1),
  'dihitung/sistem/dihitung ulang; pengajuan batal');
select pg_temp.segarkan();
set local role pintu;
insert into h values ('rilis_sesudah_batal', api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'pin', '905172')));
insert into h values ('ajukan_1b', api.pintu_ajukan(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1),
  'versi_gaji', pg_temp.vb(1))));
reset role;
select uji.sama('8b: rilis periode yang pengajuannya batal ditolak', pg_temp.k('rilis_sesudah_batal') ->> 'hasil', 'tidak_bisa');
select uji.sama('8b: diajukan lagi dengan versi baru', pg_temp.k('ajukan_1b') ->> 'hasil', 'diajukan');
insert into hitung.versi_hitung (periode_id, jenis, nomor, versi_kode, sidik_masukan, sidik_hasil)
values (pg_temp.pid(1), 'baca_tap', 99, 'uji-8b', 'b99', 'b99');
select pg_temp.segarkan();
set local role pintu;
insert into h values ('rilis_baca_baru', api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'pin', '905172')));
reset role;
select uji.sama('8b: baca tap baru sesudah diajukan (gaji belum dihitung ulang) -> rilis ditolak', pg_temp.k('rilis_baca_baru') ->> 'hasil', 'versi_berubah');
select pg_temp.hitung(1);
select pg_temp.segarkan();
set local role pintu;
insert into h values ('ajukan_1c', api.pintu_ajukan(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1),
  'versi_gaji', pg_temp.vb(1))));
-- Batas 5 PIN salah per jam (salah 1 kali di pin_lama_salah, ditambah 4 di sini = 5)
insert into h select 'pin_salah' || i, api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'pin', '111112'))
from generate_series(1, 4) i;
insert into h values ('rilis_terkunci', api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'pin', '905172')));
reset role;
select uji.sama('8b: PIN salah ditolak', (select string_agg(isi ->> 'hasil', ',') from h where nama like 'pin_salah%'),
  'pin_salah,pin_salah,pin_salah,pin_salah');
select uji.sama('8b: 5 PIN salah dalam 1 jam -> terkunci, PIN benar pun ditolak; periode tetap diajukan',
  pg_temp.k('rilis_terkunci') ->> 'hasil' || '/' || pg_temp.status(1), 'terkunci/diajukan');
update fakta.percobaan_pin set waktu = waktu - interval '61 minutes';
select pg_temp.segarkan();
set local role pintu;
insert into h values ('rilis_1', api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'pin', '905172')));
insert into h values ('rilis_1_lagi', api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(1), 'pin', '905172')));
reset role;
select uji.sama('8b (K5): PIN benar -> dirilis; tercatat siapa dan versi mana',
  pg_temp.k('rilis_1') ->> 'hasil' || '/' || pg_temp.status(1) || '/' ||
  ((select versi_gaji from fakta.rilis_gaji where periode_id = pg_temp.pid(1)) = fakta.versi_gaji_berlaku(pg_temp.pid(1)))::text,
  'dirilis/dirilis/true');
select uji.sama('8b: ringkasan sesudah rilis tanpa orang rahasia', pg_temp.k('rilis_1') ->> 'bersih', '4000');
select uji.sama('8b: rilis dua kali ditolak', pg_temp.k('rilis_1_lagi') ->> 'hasil', 'tidak_bisa');
select uji.harus_ditolak('8b: periode dirilis tidak bisa dihitung ulang (versi baru ditolak)', 'select pg_temp.hitung(1)');
select uji.harus_ditolak('8b: rilis gaji hanya bertambah', $$update fakta.rilis_gaji set versi_gaji = versi_gaji$$);
select uji.harus_ditolak('8b: status dirilis tidak bisa dikembalikan ke dihitung',
  $$select fakta.ubah_status_periode(pg_temp.pid(1), 'dihitung', 'hrd', 'uji')$$);

-- Antrean: file baru menyentuh periode dirilis -> dilewati, kejadian segera
insert into fakta.antrean_kerja (periode_id) values (pg_temp.pid(1));
select pg_temp.segarkan();
set local role pintu;
insert into h values ('kerjakan_dirilis', api.pintu_kerjakan());
reset role;
select uji.sama('8b: antrean periode dirilis dilewati, tanpa hitung ulang',
  pg_temp.k('kerjakan_dirilis') -> 'hasil', '{"dilewati": "dirilis"}'::jsonb);
select uji.sama('8b: kejadian segera "periode dirilis kena file" tercatat',
  (select count(*) from fakta.kejadian_segera() k where k.jenis = 'periode_dirilis_kena_file'
     and (k.isi ->> 'periode_id')::bigint = pg_temp.pid(1)), 1::bigint);
select uji.sama('8b: halaman unggah menampilkan hasil "dilewati" apa adanya',
  fakta.hasil_antrean_tampil('{"dilewati": "dirilis"}'::jsonb), '{"dilewati": "dirilis"}'::jsonb);

-- Paket 8b-3 (urutan rilis): periode 2 dihitung ulang tanpa orang tertahan dan dirilis sebelum periode 3.
select pg_temp.hitung(2);
select pg_temp.segarkan();
set local role pintu;
insert into h values ('ajukan_2', api.pintu_ajukan(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(2),
  'versi_gaji', pg_temp.vb(2))));
insert into h values ('rilis_2', api.pintu_rilis(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(2), 'pin', '905172')));
reset role;
select uji.sama('8b-3: periode 2 dirilis sebelum periode 3', pg_temp.k('rilis_2') ->> 'hasil' || '/' || pg_temp.status(2), 'dirilis/dirilis');

-- HRD lalu bos (pengaturan persetujuan_rilis)
insert into aturan.pengaturan (kunci, nilai, berlaku_dari) values ('persetujuan_rilis', 'hrd_lalu_bos', current_date);
select pg_temp.segarkan();
set local role pintu;
insert into h values ('ajukan_3', api.pintu_ajukan(jsonb_build_object('telegram_id', 8804, 'periode_id', pg_temp.pid(3),
  'versi_gaji', pg_temp.vb(3))));
insert into h values ('pin_8804', api.pintu_atur_pin('{"telegram_id": 8804, "pin_baru": "730418"}'));
insert into h values ('rilis_3_belum', api.pintu_rilis(jsonb_build_object('telegram_id', 8804, 'periode_id', pg_temp.pid(3), 'pin', '730418')));
insert into h values ('setuju_hrd', api.pintu_setujui(jsonb_build_object('telegram_id', 8801, 'periode_id', pg_temp.pid(3),
  'pengajuan_id', (pg_temp.k('ajukan_3') ->> 'pengajuan_id')::bigint, 'setuju', true)));
insert into h values ('setuju_salah_id', api.pintu_setujui(jsonb_build_object('telegram_id', 8803, 'periode_id', pg_temp.pid(3),
  'pengajuan_id', -1, 'setuju', true)));
insert into h values ('tolak_bos', api.pintu_setujui(jsonb_build_object('telegram_id', 8803, 'periode_id', pg_temp.pid(3),
  'pengajuan_id', (pg_temp.k('ajukan_3') ->> 'pengajuan_id')::bigint, 'setuju', false)));
insert into h values ('ajukan_3b', api.pintu_ajukan(jsonb_build_object('telegram_id', 8804, 'periode_id', pg_temp.pid(3),
  'versi_gaji', pg_temp.vb(3))));
insert into h values ('setuju_lama', api.pintu_setujui(jsonb_build_object('telegram_id', 8803, 'periode_id', pg_temp.pid(3),
  'pengajuan_id', (pg_temp.k('ajukan_3') ->> 'pengajuan_id')::bigint, 'setuju', true)));
insert into h values ('setuju_bos', api.pintu_setujui(jsonb_build_object('telegram_id', 8803, 'periode_id', pg_temp.pid(3),
  'pengajuan_id', (pg_temp.k('ajukan_3b') ->> 'pengajuan_id')::bigint, 'setuju', true)));
insert into h values ('rilis_3', api.pintu_rilis(jsonb_build_object('telegram_id', 8804, 'periode_id', pg_temp.pid(3), 'pin', '730418')));
reset role;
select uji.sama('8b: HRD lalu bos: pengajuan memberi tahu akun bos',
  concat_ws('/', pg_temp.k('ajukan_3') ->> 'perlu_bos', pg_temp.k('ajukan_3') ->> 'bos'), 'true/[8803]');
select uji.sama('8b: HRD lalu bos: rilis sebelum disetujui ditolak', pg_temp.k('rilis_3_belum') ->> 'hasil', 'belum_disetujui');
select uji.sama('8b: hanya akun bos yang bisa menyetujui', pg_temp.k('setuju_hrd') ->> 'hasil', 'bukan_bos');
select uji.sama('8b: persetujuan untuk pengajuan yang salah tidak berlaku', pg_temp.k('setuju_salah_id') ->> 'hasil', 'tidak_berlaku');
select uji.sama('8b: bos menolak -> kembali dihitung; pengaju diberi tahu',
  concat_ws('/', pg_temp.k('tolak_bos') ->> 'hasil', pg_temp.k('tolak_bos') ->> 'status', pg_temp.k('tolak_bos') ->> 'pengaju'), 'ditolak/dihitung/8804');
select uji.sama('8b: tombol bos untuk pengajuan lama tidak berlaku', pg_temp.k('setuju_lama') ->> 'hasil', 'tidak_berlaku');
select uji.sama('8b: bos setuju -> disetujui -> HRD merilis dengan PIN',
  concat_ws('/', pg_temp.k('setuju_bos') ->> 'hasil', pg_temp.k('rilis_3') ->> 'hasil', pg_temp.status(3)), 'disetujui/dirilis/dirilis');
select uji.sama('8b: persetujuan dan penolakan bos tercatat',
  (select string_agg(keputusan, ',' order by id) from fakta.persetujuan where perihal = 'rilis'), 'tolak,setuju');
select uji.sama('8b: riwayat status periode 3 lengkap',
  (select string_agg(status_baru, '>' order by id) from fakta.riwayat_status_periode where periode_id = pg_temp.pid(3)),
  'dihitung>diajukan>dihitung>diajukan>disetujui>dirilis');

-- Daftar karyawan sebelum tanggal mulai (keputusan pemilik 19 Nov 2026)
select pg_temp.segarkan();
set local role pintu;
insert into h values ('kode_mulai_nanti', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8801, 'id_karyawan', 'R8D',
  'sidik', encode(sha256('8b-mulai-nanti'), 'hex'))));
insert into h values ('kode_berhenti', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8801, 'id_karyawan', 'R8E',
  'sidik', encode(sha256('8b-berhenti'), 'hex'))));
insert into h values ('daftar_mulai_nanti', api.pintu_daftar(jsonb_build_object('telegram_id', 8901, 'sidik', encode(sha256('8b-mulai-nanti'), 'hex'))));
reset role;
select uji.sama('8b: karyawan yang mulai bekerja 20 hari lagi boleh dibuatkan kode dan mendaftar',
  pg_temp.k('kode_mulai_nanti') ->> 'hasil' || '/' || (pg_temp.k('daftar_mulai_nanti') ->> 'hasil'), 'dibuat/konfirmasi');
select uji.sama('8b: karyawan yang berhenti kemarin tetap ditolak', pg_temp.k('kode_berhenti') ->> 'hasil', 'berhenti');

-- Hak akses
select uji.harus_ditolak('8b: pintu tidak bisa memanggil hitung.ringkasan_rilis', 'select hitung.ringkasan_rilis(1)', 'pintu');
select uji.harus_ditolak('8b: pintu tidak bisa memeriksa PIN langsung', $$select fakta.periksa_pin(1, '000000')$$, 'pintu');
select uji.harus_ditolak('8b: pintu tidak bisa membaca rilis_gaji', 'select count(*) from fakta.rilis_gaji', 'pintu');
select uji.sama('8b: anon dan authenticated tidak bisa memanggil fungsi rilis',
  (select count(*) from pg_roles r cross join (values ('api.pintu_rilis(jsonb)'), ('api.pintu_ajukan(jsonb)'), ('api.pintu_atur_pin(jsonb)')) f(n)
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.oid, f.n::regprocedure, 'execute')), 0::bigint);

rollback;
