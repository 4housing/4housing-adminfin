-- =====================================================================
-- Administración y Finanzas · Contabilidad UY (Avance Oriental SAS) — estructura (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor ANTES de publicar
-- el index.html que trae la solapa "Contabilidad UY".
--
-- Qué hace:
--   Tabla adminfin_contabilidad_uy: una fila por CFE recibido (e-Factura, Nota de Crédito, Factura BPS…).
--   Una sola fuente de verdad por fila: si origen_moneda = 'USD' se cargan *_usd + tc (los pesos se
--   calculan en pantalla: *_usd * tc); si es 'UYU' se cargan *_uyu. tc null = pendiente de completar.
--   Notas de crédito en negativo.
--   Acceso: lee quien tiene el sector adminfin (y dirección); escribe quien edita adminfin
--   (puede_editar_sector: los cargos lector/lectura solo ven). RLS solo para authenticated.
--
-- Los datos iniciales (18 comprobantes jul–set 2026) NO están en este archivo: el repo es público.
-- Van en un .sql aparte que no se sube al repo (contabilidad_uy_seed.sql), y se corre después de este.
--
-- Reversible:
--   drop table public.adminfin_contabilidad_uy; drop sequence public.adminfin_contabilidad_uy_seq;
--   drop function public.adminfin_contabilidad_uy_audit();
-- =====================================================================

begin;

create sequence if not exists public.adminfin_contabilidad_uy_seq start 19;   -- uy-001…uy-018 vienen del seed

create table if not exists public.adminfin_contabilidad_uy (
  id               text primary key default ('uy-' || lpad(nextval('public.adminfin_contabilidad_uy_seq')::text, 3, '0')),
  fecha            date not null,
  periodo          integer,          -- período contable AAAAMM (ej. 202608)
  proveedor        text not null,
  proveedor_cod    text,             -- código del diccionario de proveedores (ej. LASENS)
  rut_emisor       text,
  tipo_cfe         text,             -- e-Factura | Nota de Crédito | Factura BPS | …
  serie_numero     text,
  concepto         text,
  rubro            text,             -- ej. "B) CMV VENTA", "K) ESTRUCTURA"
  proyecto         text,             -- ej. PL0090 (puede ir vacío)
  origen_moneda    text not null check (origen_moneda in ('USD','UYU')),
  neto_usd numeric, iva_usd numeric, total_usd numeric,
  tc               numeric check (tc is null or tc > 0),
  neto_uyu numeric, iva_uyu numeric, total_uyu numeric,
  estado_pago      text,             -- PAGADO | PENDIENTE | ANULADA | N/C | …
  cuenta           text,             -- Santander USD | Santander pesos | …
  fecha_pago       date,
  anulada          boolean not null default false,
  doc_relacionado  text,             -- serie del CFE relacionado (anula / anulado por)
  observaciones    text,
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text
);
alter sequence public.adminfin_contabilidad_uy_seq owned by public.adminfin_contabilidad_uy.id;

-- Quién y cuándo (lo completa la base, no la pantalla)
create or replace function public.adminfin_contabilidad_uy_audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
begin
  if tg_op = 'INSERT' then new.creado_en := now(); new.creado_por := v_autor;
  else new.creado_en := old.creado_en; new.creado_por := old.creado_por; end if;
  new.actualizado_en := now(); new.actualizado_por := v_autor;
  return new;
end $$;
drop trigger if exists adminfin_contabilidad_uy_audit on public.adminfin_contabilidad_uy;
create trigger adminfin_contabilidad_uy_audit before insert or update on public.adminfin_contabilidad_uy
  for each row execute function public.adminfin_contabilidad_uy_audit();

alter table public.adminfin_contabilidad_uy enable row level security;
revoke all on public.adminfin_contabilidad_uy from anon;
revoke all on sequence public.adminfin_contabilidad_uy_seq from anon;
grant select, insert, update, delete on public.adminfin_contabilidad_uy to authenticated;
grant usage, select on sequence public.adminfin_contabilidad_uy_seq to authenticated;

drop policy if exists adminfin_cuy_sel on public.adminfin_contabilidad_uy;
drop policy if exists adminfin_cuy_ins on public.adminfin_contabilidad_uy;
drop policy if exists adminfin_cuy_upd on public.adminfin_contabilidad_uy;
drop policy if exists adminfin_cuy_del on public.adminfin_contabilidad_uy;
create policy adminfin_cuy_sel on public.adminfin_contabilidad_uy for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));
create policy adminfin_cuy_ins on public.adminfin_contabilidad_uy for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuy_upd on public.adminfin_contabilidad_uy for update to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_cuy_del on public.adminfin_contabilidad_uy for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

commit;

-- Verificación: tabla, RLS activa y las 4 policies
select relname, relrowsecurity from pg_class where relname = 'adminfin_contabilidad_uy';
select policyname, cmd from pg_policies where tablename = 'adminfin_contabilidad_uy' order by 1;
