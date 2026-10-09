-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — diccionario de clientes (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor (después de los SQL anteriores de
-- Contabilidad UY).
--
-- Qué hace:
--   Tabla adminfin_cuy_clientes: un registro por cliente de Avance Oriental (código corto, razón social / nombre,
--   RUT o documento, país, moneda y, opcional, la cuenta contable / rubro / proyecto que suele llevar la cobranza).
--   Los movimientos de tipo Ingreso lo usan para completar cliente, código, contrapartida, rubro y proyecto.
--   Solo crea la tabla: los clientes se cargan desde la app (solapa Clientes).
--   Acceso: igual que el resto de Contabilidad UY.
--
-- Reversible:
--   drop table public.adminfin_cuy_clientes;
-- =====================================================================

begin;

create table if not exists public.adminfin_cuy_clientes (
  codigo           text primary key,   -- ej. ANDY (el mismo que va en el movimiento → Código cliente)
  nombre           text not null,      -- razón social / nombre
  rut              text,               -- RUT o documento (si es del exterior)
  pais             text,
  moneda           text,               -- USD | UY (como cobra habitualmente)
  email            text,
  cuenta_contable  text,               -- cuenta Tango de la cobranza (ej. 41000001 Ventas)
  rubro            text,               -- rubro habitual (ej. A) VENTA)
  proyecto         text,               -- proyecto habitual (ej. PL0096 ANDY)
  observaciones    text,
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text
);

drop trigger if exists adminfin_cuy_cli_audit on public.adminfin_cuy_clientes;
create trigger adminfin_cuy_cli_audit before insert or update on public.adminfin_cuy_clientes
  for each row execute function public.adminfin_contabilidad_uy_audit();

alter table public.adminfin_cuy_clientes enable row level security;
revoke all on public.adminfin_cuy_clientes from anon;
grant select, insert, update, delete on public.adminfin_cuy_clientes to authenticated;

drop policy if exists adminfin_cuycli_sel on public.adminfin_cuy_clientes;
drop policy if exists adminfin_cuycli_ins on public.adminfin_cuy_clientes;
drop policy if exists adminfin_cuycli_upd on public.adminfin_cuy_clientes;
drop policy if exists adminfin_cuycli_del on public.adminfin_cuy_clientes;
create policy adminfin_cuycli_sel on public.adminfin_cuy_clientes for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycli_ins on public.adminfin_cuy_clientes for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycli_upd on public.adminfin_cuy_clientes for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuycli_del on public.adminfin_cuy_clientes for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

commit;

-- Verificación: tiene que salir la tabla con RLS activa (true)
select relname, relrowsecurity from pg_class where relname = 'adminfin_cuy_clientes';
