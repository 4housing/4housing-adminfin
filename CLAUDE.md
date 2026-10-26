# 4housing — Administración y Finanzas

App de una sola página (`index.html`, JS + Supabase), publicada en GitHub Pages.

## Reglas

- **Instructivos:** cada sección tiene una solapa «Instructivo» con texto fijo: `spGuia()` (Solicitudes de pago), `cuyGuia()` (Contabilidad UY) y `tarRenderAyuda()` (Tareas). **Todo cambio que modifique cómo se usa una pantalla (botones, pestañas, estados, columnas, permisos, circuito) tiene que actualizar el instructivo de esa sección en el mismo commit.**
- SQL: nunca lo corre Claude. Se entrega un `.sql` en `sql/` y lo corre el usuario en el SQL Editor de Supabase. Orden de deploy: primero SQL, después HTML.
- RLS para `authenticated`, nunca `anon`. Sin secretos en `index.html`.
- Datos del negocio no van al repo (es público): `.gitignore` excluye `*_seed*`.
- Validar con `node --check` sobre el `<script>` extraído antes de commitear.
- Commits en español. No romper lo que funciona.
