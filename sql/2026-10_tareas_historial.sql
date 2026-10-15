-- =====================================================================
-- Administración y Finanzas · Tareas: historial (archivo de eliminadas y cambios) y permisos de supervisión (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_fijas.sql.
--
-- Qué hace:
--   · adminfin_tareas_historial: cada modificación o eliminación de una tarea o de una tarea fija queda registrada
--     (quién, cuándo, cómo estaba antes y cómo quedó). Las tareas eliminadas se archivan con sus comentarios y
--     adjuntos y se pueden restaurar (adminfin_tareas_restaurar). Solo supervisión lo ve; nadie lo puede editar.
--   · Eliminar tareas: solo supervisión (tilde "Tareas · ver todas"). Antes también podía quien la creó.
--   · Tareas del mes (las que tienen período): solo supervisión las agrega, modifica o transfiere. El resto solo
--     cambia el estado (y comenta / adjunta).
--   · La plantilla de tareas fijas ya era solo de supervisión.
--   · A quién se puede asignar / hacer responsable: solo quien tenga TILDADO "Tareas" (Ver) en Adm. y Finanzas en la
--     pantalla Usuarios del portal. Antes entraba todo el que tuviera el sector (o dirección) aunque no lo tuviera tildado.
--
-- Reversible:
--   drop trigger adminfin_tareas_guard on public.adminfin_tareas; drop trigger adminfin_tareas_hist_del on public.adminfin_tareas;
--   drop trigger adminfin_tareas_hist_upd on public.adminfin_tareas; drop trigger adminfin_tareas_fijas_hist_upd on public.adminfin_tareas_fijas;
--   drop trigger adminfin_tareas_fijas_hist_del on public.adminfin_tareas_fijas;
--   drop function public.adminfin_tareas_restaurar(bigint), public.adminfin_tareas_hist_trg(), public.adminfin_tareas_guard_trg();
--   drop table public.adminfin_tareas_historial;   (y volver a correr la política adminfin_tar_del de 2026-10_adminfin_secciones.sql)
-- =====================================================================

begin;

create table if not exists public.adminfin_tareas_historial (
  id          bigserial primary key,
  tabla       text not null check (tabla in ('tarea','fija')),
  registro_id bigint not null,
  accion      text not null check (accion in ('modificada','eliminada','restaurada')),
  antes       jsonb,
  despues     jsonb,
  extra       jsonb,              -- eliminadas: comentarios y adjuntos que tenía
  usuario     uuid default auth.uid(),
  cuando      timestamptz not null default now(),
  restaurada  boolean not null default false
);
create index if not exists adminfin_tareas_hist_reg on public.adminfin_tareas_historial (tabla, registro_id);

-- Registro de cambios / eliminaciones (BEFORE DELETE: así todavía están los comentarios y adjuntos)
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
  -- UPDATE: se registra solo si cambió algo más que la fecha de actualización (o el vínculo a una fija borrada)
  a := to_jsonb(old) - 'actualizado_en' - 'fija_id'; d := to_jsonb(new) - 'actualizado_en' - 'fija_id';
  if a is distinct from d then
    insert into public.adminfin_tareas_historial (tabla, registro_id, accion, antes, despues) values (t, new.id, 'modificada', to_jsonb(old), to_jsonb(new));
  end if;
  return new;
end $$;
drop trigger if exists adminfin_tareas_hist_del on public.adminfin_tareas;
create trigger adminfin_tareas_hist_del before delete on public.adminfin_tareas for each row execute function public.adminfin_tareas_hist_trg();
drop trigger if exists adminfin_tareas_hist_upd on public.adminfin_tareas;
create trigger adminfin_tareas_hist_upd after update on public.adminfin_tareas for each row execute function public.adminfin_tareas_hist_trg();
drop trigger if exists adminfin_tareas_fijas_hist_del on public.adminfin_tareas_fijas;
create trigger adminfin_tareas_fijas_hist_del before delete on public.adminfin_tareas_fijas for each row execute function public.adminfin_tareas_hist_trg();
drop trigger if exists adminfin_tareas_fijas_hist_upd on public.adminfin_tareas_fijas;
create trigger adminfin_tareas_fijas_hist_upd after update on public.adminfin_tareas_fijas for each row execute function public.adminfin_tareas_hist_trg();

-- Tareas del mes: solo supervisión agrega o modifica; el resto solo cambia el estado
create or replace function public.adminfin_tareas_guard_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.adminfin_tareas_es_supervisor() or auth.uid() is null then return new; end if;   -- sin usuario = SQL Editor
  if tg_op = 'INSERT' and new.periodo is not null then
    raise exception 'Solo supervisión puede agregar tareas del mes';
  end if;
  if tg_op = 'UPDATE' and old.periodo is not null
     and (to_jsonb(new) - 'estado' - 'completada_en' - 'actualizado_en') is distinct from (to_jsonb(old) - 'estado' - 'completada_en' - 'actualizado_en') then
    raise exception 'Solo supervisión puede modificar o transferir tareas del mes (podés cambiar el estado)';
  end if;
  return new;
end $$;
drop trigger if exists adminfin_tareas_guard on public.adminfin_tareas;
create trigger adminfin_tareas_guard before insert or update on public.adminfin_tareas for each row execute function public.adminfin_tareas_guard_trg();

-- Eliminar tareas: solo supervisión
drop policy if exists adminfin_tar_del on public.adminfin_tareas;
create policy adminfin_tar_del on public.adminfin_tareas for delete to authenticated using (public.adminfin_tareas_es_supervisor());

-- Restaurar una tarea (con sus comentarios y adjuntos) o una tarea fija eliminada
create or replace function public.adminfin_tareas_restaurar(p_hist bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare h public.adminfin_tareas_historial;
begin
  if not public.adminfin_tareas_es_supervisor() then raise exception 'Solo supervisión puede restaurar'; end if;
  select * into h from public.adminfin_tareas_historial where id = p_hist and accion = 'eliminada';
  if not found then raise exception 'No está en el archivo de eliminadas'; end if;
  if h.restaurada then raise exception 'Ya fue restaurada'; end if;
  if h.tabla = 'fija' then
    insert into public.adminfin_tareas_fijas select * from jsonb_populate_record(null::public.adminfin_tareas_fijas, h.antes);
  else
    insert into public.adminfin_tareas select * from jsonb_populate_record(null::public.adminfin_tareas, h.antes);
    insert into public.adminfin_tareas_comentarios select * from jsonb_populate_recordset(null::public.adminfin_tareas_comentarios, coalesce(h.extra -> 'comentarios', '[]'));
    insert into public.adminfin_tareas_adjuntos select * from jsonb_populate_recordset(null::public.adminfin_tareas_adjuntos, coalesce(h.extra -> 'adjuntos', '[]'));
  end if;
  update public.adminfin_tareas_historial set restaurada = true where id = p_hist;
  insert into public.adminfin_tareas_historial (tabla, registro_id, accion, despues) values (h.tabla, h.registro_id, 'restaurada', h.antes);
  return h.registro_id;
end $$;

alter table public.adminfin_tareas_historial enable row level security;
revoke all on public.adminfin_tareas_historial from anon, authenticated;
grant select on public.adminfin_tareas_historial to authenticated;
drop policy if exists adminfin_thist_sel on public.adminfin_tareas_historial;
create policy adminfin_thist_sel on public.adminfin_tareas_historial for select to authenticated using (public.adminfin_tareas_es_supervisor());
revoke all on function public.adminfin_tareas_restaurar(bigint), public.adminfin_tareas_hist_trg(), public.adminfin_tareas_guard_trg() from public, anon;
grant execute on function public.adminfin_tareas_restaurar(bigint) to authenticated;

-- A quién se puede asignar: activos con "Tareas" tildado explícitamente en el portal (Ver)
create or replace function public.adminfin_tareas_usuarios() returns table (id uuid, nombre text, email text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.adminfin_puede_ver('tareas') then return; end if;
  return query
    select p.id, p.nombre::text, p.email::text from public.perfiles p
     where p.activo and exists (select 1 from public.perfiles_sector ps where ps.perfil_id = p.id and ps.sector = 'adminfin'::public.sector_portal
             and jsonb_typeof(ps.permisos -> 'ver') = 'array' and (ps.permisos -> 'ver') ? 'tareas')
     order by coalesce(p.nombre, p.email);
end $$;

commit;

-- Verificación 1: quiénes van a aparecer para asignar (tendrían que ser Carranza, Quiencke, Cittar y Seoane)
select p.nombre, p.email from public.perfiles p join public.perfiles_sector ps on ps.perfil_id = p.id and ps.sector = 'adminfin'::public.sector_portal
 where p.activo and jsonb_typeof(ps.permisos -> 'ver') = 'array' and (ps.permisos -> 'ver') ? 'tareas' order by 1;

-- Verificación 2: tienen que aparecer los 5 triggers
select tgname from pg_trigger where tgname in ('adminfin_tareas_hist_del','adminfin_tareas_hist_upd','adminfin_tareas_fijas_hist_del',
  'adminfin_tareas_fijas_hist_upd','adminfin_tareas_guard') order by 1;
