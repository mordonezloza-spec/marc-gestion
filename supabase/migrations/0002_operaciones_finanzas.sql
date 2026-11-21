-- =====================================================================
-- MARC · 0002_operaciones_finanzas.sql
-- Base para la siguiente etapa: equipos, partes diarios, gastos, cajas y
-- compromisos fijos (préstamos, planilla). Con esto se calcula la
-- utilidad por equipo, por proyecto (RQ) y por mes sin digitar dos veces.
-- (Las pantallas se construyen en la siguiente fase.)
-- =====================================================================

create table if not exists public.equipos (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,          -- RETRO-02, RETRO-03, GRUA-01…
  nombre         text not null,                 -- Retroexcavadora CAT 416 N°02
  tipo           text not null,                 -- RETROEXCAVADORA | CAMION GRUA | CAMIONETA | MOTO | OTRO
  placa          text,
  operador       text,
  horometro      numeric(10,1),
  activo         boolean not null default true,
  created_at     timestamptz not null default now()
);

insert into public.equipos (codigo, nombre, tipo, placa, operador) values
  ('GRUA-01',  'Camión grúa',                       'CAMION GRUA',     'BRK-731', 'Nilton Barrenechea'),
  ('RETRO-02', 'Retroexcavadora CAT 416 N°02',      'RETROEXCAVADORA', null,      'Franco'),
  ('RETRO-03', 'Retroexcavadora CAT 416 N°03',      'RETROEXCAVADORA', null,      'José Ch.'),
  ('CAMIONETA','Camioneta',                         'CAMIONETA',       'BLF-910', null),
  ('MOTO-03',  'Moto lineal de apoyo',              'MOTO',            null,      null)
on conflict (codigo) do nothing;

-- Documentos del equipo con vencimiento (SOAT, revisión técnica, certificado de operatividad…)
create table if not exists public.equipo_documentos (
  id           uuid primary key default gen_random_uuid(),
  equipo_id    uuid not null references public.equipos(id) on delete cascade,
  tipo         text not null,
  numero       text,
  vence        date,
  archivo_url  text
);

-- Parte diario = ingreso del equipo (reemplaza la hoja INGRESO SEMANAL)
create table if not exists public.partes_diarios (
  id               uuid primary key default gen_random_uuid(),
  numero           int unique,
  fecha            date not null,
  equipo_id        uuid not null references public.equipos(id),
  cotizacion_id    uuid references public.cotizaciones(id),
  cliente_id       uuid references public.clientes(id),
  operador         text,
  actividad        text,
  horometro_inicio numeric(10,1),
  horometro_fin    numeric(10,1),
  horas            numeric(6,2) generated always as (horometro_fin - horometro_inicio) stored,
  horas_facturables numeric(6,2),
  recorrido        numeric(6,2),
  tarifa           numeric(12,2),
  peajes           numeric(12,2) default 0,
  monto            numeric(14,2),
  conformidad      text,          -- nombre de quien firma por el cliente
  created_at       timestamptz not null default now(),
  created_by       uuid default auth.uid()
);
create index if not exists partes_fecha_idx on public.partes_diarios (fecha, equipo_id);

-- Cajas: banco, caja chica (por responsable), efectivo de servicios libres
create table if not exists public.cajas (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null unique,     -- BCP, CAJA CHICA, CAJA CHICA - FATIMA, EFECTIVO
  tipo        text not null check (tipo in ('BANCO','CAJA CHICA','EFECTIVO')),
  fondo       numeric(12,2),
  responsable text
);
insert into public.cajas (nombre, tipo, fondo, responsable) values
  ('BANCO','BANCO',null,null), ('CAJA CHICA','CAJA CHICA',1000,'Angie Zelaya'),
  ('CAJA CHICA - FATIMA','CAJA CHICA',1000,'Fátima Fonseca'), ('EFECTIVO','EFECTIVO',null,'María Ordoñez')
on conflict (nombre) do nothing;

-- Un solo registro de gasto (egreso)
create table if not exists public.gastos (
  id               uuid primary key default gen_random_uuid(),
  fecha            date not null,
  proveedor        text,
  proveedor_ruc    text,
  tipo_documento   text,          -- FACTURA, BOLETA, NOTA DE VENTA, RECIBO POR HONORARIOS, LIBRE
  numero_documento text,
  descripcion      text not null,
  tipo_gasto       text not null check (tipo_gasto in ('OPERATIVO','PREVENTIVO','CORRECTIVO','ADMINISTRATIVO','SERV. BÁSICOS','PERSONAL','FINANCIERO','OTROS')),
  categoria        text,          -- COMBUSTIBLE, PEAJE, VIÁTICOS, REPUESTOS…
  equipo_id        uuid references public.equipos(id),
  cotizacion_id    uuid references public.cotizaciones(id),
  caja_id          uuid references public.cajas(id),
  forma_pago       text check (forma_pago in ('EFECTIVO','TRANSFERENCIA','CRÉDITO')),
  responsable      text,
  cantidad         numeric(12,3),
  monto            numeric(14,2) not null,
  observacion      text,
  created_at       timestamptz not null default now(),
  created_by       uuid default auth.uid()
);
create index if not exists gastos_fecha_idx on public.gastos (fecha);
create index if not exists gastos_equipo_idx on public.gastos (equipo_id, fecha);

-- Compromisos fijos: préstamos, planilla, AFP, SCTR, servicios
create table if not exists public.compromisos (
  id          uuid primary key default gen_random_uuid(),
  concepto    text not null,      -- PRÉSTAMO BCP, PRÉSTAMO SCOTIABANK, PLANILLA QUINCENA…
  tipo        text not null check (tipo in ('PRÉSTAMO','PLANILLA','IMPUESTOS Y SEGUROS','SERVICIOS','OTROS')),
  monto       numeric(14,2) not null,
  dia_pago    int check (dia_pago between 1 and 31),
  cuotas      int,
  desde       date,
  hasta       date,
  activo      boolean not null default true
);

-- Utilidad mensual por equipo (ingreso de partes − gastos del equipo)
create or replace view public.v_utilidad_equipo_mes with (security_invoker = true) as
with ing as (
  select equipo_id, date_trunc('month', fecha)::date as mes, sum(monto) as ingreso, sum(horas) as horas
  from public.partes_diarios group by 1,2
), gas as (
  select equipo_id, date_trunc('month', fecha)::date as mes, sum(monto) as gasto
  from public.gastos where equipo_id is not null group by 1,2
)
select e.id as equipo_id, e.nombre, m.mes,
       coalesce(i.horas,0) as horas, coalesce(i.ingreso,0) as ingreso, coalesce(g.gasto,0) as gasto,
       coalesce(i.ingreso,0) - coalesce(g.gasto,0) as utilidad
from (select equipo_id, mes from ing union select equipo_id, mes from gas) m
join public.equipos e on e.id = m.equipo_id
left join ing i on i.equipo_id = m.equipo_id and i.mes = m.mes
left join gas g on g.equipo_id = m.equipo_id and g.mes = m.mes;

-- RLS: todos los roles leen; registra operaciones (partes), administración (gastos/cajas); gerencia todo
alter table public.equipos           enable row level security;
alter table public.equipo_documentos enable row level security;
alter table public.partes_diarios    enable row level security;
alter table public.cajas             enable row level security;
alter table public.gastos            enable row level security;
alter table public.compromisos       enable row level security;

do $$
declare t text; quien text;
begin
  foreach t in array array['equipos','equipo_documentos','partes_diarios','cajas','gastos','compromisos'] loop
    quien := case t
      when 'partes_diarios'    then '(''gerencia'',''administracion'',''operaciones'')'
      when 'equipos'           then '(''gerencia'',''administracion'',''operaciones'')'
      when 'equipo_documentos' then '(''gerencia'',''administracion'',''operaciones'')'
      else '(''gerencia'',''administracion'')' end;
    execute format('drop policy if exists %1$s_leer on public.%1$s', t);
    execute format('create policy %1$s_leer on public.%1$s for select to authenticated using (public.mi_rol() is not null)', t);
    execute format('drop policy if exists %1$s_escribir on public.%1$s', t);
    execute format('create policy %1$s_escribir on public.%1$s for all to authenticated using (public.mi_rol() in %2$s) with check (public.mi_rol() in %2$s)', t, quien);
  end loop;
end $$;

grant select on public.v_utilidad_equipo_mes to authenticated;
