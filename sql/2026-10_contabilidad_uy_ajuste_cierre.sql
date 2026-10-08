-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — cierre de mes: ajuste por diferencia de cambio (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor (después de los SQL anteriores de
-- Contabilidad UY, en especial 2026-10_contabilidad_uy_cotizaciones_cierres.sql).
--
-- Qué hace:
--   Tabla adminfin_cuy_ajustes: el ajuste por diferencia de cambio de cada mes y cuenta (bancos, cajas y
--   Proveedores), tal como se cargó en Tango:
--     · ajuste_usd = asiento en DOL (cuentas en pesos uruguayos / facturas en pesos impagas: lo que cambió su
--       valor en dólares)
--     · ajuste_ars = asiento en PES (llevar el saldo en pesos argentinos a saldo US$ × cotización de cierre)
--   Con eso la app muestra el saldo en US$ ya ajustado y arranca el mes siguiente desde ahí.
--   El IVA crédito fiscal NO se ajusta (queda en pesos uruguayos: decisión de Micaela, oct 2026).
--   Acceso: igual que el resto de Contabilidad UY.
--
-- Reversible:
--   drop table public.adminfin_cuy_ajustes;
-- =====================================================================

begin;

create table if not exists public.adminfin_cuy_ajustes (
  mes              text not null check (mes ~ '^\d{4}-\d{2}$'),   -- AAAA-MM
  cuenta           text not null,    -- Santander USD | Santander pesos | Efectivo USD | Efectivo pesos | Proveedores
  codigo           text,             -- cuenta Tango
  usd_registrado   numeric,          -- saldo en US$ según lo registrado (antes del ajuste)
  usd_real         numeric,          -- saldo en US$ al cierre (pesos uruguayos ÷ BCU del último día hábil)
  ars_tango        numeric,          -- saldo en AR$ en Tango antes del ajuste
  tc_cierre        numeric,          -- AR$ por US$ del último día del mes (cotización de Tango)
  uyu_usd_cierre   numeric,          -- $U por US$ (BCU) del último día hábil del mes
  ajuste_usd       numeric,          -- asiento en DOL
  ajuste_ars       numeric,          -- asiento en PES
  asiento_dol      text,             -- N° de asiento en Tango
  asiento_pes      text,
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text,
  primary key (mes, cuenta)
);

drop trigger if exists adminfin_cuy_aj_audit on public.adminfin_cuy_ajustes;
create trigger adminfin_cuy_aj_audit before insert or update on public.adminfin_cuy_ajustes
  for each row execute function public.adminfin_contabilidad_uy_audit();

alter table public.adminfin_cuy_ajustes enable row level security;
revoke all on public.adminfin_cuy_ajustes from anon;
grant select, insert, update, delete on public.adminfin_cuy_ajustes to authenticated;

drop policy if exists adminfin_cuyaj_sel on public.adminfin_cuy_ajustes;
drop policy if exists adminfin_cuyaj_ins on public.adminfin_cuy_ajustes;
drop policy if exists adminfin_cuyaj_upd on public.adminfin_cuy_ajustes;
drop policy if exists adminfin_cuyaj_del on public.adminfin_cuy_ajustes;
create policy adminfin_cuyaj_sel on public.adminfin_cuy_ajustes for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyaj_ins on public.adminfin_cuy_ajustes for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyaj_upd on public.adminfin_cuy_ajustes for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyaj_del on public.adminfin_cuy_ajustes for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

commit;

-- Verificación: tiene que salir la tabla con RLS activa (true)
select relname, relrowsecurity from pg_class where relname = 'adminfin_cuy_ajustes';
