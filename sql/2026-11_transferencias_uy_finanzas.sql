-- =====================================================================
-- Transferencias por Santander UY (nov 2026) — etapa 2: Finanzas
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- 4housing-compras/sql/2026-11_transferencias_uy.sql (ya corrido) y ANTES de publicar el index.html de adminfin.
--
-- 1) compras_transf_uy_registrar_fac(p_id): registra en Contabilidad UY (adminfin_contabilidad_uy) la factura (CFE)
--    de un pedido de transferencia de Compras (compras_solicitudes_pago, tipo 'transferencia_uy') y deja el vínculo
--    (cuy_comprobante_id). Todo en una transacción y con la fila bloqueada: aunque dos personas abran la pantalla
--    a la vez, la factura se registra una sola vez. Si ya estaba registrada, no hace nada.
--    Datos: fecha, CFE, total/IVA/neto en US$ y proyecto los cargó el comprador; nombre, RUT y rubro salen del
--    diccionario de proveedores UY (por el mismo código de Tango) si el proveedor está. TC y cuenta de gasto los
--    completa Finanzas como con cualquier comprobante.
-- 2) compras_solpago_adminfin (misma firma): al marcar Pagada una transferencia UY, la factura en Contabilidad UY
--    pasa a PAGADO con esa fecha y cuenta Santander USD; al volverla a En gestión, vuelve a PENDIENTE.
--    El resto de las acciones queda igual que en 4housing-compras/sql/2026-10_solpago_reabrir.sql.
-- 0) compras_solicitudes_pago.og_numero: el N° de OG en el pedido (se completa para los ya cargados).
-- Permiso: quien edita Administración y Finanzas (puede_editar_sector('adminfin')). No crea tablas ni policies.
--
-- Reversible:
--   drop function if exists public.compras_transf_uy_registrar_fac(bigint);
--   alter table public.compras_solicitudes_pago drop column if exists og_numero;
--   y volver a correr 4housing-compras/sql/2026-10_solpago_reabrir.sql (versión anterior de compras_solpago_adminfin).
-- =====================================================================

begin;

-- 0) N° de OG en el pedido (para mostrarlo en Administración y Finanzas, que no lee las OG de Compras)
alter table public.compras_solicitudes_pago add column if not exists og_numero text;
update public.compras_solicitudes_pago s set og_numero = o.numero::text
  from public.compras_ogs o where o.id = s.og_id and s.og_numero is null;

-- 1) Registrar la factura del pedido en Contabilidad UY
create or replace function public.compras_transf_uy_registrar_fac(p_id bigint)
returns public.compras_solicitudes_pago
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  s   public.compras_solicitudes_pago;
  pv  public.adminfin_cuy_proveedores;
  v_og_num text;
  v_id text;
  v_iva numeric;
begin
  if not public.puede_editar_sector('adminfin'::public.sector_portal) then
    raise exception 'Sin permiso de edición en Administración y Finanzas';
  end if;
  select * into s from public.compras_solicitudes_pago where id = p_id for update;
  if not found then raise exception 'No existe el pedido %', p_id; end if;
  if s.tipo is distinct from 'transferencia_uy' then raise exception 'El pedido % no es una transferencia Santander UY', p_id; end if;
  if s.cuy_comprobante_id is not null then return s; end if;            -- ya registrada: no se duplica
  if s.estado in ('Cancelada', 'FAC cargada') then return s; end if;

  select * into pv from public.adminfin_cuy_proveedores where upper(btrim(codigo)) = upper(btrim(coalesce(s.proveedor_cod,'')));
  select numero::text into v_og_num from public.compras_ogs where id = s.og_id;
  v_iva := coalesce(s.iva, 0);

  insert into public.adminfin_contabilidad_uy
    (fecha, periodo, proveedor, proveedor_cod, rut_emisor, tipo_cfe, serie_numero, concepto, rubro, proyecto,
     origen_moneda, neto_usd, iva_usd, total_usd, estado_pago, cuenta, observaciones)
  values
    (coalesce(s.fac_fecha, current_date),
     to_char(coalesce(s.fac_fecha, current_date), 'YYYYMM')::int,
     coalesce(nullif(pv.nombre,''), nullif(s.proveedor,''), s.proveedor_cod, '(sin proveedor)'),
     nullif(btrim(coalesce(s.proveedor_cod,'')),''),
     coalesce(nullif(pv.rut,''), s.rut_emisor),
     'e-Factura',
     s.nro_factura,
     'OG ' || coalesce(v_og_num, s.og_id::text, '—') || ' · transferencia pedida por Compras',
     nullif(pv.rubro,''),
     nullif(s.proyecto_cod,''),
     'USD',
     round(coalesce(s.monto,0) - v_iva, 2), round(v_iva, 2), round(coalesce(s.monto,0), 2),
     'PENDIENTE', 'Santander USD',
     'Pedido de Compras N° ' || s.id || ' (OG ' || coalesce(v_og_num, s.og_id::text, '—') || ', comprador ' || coalesce(s.comprador,'—') || ')'
       || case when pv.codigo is null then ' · proveedor sin dar de alta en el diccionario UY' else '' end)
  returning id into v_id;

  update public.compras_solicitudes_pago
     set cuy_comprobante_id = v_id, og_numero = coalesce(og_numero, v_og_num),
         historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('fecha', now(), 'autor', v_autor,
                     'texto', 'Factura registrada en Contabilidad UY (' || v_id || ').')),
         actualizado_en = now()
   where id = p_id returning * into s;
  return s;
end $$;
revoke all on function public.compras_transf_uy_registrar_fac(bigint) from public, anon;
grant execute on function public.compras_transf_uy_registrar_fac(bigint) to authenticated;

-- 2) Acciones de Administración sobre los pedidos (misma firma; agrega el pase de la factura UY a PAGADO / PENDIENTE)
create or replace function public.compras_solpago_adminfin(p_id bigint, p_accion text, p_fecha date default null, p_texto text default null)
returns public.compras_solicitudes_pago
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  v_texto text := nullif(btrim(coalesce(p_texto,'')),'');
  s public.compras_solicitudes_pago;
  v_hist jsonb;
begin
  if not public.puede_editar_sector('adminfin'::public.sector_portal) then
    raise exception 'Sin permiso de edición en Administración y Finanzas';
  end if;
  select * into s from public.compras_solicitudes_pago where id = p_id for update;
  if not found then raise exception 'No existe la solicitud %', p_id; end if;
  if s.estado = 'FAC cargada' then raise exception 'Compras todavía no pidió el pago de esta factura'; end if;
  if s.estado = 'Pagada' and p_accion not in ('comentario','reabrir') then raise exception 'La solicitud ya está Pagada'; end if;
  if p_accion = 'reabrir' and s.estado <> 'Pagada' then raise exception 'Solo se puede volver a En gestión una solicitud Pagada'; end if;
  if s.estado = 'Cancelada' and p_accion not in ('comentario','pagada') then raise exception 'Compras canceló este pedido de pago'; end if;

  if p_accion = 'leido' then   -- pasar a En gestión
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor, 'texto', 'Administración la pasó a En gestión.' || coalesce(' ' || v_texto, ''), 'estado_nuevo', 'En gestión');
    update public.compras_solicitudes_pago
       set leido_en = coalesce(leido_en, now()), leido_por = coalesce(leido_por, v_autor), estado = 'En gestión',
           historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(v_hist), actualizado_en = now()
     where id = p_id returning * into s;
  elsif p_accion = 'pagada' then
    if p_fecha is null then raise exception 'Falta la fecha de pago'; end if;
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor, 'estado_nuevo', 'Pagada',
              'texto', 'Pagada el ' || to_char(p_fecha,'DD/MM/YYYY') || '.' || coalesce(' ' || v_texto, ''));
    update public.compras_solicitudes_pago
       set estado = 'Pagada', fecha_pago = p_fecha, leido_en = coalesce(leido_en, now()), leido_por = coalesce(leido_por, v_autor),
           historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(v_hist), actualizado_en = now()
     where id = p_id returning * into s;
    -- Transferencia UY: la factura en Contabilidad UY queda PAGADO (Santander USD)
    if s.tipo = 'transferencia_uy' and s.cuy_comprobante_id is not null then
      update public.adminfin_contabilidad_uy
         set estado_pago = 'PAGADO', fecha_pago = p_fecha, cuenta = coalesce(nullif(cuenta,''), 'Santander USD')
       where id = s.cuy_comprobante_id;
    end if;
  elsif p_accion = 'reabrir' then   -- deshacer Pagada (no se pudo pagar / se marcó por error) → En gestión
    if v_texto is null then raise exception 'Falta el motivo'; end if;
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor, 'estado_nuevo', 'En gestión',
              'texto', 'Volvió a En gestión (estaba Pagada' || coalesce(' el ' || to_char(s.fecha_pago,'DD/MM/YYYY'), '') || '). Motivo: ' || v_texto);
    update public.compras_solicitudes_pago
       set estado = 'En gestión', fecha_pago = null,
           historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(v_hist), actualizado_en = now()
     where id = p_id returning * into s;
    if s.tipo = 'transferencia_uy' and s.cuy_comprobante_id is not null then
      update public.adminfin_contabilidad_uy set estado_pago = 'PENDIENTE', fecha_pago = null where id = s.cuy_comprobante_id;
    end if;
  elsif p_accion = 'fecha_pago' then
    if p_fecha is null then raise exception 'Falta la fecha de pago'; end if;
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor,
              'texto', 'Fecha estimada de pago: ' || to_char(p_fecha,'DD/MM/YYYY') || coalesce(' — ' || v_texto, ''));
    update public.compras_solicitudes_pago
       set fecha_pago_estimada = p_fecha,
           historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(v_hist), actualizado_en = now()
     where id = p_id returning * into s;
  elsif p_accion = 'comentario' then
    if v_texto is null then raise exception 'Falta el comentario'; end if;
    update public.compras_solicitudes_pago
       set historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('fecha', now(), 'autor', v_autor, 'texto', v_texto)),
           actualizado_en = now()
     where id = p_id returning * into s;
  else
    raise exception 'Acción desconocida: %', p_accion;
  end if;
  return s;
end $$;
revoke all on function public.compras_solpago_adminfin(bigint,text,date,text) from public, anon;
grant execute on function public.compras_solpago_adminfin(bigint,text,date,text) to authenticated;

commit;

-- Verificación: tienen que aparecer las 2 funciones y la columna og_numero
select 'función' as que, proname as nombre from pg_proc
where pronamespace = 'public'::regnamespace and proname in ('compras_transf_uy_registrar_fac','compras_solpago_adminfin')
union all
select 'columna', column_name from information_schema.columns
where table_schema = 'public' and table_name = 'compras_solicitudes_pago' and column_name = 'og_numero'
order by 1, 2;
