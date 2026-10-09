-- =====================================================================
-- Administración y Finanzas · Tareas: responsable y transferencias (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- sql/2026-10_tareas.sql y sql/2026-10_adminfin_secciones.sql.
--
-- Qué hace:
--   · Columna "responsable" en adminfin_tareas: quien responde por la tarea. No cambia al transferirla;
--     "asignado_a" es quien la está haciendo. Las tareas existentes toman como responsable a su asignado.
--   · El responsable ve y puede actualizar la tarea aunque ya no sea el asignado (y sus comentarios / adjuntos).
--   · adminfin_tarea_transferir(tarea, a, nota): transfiere y deja el comentario automático.
--
-- Reversible:
--   alter table public.adminfin_tareas drop column responsable;   (y volver a correr 2026-10_adminfin_secciones.sql)
-- =====================================================================

begin;

alter table public.adminfin_tareas add column if not exists responsable uuid references public.perfiles(id);
update public.adminfin_tareas set responsable = asignado_a where responsable is null;
create index if not exists adminfin_tareas_responsable on public.adminfin_tareas (responsable);

-- Si no viene el responsable, es el asignado
create or replace function public.adminfin_tareas_responsable_def() returns trigger language plpgsql as $$
begin
  if new.responsable is null then new.responsable := new.asignado_a; end if;
  return new;
end $$;
drop trigger if exists adminfin_tareas_responsable_def on public.adminfin_tareas;
create trigger adminfin_tareas_responsable_def before insert or update on public.adminfin_tareas
  for each row execute function public.adminfin_tareas_responsable_def();

-- Quién ve la tarea (y sus comentarios / adjuntos): supervisión, asignado, responsable o quien la creó
create or replace function public.adminfin_tarea_visible(p_tarea bigint) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.adminfin_puede_ver('tareas') and exists (
    select 1 from public.adminfin_tareas t where t.id = p_tarea
      and (public.adminfin_tareas_es_supervisor() or t.asignado_a = auth.uid() or t.responsable = auth.uid() or t.asignado_por = auth.uid()));
end $$;

drop policy if exists adminfin_tar_sel on public.adminfin_tareas;
drop policy if exists adminfin_tar_upd on public.adminfin_tareas;
create policy adminfin_tar_sel on public.adminfin_tareas for select to authenticated
  using (public.adminfin_puede_ver('tareas')
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or responsable = auth.uid() or asignado_por = auth.uid()));
-- actualizar (y transferir): supervisión, asignado, responsable o quien la creó. Después del cambio la tarea tiene que
-- seguir siendo visible para alguno de ellos (por eso el check mira también responsable / creador).
create policy adminfin_tar_upd on public.adminfin_tareas for update to authenticated
  using (public.adminfin_puede_ver('tareas')
         and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid() or responsable = auth.uid() or asignado_por = auth.uid()))
  with check (public.adminfin_puede_ver('tareas'));

-- Transferir: cambia quién la hace (el responsable no cambia) y deja el comentario automático, en un solo paso.
-- Pueden: supervisión, asignado, responsable o quien la creó (aunque después de transferirla ya no la vean).
create or replace function public.adminfin_tarea_transferir(p_tarea bigint, p_a uuid, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare t public.adminfin_tareas; v_de text; v_a text;
begin
  select * into t from public.adminfin_tareas where id = p_tarea;
  if not found then raise exception 'La tarea no existe'; end if;
  if not (public.adminfin_puede_ver('tareas') and (public.adminfin_tareas_es_supervisor() or t.asignado_a = auth.uid()
          or t.responsable = auth.uid() or t.asignado_por = auth.uid())) then
    raise exception 'No podés transferir esta tarea';
  end if;
  if not exists (select 1 from public.adminfin_tareas_usuarios() u where u.id = p_a) then
    raise exception 'Esa persona no tiene acceso a Tareas';
  end if;
  select coalesce(nombre, email) into v_de from public.perfiles where id = auth.uid();
  select coalesce(nombre, email) into v_a from public.perfiles where id = p_a;
  update public.adminfin_tareas set asignado_a = p_a, responsable = coalesce(responsable, t.asignado_a) where id = p_tarea;
  insert into public.adminfin_tareas_comentarios (tarea_id, autor, texto)
  values (p_tarea, auth.uid(), '↪ ' || coalesce(v_de, '') || ' transfirió la tarea a ' || coalesce(v_a, '')
          || case when nullif(trim(coalesce(p_nota, '')), '') is not null then E'\n' || trim(p_nota) else '' end);
end $$;
revoke all on function public.adminfin_tarea_transferir(bigint, uuid, text) from public, anon;
grant execute on function public.adminfin_tarea_transferir(bigint, uuid, text) to authenticated;

commit;

-- Verificación: tienen que aparecer la columna responsable y la función de transferir
select 'columna' as que, column_name as nombre from information_schema.columns
 where table_schema = 'public' and table_name = 'adminfin_tareas' and column_name = 'responsable'
union all select 'función', proname from pg_proc where proname = 'adminfin_tarea_transferir';
