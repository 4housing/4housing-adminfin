-- =====================================================================
-- Administración y Finanzas · Tareas: un solo vencimiento en Impuestos y el mes abierto con la plantilla actual (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_huerfanas.sql.
--
-- Qué hace (pedido de dirección):
--   1) Impuestos: presentar, pagar y registrar vencen el MISMO día (el vto impositivo). En la plantilla el vto es
--      "Vto de pago / impositivo" (dia_registro); si un impuesto no lo tenía, toma el que tenía como "Vence".
--      El vencimiento de la tarea (registro) pasa a ser ese mismo día.
--   2) Mes abierto (hoy, cierre septiembre 2026): las tareas generadas desde la plantilla toman los vencimientos y
--      responsables de la plantilla actual (Cierre mensual por N° día hábil del mes siguiente, Impuestos, Proveedores)
--      y su nombre (bancos y tarjetas: "· Conciliar").
--      NO cambia estados, fechas de pago / registro ni comentarios. Si una tarea se transfirió, sigue con quien la tiene.
--   3) Agrega al mes abierto las tareas de la plantilla que le faltan (proveedores nuevos, "· Cargar FAC de gastos" de
--      bancos y tarjetas). Si a alguna tarea fija activa le falta responsable o vencimiento, no agrega ninguna y lo dice
--      en el resultado (completarlas en Tareas fijas y volver a correr este SQL: no duplica nada).
--   Los vencimientos por día hábil usan los feriados cargados en la app (Tareas fijas → Feriados).
-- =====================================================================

begin;

-- 1) Impuestos: un solo vencimiento
update public.adminfin_tareas_fijas
   set dia_registro  = coalesce(dia_registro, dia_vence),
       tipo_registro = case when dia_registro is null then tipo_vence else tipo_registro end,
       mes_registro  = case when dia_registro is null then mes_vence  else mes_registro end
 where lista ilike 'impuesto%';
update public.adminfin_tareas_fijas set dia_vence = dia_registro, tipo_vence = tipo_registro, mes_vence = mes_registro
 where lista ilike 'impuesto%' and dia_registro is not null;

create or replace function public.adminfin_tareas_generar(p_periodo text, p_fija bigint default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int; nf int; nombres text;
begin
  select count(*), string_agg(titulo, ', ' order by orden) into nf, nombres
    from public.adminfin_tareas_fijas where activa and (p_fija is null or id = p_fija)
     and (responsable is null or dia_vence is null or (lista ilike 'impuesto%' and dia_registro is null));
  if nf > 0 then
    raise exception 'Faltan responsable, día de vencimiento o vto de pago (Impuestos) en % tarea(s) fija(s): %', nf, left(nombres, 300);
  end if;
  insert into public.adminfin_tareas (titulo, descripcion, asignado_por, asignado_a, responsable, fecha, vencimiento, estado,
                                      periodo, fija_id, lista, repeticion, reg_vencimiento, reg_responsable, reg_estado,
                                      req_presentacion, req_pago, req_registro)
  select f.titulo || case when f.veces > 1 then ' (' || r || '/' || f.veces || ')' else '' end, f.descripcion,
         auth.uid(), f.responsable, f.responsable, to_date(p_periodo || '-01', 'YYYY-MM-DD'),
         -- Impuestos: un solo vencimiento (presentar, pagar y registrar): el del vto impositivo
         case when f.lista ilike 'impuesto%' and f.dia_registro is not null
              then public.adminfin_tareas_vence2(p_periodo, f.dia_registro, f.tipo_registro, f.mes_registro)
              else public.adminfin_tareas_vence2(p_periodo, f.dia_vence, f.tipo_vence, f.mes_vence) end, 'pendiente', p_periodo, f.id, f.lista, r,
         public.adminfin_tareas_vence2(p_periodo, f.dia_registro, f.tipo_registro, f.mes_registro),
         case when f.dia_registro is not null then coalesce(f.responsable_registro, f.responsable) end,
         -- Impuestos sin pago requerido: la etapa de pago nace resuelta (no traba el cierre)
         case when f.dia_registro is not null then case when f.lista ilike 'impuesto%' and not f.req_pago then 'hecha' else 'pendiente' end end,
         case when f.lista ilike 'impuesto%' then f.req_presentacion end, case when f.lista ilike 'impuesto%' then f.req_pago end,
         case when f.lista ilike 'impuesto%' then f.req_registro end
    from public.adminfin_tareas_fijas f cross join lateral generate_series(1, f.veces) r
   where f.activa and (p_fija is null or f.id = p_fija)
   order by f.orden, r
  on conflict (periodo, fija_id, repeticion) where fija_id is not null do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.adminfin_tareas_generar(text, bigint) from public, anon, authenticated;

-- 2) Mes abierto: vencimientos y responsables de la plantilla actual
update public.adminfin_tareas t
   set vencimiento = case when f.lista ilike 'impuesto%' and f.dia_registro is not null
                          then public.adminfin_tareas_vence2(t.periodo, f.dia_registro, f.tipo_registro, f.mes_registro)
                          else public.adminfin_tareas_vence2(t.periodo, f.dia_vence, f.tipo_vence, f.mes_vence) end,
       reg_vencimiento = case when t.reg_estado is not null and f.dia_registro is not null
                              then public.adminfin_tareas_vence2(t.periodo, f.dia_registro, f.tipo_registro, f.mes_registro)
                              else t.reg_vencimiento end,
       reg_responsable = case when t.reg_estado is not null then coalesce(f.responsable_registro, f.responsable) else t.reg_responsable end,
       asignado_a = case when t.asignado_a is not distinct from coalesce(t.responsable, t.asignado_a) then coalesce(f.responsable, t.asignado_a) else t.asignado_a end,
       responsable = coalesce(f.responsable, t.responsable),
       lista = f.lista,
       -- mismo nombre que la plantilla (ej. "Banco Ciudad" → "Banco Ciudad · Conciliar")
       titulo = f.titulo || case when f.veces > 1 then ' (' || t.repeticion || '/' || f.veces || ')' else '' end
  from public.adminfin_tareas_fijas f
 where t.fija_id = f.id
   and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);

-- 3) Lo que le falta al mes abierto (generar necesita un usuario: se usa el de dirección micaela@ como "asignada por")
create temp table _gen (periodo text, agregadas int, error text) on commit drop;
do $$
declare p text; n int;
begin
  perform set_config('request.jwt.claim.sub', (select id::text from public.perfiles where lower(email) = 'micaela@4housing.com.ar'), true);
  for p in select periodo from public.adminfin_tareas_meses where cerrado_en is null loop
    begin
      n := public.adminfin_tareas_generar(p, null);
      insert into _gen values (p, n, null);
    exception when others then
      insert into _gen values (p, 0, sqlerrm);
    end;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
select * from _gen;

commit;

-- Verificación: el mes abierto ordenado por vencimiento
select t.periodo, t.lista, t.titulo, (select email from public.perfiles p where p.id = t.asignado_a) as asignada_a, t.vencimiento,
       t.reg_vencimiento as vto_impositivo, t.estado
  from public.adminfin_tareas t
 where t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null)
 order by t.vencimiento nulls last, t.lista, t.titulo;
