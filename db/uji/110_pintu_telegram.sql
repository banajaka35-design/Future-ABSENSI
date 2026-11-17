-- Uji paket 5b: fungsi api pintu Telegram dan peran `pintu` (docs/pintu-telegram.md, kasus T2, T3, T6, T9, T10).
-- Alur lengkap dengan file simulasi dan pesan Telegram tiruan ada di sistem/pintu/uji_pintu.ts.
-- Satu transaksi yang dibatalkan di akhir.
begin;
set local app.pengguna = 'uji-otomatis';

insert into aturan.jendela_tap (menit_sebelum_masuk, menit_sesudah_pulang, jarak_minimal_menit, berlaku_dari) values (120, 360, 60, '2026-01-01');
insert into aturan.toleransi (telat_menit, pulang_cepat_menit, berlaku_dari) values (5, 0, '2026-01-01');
insert into aturan.lembur (menit_minimal, kelipatan_menit, cara_bulat, dasar_upah, berlaku_dari) values (60, 30, 'bawah', 'penuh', '2021-01-01');
insert into aturan.pengali_lembur (jenis_hari, jam_ke, pengali_x10, berlaku_dari)
select 'kerja', j, case when j = 1 then 15 else 20 end, date '2021-02-02' from generate_series(1, 12) j;
insert into aturan.upah_minimum (wilayah, nilai, berlaku_dari) values ('Kabupaten Langkat', 3402892, '2026-01-01');
insert into induk.mesin (kode, nama) values ('MA1', 'Gerbang'), ('MA2', 'Kantor');
insert into induk.kode_jadwal (kode, jam_masuk, jam_pulang, istirahat_menit) values ('P', '07:00', '15:00', 60);
insert into induk.divisi (kode, nama, pola, jumlah_regu, mesin_utama) values ('TL', 'Uji', 'mingguan', 1, 'MA1');
insert into induk.jadwal_hari (divisi, regu, hari_ke, kode, berlaku_dari)
select 'TL', 0, h, case when h = 7 then null else 'P' end, '2026-01-01' from generate_series(1, 7) h;
insert into induk.karyawan (id, nama) values ('K1', 'Uji K1');
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, gaji_pokok, tunjangan_tetap, ptkp, cara_bayar,
                                    bpjs_kesehatan, bpjs_ketenagakerjaan)
values ('K1', '2025-01-01', 'TL', 3500000, 500000, 'TK/0', 'transfer', false, false);
insert into induk.status_kerja (id_karyawan, jenis, tanggal) values ('K1', 'mulai', '2025-01-01');
insert into induk.penugasan_regu (id_karyawan, regu, berlaku_dari) values ('K1', 0, '2025-01-01');
insert into induk.pemetaan_id_mesin (mesin, id_mesin, id_karyawan, berlaku_dari) values ('MA1', '1', 'K1', '2025-01-01');
insert into fakta.periode (tanggal_awal, tanggal_akhir, tanggal_bayar) values
  ('2026-03-21', '2026-04-20', '2026-04-25'), ('2026-04-21', '2026-05-20', '2026-05-25');
insert into induk.pengguna (telegram_id, peran) values (111, 'hrd'), (222, 'karyawan'), (333, 'hrd');
update induk.pengguna set aktif = false where telegram_id = 333;

create temp table hasil_uji (nama text primary key, isi jsonb);
grant all on hasil_uji to pintu;
-- Semua panggilan api di bawah dijalankan sebagai peran pintu, seperti Edge Function.
set local role pintu;
insert into hasil_uji values ('pesan1', api.pintu_pesan('{"update_id": 9001, "telegram_id": 111, "jenis": "dokumen"}'));
insert into hasil_uji values ('pesan1_ulang', api.pintu_pesan('{"update_id": 9001, "telegram_id": 111, "jenis": "dokumen"}'));
insert into hasil_uji values ('pesan_bukan_hrd', api.pintu_pesan('{"update_id": 9002, "telegram_id": 222, "jenis": "dokumen"}'));
insert into hasil_uji values ('pesan_nonaktif', api.pintu_pesan('{"update_id": 9003, "telegram_id": 333, "jenis": "dokumen"}'));
insert into hasil_uji values ('terima', api.pintu_terima_file(jsonb_build_object(
  'update_id', 9001, 'telegram_id', 111, 'nama_file', 'uji.csv', 'sidik', repeat('a', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-07 06:55:00", "Masuk", 2], ["1", "2026-04-07 15:05:00", "Keluar", 3]]'::jsonb)));
insert into hasil_uji values ('terima_dobel', api.pintu_terima_file(jsonb_build_object(
  'update_id', 9004, 'telegram_id', 111, 'nama_file', 'uji lagi.csv', 'sidik', repeat('a', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-07 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('terima_bukan_hrd', api.pintu_terima_file(jsonb_build_object(
  'update_id', 9002, 'telegram_id', 222, 'nama_file', 'x.csv', 'sidik', repeat('b', 64), 'mesin', 'MA1',
  'tap', '[["1", "2026-04-08 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('terima_mesin_asing', api.pintu_terima_file(jsonb_build_object(
  'update_id', 9005, 'telegram_id', 111, 'nama_file', 'x.csv', 'sidik', repeat('c', 64), 'mesin', 'ZZ9',
  'tap', '[["1", "2026-04-08 06:55:00", "Masuk", 2]]'::jsonb)));
insert into hasil_uji values ('terima_rusak', api.pintu_terima_file(jsonb_build_object(
  'update_id', 9006, 'telegram_id', 111, 'nama_file', 'rusak.csv', 'sidik', repeat('d', 64), 'mesin', 'MA1',
  'tap', '[]'::jsonb, 'alasan', 'No.ID rusak karena Excel')));
insert into hasil_uji values ('tunda', api.pintu_tunda('{"update_id": 9007, "telegram_id": 111, "file_id": "F1", "nama_file": "a.csv"}'));
insert into hasil_uji values ('ambil_orang_lain', coalesce(api.pintu_ambil_tunda('{"update_id": 9007, "telegram_id": 222}'), 'null'));
insert into hasil_uji values ('ambil', api.pintu_ambil_tunda('{"update_id": 9007, "telegram_id": 111}'));
insert into hasil_uji values ('ambil_lagi', coalesce(api.pintu_ambil_tunda('{"update_id": 9007, "telegram_id": 111}'), 'null'));
insert into hasil_uji values ('kerja1', api.pintu_kerjakan());
insert into hasil_uji values ('kerja2', api.pintu_kerjakan());
reset role;

create function pg_temp.h(p text) returns jsonb language sql as $$ select isi from hasil_uji where nama = p $$;
select uji.sama('T3: pesan pertama baru, dari HRD', (pg_temp.h('pesan1') ->> 'baru') || '/' || (pg_temp.h('pesan1') ->> 'hrd'), 'true/true');
select uji.sama('T3: update_id sama dikenali sebagai ulangan', pg_temp.h('pesan1_ulang') ->> 'baru', 'false');
select uji.sama('pesan: daftar mesin dikirim', pg_temp.h('pesan1') -> 'mesin', '["MA1", "MA2"]'::jsonb);
select uji.sama('T6: pengirim bukan HRD dikenali', pg_temp.h('pesan_bukan_hrd') ->> 'hrd', 'false');
select uji.sama('T6: akun HRD nonaktif tidak dianggap HRD', pg_temp.h('pesan_nonaktif') ->> 'hrd', 'false');
select uji.sama('T1: file diterima dengan pengirim dan nomor pesan',
  (select hasil || '/' || (pengirim = (select id from induk.pengguna where telegram_id = 111)) || '/' || nomor_pesan
   from fakta.kiriman_file where nama_file = 'uji.csv'), 'diterima/true/9001');
select uji.sama('T1: periode yang terkena dikirim balik', jsonb_array_length(pg_temp.h('terima') -> 'periode'), 1);
select uji.sama('T2: file yang sama ditolak sebagai dobel', pg_temp.h('terima_dobel') ->> 'hasil', 'ditolak');
select uji.sama('T2: tap tidak bertambah', (select count(*) from fakta.tap_mentah)::int, 2);
select uji.sama('T9: bukan HRD ditolak oleh database', pg_temp.h('terima_bukan_hrd') ->> 'hasil', 'ditolak');
select uji.sama('T9: bukan HRD tidak tercatat sebagai kiriman', (select count(*) from fakta.kiriman_file where nama_file = 'x.csv')::int, 0);
select uji.sama('mesin tidak dikenal ditolak tanpa dicatat', pg_temp.h('terima_mesin_asing') ->> 'dicatat', 'false');
select uji.sama('T4: file ditolak pembaca dicatat dengan alasannya',
  (select hasil || ': ' || alasan from fakta.kiriman_file where nama_file = 'rusak.csv'), 'ditolak: No.ID rusak karena Excel');
select uji.sama('T7: file tertunda hanya bisa diambil HRD yang sama', pg_temp.h('ambil_orang_lain'), 'null'::jsonb);
select uji.sama('T7: file tertunda diambil sekali', (pg_temp.h('ambil') ->> 'file_id') || '/' || pg_temp.h('ambil_lagi'), 'F1/null');
select uji.sama('antrean: periode terkena dikerjakan (baca tap dan gaji)',
  (pg_temp.h('kerja1') -> 'periode' ->> 'id')::bigint = (select id from fakta.periode where tanggal_awal = '2026-03-21')
  and (pg_temp.h('kerja1') -> 'hasil' ->> 'orang')::int = 1, true);
select uji.sama('antrean: sesudah itu kosong', pg_temp.h('kerja2') ->> 'kosong', 'true');
select uji.sama('antrean: hasil gaji periode itu ada',
  exists (select 1 from hitung.versi_terakhir v join fakta.periode p on p.id = v.periode_id
          where v.jenis = 'hitung_gaji' and p.tanggal_awal = '2026-03-21'), true);
select uji.harus_ditolak('T10: peran pintu tidak bisa membaca tabel langsung', 'select * from fakta.kiriman_file', 'pintu');
select uji.harus_ditolak('T10: peran pintu tidak bisa mengubah data karyawan', 'delete from induk.karyawan', 'pintu');
select uji.harus_ditolak('T10: peran pintu tidak bisa menjalankan hitung langsung',
  'select hitung.baca_tap((select 1))', 'pintu');

rollback;
