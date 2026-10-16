-- =====================================================================
-- Administración y Finanzas · Tareas: Impuestos, Proveedores (pagado + fecha), bancos y tarjetas en 2 tareas (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_vencimientos.sql.
--
-- Qué hace:
--   · adminfin_tareas.fecha_pago: fecha en que se pagó (Proveedores, y el vto de pago de Impuestos).
--     Quien no es supervisión la puede cargar (junto con el estado).
--   · Lista "Impuestos": pasan ahí las tareas fijas "Pago y Registro …" (AGIP, ARBA, Sicore, SUSS, CM, IVA).
--     En esa lista el vto de pago es obligatorio para generar el mes.
--   · Se borran de la plantilla las "Conciliacion Excel …" (duplicaban a los bancos). Quedan en el historial.
--   · Bancos y tarjetas (Cierre mensual: "Banco …" y "TC …") pasan a 2 tareas: "· Cargar FAC de gastos" y "· Conciliar"
--     (misma configuración; la de cargar FAC va primero).
--   · El orden de la plantilla se renumera de 10 en 10 (para poder subir / bajar tareas desde la app).
--   Las tareas del mes ya generado (septiembre de prueba) NO cambian: ver sql/2026-10_tareas_reiniciar_prueba.sql.
-- =====================================================================

begin;

alter table public.adminfin_tareas add column if not exists fecha_pago date;

-- quien no es supervisión: estados y fecha de pago
create or replace function public.adminfin_tareas_guard_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.adminfin_tareas_es_supervisor() or auth.uid() is null then return new; end if;   -- sin usuario = SQL Editor
  if tg_op = 'INSERT' and new.periodo is not null then
    raise exception 'Solo supervisión puede agregar tareas del mes';
  end if;
  if tg_op = 'UPDATE' and old.periodo is not null
     and (to_jsonb(new) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'actualizado_en')
         is distinct from (to_jsonb(old) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'actualizado_en') then
    raise exception 'Solo supervisión puede modificar o transferir tareas del mes (podés cambiar el estado)';
  end if;
  return new;
end $$;

-- generar: en Impuestos el vto de pago es obligatorio
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

-- el orden de la plantilla (subir / bajar) no se registra en el historial
create or replace function public.adminfin_tareas_hist_trg() returns trigger
language plpgsql security definer set search_path = public as $$
declare t text := case when tg_table_name = 'adminfin_tareas_fijas' then 'fija' else 'tarea' end; a jsonb; d jsonb;
begin
  if tg_op = 'DELETE' then
    insert into public.adminfin_tareas_historial (tabla, registro_id, accion, antes, extra)
    values (t, old.id, 'eliminada', to_jsonb(old),
      case when t = 'tarea' then jsonb_build_object(
        'comentarios', coalesce((select jsonb_agg(to_jsonb(c) order by c.id) from public.adminfin_tareas_comentarios c where c.tarea_id = old.id), '[]'::jsonb),
        'adjuntos',    coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from public.adminfin_tareas_adjuntos x where x.tarea_id = old.id), '[]'::jsonb)) end);
    return old;
  end if;
  a := to_jsonb(old) - 'actualizado_en' - 'fija_id' - 'orden'; d := to_jsonb(new) - 'actualizado_en' - 'fija_id' - 'orden';
  if a is distinct from d then
    insert into public.adminfin_tareas_historial (tabla, registro_id, accion, antes, despues) values (t, new.id, 'modificada', to_jsonb(old), to_jsonb(new));
  end if;
  return new;
end $$;

-- 1) Impuestos
update public.adminfin_tareas_fijas set lista = 'Impuestos' where titulo ilike 'Pago y Registro %' and lista <> 'Impuestos';

-- 2) Fuera las "Conciliacion Excel …" (quedan archivadas en el historial)
delete from public.adminfin_tareas_fijas where titulo ilike 'Conciliacion Excel %';

-- 3) Orden de 10 en 10
update public.adminfin_tareas_fijas f set orden = x.n * 10
  from (select id, row_number() over (order by orden, id) n from public.adminfin_tareas_fijas) x where x.id = f.id;

-- 4) Bancos y tarjetas: "· Cargar FAC de gastos" (nueva, va antes) y "· Conciliar" (la existente)
insert into public.adminfin_tareas_fijas (lista, titulo, descripcion, responsable, dia_vence, veces, orden, activa,
       dia_registro, responsable_registro, tipo_vence, mes_vence, tipo_registro, mes_registro)
select lista, titulo || ' · Cargar FAC de gastos', descripcion, responsable, dia_vence, veces, orden - 5, activa,
       dia_registro, responsable_registro, tipo_vence, mes_vence, tipo_registro, mes_registro
  from public.adminfin_tareas_fijas
 where lista = 'Cierre mensual' and (titulo ilike 'Banco %' or titulo ilike 'TC %') and titulo not like '% · %';
update public.adminfin_tareas_fijas set titulo = titulo || ' · Conciliar'
 where lista = 'Cierre mensual' and (titulo ilike 'Banco %' or titulo ilike 'TC %') and titulo not like '% · %';

commit;

-- Verificación: tareas fijas por lista
select lista, count(*) as tareas, count(*) filter (where activa) as activas from public.adminfin_tareas_fijas group by lista order by min(orden);
