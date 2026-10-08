-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — diccionario de proveedores de Uruguay (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor (después de los SQL anteriores de
-- Contabilidad UY).
--
-- Qué hace:
--   Tabla adminfin_cuy_proveedores: un registro por proveedor de Avance Oriental (código corto, razón social,
--   RUT, moneda, datos bancarios y, opcional, la cuenta contable / rubro / proyecto que suele llevar).
--   Comprobantes y la carga de facturas lo usan para completar código y RUT y mantenerlos consistentes.
--   Solo crea la tabla: los datos se importan desde la app (solapa Proveedores → Importar del Excel), porque los
--   datos de negocio (RUT, cuentas bancarias) no van al repo.
--   Acceso: igual que el resto de Contabilidad UY.
--
-- Reversible:
--   drop table public.adminfin_cuy_proveedores;
-- =====================================================================

begin;

create table if not exists public.adminfin_cuy_proveedores (
  codigo           text primary key,   -- ej. LASENS, STOREH (el mismo que va en Comprobantes → Código proveedor)
  nombre           text not null,      -- razón social
  rut              text,
  moneda           text,               -- USD | UY (como factura habitualmente)
  banco            text,
  sucursal         text,
  cuenta_bancaria  text,
  cuenta_contable  text,               -- cuenta Tango que suele llevar (sugerencia)
  rubro            text,               -- rubro / auxiliar EERR habitual (sugerencia)
  proyecto         text,               -- proyecto habitual (sugerencia)
  observaciones    text,
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text
);
create unique index if not exists adminfin_cuy_prov_rut on public.adminfin_cuy_proveedores (rut) where rut is not null and rut <> '';

drop trigger if exists adminfin_cuy_prov_audit on public.adminfin_cuy_proveedores;
create trigger adminfin_cuy_prov_audit before insert or update on public.adminfin_cuy_proveedores
  for each row execute function public.adminfin_contabilidad_uy_audit();

alter table public.adminfin_cuy_proveedores enable row level security;
revoke all on public.adminfin_cuy_proveedores from anon;
grant select, insert, update, delete on public.adminfin_cuy_proveedores to authenticated;

drop policy if exists adminfin_cuyprov_sel on public.adminfin_cuy_proveedores;
drop policy if exists adminfin_cuyprov_ins on public.adminfin_cuy_proveedores;
drop policy if exists adminfin_cuyprov_upd on public.adminfin_cuy_proveedores;
drop policy if exists adminfin_cuyprov_del on public.adminfin_cuy_proveedores;
create policy adminfin_cuyprov_sel on public.adminfin_cuy_proveedores for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyprov_ins on public.adminfin_cuy_proveedores for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyprov_upd on public.adminfin_cuy_proveedores for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuyprov_del on public.adminfin_cuy_proveedores for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

commit;

-- Verificación: tiene que salir la tabla con RLS activa (true)
select relname, relrowsecurity from pg_class where relname = 'adminfin_cuy_proveedores';
