-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — conciliación de bancos y efectivo + asientos (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor DESPUÉS de
-- 2026-10_contabilidad_uy.sql y ANTES de publicar el index.html con las solapas nuevas.
--
-- Qué hace:
--   1. adminfin_cuy_movimientos: una fila por movimiento de una cuenta (extracto Santander USD / pesos,
--      o caja Efectivo USD / pesos). importe con signo, en la moneda de la cuenta (egreso negativo).
--      tipo: pago | gasto_bancario | entre_cuentas | ingreso | saldo_inicial | otro.
--      asiento_num = N° de asiento de Tango del pago / gasto (se carga a mano después de importarlo).
--   2. adminfin_contabilidad_uy: + movimiento_id (con qué movimiento se pagó: conciliación; varias facturas
--      pueden ir contra un mismo movimiento) y + asiento_num (N° de asiento Tango del registro de la factura).
--   3. adminfin_cuy_plan: plan de cuentas para armar los asientos (clave → código de cuenta Tango, nombre,
--      código de auxiliar EERR). Para las claves CUENTA:* guarda también el saldo de control
--      (saldo según extracto bancario o arqueo de caja) y su fecha.
--   Acceso: igual que adminfin_contabilidad_uy (lee el sector adminfin, escribe puede_editar_sector).
--
-- Reversible:
--   alter table public.adminfin_contabilidad_uy drop column movimiento_id, drop column asiento_num;
--   drop table public.adminfin_cuy_movimientos; drop sequence public.adminfin_cuy_movimientos_seq;
--   drop table public.adminfin_cuy_plan;
-- =====================================================================

begin;

create sequence if not exists public.adminfin_cuy_movimientos_seq;

create table if not exists public.adminfin_cuy_movimientos (
  id               text primary key default ('mv-' || lpad(nextval('public.adminfin_cuy_movimientos_seq')::text, 4, '0')),
  cuenta           text not null,    -- Santander USD | Santander pesos | Efectivo USD | Efectivo pesos
  fecha            date not null,
  concepto         text,
  importe          numeric not null, -- moneda de la cuenta; egreso en negativo
  tipo             text not null default 'otro'
                   check (tipo in ('pago','gasto_bancario','entre_cuentas','ingreso','saldo_inicial','otro')),
  rubro            text,
  periodo          integer,
  auxiliar         text,
  clasificacion    text,
  benef            text,
  proveedor        text,
  proveedor_cod    text,
  fac              text,
  tc               numeric check (tc is null or tc > 0),
  comentarios      text,
  asiento_num      text,             -- N° de asiento Tango del pago / gasto
  origen           text,             -- import | manual | factura_efectivo
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text
);
alter sequence public.adminfin_cuy_movimientos_seq owned by public.adminfin_cuy_movimientos.id;
create index if not exists adminfin_cuy_mov_cuenta_fecha on public.adminfin_cuy_movimientos (cuenta, fecha);

alter table public.adminfin_contabilidad_uy
  add column if not exists movimiento_id text references public.adminfin_cuy_movimientos(id) on delete set null,
  add column if not exists asiento_num   text;
create index if not exists adminfin_cuy_movimiento_id on public.adminfin_contabilidad_uy (movimiento_id);

create table if not exists public.adminfin_cuy_plan (
  clave            text primary key, -- PROVEEDORES | IVA_COMPRAS | MONEDA:UYU | CUENTA:Santander USD | RUBRO:K) ESTRUCTURA | CLASIF:GASTOS BANCARIOS …
  codigo           text,             -- código de cuenta (o de moneda) en Tango
  nombre           text,
  aux_eerr         text,             -- código del auxiliar 02 EERR (solo cuentas de resultado)
  saldo_control    numeric,          -- CUENTA:*: saldo según extracto / arqueo
  fecha_control    date,
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text
);

-- Quién y cuándo: misma función de auditoría que adminfin_contabilidad_uy
drop trigger if exists adminfin_cuy_mov_audit on public.adminfin_cuy_movimientos;
create trigger adminfin_cuy_mov_audit before insert or update on public.adminfin_cuy_movimientos
  for each row execute function public.adminfin_contabilidad_uy_audit();
drop trigger if exists adminfin_cuy_plan_audit on public.adminfin_cuy_plan;
create trigger adminfin_cuy_plan_audit before insert or update on public.adminfin_cuy_plan
  for each row execute function public.adminfin_contabilidad_uy_audit();

alter table public.adminfin_cuy_movimientos enable row level security;
alter table public.adminfin_cuy_plan enable row level security;
revoke all on public.adminfin_cuy_movimientos from anon;
revoke all on public.adminfin_cuy_plan from anon;
revoke all on sequence public.adminfin_cuy_movimientos_seq from anon;
grant select, insert, update, delete on public.adminfin_cuy_movimientos to authenticated;
grant select, insert, update, delete on public.adminfin_cuy_plan to authenticated;
grant usage, select on sequence public.adminfin_cuy_movimientos_seq to authenticated;

drop policy if exists adminfin_cuymov_sel on public.adminfin_cuy_movimientos;
drop policy if exists adminfin_cuymov_ins on public.adminfin_cuy_movimientos;
drop policy if exists adminfin_cuymov_upd on public.adminfin_cuy_movimientos;
drop policy if exists adminfin_cuymov_del on public.adminfin_cuy_movimientos;
create policy adminfin_cuymov_sel on public.adminfin_cuy_movimientos for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuymov_ins on public.adminfin_cuy_movimientos for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuymov_upd on public.adminfin_cuy_movimientos for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuymov_del on public.adminfin_cuy_movimientos for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

drop policy if exists adminfin_cuyplan_sel on public.adminfin_cuy_plan;
drop policy if exists adminfin_cuyplan_ins on public.adminfin_cuy_plan;
drop policy if exists adminfin_cuyplan_upd on public.adminfin_cuy_plan;
drop policy if exists adminfin_cuyplan_del on public.adminfin_cuy_plan;
create policy adminfin_cuyplan_sel on public.adminfin_cuy_plan for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyplan_ins on public.adminfin_cuy_plan for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyplan_upd on public.adminfin_cuy_plan for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyplan_del on public.adminfin_cuy_plan for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

commit;

-- Verificación
select relname, relrowsecurity from pg_class where relname in ('adminfin_cuy_movimientos','adminfin_cuy_plan');
select tablename, policyname, cmd from pg_policies where tablename in ('adminfin_cuy_movimientos','adminfin_cuy_plan') order by 1,2;
select column_name from information_schema.columns where table_name = 'adminfin_contabilidad_uy' and column_name in ('movimiento_id','asiento_num');
