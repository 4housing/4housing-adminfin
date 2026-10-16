-- =====================================================================
-- Administración y Finanzas · Tareas fijas: vencimientos por día fijo o día hábil, en el mes siguiente al cierre (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_registro.sql.
--
-- Qué hace:
--   · Cada tarea fija (y su registro contable) vence:
--       - "día fijo": ese día del mes (si cae sábado, domingo o feriado → siguiente día hábil), o
--       - "día hábil": el N° día hábil del mes (lunes a viernes sin feriados).
--   · Mes del vencimiento: el SIGUIENTE al mes de cierre (por defecto) o el mismo.
--     Ej.: Control Ingresos Alquileres · 1er día hábil · mes siguiente → cierre de septiembre 2026 vence el 01/10/26.
--   · adminfin_feriados: feriados que no cuentan como hábiles (se cargan desde la app, en Tareas fijas).
--   · Las tareas ya generadas no cambian; vale para los meses que se abran de acá en adelante.
--
-- Reversible:
--   alter table public.adminfin_tareas_fijas drop column tipo_vence, drop column mes_vence, drop column tipo_registro, drop column mes_registro;
--   drop function public.adminfin_tareas_vence2(text, int, text, int); drop table public.adminfin_feriados;
--   (y volver a correr 2026-10_tareas_registro.sql)
-- =====================================================================

begin;

alter table public.adminfin_tareas_fijas add column if not exists tipo_vence text not null default 'dia' check (tipo_vence in ('dia','habil'));
alter table public.adminfin_tareas_fijas add column if not exists mes_vence int not null default 1 check (mes_vence in (0, 1));
alter table public.adminfin_tareas_fijas add column if not exists tipo_registro text not null default 'dia' check (tipo_registro in ('dia','habil'));
alter table public.adminfin_tareas_fijas add column if not exists mes_registro int not null default 1 check (mes_registro in (0, 1));

create table if not exists public.adminfin_feriados (
  fecha  date primary key,
  nombre text
);
alter table public.adminfin_feriados enable row level security;
revoke all on public.adminfin_feriados from anon;
grant select, insert, update, delete on public.adminfin_feriados to authenticated;
drop policy if exists adminfin_fer_sel on public.adminfin_feriados;
drop policy if exists adminfin_fer_all on public.adminfin_feriados;
create policy adminfin_fer_sel on public.adminfin_feriados for select to authenticated using (public.adminfin_puede_ver('tareas'));
create policy adminfin_fer_all on public.adminfin_feriados for all to authenticated
  using (public.adminfin_tareas_es_supervisor()) with check (public.adminfin_tareas_es_supervisor());

-- Vencimiento: p_periodo = mes de cierre (AAAA-MM); p_mes = 0 mismo mes / 1 mes siguiente
create or replace function public.adminfin_tareas_vence2(p_periodo text, p_dia int, p_tipo text, p_mes int) returns date
language plpgsql stable security definer set search_path = public as $$
declare d0 date; v date; n int := 0;
begin
  if p_dia is null then return null; end if;
  d0 := (to_date(p_periodo || '-01', 'YYYY-MM-DD') + make_interval(months => coalesce(p_mes, 1)))::date;
  if p_tipo = 'habil' then
    v := d0;
    loop
      if extract(isodow from v) < 6 and not exists (select 1 from public.adminfin_feriados f where f.fecha = v) then
        n := n + 1; exit when n >= p_dia;
      end if;
      v := v + 1;
    end loop;
    return v;
  end if;
  v := d0 + (least(p_dia, extract(day from (d0 + interval '1 month' - interval '1 day'))::int) - 1);
  while extract(isodow from v) >= 6 or exists (select 1 from public.adminfin_feriados f where f.fecha = v) loop v := v + 1; end loop;
  return v;
end $$;

create or replace function public.adminfin_tareas_generar(p_periodo text, p_fija bigint default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int; nf int; nombres text;
begin
  select count(*), string_agg(titulo, ', ' order by orden) into nf, nombres
    from public.adminfin_tareas_fijas where activa and (p_fija is null or id = p_fija) and (responsable is null or dia_vence is null);
  if nf > 0 then
    raise exception 'Faltan responsable o día de vencimiento en % tarea(s) fija(s): %', nf, left(nombres, 300);
  end if;
  insert into public.adminfin_tareas (titulo, descripcion, asignado_por, asignado_a, responsable, fecha, vencimiento, estado,
                                      periodo, fija_id, lista, repeticion, reg_vencimiento, reg_responsable, reg_estado)
  select f.titulo || case when f.veces > 1 then ' (' || r || '/' || f.veces || ')' else '' end, f.descripcion,
         auth.uid(), f.responsable, f.responsable, to_date(p_periodo || '-01', 'YYYY-MM-DD'),
         public.adminfin_tareas_vence2(p_periodo, f.dia_vence, f.tipo_vence, f.mes_vence), 'pendiente', p_periodo, f.id, f.lista, r,
         public.adminfin_tareas_vence2(p_periodo, f.dia_registro, f.tipo_registro, f.mes_registro),
         case when f.dia_registro is not null then coalesce(f.responsable_registro, f.responsable) end,
         case when f.dia_registro is not null then 'pendiente' end
    from public.adminfin_tareas_fijas f cross join lateral generate_series(1, f.veces) r
   where f.activa and (p_fija is null or f.id = p_fija)
   order by f.orden, r
  on conflict (periodo, fija_id, repeticion) where fija_id is not null do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.adminfin_tareas_generar(text, bigint) from public, anon, authenticated;
grant execute on function public.adminfin_tareas_vence2(text, int, text, int) to authenticated;

commit;

-- Verificación: ejemplos con el cierre de septiembre 2026 (vencen en octubre)
select '1er día hábil' as regla, public.adminfin_tareas_vence2('2026-09', 1, 'habil', 1) as vence   -- jueves 01/10/26
union all select '5° día hábil', public.adminfin_tareas_vence2('2026-09', 5, 'habil', 1)           -- miércoles 07/10/26
union all select 'día 10 fijo',  public.adminfin_tareas_vence2('2026-09', 10, 'dia', 1)            -- sábado → lunes 12/10/26
union all select 'día 20, mismo mes', public.adminfin_tareas_vence2('2026-09', 20, 'dia', 0);      -- domingo → lunes 21/09/26
