-- =====================================================================
-- Administración y Finanzas · Tareas: borrar del mes abierto las tareas que ya no están en la plantilla (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_sin_supervision.sql.
--
-- Qué hace (pedido de dirección):
--   En los meses ABIERTOS borra las tareas que se generaron desde la plantilla y cuya tarea fija ya se borró
--   (ej. "Conciliacion Excel …", "Informe imputación contable Mensual", proveedores sacados de la lista).
--   Se reconocen porque vinieron de la plantilla (tienen n° de repetición) y ya no tienen tarea fija.
--   Solo las que NO están cumplidas (son las que traban el cierre); las cumplidas quedan como constancia.
--   NO toca las agregadas a mano ("Agregar tarea al mes" / puntuales), ni meses cerrados.
--   Se borran con sus comentarios y adjuntos y NO quedan en el historial.
--   (Los archivos adjuntos, si los hubiera, quedan en el bucket "adminfin-tareas"; no se ven desde la app.)
-- No se puede deshacer.
-- =====================================================================

begin;

create temp table _huerfanas on commit drop as
  select t.id, t.periodo, t.lista, t.titulo, t.estado
    from public.adminfin_tareas t
   where t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null)
     and t.fija_id is null and t.repeticion is not null
     and (t.estado <> 'hecha' or coalesce(t.reg_estado, 'hecha') <> 'hecha');   -- las cumplidas quedan (constancia, ej. un pago hecho)

-- control (antes de borrar): qué se borra
select periodo, lista, titulo, estado from _huerfanas order by periodo, lista, titulo;

delete from public.adminfin_tareas where id in (select id from _huerfanas);
delete from public.adminfin_tareas_historial where tabla = 'tarea' and accion = 'eliminada' and registro_id in (select id from _huerfanas);

commit;

-- Verificación: tiene que dar 0
select count(*) as huerfanas_sin_cumplir from public.adminfin_tareas
 where periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null) and fija_id is null and repeticion is not null
   and (estado <> 'hecha' or coalesce(reg_estado, 'hecha') <> 'hecha');
