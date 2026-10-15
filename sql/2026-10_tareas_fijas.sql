-- =====================================================================
-- Administración y Finanzas · Tareas fijas mensuales (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- sql/2026-10_tareas.sql, sql/2026-10_adminfin_secciones.sql y sql/2026-10_tareas_responsable.sql.
--
-- Qué hace:
--   · adminfin_tareas_fijas: la plantilla (lista, tarea, detalle, responsable, día de vencimiento, veces por mes).
--     Se carga con las 82 tareas de los Excel "Seguimiento de hábitos" (Cierre mensual, Supervisión, Proveedores).
--     Cierre mensual trae el responsable del Excel (Alexis = administracion@, Mica = micaela@); el resto, vacío.
--     El día de vencimiento viene vacío: hay que completarlo en la app antes de abrir el primer mes.
--   · adminfin_tareas_meses: qué meses se abrieron y cuáles se cerraron (uno abierto a la vez).
--   · adminfin_tareas gana: periodo (AAAA-MM), fija_id, lista, repeticion. Las tareas del mes son tareas
--     normales (mismo estado, comentarios, adjuntos, transferir).
--   · adminfin_tareas_abrir_mes(periodo): genera las tareas del mes desde la plantilla. Vencimiento = día fijo
--     del mes (si el mes es más corto, el último día); si cae sábado o domingo, pasa al lunes siguiente.
--   · adminfin_tareas_cerrar_mes(periodo): solo si TODAS las tareas del mes están hechas. Cierra y abre el
--     mes siguiente en el mismo paso.
--   · adminfin_tareas_sumar_fija(fija): agrega una tarea fija nueva al mes abierto.
--   Abrir / cerrar / editar la plantilla: solo supervisión (tilde "Tareas · ver todas" en el portal).
--
-- Reversible:
--   drop function public.adminfin_tareas_abrir_mes(text), public.adminfin_tareas_cerrar_mes(text),
--                 public.adminfin_tareas_sumar_fija(bigint), public.adminfin_tareas_generar(text, bigint),
--                 public.adminfin_tareas_vence(text, int);
--   alter table public.adminfin_tareas drop column periodo, drop column fija_id, drop column lista, drop column repeticion;
--   drop table public.adminfin_tareas_meses, public.adminfin_tareas_fijas;
-- =====================================================================

begin;

create table if not exists public.adminfin_tareas_fijas (
  id          bigserial primary key,
  lista       text not null,
  titulo      text not null,
  descripcion text,
  responsable uuid references public.perfiles(id),
  dia_vence   int check (dia_vence between 1 and 31),
  veces       int not null default 1 check (veces between 1 and 31),
  orden       int not null default 0,
  activa      boolean not null default true,
  creado_en   timestamptz not null default now()
);

create table if not exists public.adminfin_tareas_meses (
  periodo     text primary key check (periodo ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  abierto_en  timestamptz not null default now(),
  abierto_por uuid references public.perfiles(id),
  cerrado_en  timestamptz,
  cerrado_por uuid references public.perfiles(id)
);

alter table public.adminfin_tareas add column if not exists periodo text;
alter table public.adminfin_tareas add column if not exists fija_id bigint references public.adminfin_tareas_fijas(id) on delete set null;
alter table public.adminfin_tareas add column if not exists lista text;
alter table public.adminfin_tareas add column if not exists repeticion int;
create index if not exists adminfin_tareas_periodo on public.adminfin_tareas (periodo);
create unique index if not exists adminfin_tareas_fija_mes on public.adminfin_tareas (periodo, fija_id, repeticion) where fija_id is not null;

-- Vencimiento: día fijo del mes (tope: último día); sábado/domingo → lunes siguiente
create or replace function public.adminfin_tareas_vence(p_periodo text, p_dia int) returns date
language plpgsql immutable as $$
declare d0 date := to_date(p_periodo || '-01', 'YYYY-MM-DD'); v date;
begin
  if p_dia is null then return null; end if;
  v := d0 + (least(p_dia, extract(day from (d0 + interval '1 month' - interval '1 day'))::int) - 1);
  if extract(isodow from v) = 6 then v := v + 2; elsif extract(isodow from v) = 7 then v := v + 1; end if;
  return v;
end $$;

-- Genera (sin duplicar) las tareas del mes desde la plantilla; p_fija = solo esa tarea fija
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
                                      periodo, fija_id, lista, repeticion)
  select f.titulo || case when f.veces > 1 then ' (' || r || '/' || f.veces || ')' else '' end, f.descripcion,
         auth.uid(), f.responsable, f.responsable, to_date(p_periodo || '-01', 'YYYY-MM-DD'),
         public.adminfin_tareas_vence(p_periodo, f.dia_vence), 'pendiente', p_periodo, f.id, f.lista, r
    from public.adminfin_tareas_fijas f cross join lateral generate_series(1, f.veces) r
   where f.activa and (p_fija is null or f.id = p_fija)
   order by f.orden, r
  on conflict (periodo, fija_id, repeticion) where fija_id is not null do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.adminfin_tareas_generar(text, bigint) from public, anon, authenticated;

-- Abrir un mes (el primero; después se abren solos al cerrar el anterior)
create or replace function public.adminfin_tareas_abrir_mes(p_periodo text) returns int
language plpgsql security definer set search_path = public as $$
declare abierto text;
begin
  if not public.adminfin_tareas_es_supervisor() then raise exception 'Solo supervisión puede abrir el mes'; end if;
  if p_periodo !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Período inválido: %', p_periodo; end if;
  select periodo into abierto from public.adminfin_tareas_meses where cerrado_en is null limit 1;
  if abierto is not null then raise exception 'El mes % sigue abierto: hay que cerrarlo antes', abierto; end if;
  if exists (select 1 from public.adminfin_tareas_meses where periodo = p_periodo) then raise exception 'El mes % ya fue abierto', p_periodo; end if;
  insert into public.adminfin_tareas_meses (periodo, abierto_por) values (p_periodo, auth.uid());
  return public.adminfin_tareas_generar(p_periodo, null);
end $$;

-- Cerrar el mes: solo con todas las tareas hechas. Abre el siguiente.
create or replace function public.adminfin_tareas_cerrar_mes(p_periodo text) returns int
language plpgsql security definer set search_path = public as $$
declare pend int; sig text;
begin
  if not public.adminfin_tareas_es_supervisor() then raise exception 'Solo supervisión puede cerrar el mes'; end if;
  if not exists (select 1 from public.adminfin_tareas_meses where periodo = p_periodo and cerrado_en is null) then
    raise exception 'El mes % no está abierto', p_periodo; end if;
  select count(*) into pend from public.adminfin_tareas where periodo = p_periodo and estado <> 'hecha';
  if pend > 0 then raise exception 'No se puede cerrar %: quedan % tarea(s) sin hacer', p_periodo, pend; end if;
  update public.adminfin_tareas_meses set cerrado_en = now(), cerrado_por = auth.uid() where periodo = p_periodo;
  sig := to_char(to_date(p_periodo || '-01', 'YYYY-MM-DD') + interval '1 month', 'YYYY-MM');
  insert into public.adminfin_tareas_meses (periodo, abierto_por) values (sig, auth.uid()) on conflict (periodo) do update set cerrado_en = null, cerrado_por = null;
  return public.adminfin_tareas_generar(sig, null);
end $$;

-- Sumar una tarea fija nueva al mes abierto
create or replace function public.adminfin_tareas_sumar_fija(p_fija bigint) returns int
language plpgsql security definer set search_path = public as $$
declare abierto text;
begin
  if not public.adminfin_tareas_es_supervisor() then raise exception 'Solo supervisión'; end if;
  select periodo into abierto from public.adminfin_tareas_meses where cerrado_en is null limit 1;
  if abierto is null then return 0; end if;
  return public.adminfin_tareas_generar(abierto, p_fija);
end $$;

-- Permisos
alter table public.adminfin_tareas_fijas enable row level security;
alter table public.adminfin_tareas_meses enable row level security;
revoke all on public.adminfin_tareas_fijas, public.adminfin_tareas_meses from anon;
grant select, insert, update, delete on public.adminfin_tareas_fijas to authenticated;
grant select on public.adminfin_tareas_meses to authenticated;
grant usage, select on sequence public.adminfin_tareas_fijas_id_seq to authenticated;
revoke all on function public.adminfin_tareas_abrir_mes(text), public.adminfin_tareas_cerrar_mes(text), public.adminfin_tareas_sumar_fija(bigint) from public, anon;
grant execute on function public.adminfin_tareas_abrir_mes(text), public.adminfin_tareas_cerrar_mes(text), public.adminfin_tareas_sumar_fija(bigint) to authenticated;

drop policy if exists adminfin_tfij_sel on public.adminfin_tareas_fijas;
drop policy if exists adminfin_tfij_all on public.adminfin_tareas_fijas;
create policy adminfin_tfij_sel on public.adminfin_tareas_fijas for select to authenticated using (public.adminfin_puede_ver('tareas'));
create policy adminfin_tfij_all on public.adminfin_tareas_fijas for all to authenticated
  using (public.adminfin_tareas_es_supervisor()) with check (public.adminfin_tareas_es_supervisor());
drop policy if exists adminfin_tmes_sel on public.adminfin_tareas_meses;
create policy adminfin_tmes_sel on public.adminfin_tareas_meses for select to authenticated using (public.adminfin_puede_ver('tareas'));

-- Plantilla inicial (solo si está vacía): listas de los Excel "Seguimiento de hábitos"
insert into public.adminfin_tareas_fijas (lista, titulo, descripcion, responsable, veces, orden)
select v.lista, v.titulo, v.descripcion, p.id, v.veces, v.orden
  from (values
  ('Cierre mensual', 'Control Ingresos Alquileres', null, 'administracion@4housing.com.ar', 1, 1),
  ('Cierre mensual', 'Cargar Alquileres Mes nuevo', null, 'administracion@4housing.com.ar', 1, 2),
  ('Cierre mensual', 'Control Ingresos Logística', null, 'micaela@4housing.com.ar', 1, 3),
  ('Cierre mensual', 'Control Ingresos DTM', null, 'micaela@4housing.com.ar', 1, 4),
  ('Cierre mensual', 'Caja ARS', null, 'micaela@4housing.com.ar', 1, 5),
  ('Cierre mensual', 'Caja USD', null, 'micaela@4housing.com.ar', 1, 6),
  ('Cierre mensual', 'Asiento Sueldos', null, 'micaela@4housing.com.ar', 1, 7),
  ('Cierre mensual', 'Informe Sueldos', null, 'micaela@4housing.com.ar', 1, 8),
  ('Cierre mensual', 'Caja Chica Quartier', null, 'micaela@4housing.com.ar', 1, 9),
  ('Cierre mensual', 'Caja Chica Taller', null, 'micaela@4housing.com.ar', 1, 10),
  ('Cierre mensual', 'Caja Chica Neuquen', null, 'micaela@4housing.com.ar', 1, 11),
  ('Cierre mensual', 'Préstamos Personal', null, 'micaela@4housing.com.ar', 1, 12),
  ('Cierre mensual', 'Banco Ciudad', null, 'administracion@4housing.com.ar', 1, 13),
  ('Cierre mensual', 'Banco BBVA', null, 'administracion@4housing.com.ar', 1, 14),
  ('Cierre mensual', 'Banco BBVA USD', null, 'administracion@4housing.com.ar', 1, 15),
  ('Cierre mensual', 'Banco Nacion', null, 'administracion@4housing.com.ar', 1, 16),
  ('Cierre mensual', 'Banco Provincia', null, 'administracion@4housing.com.ar', 1, 17),
  ('Cierre mensual', 'Banco Comafi', null, 'administracion@4housing.com.ar', 1, 18),
  ('Cierre mensual', 'Banco Santander', null, 'administracion@4housing.com.ar', 1, 19),
  ('Cierre mensual', 'Banco Galicia', null, 'administracion@4housing.com.ar', 1, 20),
  ('Cierre mensual', 'Banco Macro', null, 'administracion@4housing.com.ar', 1, 21),
  ('Cierre mensual', 'Banco Macro USD', null, 'administracion@4housing.com.ar', 1, 22),
  ('Cierre mensual', 'Informe Préstamos', null, 'administracion@4housing.com.ar', 1, 23),
  ('Cierre mensual', 'TC AMEX', null, 'administracion@4housing.com.ar', 1, 24),
  ('Cierre mensual', 'TC Visa Galicia', null, 'administracion@4housing.com.ar', 1, 25),
  ('Cierre mensual', 'TC Visa Macro', null, 'administracion@4housing.com.ar', 1, 26),
  ('Cierre mensual', 'TC Visa BBVA', null, 'administracion@4housing.com.ar', 1, 27),
  ('Cierre mensual', 'TC Visa Provincia', null, 'administracion@4housing.com.ar', 1, 28),
  ('Cierre mensual', 'Control Imputacion cargos', null, 'administracion@4housing.com.ar', 1, 29),
  ('Cierre mensual', 'Informe MM', null, 'micaela@4housing.com.ar', 1, 30),
  ('Cierre mensual', 'Informe CPS', null, 'micaela@4housing.com.ar', 1, 31),
  ('Cierre mensual', 'Control Deuda Pólizas', null, 'administracion@4housing.com.ar', 1, 32),
  ('Cierre mensual', 'Asiento IIBB/IVA', null, 'micaela@4housing.com.ar', 1, 33),
  ('Cierre mensual', 'EERR', null, 'micaela@4housing.com.ar', 1, 34),
  ('Cierre mensual', 'Informe Financiero', null, 'micaela@4housing.com.ar', 1, 35),
  ('Supervisión', 'Conciliacion Excel CIUDAD', null, null, 1, 36),
  ('Supervisión', 'Conciliacion Excel BBVA', null, null, 1, 37),
  ('Supervisión', 'Conciliacion Excel NACION', null, null, 1, 38),
  ('Supervisión', 'Conciliacion Excel PROVINCIA', null, null, 1, 39),
  ('Supervisión', 'Conciliacion Excel COMAFI', null, null, 1, 40),
  ('Supervisión', 'Conciliacion Excel SANTANDER', null, null, 1, 41),
  ('Supervisión', 'Control de Pendientes de Imputacion Compras', null, null, 1, 42),
  ('Supervisión', 'Control de Pendientes de Imputacion Ventas', null, null, 1, 43),
  ('Supervisión', 'Control Caja Chica Quartier', null, null, 1, 44),
  ('Supervisión', 'Pago y Registro AGIP', null, null, 1, 45),
  ('Supervisión', 'Pago y Registro ARBA', null, null, 1, 46),
  ('Supervisión', 'Pago y Registro Sicore', null, null, 1, 47),
  ('Supervisión', 'Pago y Registro SUSS', null, null, 1, 48),
  ('Supervisión', 'Pago y Registro CM', null, null, 1, 49),
  ('Supervisión', 'Pago y Registro IVA', null, null, 1, 50),
  ('Supervisión', 'Informe Logistica Mensual', null, null, 1, 51),
  ('Supervisión', 'Informe DTM Mensual', null, null, 1, 52),
  ('Supervisión', 'Informe imputación contable Mensual', null, null, 1, 53),
  ('Supervisión', 'Informe Prestamos Bancarios', null, null, 1, 54),
  ('Supervisión', 'Informe CPS', null, null, 1, 55),
  ('Supervisión', 'Informe PROVEEDORES', null, null, 1, 56),
  ('Supervisión', 'Informe POLIZAS', null, null, 1, 57),
  ('Proveedores', 'OSDE GERENCIA', 'Medicina Prepaga', null, 1, 58),
  ('Proveedores', 'OSDE ADMINISTRACIÓN', 'Medicina Prepaga', null, 1, 59),
  ('Proveedores', 'OSDIPP', 'Medicina Prepaga', null, 1, 60),
  ('Proveedores', 'SWISS', 'Medicina Prepaga', null, 1, 61),
  ('Proveedores', 'PRINCI', 'Alquileres', null, 1, 62),
  ('Proveedores', 'EDESUR', 'Alquileres', null, 1, 63),
  ('Proveedores', 'POYSE', 'Alquileres', null, 1, 64),
  ('Proveedores', 'ICON', 'Alquileres', null, 1, 65),
  ('Proveedores', 'EXPENSAS', 'Alquileres', null, 1, 66),
  ('Proveedores', 'GALA', 'Food & Bev', null, 1, 67),
  ('Proveedores', 'STAR', 'Food & Bev', null, 1, 68),
  ('Proveedores', 'POGGIO', 'Gasto comercial', null, 1, 69),
  ('Proveedores', 'WZBSA', 'Gasto comercial', null, 1, 70),
  ('Proveedores', 'TIRAVA', 'Gastos Asesoramiento y Capacitacion', null, 1, 71),
  ('Proveedores', 'SISA', 'Gastos varios Taller', null, 1, 72),
  ('Proveedores', 'AYZ', 'Honorarios Contables', null, 1, 73),
  ('Proveedores', 'CASSEL', 'Honorarios Contables', null, 1, 74),
  ('Proveedores', 'ROLDAN', 'Honorarios Contables', null, 1, 75),
  ('Proveedores', 'RAZQUI', 'Honorarios Contables', null, 1, 76),
  ('Proveedores', 'LIMBER', 'Honorarios Legales', null, 1, 77),
  ('Proveedores', 'SEGMAC', 'Honorarios SIG & S&G', null, 1, 78),
  ('Proveedores', 'CABIFY', 'Movilidad Combustible', null, 1, 79),
  ('Proveedores', 'EDENRE', 'Movilidad Combustible', null, 3, 80),
  ('Proveedores', 'PANAME', 'Movilidad Combustible', null, 3, 81),
  ('Proveedores', 'DELMAR', null, null, 1, 82)

  ) as v(lista, titulo, descripcion, email, veces, orden)
  left join public.perfiles p on lower(p.email) = v.email
 where not exists (select 1 from public.adminfin_tareas_fijas);

commit;

-- Verificación: cantidad de tareas fijas por lista y cuántas tienen responsable
select lista, count(*) as tareas, count(responsable) as con_responsable from public.adminfin_tareas_fijas group by lista order by min(orden);
