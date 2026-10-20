-- =====================================================================
-- Administración y Finanzas · Tareas: se elimina la lista "Supervisión" (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_impuestos_proveedores.sql.
--
-- Qué hace (pedido de dirección): la lista "Supervisión" no va más.
--   · Plantilla: cada tarea de Supervisión que ya exista en Cierre mensual (mismo nombre) se borra; el resto pasa a
--     Cierre mensual (hoy: Informe CPS e Informe PROVEEDORES), al final de la lista.
--   · Meses abiertos: lo mismo con las tareas ya generadas (si en ese mes hay una igual en Cierre mensual, se borra;
--     si no, pasa a Cierre mensual).
--   · Lo borrado NO queda en el historial.
--   (No tiene que ver con "supervisión" como permiso — el tilde "Tareas · ver todas" — que sigue igual.)
-- No crea tablas ni cambia permisos.
-- =====================================================================

begin;

create or replace function pg_temp.nrm(t text) returns text language sql immutable as $f$
  select translate(lower(btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g'))), 'áéíóúü', 'aeiouu') $f$;

-- 1) Plantilla
create temp table _fij_dup on commit drop as
  select s.id from public.adminfin_tareas_fijas s
   where s.lista = 'Supervisión'
     and exists (select 1 from public.adminfin_tareas_fijas c where c.lista = 'Cierre mensual' and pg_temp.nrm(c.titulo) = pg_temp.nrm(s.titulo));
delete from public.adminfin_tareas_fijas where id in (select id from _fij_dup);
delete from public.adminfin_tareas_historial where tabla = 'fija' and accion = 'eliminada' and registro_id in (select id from _fij_dup);
-- las que quedan van al final de Cierre mensual (antes de la lista que sigue)
update public.adminfin_tareas_fijas f set lista = 'Cierre mensual',
       orden = (select max(orden) from public.adminfin_tareas_fijas where lista = 'Cierre mensual') + x.n
  from (select id, row_number() over (order by orden, id) n from public.adminfin_tareas_fijas where lista = 'Supervisión') x
 where x.id = f.id;
update public.adminfin_tareas_fijas f set orden = x.n * 10
  from (select id, row_number() over (order by orden, id) n from public.adminfin_tareas_fijas) x where x.id = f.id;

-- 2) Meses abiertos
create temp table _tar_dup on commit drop as
  select s.id from public.adminfin_tareas s
   where s.lista = 'Supervisión' and s.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null)
     and exists (select 1 from public.adminfin_tareas c where c.periodo = s.periodo and c.lista = 'Cierre mensual'
                   and pg_temp.nrm(c.titulo) = pg_temp.nrm(s.titulo));
delete from public.adminfin_tareas where id in (select id from _tar_dup);
delete from public.adminfin_tareas_historial where tabla = 'tarea' and accion = 'eliminada' and registro_id in (select id from _tar_dup);
update public.adminfin_tareas set lista = 'Cierre mensual'
 where lista = 'Supervisión' and periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);

-- control (antes del commit): lo que se borró por duplicado
select 'plantilla' as donde, count(*) as borradas_por_duplicado from _fij_dup
union all select 'meses abiertos', count(*) from _tar_dup;

commit;

-- Verificación: no tiene que quedar nada en "Supervisión" (plantilla ni meses abiertos)
select 'plantilla' as donde, count(*) as en_supervision from public.adminfin_tareas_fijas where lista = 'Supervisión'
union all
select 'meses abiertos', count(*) from public.adminfin_tareas
 where lista = 'Supervisión' and periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);
select lista, count(*) as tareas, count(*) filter (where activa) as activas from public.adminfin_tareas_fijas group by lista order by min(orden);
