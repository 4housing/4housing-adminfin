-- =====================================================================
-- Administración y Finanzas · Impuestos (presentación / pago / registro contable), Proveedores y Cierre mensual (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de sql/2026-10_tareas_tipos.sql,
-- y ANTES de publicar el index.html con la solapa "Impuestos".
--
-- Qué hace:
--   1) adminfin_tareas.fecha_registro: fecha del registro contable (Impuestos: "Pago y Registro …").
--      Quien no es supervisión la puede cargar, igual que el estado y la fecha de pago.
--   2) Impuestos: cada impuesto de la plantilla dice qué requiere — Presentación, Pago y/o Registro contable
--      (req_presentacion / req_pago / req_registro). IVA e IIBB (AGIP, ARBA, CM): los 3. Sicore y SUSS: pago y
--      registro (como hasta ahora; se tilda Presentación desde Tareas fijas si corresponde).
--      Todos tienen fecha de vencimiento (la del vto, obligatoria en Impuestos). Las tareas del mes copian los tildes
--      y suman fecha_presentacion. La tarea queda cumplida cuando están todas las fechas que requiere; si no requiere
--      pago, la etapa de pago nace resuelta. Al mes abierto se le aplican los tildes de la plantilla.
--   3) Plantilla, lista "Proveedores" (según "Gastos de Estructura 202610", OCs con período por varios meses):
--      · Se sacan: POGGIO, GALA y los que no tienen OC mensual (PRINCI, POYSE, ICON, EXPENSAS, STAR, TIRAVA,
--        RAZQUI, CABIFY, EDENRE, PANAME, DELMAR). Quedan archivados en el historial (se pueden ver ahí).
--      · Se agregan 15: ARAAGU, BERGER, BINASE, CACMI, CAISSA, CHINNI, CLARO, EPEN, IPLAN, METEL, NOSIS, REPCON, RSV,
--        SEGUME, SPWORK. Activas, responsable administracion@ (Carranza, A.), vencen el 5° día hábil del mes
--        siguiente al cierre. Si un proveedor ya está en la lista (mismo nombre), no se duplica.
--   4) Plantilla, Cierre mensual y Supervisión (planilla de oct 2026): responsable y vencimiento = N° día hábil del mes
--      siguiente al cierre, para 36 tareas (bancos y tarjetas: sus dos tareas, "· Cargar FAC de gastos" y "· Conciliar").
--      · Pasan de Supervisión a Cierre mensual: Pendientes de Imputación Compras / Ventas, Control Caja Chica Quartier,
--        Informe Logística, DTM, Préstamos Bancarios y PÓLIZAS. Informe CPS e Informe PROVEEDORES siguen en Supervisión.
--      · Banco Comafi: desactivada (queda en la plantilla, no se genera).
--      · Se BORRAN y NO quedan en el historial: Control Ingresos Logística, Control Ingresos DTM, Informe Préstamos,
--        Control Imputacion cargos, Informe MM, Informe CPS (la de Cierre mensual), Control Deuda Pólizas, Asiento IIBB/IVA
--        (Cierre mensual) e Informe imputación contable Mensual (Supervisión).
--      · La plantilla se renumera: Cierre mensual y Supervisión en el orden de la planilla.
--   Las tareas del mes ya abierto NO cambian (las de los proveedores sacados siguen ahí; las nuevas aparecen desde el
--   próximo mes que se abra, o supervisión las suma con "Agregar tarea al mes").
--
-- Reversible:
--   alter table public.adminfin_tareas drop column fecha_registro, drop column fecha_presentacion, drop column req_presentacion,
--     drop column req_pago, drop column req_registro;
--   alter table public.adminfin_tareas_fijas drop column req_presentacion, drop column req_pago, drop column req_registro;
--   (y volver a correr las funciones guard y generar de 2026-10_tareas_tipos.sql)
--   Proveedores: restaurar desde "Historial y eliminadas" / borrar los agregados desde Tareas fijas.
-- =====================================================================

begin;

alter table public.adminfin_tareas add column if not exists fecha_registro date;
alter table public.adminfin_tareas add column if not exists fecha_presentacion date;
alter table public.adminfin_tareas add column if not exists req_presentacion boolean;
alter table public.adminfin_tareas add column if not exists req_pago boolean;
alter table public.adminfin_tareas add column if not exists req_registro boolean;
alter table public.adminfin_tareas_fijas add column if not exists req_presentacion boolean not null default false;
alter table public.adminfin_tareas_fijas add column if not exists req_pago boolean not null default true;
alter table public.adminfin_tareas_fijas add column if not exists req_registro boolean not null default true;
alter table public.adminfin_tareas_fijas drop constraint if exists adminfin_tfij_req_alguno;
alter table public.adminfin_tareas_fijas add constraint adminfin_tfij_req_alguno check (req_presentacion or req_pago or req_registro);

-- IVA e IIBB (AGIP, ARBA, CM): presentación, pago y registro
update public.adminfin_tareas_fijas set req_presentacion = true, req_pago = true, req_registro = true
 where lista ilike 'impuesto%' and titulo ~* '(IVA|AGIP|ARBA|\mCM\M)';

-- quien no es supervisión: estados y fechas de presentación, pago y registro
create or replace function public.adminfin_tareas_guard_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.adminfin_tareas_es_supervisor() or auth.uid() is null then return new; end if;   -- sin usuario = SQL Editor
  if tg_op = 'INSERT' and new.periodo is not null then
    raise exception 'Solo supervisión puede agregar tareas del mes';
  end if;
  if tg_op = 'UPDATE' and old.periodo is not null
     and (to_jsonb(new) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'fecha_registro' - 'fecha_presentacion' - 'actualizado_en')
         is distinct from (to_jsonb(old) - 'estado' - 'completada_en' - 'reg_estado' - 'reg_completada_en' - 'fecha_pago' - 'fecha_registro' - 'fecha_presentacion' - 'actualizado_en') then
    raise exception 'Solo supervisión puede modificar o transferir tareas del mes (podés cambiar el estado)';
  end if;
  return new;
end $$;

-- generar el mes: copia qué requiere cada impuesto
create or replace function public.adminfin_tareas_generar(p_periodo text, p_fija bigint default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int; nf int; nombres text;
begin
  select count(*), string_agg(titulo, ', ' order by orden) into nf, nombres
    from public.adminfin_tareas_fijas where activa and (p_fija is null or id = p_fija)
     and (responsable is null or dia_vence is null or (lista ilike 'impuesto%' and dia_registro is null));
  if nf > 0 then
    raise exception 'Faltan responsable, día de vencimiento o vto de pago (Impuestos) en % tarea(s) fija(s): %', nf, left(nombres, 300);
  end if;
  insert into public.adminfin_tareas (titulo, descripcion, asignado_por, asignado_a, responsable, fecha, vencimiento, estado,
                                      periodo, fija_id, lista, repeticion, reg_vencimiento, reg_responsable, reg_estado,
                                      req_presentacion, req_pago, req_registro)
  select f.titulo || case when f.veces > 1 then ' (' || r || '/' || f.veces || ')' else '' end, f.descripcion,
         auth.uid(), f.responsable, f.responsable, to_date(p_periodo || '-01', 'YYYY-MM-DD'),
         public.adminfin_tareas_vence2(p_periodo, f.dia_vence, f.tipo_vence, f.mes_vence), 'pendiente', p_periodo, f.id, f.lista, r,
         public.adminfin_tareas_vence2(p_periodo, f.dia_registro, f.tipo_registro, f.mes_registro),
         case when f.dia_registro is not null then coalesce(f.responsable_registro, f.responsable) end,
         -- Impuestos sin pago requerido: la etapa de pago nace resuelta (no traba el cierre)
         case when f.dia_registro is not null then case when f.lista ilike 'impuesto%' and not f.req_pago then 'hecha' else 'pendiente' end end,
         case when f.lista ilike 'impuesto%' then f.req_presentacion end, case when f.lista ilike 'impuesto%' then f.req_pago end,
         case when f.lista ilike 'impuesto%' then f.req_registro end
    from public.adminfin_tareas_fijas f cross join lateral generate_series(1, f.veces) r
   where f.activa and (p_fija is null or f.id = p_fija)
   order by f.orden, r
  on conflict (periodo, fija_id, repeticion) where fija_id is not null do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.adminfin_tareas_generar(text, bigint) from public, anon, authenticated;

-- Mes abierto: los impuestos ya generados toman la lista y los tildes de la plantilla.
-- Lo ya registrado por estado (sin fecha) conserva la fecha en que se marcó; si ahora también requiere presentación
-- y no está presentado, vuelve a "En gestión"; si no requiere pago, el pago queda resuelto.
-- (si el mes se generó cuando los impuestos todavía estaban en "Supervisión", pasan a la lista Impuestos)
update public.adminfin_tareas t set lista = f.lista
  from public.adminfin_tareas_fijas f
 where t.fija_id = f.id and f.lista ilike 'impuesto%' and t.lista is distinct from f.lista
   and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);
update public.adminfin_tareas t
   set fecha_registro = coalesce(t.fecha_registro, case when t.estado = 'hecha' then (t.completada_en at time zone 'America/Argentina/Buenos_Aires')::date end),
       req_presentacion = f.req_presentacion, req_pago = f.req_pago, req_registro = f.req_registro
  from public.adminfin_tareas_fijas f
 where t.fija_id = f.id and f.lista ilike 'impuesto%'
   and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);
update public.adminfin_tareas t set estado = 'en_curso'
 where t.lista ilike 'impuesto%' and t.req_presentacion and t.fecha_presentacion is null and t.estado = 'hecha'
   and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);
update public.adminfin_tareas t set reg_estado = 'hecha'
 where t.lista ilike 'impuesto%' and t.req_pago = false and t.reg_estado is distinct from 'hecha' and t.reg_estado is not null
   and t.periodo in (select periodo from public.adminfin_tareas_meses where cerrado_en is null);

-- Proveedores que salen de la plantilla
delete from public.adminfin_tareas_fijas
 where lista = 'Proveedores' and upper(btrim(titulo)) in ('POGGIO','GALA','PRINCI','POYSE','ICON','EXPENSAS','STAR','TIRAVA','RAZQUI','CABIFY','EDENRE','PANAME','DELMAR');

-- Proveedores nuevos (al final de la lista, de 10 en 10)
-- primero se hace lugar: lo que viene después de Proveedores en la plantilla baja 150 (15 tareas × 10)
update public.adminfin_tareas_fijas set orden = orden + 150
 where orden > (select max(orden) from public.adminfin_tareas_fijas where lista = 'Proveedores');
insert into public.adminfin_tareas_fijas (lista, titulo, descripcion, responsable, dia_vence, tipo_vence, mes_vence, veces, orden, activa)
select 'Proveedores', v.titulo, v.descripcion, p.id, 5, 'habil', 1, 1,
       coalesce((select max(orden) from public.adminfin_tareas_fijas where lista = 'Proveedores'),
                (select max(orden) from public.adminfin_tareas_fijas), 0) + v.n * 10, true
  from (values
    ('ARAAGU', 'Seguridad · Servicio de seguridad / vigilancia', 1),
    ('BERGER', 'Alquileres · Alquiler oficina comercial', 2),
    ('BINASE', 'Medicina Prepaga · Administración', 3),
    ('CACMI', 'Gasto comercial · Cuota CACMI', 4),
    ('CAISSA', 'Gasto publicidad · Servicio de marketing', 5),
    ('CHINNI', 'Gastos mantenimiento módulos · Comisiones módulos', 6),
    ('CLARO', 'Teléfono · Telefonía celular', 7),
    ('EPEN', 'Energía eléctrica · Base Neuquén', 8),
    ('IPLAN', 'Teléfono · Telefonía fija', 9),
    ('METEL', 'Teléfono · Internet', 10),
    ('NOSIS', 'Licencias · Servicio de informes', 11),
    ('REPCON', 'Gastos mantenimiento reefer', 12),
    ('RSV', 'Rodados · Rastreo satelital', 13),
    ('SEGUME', 'Seguridad · Servicio de seguridad', 14),
    ('SPWORK', 'Alquileres · Alquiler base Neuquén', 15)
  ) as v(titulo, descripcion, n)
  left join public.perfiles p on lower(p.email) = 'administracion@4housing.com.ar'
 where not exists (select 1 from public.adminfin_tareas_fijas f where f.lista = 'Proveedores' and upper(btrim(f.titulo)) = v.titulo);

-- 4) Cierre mensual y Supervisión
-- comparación sin mayúsculas, tildes ni espacios de más
create or replace function pg_temp.nrm(t text) returns text language sql immutable as $f$
  select translate(lower(btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g'))), 'áéíóúü', 'aeiouu') $f$;
create temp table _cierre (n int, titulo text, lista_actual text, lista text, email text, dia int) on commit drop;
insert into _cierre values
  (1, 'Control de Pendientes de Imputacion Compras', 'Supervisión', 'Cierre mensual', 'administracion@4housing.com.ar', 1),
  (2, 'Control de Pendientes de Imputacion Ventas', 'Supervisión', 'Cierre mensual', 'administracion@4housing.com.ar', 1),
  (3, 'Control Caja Chica Quartier', 'Supervisión', 'Cierre mensual', 'administracion@4housing.com.ar', 1),
  (4, 'Control Ingresos Alquileres', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 1),
  (5, 'Cargar Alquileres Mes nuevo', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 1),
  (6, 'Informe Logistica Mensual', 'Supervisión', 'Cierre mensual', 'administracion@4housing.com.ar', 2),
  (7, 'Informe DTM Mensual', 'Supervisión', 'Cierre mensual', 'administracion@4housing.com.ar', 2),
  (8, 'Informe Prestamos Bancarios', 'Supervisión', 'Cierre mensual', 'administracion@4housing.com.ar', 2),
  (9, 'Informe POLIZAS', 'Supervisión', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (10, 'Banco Ciudad', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (11, 'Banco BBVA', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (12, 'Banco BBVA USD', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (13, 'Banco Nacion', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (14, 'Banco Provincia', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (15, 'Banco Comafi', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (16, 'Banco Santander', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (17, 'Banco Galicia', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (18, 'Banco Macro', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (19, 'Banco Macro USD', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (20, 'TC AMEX', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (21, 'TC Visa Galicia', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (22, 'TC Visa Macro', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (23, 'TC Visa BBVA', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (24, 'TC Visa Provincia', 'Cierre mensual', 'Cierre mensual', 'administracion@4housing.com.ar', 5),
  (25, 'Informe CPS', 'Supervisión', 'Supervisión', 'micaela@4housing.com.ar', 5),
  (26, 'Informe PROVEEDORES', 'Supervisión', 'Supervisión', 'micaela@4housing.com.ar', 5),
  (27, 'Caja ARS', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (28, 'Caja USD', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (29, 'Asiento Sueldos', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (30, 'Informe Sueldos', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (31, 'Caja Chica Quartier', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (32, 'Caja Chica Taller', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (33, 'Caja Chica Neuquen', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (34, 'Préstamos Personal', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 5),
  (35, 'EERR', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 10),
  (36, 'Informe Financiero', 'Cierre mensual', 'Cierre mensual', 'micaela@4housing.com.ar', 10);
create temp table _cierre_borrar (lista text, titulo text) on commit drop;
insert into _cierre_borrar values
  ('Cierre mensual', 'Control Ingresos Logística'),
  ('Cierre mensual', 'Control Ingresos DTM'),
  ('Cierre mensual', 'Informe Préstamos'),
  ('Cierre mensual', 'Control Imputacion cargos'),
  ('Cierre mensual', 'Informe MM'),
  ('Cierre mensual', 'Informe CPS'),
  ('Cierre mensual', 'Control Deuda Pólizas'),
  ('Cierre mensual', 'Asiento IIBB/IVA'),
  ('Supervisión', 'Informe imputación contable Mensual');

update public.adminfin_tareas_fijas f
   set lista = c.lista, responsable = p.id, dia_vence = c.dia, tipo_vence = 'habil', mes_vence = 1
  from _cierre c left join public.perfiles p on lower(p.email) = c.email
 where f.lista = c.lista_actual
   and (pg_temp.nrm(f.titulo) = pg_temp.nrm(c.titulo) or pg_temp.nrm(f.titulo) like pg_temp.nrm(c.titulo) || ' · %');
update public.adminfin_tareas_fijas set activa = false where lista = 'Cierre mensual' and pg_temp.nrm(titulo) like 'banco comafi%';

-- borrar sin dejar rastro en el historial (pedido de dirección)
create temp table _borradas on commit drop as
  select f.id from public.adminfin_tareas_fijas f join _cierre_borrar b on f.lista = b.lista and pg_temp.nrm(f.titulo) = pg_temp.nrm(b.titulo);
delete from public.adminfin_tareas_fijas where id in (select id from _borradas);
delete from public.adminfin_tareas_historial where tabla = 'fija' and accion = 'eliminada' and registro_id in (select id from _borradas);

-- orden: las listas como estaban; dentro de Cierre mensual y Supervisión, el de la planilla; de 10 en 10
update public.adminfin_tareas_fijas f set orden = x.n * 10
  from (select y.id, row_number() over (order by y.lmin, y.k, y.orden, y.id) n
          from (select f2.id, f2.orden, min(f2.orden) over (partition by f2.lista) lmin, coalesce(min(c.n), 1000) k
                  from public.adminfin_tareas_fijas f2
                  left join _cierre c on f2.lista = c.lista
                   and (pg_temp.nrm(f2.titulo) = pg_temp.nrm(c.titulo) or pg_temp.nrm(f2.titulo) like pg_temp.nrm(c.titulo) || ' · %')
                 group by f2.id, f2.orden, f2.lista) y) x
 where x.id = f.id;

-- control (antes del commit): filas de la planilla que no encontraron su tarea (tiene que dar vacío)
select c.n, c.titulo as sin_coincidencia from _cierre c
 where not exists (select 1 from public.adminfin_tareas_fijas f where f.lista = c.lista
                     and (pg_temp.nrm(f.titulo) = pg_temp.nrm(c.titulo) or pg_temp.nrm(f.titulo) like pg_temp.nrm(c.titulo) || ' · %'));

commit;

-- Verificación: la columna nueva, y la lista Proveedores (tienen que quedar 27 si la lista estaba como en el alta inicial;
-- "sin_responsable" tiene que ser 0 para los nuevos: si no, administracion@ no tiene perfil en el portal)
select column_name from information_schema.columns where table_name = 'adminfin_tareas' and column_name in ('fecha_registro','fecha_presentacion','req_presentacion','req_pago','req_registro');
select titulo, req_presentacion as presentacion, req_pago as pago, req_registro as registro from public.adminfin_tareas_fijas where lista ilike 'impuesto%' order by orden;
select count(*) as proveedores, count(*) filter (where responsable is null) as sin_responsable,
       string_agg(titulo, ', ' order by orden) as lista
  from public.adminfin_tareas_fijas where lista = 'Proveedores';
select lista, titulo, (select email from public.perfiles p where p.id = f.responsable) as responsable, dia_vence as dia_habil, activa
  from public.adminfin_tareas_fijas f where lista in ('Cierre mensual', 'Supervisión') order by orden;
