-- =====================================================================
-- Administración y Finanzas · Tareas: a quién se puede asignar (incluye dirección) (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_historial.sql.
--
-- Para asignar / hacer responsable aparecen:
--   · quien tenga TILDADO "Tareas" (Ver) en Administración y Finanzas, en Usuarios del portal;
--   · dirección, si tiene agregada la app Administración y Finanzas (en el portal dirección no tiene tildes:
--     "ve y edita todo"; sacarle la app no le cambia el acceso, solo deja de aparecer en la lista).
-- =====================================================================

begin;

create or replace function public.adminfin_tareas_usuarios() returns table (id uuid, nombre text, email text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.adminfin_puede_ver('tareas') then return; end if;
  return query
    select p.id, p.nombre::text, p.email::text from public.perfiles p
     where p.activo and exists (select 1 from public.perfiles_sector ps where ps.perfil_id = p.id and ps.sector = 'adminfin'::public.sector_portal
             and (p.es_direccion or (jsonb_typeof(ps.permisos -> 'ver') = 'array' and (ps.permisos -> 'ver') ? 'tareas')))
     order by coalesce(p.nombre, p.email);
end $$;

commit;

-- Verificación: quiénes aparecen para asignar y por qué
select p.nombre, p.email, case when p.es_direccion then 'dirección con la app' else 'tilde Tareas' end as motivo
  from public.perfiles p join public.perfiles_sector ps on ps.perfil_id = p.id and ps.sector = 'adminfin'::public.sector_portal
 where p.activo and (p.es_direccion or (jsonb_typeof(ps.permisos -> 'ver') = 'array' and (ps.permisos -> 'ver') ? 'tareas'))
 order by 1;
