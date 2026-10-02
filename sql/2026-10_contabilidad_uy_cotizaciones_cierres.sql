-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — cotizaciones diarias y cierres mensuales (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor (después de
-- 2026-10_contabilidad_uy_conciliacion.sql y 2026-10_contabilidad_uy_diccionario.sql).
--
-- Esquema de monedas (acordado con Micaela, oct 2026):
--   · Operación y conciliación en la moneda del banco: UYU (Santander UY pesos / efectivo pesos) y USD.
--   · Contabilidad en Tango: pesos argentinos (PES) y dólares (DOL).
--       USD → asiento DOL con cotización ARS/USD (BNA divisa) del día.
--       UYU → asiento PES con el importe pasado a ARS por el dólar: UYU ÷ (UYU por USD) × (ARS por USD).
--
-- Qué hace:
--   1. adminfin_cuy_cotizaciones: una fila por fecha con ars_usd (BNA divisa) y uyu_usd (UYU por USD).
--      Para una fecha sin fila se usa la última cotización anterior.
--   2. adminfin_cuy_cierres: saldo según extracto (o arqueo) de cada cuenta a fin de cada mes,
--      para controlar mes a mes que saldo inicial + movimientos = saldo del extracto.
--   Acceso: igual que el resto de Contabilidad UY (lee adminfin, escribe puede_editar_sector).
--
-- Reversible:
--   drop table public.adminfin_cuy_cotizaciones; drop table public.adminfin_cuy_cierres;
-- =====================================================================

begin;

create table if not exists public.adminfin_cuy_cotizaciones (
  fecha            date primary key,
  ars_usd          numeric check (ars_usd is null or ars_usd > 0),  -- pesos argentinos por USD (BNA divisa)
  uyu_usd          numeric check (uyu_usd is null or uyu_usd > 0),  -- pesos uruguayos por USD
  fuente_ars       text,    -- manual | …
  fuente_uyu       text,    -- manual | dolarapi | cambio banco
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text
);

create table if not exists public.adminfin_cuy_cierres (
  cuenta           text not null,   -- Santander USD | Santander pesos | Efectivo USD | Efectivo pesos
  mes              text not null check (mes ~ '^\d{4}-\d{2}$'),   -- AAAA-MM
  saldo_extracto   numeric,         -- saldo según extracto (o arqueo) al último día del mes
  observaciones    text,
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text,
  primary key (cuenta, mes)
);

drop trigger if exists adminfin_cuy_cot_audit on public.adminfin_cuy_cotizaciones;
create trigger adminfin_cuy_cot_audit before insert or update on public.adminfin_cuy_cotizaciones
  for each row execute function public.adminfin_contabilidad_uy_audit();
drop trigger if exists adminfin_cuy_cierre_audit on public.adminfin_cuy_cierres;
create trigger adminfin_cuy_cierre_audit before insert or update on public.adminfin_cuy_cierres
  for each row execute function public.adminfin_contabilidad_uy_audit();

alter table public.adminfin_cuy_cotizaciones enable row level security;
alter table public.adminfin_cuy_cierres enable row level security;
revoke all on public.adminfin_cuy_cotizaciones from anon;
revoke all on public.adminfin_cuy_cierres from anon;
grant select, insert, update, delete on public.adminfin_cuy_cotizaciones to authenticated;
grant select, insert, update, delete on public.adminfin_cuy_cierres to authenticated;

drop policy if exists adminfin_cuycot_sel on public.adminfin_cuy_cotizaciones;
drop policy if exists adminfin_cuycot_ins on public.adminfin_cuy_cotizaciones;
drop policy if exists adminfin_cuycot_upd on public.adminfin_cuy_cotizaciones;
drop policy if exists adminfin_cuycot_del on public.adminfin_cuy_cotizaciones;
create policy adminfin_cuycot_sel on public.adminfin_cuy_cotizaciones for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycot_ins on public.adminfin_cuy_cotizaciones for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycot_upd on public.adminfin_cuy_cotizaciones for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycot_del on public.adminfin_cuy_cotizaciones for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

drop policy if exists adminfin_cuycie_sel on public.adminfin_cuy_cierres;
drop policy if exists adminfin_cuycie_ins on public.adminfin_cuy_cierres;
drop policy if exists adminfin_cuycie_upd on public.adminfin_cuy_cierres;
drop policy if exists adminfin_cuycie_del on public.adminfin_cuy_cierres;
create policy adminfin_cuycie_sel on public.adminfin_cuy_cierres for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycie_ins on public.adminfin_cuy_cierres for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycie_upd on public.adminfin_cuy_cierres for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycie_del on public.adminfin_cuy_cierres for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

commit;

-- Verificación: tienen que salir las 2 tablas con RLS activa (true)
select relname, relrowsecurity from pg_class where relname in ('adminfin_cuy_cotizaciones','adminfin_cuy_cierres') order by 1;
