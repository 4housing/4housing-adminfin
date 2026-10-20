-- =====================================================================
-- Administración y Finanzas · Tareas: fecha de cumplido (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_impuestos_registro_2habiles.sql.
--
-- Qué hace (pedido de dirección):
--   · adminfin_tareas.fecha_cumplido: el día en que se cumplió una tarea de Cierre de mes (o varias). La app propone la
--     fecha del día al marcarla "Cumplido"; si se carga otra, avisa y deja el comentario "⚠ Fecha distinta a la del día".
--     Quien puede cambiar el estado la puede cargar.
--   · El índice (a tiempo / fuera de término) usa esa fecha; si no está, el día en que se marcó (como antes).
-- No cambia datos existentes.
-- =====================================================================

begin;

alter table public.adminfin_tareas add column if not exists fecha_cumplido date;

-- quien no es supervisión: estados y fechas (presentación, pago, registro, cumplido)
create or replace function public.adminfin_tareas_guard_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.adminfin_tareas_es_supervisor() or auth.uid() is null then return new; end if;   -- sin usuario = SQL Editor
  if tg_op = 'INSERT' and new.periodo is not null then
    raise exception 'Solo supervisión puede agregar tareas del mes';
  end if;
  if tg_op = 'UPDATE' and old.periodo is not null
     and (to_jsonb(new) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'fecha_registro' - 'fecha_presentacion' - 'fecha_cumplido' - 'actualizado_en')
         is distinct from (to_jsonb(old) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'fecha_registro' - 'fecha_presentacion' - 'fecha_cumplido' - 'actualizado_en') then
    raise exception 'Solo supervisión puede modificar o transferir tareas del mes (podés cambiar el estado)';
  end if;
  return new;
end $$;

create or replace function public.adminfin_tareas_fecha_cumplida(t public.adminfin_tareas) returns date
language sql stable set search_path = public as $$
  select case when t.estado = 'hecha' and coalesce(t.reg_estado, 'hecha') = 'hecha' then
    coalesce(
      case when t.lista ilike 'impuesto%' then greatest(case when coalesce(t.req_presentacion, false) then t.fecha_presentacion end,
                                                       case when coalesce(t.req_pago, true) then t.fecha_pago end,
                                                       case when coalesce(t.req_registro, true) then t.fecha_registro end)
           when t.lista ilike 'proveedor%' then greatest(t.fecha_registro, t.fecha_pago) end,
      greatest(coalesce(t.fecha_cumplido, (t.completada_en at time zone 'America/Argentina/Buenos_Aires')::date),
               (t.reg_completada_en at time zone 'America/Argentina/Buenos_Aires')::date))
  end $$;

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
    else case when (t.vencimiento is null or coalesce(t.fecha_cumplido, (t.completada_en at time zone 'America/Argentina/Buenos_Aires')::date) <= t.vencimiento)
               and (t.reg_estado is null or t.reg_vencimiento is null
                    or (t.reg_completada_en at time zone 'America/Argentina/Buenos_Aires')::date <= t.reg_vencimiento)
              then 'tiempo' else 'tarde' end
  end $$;

commit;

-- Verificación
select column_name from information_schema.columns where table_name = 'adminfin_tareas' and column_name = 'fecha_cumplido';
