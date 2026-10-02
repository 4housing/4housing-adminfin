-- =====================================================================
-- Administración y Finanzas · Contabilidad UY — lectura del diccionario contable de Compras (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor (después de
-- 2026-10_contabilidad_uy_conciliacion.sql).
--
-- Qué hace:
--   Avance Oriental usa el mismo plan de cuentas Tango que Argentina (diccionario / Cuentas contables de
--   4housing-compras). Para que el Plan de cuentas UY pueda buscar cuentas y auxiliares de ese diccionario,
--   agrega una policy de SOLO LECTURA para el sector adminfin en:
--     · compras_cuentas_contables  (plan de cuentas)
--     · compras_aux_opciones       (opciones de auxiliares: 02 EERR, 03 proyectos, …)
--   Las cuentas / opciones marcadas confidenciales no se ven. No cambia nada de lo que ya tenía Compras
--   (las policies se suman con OR) y adminfin no puede escribir el diccionario.
--   Además deja cargadas las dos cuentas del Santander UY en el plan (adminfin_cuy_plan).
--
-- Reversible:
--   drop policy adminfin_conta_sel on public.compras_cuentas_contables;
--   drop policy adminfin_auxo_sel on public.compras_aux_opciones;
-- =====================================================================

begin;

drop policy if exists adminfin_conta_sel on public.compras_cuentas_contables;
create policy adminfin_conta_sel on public.compras_cuentas_contables
  for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal) and confidencial = false);

drop policy if exists adminfin_auxo_sel on public.compras_aux_opciones;
create policy adminfin_auxo_sel on public.compras_aux_opciones
  for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal) and confidencial = false);

-- Cuentas del Santander UY (dato de Micaela, oct 2026). No pisa un código que ya se haya cargado a mano.
insert into public.adminfin_cuy_plan (clave, codigo, nombre) values
  ('CUENTA:Santander USD',   '11120025', 'Santander UY USD'),
  ('CUENTA:Santander pesos', '11120026', 'Santander UY')
on conflict (clave) do update
  set codigo = coalesce(public.adminfin_cuy_plan.codigo, excluded.codigo),
      nombre = coalesce(public.adminfin_cuy_plan.nombre, excluded.nombre);

commit;

-- Verificación: las 2 policies nuevas y las 2 cuentas del plan
select tablename, policyname from pg_policies where policyname in ('adminfin_conta_sel','adminfin_auxo_sel') order by 1;
select clave, codigo, nombre from public.adminfin_cuy_plan where clave like 'CUENTA:Santander%' order by 1;
