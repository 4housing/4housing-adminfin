-- =====================================================================
-- Administración y Finanzas · Tareas fijas: segunda etapa "Registro contable" (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_historial.sql.
--
-- Qué hace:
--   · Tareas fijas: día de vencimiento del registro contable (opcional) y responsable del registro (si queda vacío,
--     el mismo responsable). Si no tiene día de registro, la tarea tiene una sola etapa, como hasta ahora.
--   · Tareas: reg_vencimiento, reg_responsable, reg_estado (pendiente / en_curso / hecha = Pendiente / En gestión /
--     Cumplido) y reg_completada_en. La tarea está cumplida cuando las dos etapas están cumplidas.
--   · El responsable del registro ve la tarea y puede cambiar su estado (y comentar / adjuntar).
--   · Cerrar el mes exige las dos etapas cumplidas.
--
-- Reversible:
--   alter table public.adminfin_tareas drop column reg_vencimiento, drop column reg_responsable, drop column reg_estado,
--     drop column reg_completada_en;
--   alter table public.adminfin_tareas_fijas drop column dia_registro, drop column responsable_registro;
--   (y volver a correr 2026-10_tareas_responsable.sql, 2026-10_tareas_fijas.sql y 2026-10_tareas_historial.sql)
-- =====================================================================

begin;

alter table public.adminfin_tareas_fijas add column if not exists dia_registro int check (dia_registro between 1 and 31);
alter table public.adminfin_tareas_fijas add column if not exists responsable_registro uuid references public.perfiles(id);

alter table public.adminfin_tareas add column if not exists reg_vencimiento date;
alter table public.adminfin_tareas add column if not exists reg_responsable uuid references public.perfiles(id);
alter table public.adminfin_tareas add column if not exists reg_estado text check (reg_estado in ('pendiente','en_curso','hecha'));
alter table public.adminfin_tareas add column if not exists reg_completada_en timestamptz;
create index if not exists adminfin_tareas_reg_resp on public.adminfin_tareas (reg_responsable);

-- Fecha de cumplido de cada etapa (automática)
create or replace function public.adminfin_tareas_touch() returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  if new.estado = 'hecha' and (tg_op = 'INSERT' or old.estado is distinct from 'hecha') then new.completada_en := now(); end if;
  if new.estado <> 'hecha' then new.completada_en := null; end if;
  if new.reg_estado = 'hecha' and (tg_op = 'INSERT' or old.reg_estado is distinct from 'hecha') then new.reg_completada_en := now(); end if;
  if new.reg_estado is distinct from 'hecha' then new.reg_completada_en := null; end if;
  return new;
end $$;

-- Quién ve / actualiza: supervisión, asignado, responsable, responsable del registro o quien la creó
create or replace function public.adminfin_tarea_visible(p_tarea bigint) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.adminfin_puede_ver('tareas') and exists (
    select 1 from public.adminfin_tareas t where t.id = p_tarea
      and (public.adminfin_tareas_es_supervisor() or t.asignado_a = auth.uid() or t.responsable = auth.uid()
           or t.reg_responsable = auth.uid() or t.asignado_por = auth.uid()));
end $$;
drop policy if exists adminfin_tar_sel on public.adminfin_tareas;
drop policy if exists adminfin_tar_upd on public.adminfin_tareas;
create policy adminfin_tar_sel on public.adminfin_tareas for select to authenticated
  using (public.adminfin_puede_ver('tareas') and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid()
         or responsable = auth.uid() or reg_responsable = auth.uid() or asignado_por = auth.uid()));
create policy adminfin_tar_upd on public.adminfin_tareas for update to authenticated
  using (public.adminfin_puede_ver('tareas') and (public.adminfin_tareas_es_supervisor() or asignado_a = auth.uid()
         or responsable = auth.uid() or reg_responsable = auth.uid() or asignado_por = auth.uid()))
  with check (public.adminfin_puede_ver('tareas'));

-- Tareas del mes: quien no es supervisión solo cambia los estados de las etapas
create or replace function public.adminfin_tareas_guard_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.adminfin_tareas_es_supervisor() or auth.uid() is null then return new; end if;   -- sin usuario = SQL Editor
  if tg_op = 'INSERT' and new.periodo is not null then
    raise exception 'Solo supervisión puede agregar tareas del mes';
  end if;
  if tg_op = 'UPDATE' and old.periodo is not null
     and (to_jsonb(new) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'actualizado_en')
         is distinct from (to_jsonb(old) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'actualizado_en') then
    raise exception 'Solo supervisión puede modificar o transferir tareas del mes (podés cambiar el estado)';
  end if;
  return new;
end $$;

-- Generar el mes: con la etapa de registro si la tarea fija tiene día de registro
create or replace function public.adminfin_tareas_generar(p_periodo text, p_fija bigint default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int; nf int; nombres text;
begin
  select count(*), string_agg(titulo, ', ' order by orden) into nf, nombres
    from public.adminfin_tareas_fijas where activa and (p_fija is null or id = p_fija) and (responsable is null or dia_vence is null);
  if nf > 0 then
    raise exception 'Faltan responsable o día de vencimiento en % tarea(s) fija(s): %', nf, left(nombres, 300);
  end if;
  insert into public.adminfin_tareas (titulo, descripcion, asignado_por, asignado_a, responsable, fecha, vencimiento, estado,
                                      periodo, fija_id, lista, repeticion, reg_vencimiento, reg_responsable, reg_estado)
  select f.titulo || case when f.veces > 1 then ' (' || r || '/' || f.veces || ')' else '' end, f.descripcion,
         auth.uid(), f.responsable, f.responsable, to_date(p_periodo || '-01', 'YYYY-MM-DD'),
         public.adminfin_tareas_vence(p_periodo, f.dia_vence), 'pendiente', p_periodo, f.id, f.lista, r,
         public.adminfin_tareas_vence(p_periodo, f.dia_registro),
         case when f.dia_registro is not null then coalesce(f.responsable_registro, f.responsable) end,
         case when f.dia_registro is not null then 'pendiente' end
    from public.adminfin_tareas_fijas f cross join lateral generate_series(1, f.veces) r
   where f.activa and (p_fija is null or f.id = p_fija)
   order by f.orden, r
  on conflict (periodo, fija_id, repeticion) where fija_id is not null do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.adminfin_tareas_generar(text, bigint) from public, anon, authenticated;

-- Cerrar el mes: las dos etapas cumplidas
create or replace function public.adminfin_tareas_cerrar_mes(p_periodo text) returns int
language plpgsql security definer set search_path = public as $$
declare pend int; sig text;
begin
  if not public.adminfin_tareas_es_supervisor() then raise exception 'Solo supervisión puede cerrar el mes'; end if;
  if not exists (select 1 from public.adminfin_tareas_meses where periodo = p_periodo and cerrado_en is null) then
    raise exception 'El mes % no está abierto', p_periodo; end if;
  select count(*) into pend from public.adminfin_tareas
   where periodo = p_periodo and (estado <> 'hecha' or coalesce(reg_estado, 'hecha') <> 'hecha');
  if pend > 0 then raise exception 'No se puede cerrar %: quedan % tarea(s) sin cumplir', p_periodo, pend; end if;
  update public.adminfin_tareas_meses set cerrado_en = now(), cerrado_por = auth.uid() where periodo = p_periodo;
  sig := to_char(to_date(p_periodo || '-01', 'YYYY-MM-DD') + interval '1 month', 'YYYY-MM');
  insert into public.adminfin_tareas_meses (periodo, abierto_por) values (sig, auth.uid()) on conflict (periodo) do update set cerrado_en = null, cerrado_por = null;
  return public.adminfin_tareas_generar(sig, null);
end $$;

commit;

-- Verificación: tienen que aparecer las 2 columnas nuevas de tareas fijas y las 4 de tareas
select table_name, column_name from information_schema.columns
 where table_schema = 'public' and column_name in ('dia_registro','responsable_registro','reg_vencimiento','reg_responsable','reg_estado','reg_completada_en')
 order by 1, 2;
