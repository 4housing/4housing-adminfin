-- =====================================================================
-- Administración y Finanzas · Tareas: cerrar el mes ya no genera el siguiente (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_fecha_cumplido.sql.
--
-- Qué hace (pedido de dirección): cerrar el mes guarda el índice y cierra, pero NO abre el mes siguiente ni genera sus
-- tareas. Así, entre el cierre y el mes nuevo se puede revisar la plantilla (exportar / importar Excel). El mes nuevo se
-- genera desde la app ("Generar tareas de …" = adminfin_tareas_abrir_mes, que ya existía).
-- Devuelve la cantidad de tareas que quedaron sin cumplir al cierre.
-- =====================================================================

begin;

create or replace function public.adminfin_tareas_cerrar_mes(p_periodo text) returns int
language plpgsql security definer set search_path = public as $$
declare sin int;
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
  select coalesce(sum(sin_cumplir), 0) into sin from public.adminfin_tareas_indices where periodo = p_periodo;
  return sin;
end $$;
revoke all on function public.adminfin_tareas_cerrar_mes(text) from public, anon;
grant execute on function public.adminfin_tareas_cerrar_mes(text) to authenticated;

commit;

-- Verificación: la función ya no llama a generar
select position('adminfin_tareas_generar' in prosrc) = 0 as no_genera from pg_proc where proname = 'adminfin_tareas_cerrar_mes';
