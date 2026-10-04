-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — lectura del USD Billete diario del diccionario (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor.
--
-- Qué hace:
--   compras_usd_diario (USD Billete / Blue día a día, compra y venta, que registra Compras desde dolarapi; es la
--   "Cotización Billete" DOL que se carga en Tango) hoy solo la leen los sectores compras y eerr. Agrega una policy
--   de SOLO LECTURA para adminfin: Contabilidad UY la usa como ARS/USD (promedio compra/venta del día) para Tango.
--   No cambia lo que ya tenían Compras / EERR y adminfin no puede escribir la tabla.
--
-- Reversible:
--   drop policy adminfin_usdbill_sel on public.compras_usd_diario;
-- =====================================================================

begin;

drop policy if exists adminfin_usdbill_sel on public.compras_usd_diario;
create policy adminfin_usdbill_sel on public.compras_usd_diario
  for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));

commit;

-- Verificación: la policy nueva y el rango de fechas de la tabla (con el promedio del último día)
select policyname from pg_policies where tablename = 'compras_usd_diario' order by 1;
select min(fecha) as desde, max(fecha) as hasta, count(*) as dias from public.compras_usd_diario;
select fecha, compra, venta, (coalesce(compra, venta) + coalesce(venta, compra)) / 2 as promedio, fuente
  from public.compras_usd_diario order by fecha desc limit 5;
