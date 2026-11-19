-- Uji paket 8a (docs/rencana-8a.md): pendaftaran karyawan lewat bot, PRD v2 celah K1, K8.
-- Fungsi dipanggil sebagai peran pintu, seperti Edge Function. Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into induk.divisi (kode, nama, pola) values ('ZD8', 'Uji Daftar', 'mingguan');
insert into induk.karyawan (id, nama) values ('Z8A', 'Uji Aktif'), ('Z8B', 'Uji Berhenti Kemarin'),
  ('Z8C', 'Uji Berhenti Hari Ini'), ('Z8D', 'Uji Ganti HP'), ('Z8E', 'Uji Bukan');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, ptkp, cara_bayar)
select id, '2020-01-01', 'ZD8', 1, 'TK/0', 'transfer' from induk.karyawan where id like 'Z8%';
insert into induk.status_kerja (id_karyawan, jenis, tanggal)
select id, 'mulai', '2020-01-01' from induk.karyawan where id like 'Z8%';
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values
  ('Z8B', 'berhenti', current_date - 1), ('Z8C', 'berhenti', current_date);
insert into induk.pengguna (telegram_id, peran) values (8101, 'hrd'), (8102, 'karyawan'), (8104, 'pembangun');

create temp table h (nama text primary key, isi jsonb);
create temp table s (nama text primary key, sidik text);
insert into s select x, encode(sha256(convert_to('KODE-' || x, 'utf8')), 'hex')
from unnest(array['a', 'b', 'c', 'd', 'd2', 'e', 'salah', 'x']) x;
grant all on h, s to pintu;
create function pg_temp.sd(t text) returns text language sql as $$ select sidik from s where nama = t $$;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
grant execute on function pg_temp.sd(text), pg_temp.k(text) to pintu;

set local role pintu;
-- Membuat kode
insert into h values ('buat_a', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'z8a', 'sidik', pg_temp.sd('a'))));
insert into h values ('buat_bukan_hrd', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8102, 'id_karyawan', 'Z8E', 'sidik', pg_temp.sd('x'))));
insert into h values ('buat_tak_dikenal', api.pintu_buat_kode(jsonb_build_object('telegram_id', 9999, 'id_karyawan', 'Z8E', 'sidik', pg_temp.sd('x'))));
insert into h values ('buat_tidak_ada', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'ZZZ', 'sidik', pg_temp.sd('x'))));
insert into h values ('buat_berhenti', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8B', 'sidik', pg_temp.sd('x'))));
insert into h values ('buat_c', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8104, 'id_karyawan', 'Z8C', 'sidik', pg_temp.sd('c'))));
insert into h values ('buat_e', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8E', 'sidik', pg_temp.sd('e'))));
-- Daftar dan konfirmasi
insert into h values ('daftar_a', api.pintu_daftar(jsonb_build_object('telegram_id', 8201, 'sidik', pg_temp.sd('a'))));
insert into h values ('daftar_a_orang_lain', api.pintu_daftar(jsonb_build_object('telegram_id', 8202, 'sidik', pg_temp.sd('a'))));
insert into h values ('jawab_a_orang_lain', api.pintu_daftar_jawab(jsonb_build_object('telegram_id', 8202,
  'kode_id', (pg_temp.k('daftar_a') ->> 'kode_id')::bigint, 'jawab', 'ya')));
insert into h values ('jawab_a', api.pintu_daftar_jawab(jsonb_build_object('telegram_id', 8201,
  'kode_id', (pg_temp.k('daftar_a') ->> 'kode_id')::bigint, 'jawab', 'ya')));
insert into h values ('jawab_a_lagi', api.pintu_daftar_jawab(jsonb_build_object('telegram_id', 8201,
  'kode_id', (pg_temp.k('daftar_a') ->> 'kode_id')::bigint, 'jawab', 'ya')));
insert into h values ('daftar_a_dipakai', api.pintu_daftar(jsonb_build_object('telegram_id', 8203, 'sidik', pg_temp.sd('a'))));
insert into h values ('daftar_sudah', api.pintu_daftar(jsonb_build_object('telegram_id', 8201, 'sidik', pg_temp.sd('c'))));
insert into h values ('daftar_hrd', api.pintu_daftar(jsonb_build_object('telegram_id', 8101, 'sidik', pg_temp.sd('c'))));
insert into h values ('buat_a_lagi', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8A', 'sidik', pg_temp.sd('x'))));
-- Berhenti hari ini = hari kerja terakhir (C11): masih boleh
insert into h values ('daftar_c', api.pintu_daftar(jsonb_build_object('telegram_id', 8204, 'sidik', pg_temp.sd('c'))));
insert into h values ('jawab_c', api.pintu_daftar_jawab(jsonb_build_object('telegram_id', 8204,
  'kode_id', (pg_temp.k('daftar_c') ->> 'kode_id')::bigint, 'jawab', 'ya')));
-- "Bukan": kode dibatalkan
insert into h values ('daftar_e', api.pintu_daftar(jsonb_build_object('telegram_id', 8205, 'sidik', pg_temp.sd('e'))));
insert into h values ('jawab_e_bukan', api.pintu_daftar_jawab(jsonb_build_object('telegram_id', 8205,
  'kode_id', (pg_temp.k('daftar_e') ->> 'kode_id')::bigint, 'jawab', 'bukan')));
insert into h values ('jawab_e_ya_sesudah', api.pintu_daftar_jawab(jsonb_build_object('telegram_id', 8205,
  'kode_id', (pg_temp.k('daftar_e') ->> 'kode_id')::bigint, 'jawab', 'ya')));
reset role;

select uji.sama('8a: HRD membuat kode (ID huruf kecil dirapikan) dengan nama dan divisi, tanpa angka gaji',
  (select isi - 'berlaku_sampai' from h where nama = 'buat_a'),
  '{"hasil": "dibuat", "ganti": false, "id": "Z8A", "nama": "Uji Aktif", "divisi": "Uji Daftar"}'::jsonb);
select uji.sama('8a: kode berlaku 60 menit',
  (select (kedaluwarsa - dibuat) from fakta.kode_daftar where id_karyawan = 'Z8A' order by id limit 1), interval '60 minutes');
select uji.sama('8a: database hanya menyimpan sidik kode', (select count(*) from fakta.kode_daftar where sidik !~ '^[0-9a-f]{64}$'), 0::bigint);
select uji.sama('8a: akun karyawan tidak bisa membuat kode', pg_temp.k('buat_bukan_hrd') ->> 'hasil', 'bukan_hrd');
select uji.sama('8a: akun tak dikenal tidak bisa membuat kode', pg_temp.k('buat_tak_dikenal') ->> 'hasil', 'bukan_hrd');
select uji.sama('8a: ID tidak ada', pg_temp.k('buat_tidak_ada') ->> 'hasil', 'tidak_ada');
select uji.sama('8a: karyawan yang berhenti kemarin tidak dibuatkan kode', pg_temp.k('buat_berhenti') ->> 'hasil', 'berhenti');
select uji.sama('8a: pembangun boleh membuat kode', pg_temp.k('buat_c') ->> 'hasil', 'dibuat');
select uji.sama('8a (K8): kode benar -> konfirmasi nama dan divisi',
  pg_temp.k('daftar_a') - 'kode_id', '{"hasil": "konfirmasi", "id": "Z8A", "nama": "Uji Aktif", "divisi": "Uji Daftar"}'::jsonb);
select uji.sama('8a: kode yang sedang dikonfirmasi orang lain = salah bagi akun lain', pg_temp.k('daftar_a_orang_lain') ->> 'hasil', 'salah');
select uji.sama('8a: tombol konfirmasi hanya berlaku untuk akun yang mengetik /daftar', pg_temp.k('jawab_a_orang_lain') ->> 'hasil', 'tidak_berlaku');
select uji.sama('8a: "Ya" -> terdaftar', pg_temp.k('jawab_a') ->> 'hasil', 'terdaftar');
select uji.sama('8a: akun baru = karyawan Z8A, aktif',
  (select peran || '/' || id_karyawan || '/' || aktif from induk.pengguna where telegram_id = 8201), 'karyawan/Z8A/true');
select uji.sama('8a: tombol ditekan lagi -> tidak berlaku', pg_temp.k('jawab_a_lagi') ->> 'hasil', 'tidak_berlaku');
select uji.sama('8a: kode yang sudah dipakai ditolak', pg_temp.k('daftar_a_dipakai') ->> 'hasil', 'salah');
select uji.sama('8a (K1): satu akun Telegram satu ID', pg_temp.k('daftar_sudah') ->> 'hasil', 'sudah_terdaftar');
select uji.sama('8a: akun HRD tidak bisa mendaftar sebagai karyawan', pg_temp.k('daftar_hrd') ->> 'hasil', 'sudah_terdaftar');
select uji.sama('8a (K1): ID yang sudah punya akun aktif tidak dibuatkan kode tanpa "ganti"', pg_temp.k('buat_a_lagi') ->> 'hasil', 'sudah_punya_akun');
select uji.sama('8a (C11): berhenti hari ini masih boleh mendaftar', pg_temp.k('jawab_c') ->> 'hasil', 'terdaftar');
select uji.sama('8a: "Bukan" -> kode dibatalkan', pg_temp.k('jawab_e_bukan') ->> 'hasil', 'dibatalkan');
select uji.sama('8a: sesudah "Bukan", "Ya" tidak berlaku dan tidak ada akun', pg_temp.k('jawab_e_ya_sesudah') ->> 'hasil' || '/' ||
  (select count(*) from induk.pengguna where telegram_id = 8205), 'tidak_berlaku/0');
select uji.sama('8a: pendaftaran tercatat di jejak perubahan', (select count(*) from jejak.perubahan
  where tabel = 'induk.pengguna' and aksi = 'INSERT' and data_baru ->> 'telegram_id' = '8201'), 1::bigint);

-- Kode kedaluwarsa; kode lama dibatalkan bila kode baru dibuat untuk ID yang sama
set local role pintu;
insert into h values ('buat_d_lama', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8D', 'sidik', pg_temp.sd('d'))));
reset role;
update fakta.kode_daftar set kedaluwarsa = now() - interval '1 second' where sidik = pg_temp.sd('d');
set local role pintu;
insert into h values ('daftar_d_lewat', api.pintu_daftar(jsonb_build_object('telegram_id', 8206, 'sidik', pg_temp.sd('d'))));
insert into h values ('buat_d', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8D', 'sidik', pg_temp.sd('d2'))));
reset role;
select uji.sama('8a: kode lewat 60 menit ditolak', pg_temp.k('daftar_d_lewat') ->> 'hasil', 'salah');
select uji.sama('8a: kode baru untuk ID yang sama menutup kode lama',
  (select hasil from fakta.kode_daftar where sidik = pg_temp.sd('d')), 'diganti');

-- Ganti HP lewat HRD (K1): akun lama dinonaktifkan hanya setelah akun baru menekan "Ya"
insert into induk.pengguna (telegram_id, peran, id_karyawan) values (8301, 'karyawan', 'Z8D');
set local role pintu;
insert into h values ('ganti_tanpa_kata', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8D', 'sidik', pg_temp.sd('x'))));
reset role;
delete from s where nama = 'x';
insert into s values ('g', encode(sha256(convert_to('KODE-g', 'utf8')), 'hex'));
set local role pintu;
insert into h values ('ganti', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8D', 'ganti', true, 'sidik', pg_temp.sd('g'))));
insert into h values ('ganti_daftar', api.pintu_daftar(jsonb_build_object('telegram_id', 8302, 'sidik', pg_temp.sd('g'))));
reset role;
select uji.sama('8a (K1): tanpa "ganti" ditolak karena sudah punya akun', pg_temp.k('ganti_tanpa_kata') ->> 'hasil', 'sudah_punya_akun');
select uji.sama('8a (K1): sebelum "Ya", akun lama tetap aktif', (select aktif from induk.pengguna where telegram_id = 8301), true);
set local role pintu;
insert into h values ('ganti_jawab', api.pintu_daftar_jawab(jsonb_build_object('telegram_id', 8302,
  'kode_id', (pg_temp.k('ganti_daftar') ->> 'kode_id')::bigint, 'jawab', 'ya')));
reset role;
select uji.sama('8a (K1): sesudah "Ya", akun lama nonaktif dan hanya akun baru yang aktif',
  (select string_agg(telegram_id || ':' || aktif, ',' order by telegram_id) from induk.pengguna where id_karyawan = 'Z8D'),
  '8301:false,8302:true');

-- Batas 5 kode salah per akun Telegram per jam
set local role pintu;
insert into h select 'salah' || i, api.pintu_daftar(jsonb_build_object('telegram_id', 8401, 'sidik', pg_temp.sd('salah')))
from generate_series(1, 5) i;
insert into h values ('salah6', api.pintu_daftar(jsonb_build_object('telegram_id', 8401, 'sidik', pg_temp.sd('salah'))));
insert into h values ('buat_e2', api.pintu_buat_kode(jsonb_build_object('telegram_id', 8101, 'id_karyawan', 'Z8E', 'sidik', pg_temp.sd('salah'))));
insert into h values ('terkunci_kode_benar', api.pintu_daftar(jsonb_build_object('telegram_id', 8401, 'sidik', pg_temp.sd('salah'))));
insert into h values ('akun_lain_tidak_terkunci', api.pintu_daftar(jsonb_build_object('telegram_id', 8402, 'sidik', pg_temp.sd('salah'))));
reset role;
select uji.sama('8a: kode salah ke-1 sampai ke-5 ditolak dengan sisa 4..0',
  (select string_agg(isi ->> 'hasil' || ':' || (isi ->> 'sisa'), ',' order by nama) from h where nama ~ '^salah[1-5]$'),
  'salah:4,salah:3,salah:2,salah:1,salah:0');
select uji.sama('8a: kode salah ke-6 -> terkunci', pg_temp.k('salah6') ->> 'hasil', 'terkunci');
select uji.sama('8a: terkunci -> kode benar pun ditolak', pg_temp.k('terkunci_kode_benar') ->> 'hasil', 'terkunci');
select uji.sama('8a: akun Telegram lain tidak ikut terkunci', pg_temp.k('akun_lain_tidak_terkunci') ->> 'hasil', 'konfirmasi');
update fakta.percobaan_daftar set waktu = waktu - interval '61 minutes' where telegram_id = 8401;
set local role pintu;
insert into h values ('sesudah_sejam', api.pintu_daftar(jsonb_build_object('telegram_id', 8401, 'sidik', pg_temp.sd('b'))));
reset role;
select uji.sama('8a: sesudah 1 jam boleh mencoba lagi', pg_temp.k('sesudah_sejam') ->> 'hasil', 'salah');

-- Akun dan hak akses
set local role pintu;
insert into h values ('akun_karyawan', api.pintu_akun('{"telegram_id": 8201}'));
insert into h values ('akun_lama', api.pintu_akun('{"telegram_id": 8301}'));
insert into h values ('akun_kosong', api.pintu_akun('{"telegram_id": 8999}'));
reset role;
select uji.sama('8a: pintu_akun karyawan', pg_temp.k('akun_karyawan'), '{"peran": "karyawan", "nama": "Uji Aktif"}'::jsonb);
select uji.sama('8a: pintu_akun akun nonaktif = tidak terdaftar', pg_temp.k('akun_lama'), '{"peran": null}'::jsonb);
select uji.sama('8a: pintu_akun tak dikenal', pg_temp.k('akun_kosong'), '{"peran": null}'::jsonb);
select uji.sama('8a: akun karyawan tidak dianggap HRD (tidak bisa kirim file atau /unggah)', api.pintu_hrd(8201), null::bigint);
select uji.harus_ditolak('8a: pintu tidak bisa membaca tabel kode daftar', 'select count(*) from fakta.kode_daftar', 'pintu');
select uji.harus_ditolak('8a: pintu tidak bisa memanggil fakta.karyawan_aktif', $$select fakta.karyawan_aktif('Z8A')$$, 'pintu');
select uji.sama('8a: tabel lama induk.kode_daftar sudah tidak ada', to_regclass('induk.kode_daftar') is null, true);

rollback;
