-- =====================================================================
-- MARC · 0003_historico.sql
-- Resumen mensual multi-año para comparar años y proyectar.
-- Funciona con cualquier año cargado (seed_2025.sql, seed_2024.sql…).
-- =====================================================================

create or replace view public.v_ventas_mensuales with (security_invoker = true) as
select
  extract(year  from c.fecha)::int                                   as anio,
  extract(month from c.fecha)::int                                   as mes,
  c.servicio,
  c.cliente_id,
  count(*)                                                           as cotizaciones,
  count(*) filter (where c.estado = 'ACEPTADO')                      as aceptadas,
  count(*) filter (where c.estado = 'RECHAZADO')                     as rechazadas,
  coalesce(sum(c.subtotal)    filter (where c.estado = 'ACEPTADO' and c.moneda = 'PEN'), 0) as venta_facturada,
  coalesce(sum(c.total_libre) filter (where c.estado = 'ACEPTADO' and c.moneda = 'PEN'), 0) as venta_libre,
  coalesce(sum(c.subtotal + c.total_libre) filter (where c.estado = 'ACEPTADO' and c.moneda = 'PEN'), 0) as venta
from public.cotizaciones c
where c.estado <> 'REEMPLAZADA'
group by 1, 2, 3, 4;

-- Años disponibles con su cobertura (para saber si un año está completo)
create or replace view public.v_anios with (security_invoker = true) as
select extract(year from fecha)::int as anio,
       min(fecha) as desde, max(fecha) as hasta,
       count(distinct extract(month from fecha)) as meses_con_datos,
       count(*) as cotizaciones
from public.cotizaciones
group by 1
order by 1;

grant select on public.v_ventas_mensuales, public.v_anios to authenticated;
