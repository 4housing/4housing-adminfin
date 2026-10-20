-- =====================================================================
-- Administración y Finanzas · Tareas: índice mensual (a tiempo / fuera de término / sin cumplir al cierre) (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_impuestos_tres_pasos.sql
-- y ANTES de publicar el index.html con la pestaña "Índice mensual".
--
-- Qué hace (pedido de dirección):
--   · Cerrar el mes ya NO exige todo cumplido: supervisión lo cierra y en ese momento se guarda la foto del índice
--     (adminfin_tareas_indices: por mes, lista y responsable → total, a tiempo, fuera de término, sin cumplir al
--     cierre, y cuántas tienen una fecha cargada a mano). La foto no cambia después.
--     Las que quedaron sin cumplir siguen en ese mes y se pueden cumplir después (cuentan fuera de término en la app;
--     el índice guardado no cambia).
--   · Fecha de cumplimiento: Impuestos y Proveedores, la última fecha de sus pasos (la que se cargó; la app propone la
--     del día y, si se pone otra, deja el aviso "⚠ Fecha distinta a la del día"); el resto, el día en que se marcó
--     cumplida (y su etapa de pago, si tiene). En término = esa fecha <= vencimiento.
--   · adminfin_tareas_clase(tarea): 'tiempo' | 'tarde' | 'sin' — la misma regla para la foto y para consultar.
--   · Lectura: supervisión ve todo el índice; el resto, sus propias filas. Nadie lo edita a mano.
--
-- Reversible:
--   drop table public.adminfin_tareas_indices; drop function public.adminfin_tareas_clase(public.adminfin_tareas),
--   public.adminfin_tareas_fecha_cumplida(public.adminfin_tareas);
--   y volver a correr la función adminfin_tareas_cerrar_mes de sql/2026-10_tareas_registro.sql.
-- =====================================================================

begin;

create table if not exists public.adminfin_tareas_indices (
  id             bigserial primary key,
  periodo        text not null,
  lista          text not null,
  responsable    uuid references public.perfiles(id),
  total          int not null,
  a_tiempo       int not null,
  fuera_termino  int not null,
  sin_cumplir    int not null,
  fecha_manual   int not null default 0,    -- tareas con algún "⚠ Fecha distinta a la del día" (para auditar)
  cerrado_en     timestamptz not null default now(),
  cerrado_por    uuid references public.perfiles(id)
);
create unique index if not exists adminfin_tareas_indices_uk
  on public.adminfin_tareas_indices (periodo, lista, coalesce(responsable, '00000000-0000-0000-0000-000000000000'::uuid));
alter table public.adminfin_tareas_indices enable row level security;
revoke all on public.adminfin_tareas_indices from anon;
grant select on public.adminfin_tareas_indices to authenticated;           -- se escribe solo desde la función de cierre
drop policy if exists adminfin_tind_sel on public.adminfin_tareas_indices;
create policy adminfin_tind_sel on public.adminfin_tareas_indices for select to authenticated
  using (public.adminfin_tareas_es_supervisor() or responsable = auth.uid());

-- Fecha en que se cumplió (null si no está cumplida)
create or replace function public.adminfin_tareas_fecha_cumplida(t public.adminfin_tareas) returns date
language sql stable set search_path = public as $$
  select case when t.estado = 'hecha' and coalesce(t.reg_estado, 'hecha') = 'hecha' then
    coalesce(
      case when t.lista ilike 'impuesto%' then greatest(case when coalesce(t.req_presentacion, false) then t.fecha_presentacion end,
                                                       case when coalesce(t.req_pago, true) then t.fecha_pago end,
                                                       case when coalesce(t.req_registro, true) then t.fecha_registro end)
           when t.lista ilike 'proveedor%' then greatest(t.fecha_registro, t.fecha_pago) end,
      greatest((t.completada_en at time zone 'America/Argentina/Buenos_Aires')::date,
               (t.reg_completada_en at time zone 'America/Argentina/Buenos_Aires')::date))
  end $$;

-- 'tiempo' | 'tarde' | 'sin'
create or replace function public.adminfin_tareas_clase(t public.adminfin_tareas) returns text
language sql stable set search_path = public as $$
  select case
    when public.adminfin_tareas_fecha_cumplida(t) is null then 'sin'
    when t.lista ilike 'impuesto%' or t.lista ilike 'proveedor%'
      then case when t.vencimiento is null or public.adminfin_tareas_fecha_cumplida(t) <= t.vencimiento then 'tiempo' else 'tarde' end
    else case when (t.vencimiento is null or (t.completada_en at time zone 'America/Argentina/Buenos_Aires')::date <= t.vencimiento)
               and (t.reg_estado is null or t.reg_vencimiento is null
                    or (t.reg_completada_en at time zone 'America/Argentina/Buenos_Aires')::date <= t.reg_vencimiento)
              then 'tiempo' else 'tarde' end
  end $$;

-- Cerrar el mes: se puede con pendientes; guarda la foto del índice y abre el siguiente
create or replace function public.adminfin_tareas_cerrar_mes(p_periodo text) returns int
language plpgsql security definer set search_path = public as $$
declare sig text;
begin
  if not public.adminfin_tareas_es_supervisor() then raise exception 'Solo supervisión puede cerrar el mes'; end if;
  if not exists (select 1 from public.adminfin_tareas_meses where periodo = p_periodo and cerrado_en is null) then
    raise exception 'El mes % no está abierto', p_periodo; end if;
  delete from public.adminfin_tareas_indices where periodo = p_periodo;
  insert into public.adminfin_tareas_indices (periodo, lista, responsable, total, a_tiempo, fuera_termino, sin_cumplir, fecha_manual, cerrado_por)
  select p_periodo, coalesce(x.lista, 'Sin lista'), x.resp, count(*),
         count(*) filter (where x.clase = 'tiempo'), count(*) filter (where x.clase = 'tarde'), count(*) filter (where x.clase = 'sin'),
         count(*) filter (where x.manual), auth.uid()
    from (select t.lista, coalesce(t.responsable, t.asignado_a) as resp, public.adminfin_tareas_clase(t) as clase,
                 exists (select 1 from public.adminfin_tareas_comentarios c where c.tarea_id = t.id and c.texto like '⚠ Fecha distinta a la del día%') as manual
            from public.adminfin_tareas t where t.periodo = p_periodo) x
   group by coalesce(x.lista, 'Sin lista'), x.resp;
  update public.adminfin_tareas_meses set cerrado_en = now(), cerrado_por = auth.uid() where periodo = p_periodo;
  sig := to_char(to_date(p_periodo || '-01', 'YYYY-MM-DD') + interval '1 month', 'YYYY-MM');
  insert into public.adminfin_tareas_meses (periodo, abierto_por) values (sig, auth.uid()) on conflict (periodo) do update set cerrado_en = null, cerrado_por = null;
  return public.adminfin_tareas_generar(sig, null);
end $$;
revoke all on function public.adminfin_tareas_cerrar_mes(text) from public, anon;
grant execute on function public.adminfin_tareas_cerrar_mes(text) to authenticated;

commit;

-- Verificación: cómo quedaría hoy el índice del mes abierto (no guarda nada)
select t.periodo, coalesce(t.lista, 'Sin lista') as lista, count(*) as total,
       count(*) filter (where public.adminfin_tareas_clase(t) = 'tiempo') as a_tiempo,
       count(*) filter (where public.adminfin_tareas_clase(t) = 'tarde') as fuera_termino,
       count(*) filter (where public.adminfin_tareas_clase(t) = 'sin') as sin_cumplir
  from public.adminfin_tareas t
 where t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null)
 group by 1, 2 order by 1, 2;
