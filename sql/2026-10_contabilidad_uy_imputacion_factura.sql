-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — imputación contable por comprobante (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor.
--
-- Qué hace:
--   Agrega a adminfin_contabilidad_uy dos códigos de cuenta Tango opcionales por comprobante:
--     · cuenta_gasto:  cuenta del gasto (Debe). Vacía = la del Plan de cuentas según el rubro.
--     · cuenta_contra: contrapartida (Haber al registrar, Debe al pagar). Vacía = Proveedores (21100001).
--   Sirve para comprobantes del mismo rubro que van a cuentas distintas (ej. aportes BPS vs. honorarios,
--   los dos K) ESTRUCTURA) o con otra contrapartida (ej. un organismo en vez de Proveedores).
--
-- Reversible:
--   alter table public.adminfin_contabilidad_uy drop column cuenta_gasto, drop column cuenta_contra;
-- =====================================================================

alter table public.adminfin_contabilidad_uy
  add column if not exists cuenta_gasto  text,
  add column if not exists cuenta_contra text;

-- Verificación: tienen que salir las 2 columnas
select column_name from information_schema.columns
 where table_name = 'adminfin_contabilidad_uy' and column_name in ('cuenta_gasto','cuenta_contra') order by 1;
