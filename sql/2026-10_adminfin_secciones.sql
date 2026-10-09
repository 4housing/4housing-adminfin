-- =====================================================================
-- Administración y Finanzas · permisos por sección desde el portal (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas.sql.
--
-- Qué hace:
--   La app publica sus secciones en la pantalla de Usuarios del portal (admin.html → SECCIONES.adminfin):
--     solicitudes  · Solicitudes de pago
--     cuy          · Contabilidad UY
--     tareas       · Tareas (Ver = ve las suyas · Editar = crea y asigna)
--     tareas_todas · Tareas · ver todas (supervisión)
--   Los tildes Ver / Editar se guardan en perfiles_sector.permisos (como en el resto del portal).
--   · adminfin_puede_ver(seccion) / adminfin_puede_editar(seccion): mismo criterio que el portal
--     (dirección = todo; sin listas guardadas = ve todo salvo "tareas_todas"; Solo visión no edita).
--   · Tareas pasa a usar esos permisos (incluso en la base): quién ve todas = tilde "Tareas · ver todas".
--     Reemplaza a la tabla adminfin_tareas_supervisores, que se borra.
--
-- Reversible: volver a correr sql/2026-10_tareas.sql (recrea la tabla de supervisores y las funciones anteriores).
-- =====================================================================

begin;

-- ¿El usuario actual ve / edita esta sección de Adm. y Finanzas?
create or replace function public.adminfin_puede_ver(p_sec text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.es_direccion() or exists (
    select 1 from public.perfiles p join public.perfiles_sector ps on ps.perfil_id = p.id
     where p.id = auth.uid() and p.activo and ps.sector = 'adminfin'::public.sector_portal
       and case when jsonb_typeof(ps.permisos -> 'ver') = 'array' then (ps.permisos -> 'ver') ? p_sec
                else p_sec <> 'tareas_todas' end);
end $$;

create or replace function public.adminfin_puede_editar(p_sec text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.es_direccion() or exists (
    select 1 from public.perfiles p join public.perfiles_sector ps on ps.perfil_id = p.id
     where p.id = auth.uid() and p.activo and ps.sector = 'adminfin'::public.sector_portal
       and lower(coalesce(ps.cargo, '')) not in ('lector', 'lectura')
       and case when jsonb_typeof(ps.permisos -> 'ver') = 'array' then (ps.permisos -> 'ver') ? p_sec else p_sec <> 'tareas_todas' end
       and case when jsonb_typeof(ps.permisos -> 'editar') = 'array' then (ps.permisos -> 'editar') ? p_sec
                else lower(coalesce(ps.cargo, '')) <> 'editor' and p_sec <> 'tareas_todas' end);
end $$;

-- Supervisión de tareas = tilde "Tareas · ver todas" en el portal (o dirección)
create or replace function public.adminfin_tareas_es_supervisor() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.adminfin_puede_ver('tareas_todas');
end $$;

create or replace function public.adminfin_tarea_visible(p_tarea bigint) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.adminfin_puede_ver('tareas') and exists (
    select 1 from public.adminfin_tareas t where t.id = p_tarea
      and (public.adminfin_tareas_es_supervisor() or t.asignado_a = auth.uid() or t.asignado_por = auth.uid()));
end $$;

-- A quién se puede asignar: activos que ven la sección Tareas (dirección incluida)
create or replace function public.adminfin_tareas_usuarios() returns table (id uuid, nombre text, email text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.adminfin_puede_ver('tareas') then return; end if;
  return query
    select p.id, p.nombre::text, p.email::text from public.perfiles p
     where p.activo
       and (p.es_direccion or exists (select 1 from public.perfiles_sector ps where ps.perfil_id = p.id and ps.sector = 'adminfin'::public.sector_portal
             and case when jsonb_typeof(ps.permisos -> 'ver') = 'array' then (ps.permisos -> 'ver') ? 'tareas' else true end))
     order by coalesce(p.nombre, p.email);
end $$;

revoke all on function public.adminfin_puede_ver(text), public.adminfin_puede_editar(text) from public, anon;
grant execute on function public.adminfin_puede_ver(text), public.adminfin_puede_editar(text) to authenticated;

-- Tareas: ver = sección "tareas"; crear = editar "tareas"
drop policy if exists adminfin_tar_sel on public.adminfin_tareas;
drop policy if exists adminfin_tar_ins on public.adminfin_tareas;
drop policy if exists adminfin_tar_upd on public.adminfin_tareas;
drop policy if exists adminfin_tar_del on public.adminfin_tareas;
create policy adminfin_tar_sel on public.adminfin_tareas for select to authenticated
  using (public.adminfin_puede_ver('tareas')
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or asignado_por = auth.uid()));
create policy adminfin_tar_ins on public.adminfin_tareas for insert to authenticated
  with check (public.adminfin_puede_editar('tareas') and asignado_por = auth.uid());
-- el asignado también puede actualizarla (la app le deja cambiar el estado); quien la creó / supervisión, todo
create policy adminfin_tar_upd on public.adminfin_tareas for update to authenticated
  using (public.adminfin_puede_ver('tareas')
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or asignado_por = auth.uid()))
  with check (public.adminfin_puede_ver('tareas')
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or asignado_por = auth.uid()));
create policy adminfin_tar_del on public.adminfin_tareas for delete to authenticated
  using (public.adminfin_tareas_es_supervisor() or asignado_por = auth.uid());

-- Ya no hace falta la tabla propia de supervisores (se gestiona desde el portal)
drop table if exists public.adminfin_tareas_supervisores;

commit;

-- Verificación: tienen que aparecer adminfin_puede_editar y adminfin_puede_ver
-- (en el SQL Editor no hay usuario logueado, por eso no se prueban los permisos acá: se ven en la app)
select proname from pg_proc where proname in ('adminfin_puede_ver', 'adminfin_puede_editar') order by 1;
