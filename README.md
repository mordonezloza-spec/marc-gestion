# MARC · Sistema de Gestión Empresarial

Web de gestión para **MARC Distribution & Solutions Import E.I.R.L.** (alquiler de maquinaria y servicios).
Stack: **React + TypeScript (Vite)** · **Supabase** (Postgres, Auth, RLS) · **Vercel**.

Fase 1 incluida: inicio de sesión con pantalla de carga, menú lateral plegable (Ctrl K), tema claro/oscuro,
**tablero ejecutivo**, **cotizaciones** (registro, tarifa sugerida, detracción por servicio, costeo estimado,
versiones, seguimiento hasta el cobro, impresión a PDF), **clientes**, **tarifario** y **ajustes**.
El resto de áreas aparece en el menú como fichas "Fase N" y ya tiene sus tablas creadas en la base de datos.

---

## 1. Base de datos (Supabase)

1. Crea un proyecto en <https://supabase.com> (región São Paulo es la más cercana a Lima).
2. **Forma rápida:** en **SQL Editor → New query** pega todo `supabase/instalacion_inicial.sql` y pulsa **Run**
   (incluye las 4 migraciones, con los permisos de la Data API, y los datos 2026; se puede volver a ejecutar sin duplicar). Luego crea los usuarios y ejecuta `supabase/usuarios.sql`.

   **Forma por partes** (equivalente): ejecuta, en este orden, el contenido de:
   1. `supabase/migrations/0001_base.sql` — usuarios, clientes, tarifario, cotizaciones, vistas, función `guardar_cotizacion` y permisos (RLS).
   2. `supabase/migrations/0002_operaciones_finanzas.sql` — equipos, partes diarios, gastos, cajas, compromisos y la vista de utilidad por equipo.
   3. `supabase/migrations/0003_historico.sql` — resúmenes multi-año (`v_ventas_mensuales`, `v_anios`) para comparar años y proyectar.
   4. `supabase/seed/seed_2026.sql` — datos reales importados de los Excel: 133 clientes, 75 tarifas y 368 cotizaciones de 2026.

   > Con la CLI: `supabase link --project-ref <ref>` y luego `supabase db push` (migraciones). El seed se ejecuta aparte en el SQL Editor.

### Usuarios

El inicio de sesión usa el **usuario** (AZELAYA, FFONSECA…). Por dentro se convierte en el correo
`usuario@marc-eirl.com` (dominio configurable con `VITE_LOGIN_DOMAIN`).

1. **Authentication → Users → Add user → Create new user** para cada persona, marcando *Auto Confirm User*:
   `mordonez@marc-eirl.com`, `azelaya@marc-eirl.com`, `ffonseca@marc-eirl.com`, `rruiz@marc-eirl.com` (con su contraseña).
2. En el SQL Editor, crea su perfil y rol:

```sql
insert into public.perfiles (id, usuario, nombre, rol)
select id, upper(split_part(email, '@', 1)), v.nombre, v.rol
from auth.users u
join (values
  ('mordonez@marc-eirl.com', 'María Ordoñez',  'gerencia'),
  ('azelaya@marc-eirl.com',  'Angie Zelaya',   'administracion'),
  ('ffonseca@marc-eirl.com', 'Fátima Fonseca', 'comercial'),
  ('rruiz@marc-eirl.com',    'Ricardo Ruiz',   'operaciones')
) as v(email, nombre, rol) on v.email = u.email
on conflict (id) do update set nombre = excluded.nombre, rol = excluded.rol;
```

| Rol | Puede |
|---|---|
| `gerencia` | Todo (incluye borrar y administrar usuarios) |
| `administracion` | Comercial, datos de la empresa, gastos, cajas y compromisos |
| `comercial` | Clientes, tarifario y cotizaciones |
| `operaciones` | Ver todo lo comercial; registrar partes diarios y equipos |

Los permisos los aplica **la base de datos (RLS)**, no solo la pantalla.

## 2. Web (VS Code)

Requisitos: Node 20 o superior.

```bash
cp .env.example .env      # completa VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY (Project Settings → API)
npm install
npm run dev               # http://localhost:5173
```

`npm run build` genera la versión de producción en `dist/`.

## 3. Publicar en Vercel

1. Sube la carpeta a un repositorio de GitHub.
2. En Vercel: **Add New → Project** → importa el repositorio (detecta Vite).
3. En **Environment Variables** agrega `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` y `VITE_LOGIN_DOMAIN`.
4. Deploy. `vercel.json` ya redirige las rutas internas (`/cotizaciones/...`) a la app.
5. En Supabase → **Authentication → URL Configuration**, pon la URL de Vercel como *Site URL*.

## 4. Volver a importar datos desde Excel

```bash
pip install openpyxl
python scripts/generar_seed.py --control "CONTROL DE COTIZACION 2026.xlsx" \
  --tarifario "TARIFARIO CLIENTES.xlsx" --anio 2026 --out supabase/seed/seed_2026.sql
```

Unifica los nombres de cliente escritos de distintas formas y usa IDs fijos: se puede ejecutar varias veces sin duplicar.

### Años anteriores (histórico)

Cada año se carga con su propio archivo de control; el tarifario solo se usa con el año vigente:

```bash
python scripts/generar_seed.py --control "CONTROL DE COTIZACION 2025.xlsx" --anio 2025 --out supabase/seed/seed_2025.sql
python scripts/generar_seed.py --control "CONTROL DE COTIZACION 2024.xlsx" --anio 2024 --out supabase/seed/seed_2024.sql
```

Luego ejecuta cada `seed_<año>.sql` en el SQL Editor (en cualquier orden). Los clientes se reconocen entre años,
y los números que no siguen el formato estándar (p. ej. "NRO DE PARTE 694") se guardan con el año para no chocar.

Con dos o más años cargados, el **tablero** muestra automáticamente:
- Selector de año y comparación contra el **mismo periodo del año anterior** (ventas y conversión).
- Línea del año anterior en el gráfico mensual y tabla de **evolución anual**.
- **Proyección de cierre**: aplica la estacionalidad de los años completos (meses fuertes y débiles: temporada de pesca,
  años con El Niño) al ritmo del año actual. Con un solo año usa el promedio de los últimos 3 meses cerrados.

## 5. Estructura

```
supabase/
  migrations/0001_base.sql                 Esquema comercial + RLS + guardar_cotizacion()
  migrations/0002_operaciones_finanzas.sql Equipos, partes, gastos, cajas, compromisos
  seed/seed_2026.sql                       Datos importados de los Excel
scripts/generar_seed.py                    Importador Excel → SQL
src/
  lib/        supabase, auth (sesión y perfil), catálogos (áreas del menú, % detracción…), formatos, tema
  components/ Layout (menú, barra superior, migas), Splash, Topo (curvas del login), BarChart, Pills, Icon
  pages/      Login, Inicio, Cotizaciones, CotizacionForm, CotizacionDetalle, Clientes, Tarifario, Ajustes, Seccion
```

### Reglas de negocio ya implementadas

- **N° de cotización** automático `AA-NNNN-MM-AAAA` (AA = años de la empresa: 2026 → 09), sin repetidos aunque dos personas guarden a la vez.
- **Detracción sugerida**: traslado 4%, termofusión/electrofusión 12%, demás servicios 10%, solo si el total supera S/ 700.
- **Tarifa sugerida** por cliente y servicio, con aviso de horas mínimas.
- **Libre / Facturado**: lo libre no lleva IGV ni detracción.
- **Nueva versión**: crea otro número enlazado y deja la anterior como REEMPLAZADA.
- **Vencimiento** = fecha de comprobante + días de la condición de pago; **días de atraso** contra la fecha real de depósito.
- **Costeo estimado** interno con gastos administrativos (10% por defecto) y utilidad estimada.

## 6. Siguiente fase sugerida

1. Partes diarios (desde el celular del operador) → ingreso por equipo.
2. Gastos con equipo, RQ y caja → utilidad real por equipo y por proyecto (`v_utilidad_equipo_mes`).
3. Compromisos (préstamos, planilla) → utilidad después de gastos fijos y caja proyectada.
4. Documentos (Supabase Storage) para OS, HES, facturas XML/PDF y documentos de equipos con vencimiento.
5. Con el histórico cargado: escenarios A/B/C (año normal, año Niño, año fuerte) y metas mensuales por asesora.
