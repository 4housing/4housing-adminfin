# 4housing — Administración y Finanzas

Módulo de Administración y Finanzas del portal 4housing: login Microsoft compartido
(proyecto Supabase `wcpkpwxhqdcdljfwzcmy`), chequea el sector `adminfin` en
`perfiles_sector` antes de mostrar contenido.

Solapas:
- **Solicitudes de pago** (espejo de la solapa de Compras, sobre las mismas tablas `compras_*`).
- **Contabilidad UY**: facturas (CFE) recibidas por Avance Oriental SAS, en pesos uruguayos (tabla
  `adminfin_contabilidad_uy`, `sql/2026-10_contabilidad_uy.sql`). Los datos de negocio no van al repo.
Diseño: mismo sistema visual que `4housing-compras` y `4housing-eerr` (paleta oliva,
Archivo/Quicksand, sidebar oscuro, cards, tablas `.grid`, badges y modales).
