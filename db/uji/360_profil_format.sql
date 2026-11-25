-- Uji paket F2 (docs/rencana-f2-konfirmasi-format.md, PP07): percakapan konfirmasi format dan profil format per mesin.
-- Satu transaksi yang dibatalkan di akhir. Fungsi dipanggil sebagai peran pintu, seperti Edge Function.
begin;
set local app.pengguna = 'uji-otomatis';
insert into induk.mesin (kode, nama) values ('MF1', 'Uji F2 satu'), ('MF2', 'Uji F2 dua');
insert into induk.karyawan (id, nama) values ('F2K', 'Uji Karyawan F2');
insert into induk.pengguna (telegram_id, peran) values (9361, 'hrd'), (9362, 'bos'), (9363, 'pembangun'), (9364, 'hrd');
insert into induk.pengguna (telegram_id, peran, id_karyawan) values (9365, 'karyawan', 'F2K');
insert into induk.pengguna (telegram_id, peran, aktif) values (9366, 'hrd', false);
create temp table h (nama text primary key, isi jsonb);
grant all on h to pintu;
create function pg_temp.k(t text) returns jsonb language sql as $$ select isi from h where nama = t $$;
grant execute on function pg_temp.k(text) to pintu;
create function pg_temp.mulai(u bigint, tg bigint, mesin text, sidik text default 'nama|noid|waktu|status') returns jsonb
language sql as $$
  select api.pintu_konfirmasi_mulai(jsonb_build_object('update_id', u, 'telegram_id', tg, 'file_id', 'file' || u,
    'nama_file', 'f' || u || '.xlsx', 'mesin', mesin, 'tanggal_kirim', '2026-11-25',
    'judul', '["Nama", "No.ID", "Waktu", "Status"]'::jsonb, 'sidik_judul', sidik, 'analisa', '[]'::jsonb))
$$;
grant execute on function pg_temp.mulai(bigint, bigint, text, text) to pintu;
create function pg_temp.ubah(id bigint, tg bigint, lama text, baru text, pil jsonb) returns jsonb language sql as $$
  select api.pintu_konfirmasi_ubah(jsonb_build_object('id', id, 'telegram_id', tg, 'langkah_lama', lama, 'langkah_baru', baru,
                                                      'pilihan', pil))
$$;
grant execute on function pg_temp.ubah(bigint, bigint, text, text, jsonb) to pintu;
create function pg_temp.selesai(id bigint, tg bigint, simpan boolean) returns jsonb language sql as $$
  select api.pintu_konfirmasi_selesai(jsonb_build_object('id', id, 'telegram_id', tg, 'simpan', simpan))
$$;
grant execute on function pg_temp.selesai(bigint, bigint, boolean) to pintu;

set local role pintu;
-- Hanya HRD dan pembangun (K2) yang bisa memulai; bos, karyawan, HRD nonaktif ditolak.
insert into h values ('bos', pg_temp.mulai(93601, 9362, 'MF1'));
insert into h values ('karyawan', pg_temp.mulai(93602, 9365, 'MF1'));
insert into h values ('nonaktif', pg_temp.mulai(93603, 9366, 'MF1'));
insert into h values ('mesin_salah', pg_temp.mulai(93604, 9361, 'XX9'));
insert into h values ('mulai', pg_temp.mulai(93605, 9361, 'MF1'));
insert into h values ('mulai_lagi', pg_temp.mulai(93605, 9361, 'MF1'));
reset role;

select uji.sama('F2: bos tidak bisa memulai konfirmasi format', pg_temp.k('bos') ->> 'hasil', 'ditolak');
select uji.sama('F2: karyawan tidak bisa memulai konfirmasi format', pg_temp.k('karyawan') ->> 'hasil', 'ditolak');
select uji.sama('F2: HRD nonaktif tidak bisa memulai konfirmasi format', pg_temp.k('nonaktif') ->> 'hasil', 'ditolak');
select uji.sama('F2: mesin tidak dikenal ditolak', pg_temp.k('mesin_salah') ->> 'hasil', 'ditolak');
select uji.sama('F2: HRD memulai konfirmasi; langkah pertama kolom ID', (pg_temp.k('mulai') ->> 'hasil') || '/' ||
  (pg_temp.k('mulai') -> 'konfirmasi' ->> 'langkah'), 'mulai/id');
select uji.sama('F2: pembangun diberi tahu (penerima = akun pembangun)', pg_temp.k('mulai') -> 'pembangun', '[9363]'::jsonb);
select uji.sama('F2: pesan yang sama tidak membuat percakapan kedua', (pg_temp.k('mulai_lagi') ->> 'hasil') || '/' ||
  (pg_temp.k('mulai_lagi') -> 'konfirmasi' ->> 'id'), 'sudah_ada/' || (pg_temp.k('mulai') -> 'konfirmasi' ->> 'id'));
select uji.sama('F2: file ditahan belum dicatat sebagai kiriman', (select count(*) from fakta.kiriman_file where nomor_pesan = 93605)::int, 0);

create temp table kid as select (pg_temp.k('mulai') -> 'konfirmasi' ->> 'id')::bigint as id;
grant select on kid to pintu;
set local role pintu;
-- Akun lain (HRD lain, pembangun) tidak bisa membaca atau mengubah percakapan milik HRD yang mengirim.
insert into h values ('ambil_lain', coalesce(api.pintu_konfirmasi_ambil(jsonb_build_object('id', (select id from kid), 'telegram_id', 9364)), 'null'));
insert into h values ('ubah_lain', pg_temp.ubah((select id from kid), 9364, 'id', 'waktu', '{"kolom_id": "No.ID"}'));
insert into h values ('ubah_pembangun', pg_temp.ubah((select id from kid), 9363, 'id', 'waktu', '{"kolom_id": "No.ID"}'));
-- Simpan sebelum langkah contoh ditolak.
insert into h values ('simpan_dini', pg_temp.selesai((select id from kid), 9361, true));
-- Langkah: ID -> waktu -> contoh. Tombol lama (langkah id) tidak berlaku lagi.
insert into h values ('ke_waktu', pg_temp.ubah((select id from kid), 9361, 'id', 'waktu', '{"kolom_id": "No.ID"}'));
insert into h values ('tombol_lama', pg_temp.ubah((select id from kid), 9361, 'id', 'waktu', '{"kolom_id": "Nama"}'));
insert into h values ('langkah_salah', pg_temp.ubah((select id from kid), 9361, 'waktu', 'selesai', '{}'));
-- Pilihan yang tidak ada di judul file tidak bisa disimpan.
insert into h values ('ke_contoh_salah', pg_temp.ubah((select id from kid), 9361, 'waktu', 'contoh',
  '{"kolom_id": "No.ID", "kolom_waktu": "Jam Scan", "susunan": "dmy"}'));
insert into h values ('simpan_salah', pg_temp.selesai((select id from kid), 9361, true));
insert into h values ('balik', pg_temp.ubah((select id from kid), 9361, 'contoh', 'contoh',
  '{"kolom_id": "No.ID", "kolom_waktu": "No.ID", "susunan": "dmy"}'));
insert into h values ('simpan_sama', pg_temp.selesai((select id from kid), 9361, true));
insert into h values ('ke_contoh', pg_temp.ubah((select id from kid), 9361, 'contoh', 'contoh',
  '{"kolom_id": "No.ID", "kolom_waktu": "Waktu", "susunan": "dmy"}'));
insert into h values ('ambil', api.pintu_konfirmasi_ambil(jsonb_build_object('id', (select id from kid), 'telegram_id', 9361)));
insert into h values ('simpan', pg_temp.selesai((select id from kid), 9361, true));
insert into h values ('simpan_lagi', pg_temp.selesai((select id from kid), 9361, true));
insert into h values ('profil', api.pintu_profil_mesin(jsonb_build_object('telegram_id', 9361, 'mesin', 'MF1',
  'sidik_judul', 'nama|noid|waktu|status')));
insert into h values ('profil_mesin_lain', coalesce(api.pintu_profil_mesin(jsonb_build_object('telegram_id', 9361, 'mesin', 'MF2',
  'sidik_judul', 'nama|noid|waktu|status')), 'null'));
insert into h values ('profil_judul_lain', coalesce(api.pintu_profil_mesin(jsonb_build_object('telegram_id', 9361, 'mesin', 'MF1',
  'sidik_judul', 'nama|noid|waktu|status|lokasi')), 'null'));
insert into h values ('profil_karyawan', coalesce(api.pintu_profil_mesin(jsonb_build_object('telegram_id', 9365, 'mesin', 'MF1',
  'sidik_judul', 'nama|noid|waktu|status')), 'null'));
insert into h values ('profil_tanpa_akun', coalesce(api.pintu_profil_mesin(jsonb_build_object('kode_sidik', repeat('0', 64),
  'mesin', 'MF1', 'sidik_judul', 'nama|noid|waktu|status')), 'null'));
reset role;

select uji.sama('F2: HRD lain tidak bisa membaca percakapan', pg_temp.k('ambil_lain'), 'null'::jsonb);
select uji.sama('F2: HRD lain tidak bisa mengubah percakapan', pg_temp.k('ubah_lain') ->> 'hasil', 'tidak_berlaku');
select uji.sama('F2: pembangun tidak bisa menekan tombol percakapan milik HRD', pg_temp.k('ubah_pembangun') ->> 'hasil', 'tidak_berlaku');
select uji.sama('F2: "Ya, simpan" sebelum contoh hasil bacaan tidak berlaku', pg_temp.k('simpan_dini') ->> 'hasil', 'tidak_berlaku');
select uji.sama('F2: pilih kolom ID -> langkah kolom waktu', pg_temp.k('ke_waktu') -> 'konfirmasi' ->> 'langkah', 'waktu');
select uji.sama('F2: tombol dari langkah lama tidak berlaku', pg_temp.k('tombol_lama') ->> 'hasil', 'tidak_berlaku');
select uji.sama('F2: langkah tidak sah ditolak', pg_temp.k('langkah_salah') ->> 'hasil', 'tidak_berlaku');
select uji.sama('F2: kolom yang tidak ada di judul file tidak bisa disimpan', pg_temp.k('simpan_salah') ->> 'hasil', 'pilihan_salah');
select uji.sama('F2: kolom ID dan waktu yang sama tidak bisa disimpan', pg_temp.k('simpan_sama') ->> 'hasil', 'pilihan_salah');
select uji.sama('F2: percakapan bisa dibaca pemiliknya dengan pilihan', pg_temp.k('ambil') -> 'pilihan' ->> 'kolom_waktu', 'Waktu');
select uji.sama('F2: "Ya, simpan" -> profil disimpan', pg_temp.k('simpan') ->> 'hasil', 'disimpan');
select uji.sama('F2: profil tersimpan dengan kolom, susunan, mesin, dan penyetuju',
  (select concat_ws('|', x.mesin, x.sidik_judul, x.kolom_id, x.kolom_waktu, x.susunan, u.telegram_id, x.aktif::text)
   from induk.profil_file_mesin x join induk.pengguna u on u.id = x.disetujui_oleh where x.mesin = 'MF1'),
  'MF1|nama|noid|waktu|status|No.ID|Waktu|dmy|9361|true');
select uji.sama('F2: pembangun diberi tahu profil baru', pg_temp.k('simpan') -> 'pembangun', '[9363]'::jsonb);
select uji.sama('F2: menyimpan dua kali tidak berlaku', pg_temp.k('simpan_lagi') ->> 'hasil', 'tidak_berlaku');
select uji.sama('F2: percakapan tercatat disimpan dengan nomor profil',
  (select k.status || '/' || (k.profil_id = (pg_temp.k('simpan') -> 'profil' ->> 'id')::bigint) from fakta.konfirmasi_format k
   where k.id = (select id from kid)), 'disimpan/true');
select uji.sama('F2: profil terbaca untuk mesin dan judul yang sama', pg_temp.k('profil') ->> 'kolom_waktu', 'Waktu');
select uji.sama('F2 (C3): profil tidak dipakai untuk mesin lain', pg_temp.k('profil_mesin_lain'), 'null'::jsonb);
select uji.sama('F2 (K3): profil tidak dipakai bila judul kolom berbeda', pg_temp.k('profil_judul_lain'), 'null'::jsonb);
select uji.sama('F2: karyawan tidak bisa membaca profil', pg_temp.k('profil_karyawan'), 'null'::jsonb);
select uji.sama('F2: tautan unggah palsu tidak bisa membaca profil', pg_temp.k('profil_tanpa_akun'), 'null'::jsonb);
select uji.sama('F2: penyimpanan profil tercatat di jejak perubahan',
  (select count(*) from jejak.perubahan j where j.tabel = 'induk.profil_file_mesin' and j.aksi = 'INSERT'
     and j.data_baru ->> 'mesin' = 'MF1')::int, 1);

-- Tautan unggah sah (halaman web) bisa membaca profil yang sudah disimpan lewat bot.
insert into fakta.tautan_unggah (sidik, pengguna, berlaku_sampai)
values (repeat('f', 64), (select id from induk.pengguna where telegram_id = 9364), now() + interval '15 minutes');
set local role pintu;
insert into h values ('profil_web', coalesce(api.pintu_profil_mesin(jsonb_build_object('kode_sidik', repeat('f', 64),
  'mesin', 'MF1', 'sidik_judul', 'nama|noid|waktu|status')), 'null'));
-- Pembangun menyimpan profil untuk file kirimannya sendiri (K2); profil kedua untuk mesin + judul yang sama menggantikan yang lama.
insert into h values ('mulai_pb', pg_temp.mulai(93606, 9363, 'MF1'));
reset role;
select uji.sama('F2: halaman unggah dengan tautan sah membaca profil', pg_temp.k('profil_web') ->> 'kolom_id', 'No.ID');
select uji.sama('F2: pembangun tidak diberi tahu dirinya sendiri', pg_temp.k('mulai_pb') -> 'pembangun', '[]'::jsonb);
set local role pintu;
insert into h values ('pb_contoh', pg_temp.ubah((pg_temp.k('mulai_pb') -> 'konfirmasi' ->> 'id')::bigint, 9363, 'id', 'contoh',
  '{"kolom_id": "No.ID", "kolom_waktu": "Waktu", "susunan": "mdy"}'));
insert into h values ('pb_simpan', pg_temp.selesai((pg_temp.k('mulai_pb') -> 'konfirmasi' ->> 'id')::bigint, 9363, true));
reset role;
select uji.sama('F2 (K2): pembangun bisa menyimpan profil', pg_temp.k('pb_simpan') ->> 'hasil', 'disimpan');
select uji.sama('F2: satu profil aktif per mesin + judul; yang lama dinonaktifkan dengan alasan',
  (select string_agg(x.susunan || ':' || x.aktif || ':' || coalesce(x.alasan_nonaktif, '-'), ' ' order by x.id)
   from induk.profil_file_mesin x where x.mesin = 'MF1'),
  'dmy:false:diganti profil dari konfirmasi no. ' || (pg_temp.k('mulai_pb') -> 'konfirmasi' ->> 'id') || ' mdy:true:-');

-- "Tidak": percakapan ditolak, profil tidak disimpan.
set local role pintu;
insert into h values ('mulai_tolak', pg_temp.mulai(93607, 9361, 'MF2', 'idkartu|jamscan'));
insert into h values ('tidak', pg_temp.selesai((pg_temp.k('mulai_tolak') -> 'konfirmasi' ->> 'id')::bigint, 9361, false));
insert into h values ('tidak_lagi', pg_temp.selesai((pg_temp.k('mulai_tolak') -> 'konfirmasi' ->> 'id')::bigint, 9361, false));
reset role;
select uji.sama('F2: "Tidak" -> percakapan ditolak dan membawa data file untuk dicatat ditolak',
  (pg_temp.k('tidak') ->> 'hasil') || '/' || (pg_temp.k('tidak') -> 'konfirmasi' ->> 'file_id'), 'ditolak/file93607');
select uji.sama('F2: "Tidak" tidak menyimpan profil', (select count(*) from induk.profil_file_mesin where mesin = 'MF2')::int, 0);
select uji.sama('F2: "Tidak" ditekan lagi tidak berlaku', pg_temp.k('tidak_lagi') ->> 'hasil', 'tidak_berlaku');

-- /profilmesin: hanya pembangun; hapus menonaktifkan, file berikutnya ditanyakan lagi.
set local role pintu;
insert into h values ('daftar_hrd', api.pintu_profil_daftar(jsonb_build_object('telegram_id', 9361)));
insert into h values ('daftar', api.pintu_profil_daftar(jsonb_build_object('telegram_id', 9363)));
insert into h values ('hapus_hrd', api.pintu_profil_hapus(jsonb_build_object('telegram_id', 9361,
  'profil_id', (pg_temp.k('pb_simpan') -> 'profil' ->> 'id')::bigint)));
insert into h values ('hapus', api.pintu_profil_hapus(jsonb_build_object('telegram_id', 9363,
  'profil_id', (pg_temp.k('pb_simpan') -> 'profil' ->> 'id')::bigint)));
insert into h values ('hapus_lagi', api.pintu_profil_hapus(jsonb_build_object('telegram_id', 9363,
  'profil_id', (pg_temp.k('pb_simpan') -> 'profil' ->> 'id')::bigint)));
insert into h values ('sesudah_hapus', coalesce(api.pintu_profil_mesin(jsonb_build_object('telegram_id', 9361, 'mesin', 'MF1',
  'sidik_judul', 'nama|noid|waktu|status')), 'null'));
reset role;
select uji.sama('F2: /profilmesin dari HRD ditolak', pg_temp.k('daftar_hrd') ->> 'hasil', 'bukan_pembangun');
select uji.sama('F2: /profilmesin pembangun menampilkan profil aktif saja, dengan penyetuju',
  (select string_agg((x ->> 'mesin') || ':' || (x ->> 'susunan') || ':' || (x ->> 'oleh'), ' ')
   from jsonb_array_elements(pg_temp.k('daftar') -> 'profil') x), 'MF1:mdy:pembangun Telegram ...9363');
select uji.sama('F2: HRD tidak bisa menghapus profil', pg_temp.k('hapus_hrd') ->> 'hasil', 'bukan_pembangun');
select uji.sama('F2: pembangun menghapus profil', pg_temp.k('hapus') ->> 'hasil', 'dihapus');
select uji.sama('F2: hapus kedua kali -> tidak ada', pg_temp.k('hapus_lagi') ->> 'hasil', 'tidak_ada');
select uji.sama('F2: sesudah dihapus tidak ada profil aktif (file berikutnya ditanyakan lagi)', pg_temp.k('sesudah_hapus'), 'null'::jsonb);

-- Penjaga: profil tidak bisa dihapus atau diubah isinya; peran pintu tidak bisa membaca tabel langsung.
select uji.harus_ditolak('F2: profil tidak boleh dihapus', $q$delete from induk.profil_file_mesin where mesin = 'MF1'$q$);
select uji.harus_ditolak('F2: isi profil tidak boleh diubah', $q$update induk.profil_file_mesin set kolom_id = 'Nama' where mesin = 'MF1'$q$);
select uji.harus_ditolak('F2: profil nonaktif tidak boleh diaktifkan lagi',
  $q$update induk.profil_file_mesin set aktif = true, dinonaktifkan = null, dinonaktifkan_oleh = null where mesin = 'MF1'$q$);
select uji.harus_ditolak('F2: pintu tidak bisa membaca profil langsung', 'select count(*) from induk.profil_file_mesin', 'pintu');
select uji.harus_ditolak('F2: pintu tidak bisa membaca percakapan langsung', 'select count(*) from fakta.konfirmasi_format', 'pintu');
select uji.harus_ditolak('F2: pintu tidak bisa memanggil fungsi pembantu langsung',
  $q$select fakta.konfirmasi_json(k) from fakta.konfirmasi_format k$q$, 'pintu');

rollback;
