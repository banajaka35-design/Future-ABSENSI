-- Alat uji. Dipasang hanya di database uji, tidak pernah di Supabase.
create schema if not exists uji;

create table if not exists uji.hasil (
  nama text primary key,
  lulus boolean not null
);

create or replace function uji.catat(p_nama text, p_lulus boolean) returns void
language plpgsql as $$
begin
  insert into uji.hasil values (p_nama, p_lulus) on conflict (nama) do update set lulus = excluded.lulus;
  if p_lulus then
    raise notice 'LULUS  %', p_nama;
  else
    raise warning 'GAGAL  %', p_nama;
  end if;
end $$;

-- Lulus kalau perintah ditolak database.
create or replace function uji.harus_ditolak(p_nama text, p_sql text, p_peran text default null) returns void
language plpgsql as $$
begin
  begin
    if p_peran is not null then
      execute format('set local role %I', p_peran);
    end if;
    execute p_sql;
    if p_peran is not null then
      reset role;
    end if;
  exception when others then
    -- Hanya penolakan yang dimaksud yang dihitung lulus: aturan bisnis (P0001), batasan data (23xxx),
    -- atau akses ditolak (42501). Salah ketik atau tabel tidak ada tetap GAGAL.
    if sqlstate = 'P0001' or sqlstate = '42501' or sqlstate like '23%' then
      perform uji.catat(p_nama, true);
    else
      raise warning '   ditolak karena alasan lain (%): %', sqlstate, sqlerrm;
      perform uji.catat(p_nama, false);
    end if;
    return;
  end;
  perform uji.catat(p_nama, false);
end $$;

-- Lulus kalau perintah diterima.
create or replace function uji.harus_diterima(p_nama text, p_sql text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise warning '   alasan: %', sqlerrm;
    perform uji.catat(p_nama, false);
    return;
  end;
  perform uji.catat(p_nama, true);
end $$;

create or replace function uji.sama(p_nama text, p_hasil anyelement, p_harapan anyelement) returns void
language plpgsql as $$
begin
  if p_hasil is not distinct from p_harapan then
    perform uji.catat(p_nama, true);
  else
    raise warning '   hasil: %, harapan: %', p_hasil, p_harapan;
    perform uji.catat(p_nama, false);
  end if;
end $$;
