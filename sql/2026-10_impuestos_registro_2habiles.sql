-- =====================================================================
-- Administración y Finanzas · Impuestos: registro contable a 2 días hábiles del vto (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_indice.sql.
--
-- Qué hace (pedido de dirección), para TODOS los impuestos:
--   · Presentación y pago vencen el día del vto impositivo (reg_vencimiento).
--   · El registro contable vence 2 días hábiles después del vto (vencimiento de la tarea). Hábil = lunes a viernes
--     sin los feriados cargados en la app.
--   · Generación del mes y meses abiertos con esa regla.
--   · Índice: un impuesto está a tiempo si se presentó y pagó hasta el vto y se registró hasta vto + 2 hábiles.
--   adminfin_mas_habiles(fecha, n): fecha + n días hábiles.
-- =====================================================================

begin;

create or replace function public.adminfin_mas_habiles(p_fecha date, p_n int) returns date
language plpgsql stable security definer set search_path = public as $$
declare d date := p_fecha; k int := 0;
begin
  if p_fecha is null then return null; end if;
  while k < coalesce(p_n, 0) loop
    d := d + 1;
    if extract(isodow from d) < 6 and not exists (select 1 from public.adminfin_feriados where fecha = d) then k := k + 1; end if;
  end loop;
  return d;
end $$;
grant execute on function public.adminfin_mas_habiles(date, int) to authenticated;

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
         -- Impuestos: el registro contable vence 2 días hábiles después del vto (presentación y pago = el vto)
         case when f.lista ilike 'impuesto%' and f.dia_registro is not null
              then public.adminfin_mas_habiles(public.adminfin_tareas_vence2(p_periodo, f.dia_registro, f.tipo_registro, f.mes_registro), 2)
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

-- Meses abiertos: vto (presentación y pago) y registro a vto + 2 hábiles
update public.adminfin_tareas t
   set reg_vencimiento = public.adminfin_tareas_vence2(t.periodo, f.dia_registro, f.tipo_registro, f.mes_registro),
       vencimiento = public.adminfin_mas_habiles(public.adminfin_tareas_vence2(t.periodo, f.dia_registro, f.tipo_registro, f.mes_registro), 2)
  from public.adminfin_tareas_fijas f
 where t.fija_id = f.id and f.lista ilike 'impuesto%' and f.dia_registro is not null
   and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);

-- Índice: impuestos a tiempo = presentado y pagado hasta el vto, registrado hasta vto + 2 hábiles
create or replace function public.adminfin_tareas_clase(t public.adminfin_tareas) returns text
language sql stable set search_path = public as $$
  select case
    when public.adminfin_tareas_fecha_cumplida(t) is null then 'sin'
    when t.lista ilike 'impuesto%'
      then case when (t.reg_vencimiento is null or coalesce(greatest(case when coalesce(t.req_presentacion, false) then t.fecha_presentacion end,
                                                                          case when coalesce(t.req_pago, true) then t.fecha_pago end), t.reg_vencimiento) <= t.reg_vencimiento)
                 and (t.vencimiento is null or not coalesce(t.req_registro, true) or t.fecha_registro is null or t.fecha_registro <= t.vencimiento)
                then 'tiempo' else 'tarde' end
    when t.lista ilike 'proveedor%'
      then case when t.vencimiento is null or public.adminfin_tareas_fecha_cumplida(t) <= t.vencimiento then 'tiempo' else 'tarde' end
    else case when (t.vencimiento is null or (t.completada_en at time zone 'America/Argentina/Buenos_Aires')::date <= t.vencimiento)
               and (t.reg_estado is null or t.reg_vencimiento is null
                    or (t.reg_completada_en at time zone 'America/Argentina/Buenos_Aires')::date <= t.reg_vencimiento)
              then 'tiempo' else 'tarde' end
  end $$;

commit;

-- Verificación: impuestos de los meses abiertos
select periodo, titulo, reg_vencimiento as vto_presentacion_y_pago, vencimiento as vto_registro
  from public.adminfin_tareas
 where lista ilike 'impuesto%' and periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null)
 order by reg_vencimiento, titulo;
