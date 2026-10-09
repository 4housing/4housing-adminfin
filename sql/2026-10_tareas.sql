-- =====================================================================
-- Administración y Finanzas · Tareas (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor.
--
-- Qué hace:
--   · adminfin_tareas: título, descripción, quién asigna, a quién, fecha, vencimiento y estado
--     (pendiente / en_curso / hecha).
--   · adminfin_tareas_comentarios y adminfin_tareas_adjuntos (los archivos van al bucket privado
--     "adminfin-tareas", carpeta = id de la tarea).
--   · adminfin_tareas_supervisores: los emails que ven TODAS las tareas. El resto del sector ve solo
--     las que le asignaron o las que creó.
--   · adminfin_tareas_usuarios(): lista de personas del sector Adm. y Finanzas (para "Asignar a").
--   Solo pueden usarlo usuarios con el sector adminfin (tiene_sector), como el resto del módulo.
--
-- Después de correrlo, cargá los supervisores (una línea por email), por ejemplo:
--   insert into public.adminfin_tareas_supervisores (email) values ('tu.mail@4housing.com.ar');
--
-- Reversible:
--   drop table public.adminfin_tareas_adjuntos, public.adminfin_tareas_comentarios, public.adminfin_tareas,
--              public.adminfin_tareas_supervisores;
--   drop function public.adminfin_tareas_usuarios(); drop function public.adminfin_tarea_visible(bigint);
--   drop function public.adminfin_tareas_es_supervisor();
--   (el bucket "adminfin-tareas" se borra desde Storage)
-- =====================================================================

begin;

create table if not exists public.adminfin_tareas_supervisores (
  email text primary key
);

create table if not exists public.adminfin_tareas (
  id             bigserial primary key,
  titulo         text not null,
  descripcion    text,
  asignado_por   uuid not null default auth.uid() references public.perfiles(id),
  asignado_a     uuid not null references public.perfiles(id),
  fecha          date not null default current_date,
  vencimiento    date,
  estado         text not null default 'pendiente' check (estado in ('pendiente','en_curso','hecha')),
  completada_en  timestamptz,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create index if not exists adminfin_tareas_asignado_a on public.adminfin_tareas (asignado_a);
create index if not exists adminfin_tareas_asignado_por on public.adminfin_tareas (asignado_por);

create table if not exists public.adminfin_tareas_comentarios (
  id        bigserial primary key,
  tarea_id  bigint not null references public.adminfin_tareas(id) on delete cascade,
  autor     uuid not null default auth.uid() references public.perfiles(id),
  texto     text not null,
  creado_en timestamptz not null default now()
);
create index if not exists adminfin_tareas_com_tarea on public.adminfin_tareas_comentarios (tarea_id);

create table if not exists public.adminfin_tareas_adjuntos (
  id         bigserial primary key,
  tarea_id   bigint not null references public.adminfin_tareas(id) on delete cascade,
  path       text not null,          -- ruta en el bucket adminfin-tareas: <tarea_id>/<archivo>
  nombre     text not null,
  tamano     bigint,
  subido_por uuid not null default auth.uid() references public.perfiles(id),
  creado_en  timestamptz not null default now()
);
create index if not exists adminfin_tareas_adj_tarea on public.adminfin_tareas_adjuntos (tarea_id);

-- (plpgsql: el cuerpo se valida al usarse, no al crearse; así no depende del orden en que el editor ejecute el script)
-- ¿El usuario actual es supervisor (ve todas las tareas)?
create or replace function public.adminfin_tareas_es_supervisor() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return exists (select 1 from public.adminfin_tareas_supervisores s join public.perfiles p on lower(p.email) = lower(s.email)
                 where p.id = auth.uid());
end $$;

-- ¿El usuario actual puede ver la tarea? (supervisor, asignado o quien la creó)
create or replace function public.adminfin_tarea_visible(p_tarea bigint) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.tiene_sector('adminfin'::public.sector_portal) and exists (
    select 1 from public.adminfin_tareas t where t.id = p_tarea
      and (public.adminfin_tareas_es_supervisor() or t.asignado_a = auth.uid() or t.asignado_por = auth.uid()));
end $$;

-- Personas del sector Adm. y Finanzas (y dirección), para elegir a quién asignar
create or replace function public.adminfin_tareas_usuarios() returns table (id uuid, nombre text, email text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.tiene_sector('adminfin'::public.sector_portal) then return; end if;
  return query
    select p.id, p.nombre::text, p.email::text from public.perfiles p
     where p.activo
       and (p.es_direccion or exists (select 1 from public.perfiles_sector ps where ps.perfil_id = p.id and ps.sector = 'adminfin'::public.sector_portal))
     order by coalesce(p.nombre, p.email);
end $$;

-- Fecha de actualización / de cierre automáticas
create or replace function public.adminfin_tareas_touch() returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  if new.estado = 'hecha' and (tg_op = 'INSERT' or old.estado is distinct from 'hecha') then new.completada_en := now(); end if;
  if new.estado <> 'hecha' then new.completada_en := null; end if;
  return new;
end $$;
drop trigger if exists adminfin_tareas_touch on public.adminfin_tareas;
create trigger adminfin_tareas_touch before insert or update on public.adminfin_tareas
  for each row execute function public.adminfin_tareas_touch();

-- Permisos
alter table public.adminfin_tareas_supervisores enable row level security;
alter table public.adminfin_tareas enable row level security;
alter table public.adminfin_tareas_comentarios enable row level security;
alter table public.adminfin_tareas_adjuntos enable row level security;
revoke all on public.adminfin_tareas_supervisores, public.adminfin_tareas, public.adminfin_tareas_comentarios, public.adminfin_tareas_adjuntos from anon;
grant select on public.adminfin_tareas_supervisores to authenticated;
grant select, insert, update, delete on public.adminfin_tareas, public.adminfin_tareas_comentarios, public.adminfin_tareas_adjuntos to authenticated;
grant usage, select on sequence public.adminfin_tareas_id_seq, public.adminfin_tareas_comentarios_id_seq, public.adminfin_tareas_adjuntos_id_seq to authenticated;
grant execute on function public.adminfin_tareas_es_supervisor(), public.adminfin_tarea_visible(bigint), public.adminfin_tareas_usuarios() to authenticated;

drop policy if exists adminfin_tsup_sel on public.adminfin_tareas_supervisores;
create policy adminfin_tsup_sel on public.adminfin_tareas_supervisores for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));

drop policy if exists adminfin_tar_sel on public.adminfin_tareas;
drop policy if exists adminfin_tar_ins on public.adminfin_tareas;
drop policy if exists adminfin_tar_upd on public.adminfin_tareas;
drop policy if exists adminfin_tar_del on public.adminfin_tareas;
create policy adminfin_tar_sel on public.adminfin_tareas for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal)
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or asignado_por = auth.uid()));
create policy adminfin_tar_ins on public.adminfin_tareas for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal) and asignado_por = auth.uid());
-- quien la creó y los supervisores editan todo; el asignado también puede actualizarla (la app le deja cambiar el estado)
create policy adminfin_tar_upd on public.adminfin_tareas for update to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal)
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or asignado_por = auth.uid()))
  with check (public.tiene_sector('adminfin'::public.sector_portal)
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or asignado_por = auth.uid()));
create policy adminfin_tar_del on public.adminfin_tareas for delete to authenticated
  using (public.adminfin_tareas_es_supervisor() or asignado_por = auth.uid());

drop policy if exists adminfin_tcom_sel on public.adminfin_tareas_comentarios;
drop policy if exists adminfin_tcom_ins on public.adminfin_tareas_comentarios;
drop policy if exists adminfin_tcom_del on public.adminfin_tareas_comentarios;
create policy adminfin_tcom_sel on public.adminfin_tareas_comentarios for select to authenticated using (public.adminfin_tarea_visible(tarea_id));
create policy adminfin_tcom_ins on public.adminfin_tareas_comentarios for insert to authenticated
  with check (public.adminfin_tarea_visible(tarea_id) and autor = auth.uid());
create policy adminfin_tcom_del on public.adminfin_tareas_comentarios for delete to authenticated
  using (autor = auth.uid() or public.adminfin_tareas_es_supervisor());

drop policy if exists adminfin_tadj_sel on public.adminfin_tareas_adjuntos;
drop policy if exists adminfin_tadj_ins on public.adminfin_tareas_adjuntos;
drop policy if exists adminfin_tadj_del on public.adminfin_tareas_adjuntos;
create policy adminfin_tadj_sel on public.adminfin_tareas_adjuntos for select to authenticated using (public.adminfin_tarea_visible(tarea_id));
create policy adminfin_tadj_ins on public.adminfin_tareas_adjuntos for insert to authenticated
  with check (public.adminfin_tarea_visible(tarea_id) and subido_por = auth.uid());
create policy adminfin_tadj_del on public.adminfin_tareas_adjuntos for delete to authenticated
  using (subido_por = auth.uid() or public.adminfin_tareas_es_supervisor());

-- Archivos: bucket privado; carpeta = id de la tarea. Se accede si se puede ver la tarea.
insert into storage.buckets (id, name, public) values ('adminfin-tareas', 'adminfin-tareas', false)
  on conflict (id) do nothing;
drop policy if exists adminfin_tareas_obj_sel on storage.objects;
drop policy if exists adminfin_tareas_obj_ins on storage.objects;
drop policy if exists adminfin_tareas_obj_del on storage.objects;
create policy adminfin_tareas_obj_sel on storage.objects for select to authenticated
  using (bucket_id = 'adminfin-tareas' and case when (storage.foldername(name))[1] ~ '^\d+$'
         then public.adminfin_tarea_visible(((storage.foldername(name))[1])::bigint) else false end);
create policy adminfin_tareas_obj_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'adminfin-tareas' and case when (storage.foldername(name))[1] ~ '^\d+$'
              then public.adminfin_tarea_visible(((storage.foldername(name))[1])::bigint) else false end);
create policy adminfin_tareas_obj_del on storage.objects for delete to authenticated
  using (bucket_id = 'adminfin-tareas' and case when (storage.foldername(name))[1] ~ '^\d+$'
         then public.adminfin_tarea_visible(((storage.foldername(name))[1])::bigint) else false end);

commit;

-- Verificación: las 4 tablas con RLS activa (true) y el bucket creado
select relname, relrowsecurity from pg_class where relname in ('adminfin_tareas','adminfin_tareas_comentarios','adminfin_tareas_adjuntos','adminfin_tareas_supervisores') order by 1;
select id, public from storage.buckets where id = 'adminfin-tareas';
