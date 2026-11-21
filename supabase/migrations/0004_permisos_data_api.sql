-- =====================================================================
-- 0004 · Permisos para la Data API (supabase-js)
-- Desde el 30-may-2026 los proyectos nuevos de Supabase ya NO exponen
-- automáticamente las tablas de "public" a la web: hay que darles GRANT.
-- La seguridad real la siguen dando las políticas RLS (todas las tablas
-- tienen RLS activo), por eso solo se concede al rol "authenticated".
-- Es idempotente: se puede ejecutar varias veces.
-- =====================================================================

grant usage on schema public to authenticated;

-- Tablas
grant select, insert, update, delete on
  public.perfiles, public.empresa, public.clientes, public.tarifas,
  public.cotizaciones, public.cotizacion_items, public.cotizacion_costos,
  public.equipos, public.equipo_documentos, public.partes_diarios,
  public.cajas, public.gastos, public.compromisos
to authenticated;

-- Vistas (solo lectura)
grant select on
  public.v_cotizaciones, public.v_clientes_resumen, public.v_utilidad_equipo_mes,
  public.v_ventas_mensuales, public.v_anios
to authenticated;

-- Secuencias y funciones
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.mi_rol(), public.puede_editar_comercial(),
  public.guardar_cotizacion(jsonb) to authenticated;

-- Nadie sin sesión (anon) puede leer nada
revoke all on all tables in schema public from anon;

-- Comprobación: debe mostrar 13 tablas con permiso
select count(*) as tablas_con_permiso
from information_schema.role_table_grants
where grantee = 'authenticated' and table_schema = 'public'
  and privilege_type = 'SELECT' and table_name not like 'v\_%';
