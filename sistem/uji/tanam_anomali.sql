-- Uji U10: menanam tiga anomali di salinan database uji Pabrik B (bukan data simulasi, bukan generator),
-- di periode April 2026, lalu menghitung ulang baca tap dan gaji April dan Desember.
--   gaji_berubah        satu karyawan Produksi naik gaji pokok 50% mulai 1 Apr (seperti salah ketik HRD)
--   lembur_divisi_naik  semua lembur Gudang April disetujui sekaligus (seperti persetujuan massal)
--   aktif_tanpa_tap     satu karyawan Produksi diubah menjadi tidak wajib tap dan ID mesinnya ditutup (karyawan fiktif)
-- Yang ditanam dicatat di public.tanam_anomali supaya pemeriksaannya tidak menebak.
begin;
set local app.pengguna = 'uji-anomali';

create table public.tanam_anomali (jenis text primary key, kunci text not null, sebelum boolean);

-- Karyawan Produksi yang aktif sepanjang Februari-Desember dengan satu riwayat yang masih terbuka.
create temp table calon on commit drop as
select r.id_karyawan, row_number() over (order by r.id_karyawan) as urut
from induk.karyawan_riwayat r
where r.divisi = 'PRD' and r.berlaku_dari < '2026-02-01' and r.berlaku_sampai is null and r.wajib_tap
  and not exists (select 1 from induk.status_kerja s where s.id_karyawan = r.id_karyawan and s.jenis = 'berhenti')
  and (select count(*) from induk.karyawan_riwayat r2 where r2.id_karyawan = r.id_karyawan) = 1;

insert into public.tanam_anomali (jenis, kunci)
select 'gaji_berubah', id_karyawan from calon where urut = 1
union all select 'aktif_tanpa_tap', id_karyawan from calon where urut = 2
union all select 'lembur_divisi_naik', 'GDG';

-- Keadaan sebelum ditanam (uji bermakna hanya bila belum ada tanda).
update public.tanam_anomali t set sebelum = exists (
  select 1 from hitung.anomali_gaji((select id from fakta.periode where tanggal_awal = '2026-04-01')) a
  where a.jenis = t.jenis and (a.id_karyawan = t.kunci or a.divisi = t.kunci));

-- 1. Gaji pokok naik 50%.
update induk.karyawan_riwayat set berlaku_sampai = '2026-04-01'
where id_karyawan = (select kunci from public.tanam_anomali where jenis = 'gaji_berubah') and berlaku_sampai is null;
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap, ptkp,
                                    cara_bayar, wajib_tap, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan)
select id_karyawan, '2026-04-01', divisi, jabatan, tipe_upah, gaji_pokok * 3 / 2, tunjangan_tetap, ptkp,
       cara_bayar, wajib_tap, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan
from induk.karyawan_riwayat
where id_karyawan = (select kunci from public.tanam_anomali where jenis = 'gaji_berubah') and berlaku_sampai = '2026-04-01';

-- 2. Semua lembur Gudang April disetujui.
insert into fakta.perintah_hrd (asal, jenis, divisi, tanggal_mulai, tanggal_selesai, alasan)
values ('file', 'setujui_lembur', 'GDG', '2026-04-01', '2026-04-30', 'uji U10: persetujuan massal');

-- 3. Karyawan fiktif: tidak wajib tap dan ID mesinnya ditutup mulai 1 Apr.
update induk.karyawan_riwayat set berlaku_sampai = '2026-04-01'
where id_karyawan = (select kunci from public.tanam_anomali where jenis = 'aktif_tanpa_tap') and berlaku_sampai is null;
insert into induk.karyawan_riwayat (id_karyawan, berlaku_dari, divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap, ptkp,
                                    cara_bayar, wajib_tap, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan)
select id_karyawan, '2026-04-01', divisi, jabatan, tipe_upah, gaji_pokok, tunjangan_tetap, ptkp,
       cara_bayar, false, gaji_rahasia, bpjs_kesehatan, bpjs_ketenagakerjaan
from induk.karyawan_riwayat
where id_karyawan = (select kunci from public.tanam_anomali where jenis = 'aktif_tanpa_tap') and berlaku_sampai = '2026-04-01';
update induk.pemetaan_id_mesin set berlaku_sampai = '2026-04-01'
where id_karyawan = (select kunci from public.tanam_anomali where jenis = 'aktif_tanpa_tap') and berlaku_sampai is null;

commit;

select count(hitung.baca_tap(id)) from fakta.periode where tanggal_awal >= '2026-04-01';
select hitung.hitung_gaji(id) from fakta.periode where tanggal_awal >= '2026-04-01' order by tanggal_awal;
