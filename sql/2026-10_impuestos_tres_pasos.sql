-- =====================================================================
-- Administración y Finanzas · Impuestos: todos con Presentado, Pagado y Registrado (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_septiembre.sql.
--
-- Qué hace (pedido de dirección):
--   1) Plantilla: los 6 impuestos requieren presentación, pago y registro contable (Sicore y SUSS también).
--      Los tildes quedan en la plantilla para impuestos que se sumen más adelante (ej. anuales).
--   2) Meses abiertos: los impuestos ya generados toman los tres pasos y se acomodan a sus fechas:
--      · si se marcó "Registrado" con el selector anterior (sin fecha), la fecha de registro es el día en que se marcó;
--      · pago según la fecha de pago; la tarea queda cumplida solo con las tres fechas (con alguna, "En gestión").
-- =====================================================================

begin;

update public.adminfin_tareas_fijas set req_presentacion = true, req_pago = true, req_registro = true
 where lista ilike 'impuesto%';

update public.adminfin_tareas t
   set req_presentacion = true, req_pago = true, req_registro = true,
       fecha_registro = coalesce(t.fecha_registro, case when t.estado = 'hecha' then (t.completada_en at time zone 'America/Argentina/Buenos_Aires')::date end)
 where t.lista ilike 'impuesto%' and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);

update public.adminfin_tareas t
   set reg_estado = case when t.reg_estado is null then null when t.fecha_pago is not null then 'hecha' else 'pendiente' end,
       estado = case when t.fecha_presentacion is not null and t.fecha_pago is not null and t.fecha_registro is not null then 'hecha'
                     when coalesce(t.fecha_presentacion, t.fecha_pago, t.fecha_registro) is not null then 'en_curso'
                     else 'pendiente' end
 where t.lista ilike 'impuesto%' and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);

commit;

-- Verificación: los 6 con los tres pasos, y cómo queda cada impuesto del mes abierto
select titulo, req_presentacion as presentacion, req_pago as pago, req_registro as registro from public.adminfin_tareas_fijas
 where lista ilike 'impuesto%' order by orden;
select periodo, titulo, fecha_presentacion as presentado, fecha_pago as pagado, fecha_registro as registrado, estado
  from public.adminfin_tareas
 where lista ilike 'impuesto%' and periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null)
 order by vencimiento, titulo;
