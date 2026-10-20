-- =====================================================================
-- Administración y Finanzas · Impuestos (fecha de registro contable) y lista Proveedores actualizada (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_tipos.sql,
-- y ANTES de publicar el index.html con la solapa "Impuestos".
--
-- Qué hace:
--   1) adminfin_tareas.fecha_registro: fecha del registro contable (Impuestos: "Pago y Registro …").
--      Quien no es supervisión la puede cargar, igual que el estado y la fecha de pago.
--   2) Plantilla, lista "Proveedores" (según "Gastos de Estructura 202610", OCs con período por varios meses):
--      · Se sacan: POGGIO, GALA y los que no tienen OC mensual (PRINCI, POYSE, ICON, EXPENSAS, STAR, TIRAVA,
--        RAZQUI, CABIFY, EDENRE, PANAME, DELMAR). Quedan archivados en el historial (se pueden ver ahí).
--      · Se agregan 15: ARAAGU, BERGER, BINASE, CACMI, CAISSA, CHINNI, CLARO, EPEN, IPLAN, METEL, NOSIS, REPCON, RSV,
--        SEGUME, SPWORK. Activas, responsable administracion@ (Carranza, A.), vencen el 5° día hábil del mes
--        siguiente al cierre. Si un proveedor ya está en la lista (mismo nombre), no se duplica.
--   Las tareas del mes ya abierto NO cambian (las de los proveedores sacados siguen ahí; las nuevas aparecen desde el
--   próximo mes que se abra, o supervisión las suma con "Agregar tarea al mes").
--
-- Reversible:
--   alter table public.adminfin_tareas drop column fecha_registro;   (y volver a correr la función guard de 2026-10_tareas_tipos.sql)
--   Proveedores: restaurar desde "Historial y eliminadas" / borrar los agregados desde Tareas fijas.
-- =====================================================================

begin;

alter table public.adminfin_tareas add column if not exists fecha_registro date;

-- quien no es supervisión: estados, fecha de pago y fecha de registro
create or replace function public.adminfin_tareas_guard_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.adminfin_tareas_es_supervisor() or auth.uid() is null then return new; end if;   -- sin usuario = SQL Editor
  if tg_op = 'INSERT' and new.periodo is not null then
    raise exception 'Solo supervisión puede agregar tareas del mes';
  end if;
  if tg_op = 'UPDATE' and old.periodo is not null
     and (to_jsonb(new) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'fecha_registro' - 'actualizado_en')
         is distinct from (to_jsonb(old) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'fecha_registro' - 'actualizado_en') then
    raise exception 'Solo supervisión puede modificar o transferir tareas del mes (podés cambiar el estado)';
  end if;
  return new;
end $$;

-- Proveedores que salen de la plantilla
delete from public.adminfin_tareas_fijas
 where lista = 'Proveedores' and upper(btrim(titulo)) in ('POGGIO','GALA','PRINCI','POYSE','ICON','EXPENSAS','STAR','TIRAVA','RAZQUI','CABIFY','EDENRE','PANAME','DELMAR');

-- Proveedores nuevos (al final de la lista, de 10 en 10)
-- primero se hace lugar: lo que viene después de Proveedores en la plantilla baja 150 (15 tareas × 10)
update public.adminfin_tareas_fijas set orden = orden + 150
 where orden > (select max(orden) from public.adminfin_tareas_fijas where lista = 'Proveedores');
insert into public.adminfin_tareas_fijas (lista, titulo, descripcion, responsable, dia_vence, tipo_vence, mes_vence, veces, orden, activa)
select 'Proveedores', v.titulo, v.descripcion, p.id, 5, 'habil', 1, 1,
       coalesce((select max(orden) from public.adminfin_tareas_fijas where lista = 'Proveedores'),
                (select max(orden) from public.adminfin_tareas_fijas), 0) + v.n * 10, true
  from (values
    ('ARAAGU', 'Seguridad · Servicio de seguridad / vigilancia', 1),
    ('BERGER', 'Alquileres · Alquiler oficina comercial', 2),
    ('BINASE', 'Medicina Prepaga · Administración', 3),
    ('CACMI', 'Gasto comercial · Cuota CACMI', 4),
    ('CAISSA', 'Gasto publicidad · Servicio de marketing', 5),
    ('CHINNI', 'Gastos mantenimiento módulos · Comisiones módulos', 6),
    ('CLARO', 'Teléfono · Telefonía celular', 7),
    ('EPEN', 'Energía eléctrica · Base Neuquén', 8),
    ('IPLAN', 'Teléfono · Telefonía fija', 9),
    ('METEL', 'Teléfono · Internet', 10),
    ('NOSIS', 'Licencias · Servicio de informes', 11),
    ('REPCON', 'Gastos mantenimiento reefer', 12),
    ('RSV', 'Rodados · Rastreo satelital', 13),
    ('SEGUME', 'Seguridad · Servicio de seguridad', 14),
    ('SPWORK', 'Alquileres · Alquiler base Neuquén', 15)
  ) as v(titulo, descripcion, n)
  left join public.perfiles p on lower(p.email) = 'administracion@4housing.com.ar'
 where not exists (select 1 from public.adminfin_tareas_fijas f where f.lista = 'Proveedores' and upper(btrim(f.titulo)) = v.titulo);

commit;

-- Verificación: la columna nueva, y la lista Proveedores (tienen que quedar 27 si la lista estaba como en el alta inicial;
-- "sin_responsable" tiene que ser 0 para los nuevos: si no, administracion@ no tiene perfil en el portal)
select column_name from information_schema.columns where table_name = 'adminfin_tareas' and column_name = 'fecha_registro';
select count(*) as proveedores, count(*) filter (where responsable is null) as sin_responsable,
       string_agg(titulo, ', ' order by orden) as lista
  from public.adminfin_tareas_fijas where lista = 'Proveedores';
