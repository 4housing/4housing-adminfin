-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — contrapartida por movimiento (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor.
--
-- Qué hace:
--   Agrega a adminfin_cuy_movimientos la columna contrapartida: código de cuenta Tango para la contrapartida
--   de ESE movimiento (ej. una transferencia recibida de un socio, un préstamo, otra cuenta propia).
--   Si está cargada, manda sobre la cuenta que sale del Plan de cuentas por la clasificación.
--   (Los cambios de moneda entre Santander USD y Santander pesos no la necesitan: van en un solo asiento
--   contra la otra cuenta.)
--
-- Reversible:
--   alter table public.adminfin_cuy_movimientos drop column contrapartida;
-- =====================================================================

alter table public.adminfin_cuy_movimientos add column if not exists contrapartida text;

-- Verificación: tiene que salir la columna
select column_name from information_schema.columns where table_name = 'adminfin_cuy_movimientos' and column_name = 'contrapartida';
