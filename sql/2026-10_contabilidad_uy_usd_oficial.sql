-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — lectura del USD Oficial diario del diccionario (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor.
--
-- Qué hace:
--   compras_usd_diario_oficial (USD Oficial día a día que registra Compras desde dolarapi y que usa EERR) hoy
--   solo la leen los sectores compras y eerr. Agrega una policy de SOLO LECTURA para adminfin, para poder
--   completar el ARS/USD de Contabilidad UY con ese valor. No cambia lo que ya tenían Compras / EERR
--   (las policies se suman con OR) y adminfin no puede escribir la tabla.
--
-- Reversible:
--   drop policy adminfin_usdofic_sel on public.compras_usd_diario_oficial;
-- =====================================================================

begin;

drop policy if exists adminfin_usdofic_sel on public.compras_usd_diario_oficial;
create policy adminfin_usdofic_sel on public.compras_usd_diario_oficial
  for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));

commit;

-- Verificación: la policy nueva y el rango de fechas que hay en la tabla
select policyname from pg_policies where tablename = 'compras_usd_diario_oficial' order by 1;
select min(fecha) as desde, max(fecha) as hasta, count(*) as dias from public.compras_usd_diario_oficial;
