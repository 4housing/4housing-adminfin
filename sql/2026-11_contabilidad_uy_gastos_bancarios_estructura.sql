-- =====================================================================
-- Contabilidad UY: los gastos bancarios (comisiones) van al rubro K) ESTRUCTURA (nov 2026, pedido de Micaela).
-- R) FINANCIERO queda solo para transferencias entre cuentas propias.
-- Corrige los movimientos ya cargados. Correr A MANO en el SQL Editor (proyecto wcpkpwxhqdcdljfwzcmy).
-- No cambia tablas ni policies. El asiento ya usaba ESTRUCTURA (aux. EERR de GASTOS BANCARIOS); esto corrige el rubro guardado.
-- Reversible: no hay vuelta automática (antes de correrlo se puede guardar la consulta de verificación).
-- =====================================================================

-- Antes: cuántos gastos bancarios hay por rubro (solo lectura)
select coalesce(rubro,'(sin rubro)') as rubro, count(*) as movimientos
from public.adminfin_cuy_movimientos
where tipo = 'gasto_bancario'
group by 1 order by 1;

begin;
update public.adminfin_cuy_movimientos
   set rubro = 'K) ESTRUCTURA'
 where tipo = 'gasto_bancario'
   and coalesce(rubro,'') <> 'K) ESTRUCTURA';
commit;

-- Después: tienen que quedar todos en K) ESTRUCTURA
select coalesce(rubro,'(sin rubro)') as rubro, count(*) as movimientos
from public.adminfin_cuy_movimientos
where tipo = 'gasto_bancario'
group by 1 order by 1;
