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
  Cotizaciones (ARS/USD BNA divisa y UYU/USD por día) · Plan de cuentas (mismo plan Tango que Argentina, con buscador
  del diccionario de Compras). Conciliación en la moneda del banco (UYU / USD); asientos en Tango: USD → DOL con
  cotización ARS/USD, UYU → PES pasado a ARS por el dólar, con diferencia de cambio. Cierres mensuales por cuenta.
  Asientos en Tango en DOL (Tango aplica su cotización); a fin de mes, Asientos → Cierre de mes arma el ajuste por
  diferencia de cambio (DOL para lo que está en pesos uruguayos, PES para el peso argentino; el IVA no se ajusta).
  SQL (en orden): `sql/2026-10_contabilidad_uy_conciliacion.sql`, `sql/2026-10_contabilidad_uy_diccionario.sql`,
  `sql/2026-10_contabilidad_uy_cotizaciones_cierres.sql`, `_aplicaciones`, `_usd_oficial`, `_contrapartida`,
  `_imputacion_factura`, `_usd_billete`, `_ajuste_cierre`, `_proveedores`, `_clientes`, `_a_revisar` (todos `sql/2026-10_contabilidad_uy_*.sql`).
  **Importar** (sin SQL): «Importar extracto» lee el .xls del banco tal cual (Santander: Fecha / Referencia / Tipo Movimiento / Débito / Crédito / Saldo; la
  cuenta se propone por moneda, los cambios de moneda se detectan por fecha + referencia en las dos cuentas, y lo ya cargado no se duplica).
  «Importar Excel» en Comprobantes usa las mismas columnas que «Exportar Excel» (vista previa, omite las ya cargadas por proveedor + serie / N°).
  Comprobantes: las observaciones son comentarios; solo se pone amarilla la fila con TC pendiente o con el tilde «Requiere acción» (`_a_revisar`).
- **Tareas** (menú lateral): quién asigna a quién, fecha, vencimiento, estado (pendiente / en curso / hecha), adjuntos y
  comentarios. Quien tiene tildado «Tareas · ver todas» ve todas; el resto, las que le asignaron o creó.
  SQL: `sql/2026-10_tareas.sql` (tablas, bucket privado `adminfin-tareas` y permisos) y después
  `sql/2026-10_adminfin_secciones.sql` y `sql/2026-10_tareas_responsable.sql` (responsable + transferir: el responsable no
  cambia al transferir la tarea; queda un comentario automático por cada transferencia).
  **Tareas fijas mensuales** (`sql/2026-10_tareas_fijas.sql`): plantilla con lista, responsable, día de vencimiento
  (sábado/domingo → lunes) y veces por mes; se carga con las listas de los Excel «Seguimiento de hábitos». Supervisión
  abre el primer mes; el mes se cierra solo con todas las tareas hechas y al cerrarlo se generan las del siguiente.
  Solapa «Tareas del mes»: avance por lista y por responsable, evolución mensual y tilde rápido de «Hecha».
  **Historial y eliminadas** (`sql/2026-10_tareas_historial.sql`, solo supervisión): la base registra cada modificación
  y eliminación (tareas y tareas fijas); las eliminadas se archivan con comentarios y adjuntos y se pueden restaurar.
  Eliminar tareas y agregar / modificar / transferir tareas del mes: solo supervisión. Para asignar aparecen solo
  quienes tengan «Tareas» tildado en el portal.
  **Vto de pago** (`sql/2026-10_tareas_registro.sql`, columnas `reg_*`; impositivos): una tarea fija puede tener un vencimiento de pago (día y
  responsable propios). Estados: Pendiente / En gestión / Cumplido; la tarea se cumple con las dos etapas cumplidas.
  **Vencimientos** (`sql/2026-10_tareas_vencimientos.sql`): «Día» fijo o «Hábil n°», en el mes siguiente al cierre
  (o el mismo); sábados, domingos y feriados (tabla `adminfin_feriados`, se cargan en Tareas fijas) no son hábiles.
  **Tipos** (`sql/2026-10_tareas_tipos.sql`): Proveedores → estado «Pagado» con fecha de pago (propone hoy); Impuestos →
  lista con vto de pago obligatorio (Pagado + fecha) y la tarea «Registrado»; bancos y tarjetas en 2 tareas (Cargar FAC
  de gastos / Conciliar); ▲▼ para ordenar la plantilla. `sql/2026-10_tareas_reiniciar_prueba.sql` borra el mes de prueba.
- **Permisos por sección** (desde la pantalla Usuarios del portal, `SECCIONES.adminfin` en `portal/admin.html`):
  `solicitudes`, `cuy`, `tareas`, `tareas_todas` (supervisión). La app oculta lo que no se ve y bloquea lo que no se
  edita; en Tareas además lo controla la base (`adminfin_puede_ver` / `adminfin_puede_editar`).
Diseño: mismo sistema visual que `4housing-compras` y `4housing-eerr` (paleta oliva,
Archivo/Quicksand, sidebar oscuro, cards, tablas `.grid`, badges y modales).
