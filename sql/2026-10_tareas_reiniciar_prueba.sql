-- =====================================================================
-- Tareas · REINICIAR LA PRUEBA de septiembre 2026 (opcional). Correr A MANO, completo.
-- Borra el mes "Cierre septiembre 2026" y TODAS sus tareas (con sus comentarios y adjuntos; quedan en el historial).
-- Después se vuelve a abrir desde la app (Tareas del mes → Abrir mes) y se genera con la plantilla actual.
-- No toca la plantilla ni otros meses.
-- =====================================================================
begin;
delete from public.adminfin_tareas where periodo = '2026-09';
delete from public.adminfin_tareas_meses where periodo = '2026-09';
commit;

-- Verificación: tiene que dar 0 y 0
select (select count(*) from public.adminfin_tareas where periodo = '2026-09') as tareas_sep,
       (select count(*) from public.adminfin_tareas_meses where periodo = '2026-09') as mes_sep;
