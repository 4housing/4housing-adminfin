# 4housing — Administración y Finanzas

Módulo de Administración y Finanzas del portal 4housing: login Microsoft compartido
(proyecto Supabase `wcpkpwxhqdcdljfwzcmy`), chequea el sector `adminfin` en
`perfiles_sector` antes de mostrar contenido.

Solapas:
- **Solicitudes de pago** (espejo de la solapa de Compras, sobre las mismas tablas `compras_*`).
- **Contabilidad UY**: facturas (CFE) recibidas por Avance Oriental SAS, en pesos uruguayos (tabla
  `adminfin_contabilidad_uy`, `sql/2026-10_contabilidad_uy.sql`). Los datos de negocio no van al repo.
  Pestañas: Comprobantes · Conciliación bancos (Santander USD / pesos: importa el Excel del extracto, vincula
  cada pago con su(s) factura(s), compara saldo según libros con el del extracto) · Efectivo (facturas pagadas
  en efectivo generan su movimiento de caja; arqueo) · Asientos (formato de importación Tango igual que
  Tesorería de Compras, para el registro de facturas y para pagos / gastos bancarios, con N° de asiento) ·
  Plan de cuentas (códigos Tango de Avance Oriental, a completar). SQL: `sql/2026-10_contabilidad_uy_conciliacion.sql`.
Diseño: mismo sistema visual que `4housing-compras` y `4housing-eerr` (paleta oliva,
Archivo/Quicksand, sidebar oscuro, cards, tablas `.grid`, badges y modales).
