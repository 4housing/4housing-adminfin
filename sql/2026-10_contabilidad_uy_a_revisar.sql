-- =====================================================================
-- Contabilidad UY · Comprobantes: tilde "Requiere acción" (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor.
--
-- Qué hace: agrega adminfin_contabilidad_uy.a_revisar (boolean, por defecto false).
--   Las observaciones pasan a ser comentarios: ya no pintan la fila en amarillo.
--   Solo queda en amarillo lo que tiene TC pendiente o el tilde "Requiere acción".
-- Las observaciones que ya existen quedan como comentarios (sin tilde).
--   Si querés que alguna siga marcada, tildala desde la app (Editar comprobante).
--
-- Reversible: alter table public.adminfin_contabilidad_uy drop column a_revisar;
-- =====================================================================

begin;
alter table public.adminfin_contabilidad_uy add column if not exists a_revisar boolean not null default false;
commit;

-- Verificación: tiene que salir la columna a_revisar
select column_name, data_type, column_default from information_schema.columns
 where table_schema = 'public' and table_name = 'adminfin_contabilidad_uy' and column_name = 'a_revisar';
