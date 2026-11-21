-- =====================================================================
-- MARC · Sistema de Gestión — INSTALACIÓN INICIAL (un solo archivo)
-- Supabase → SQL Editor → New query → pegar todo → Run
-- Incluye: 0001_base + 0002_operaciones_finanzas + 0003_historico + datos 2026
-- Se puede volver a ejecutar sin duplicar datos.
-- Después ejecuta usuarios.sql (cuando ya hayas creado los usuarios en Authentication).
-- =====================================================================


-- >>>>>>>>>>>>>>>>>>>> migrations/0001_base.sql
-- =====================================================================
-- MARC · Sistema de gestión empresarial
-- 0001_base.sql — Usuarios, clientes, tarifario y cotizaciones (Fase 1)
-- Ejecutar en Supabase: SQL Editor → pegar y ejecutar (o `supabase db push`)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create or replace function public.tg_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Perfiles de usuario (1 fila por usuario de Supabase Auth)
-- rol: gerencia | administracion | comercial | operaciones
-- ---------------------------------------------------------------------
create table if not exists public.perfiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  usuario     text not null unique,              -- AZELAYA, FFONSECA, MORDONEZ, RRUIZ
  nombre      text not null,
  rol         text not null check (rol in ('gerencia','administracion','comercial','operaciones')),
  activo      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Rol del usuario conectado (se usa en las políticas RLS)
create or replace function public.mi_rol()
returns text language sql stable security definer set search_path = public as $$
  select rol from public.perfiles where id = auth.uid() and activo
$$;

create or replace function public.puede_editar_comercial()
returns boolean language sql stable as $$
  select coalesce(public.mi_rol() in ('gerencia','administracion','comercial'), false)
$$;

-- ---------------------------------------------------------------------
-- Datos de la empresa (una sola fila)
-- ---------------------------------------------------------------------
create table if not exists public.empresa (
  id                 int primary key default 1 check (id = 1),
  razon_social       text not null,
  ruc                text not null,
  direccion          text,
  telefono           text,
  correo             text,
  cuenta_soles       text,     -- ej. Cuenta corriente BCP soles
  cuenta_detraccion  text,     -- ej. Banco de la Nación
  prefijo_base_anio  int not null default 2017,  -- 2026 - 2017 = "09"
  updated_at         timestamptz not null default now()
);
insert into public.empresa (id, razon_social, ruc, direccion)
values (1, 'MARC DISTRIBUTION & SOLUTIONS IMPORT E.I.R.L.', '20601988322', 'Nueva Panamericana Norte Km 189 – La Minka, Supe')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Clientes (maestro único; el RUC es la llave natural)
-- ---------------------------------------------------------------------
create table if not exists public.clientes (
  id              uuid primary key default gen_random_uuid(),
  razon_social    text not null,
  ruc             text unique,
  direccion       text,
  rubro           text,               -- pesquera, agroexportadora, minera, construcción…
  condicion_pago  text,               -- CONTADO, CRÉDITO 15 DÍAS, FACTORING 60 DÍAS…
  activo          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid default auth.uid()
);
create unique index if not exists clientes_razon_social_uq on public.clientes (upper(razon_social));
drop trigger if exists clientes_updated on public.clientes;
create trigger clientes_updated before update on public.clientes for each row execute function public.tg_updated_at();

-- ---------------------------------------------------------------------
-- Tarifario por cliente y servicio
-- servicio: RETROEXCAVADORA | CAMION GRUA | TRASLADO | ...
-- Para TRASLADO se usan descripcion/origen/destino y tarifa = monto por viaje
-- ---------------------------------------------------------------------
create table if not exists public.tarifas (
  id               uuid primary key default gen_random_uuid(),
  cliente_id       uuid not null references public.clientes(id) on delete cascade,
  servicio         text not null,
  horas_minimas    numeric(6,2),
  tarifa           numeric(12,2) not null,          -- S/ por hora (o por viaje en traslados)
  cobra_recorrido  boolean not null default false,
  incluye_almuerzo boolean not null default false,
  incluye_igv      boolean not null default false,
  horas_jornada    numeric(6,2),
  tarifa_jornada   numeric(12,2),
  descripcion      text,
  origen           text,
  destino          text,
  vigente_desde    date not null default current_date,
  activo           boolean not null default true,
  updated_at       timestamptz not null default now()
);
create index if not exists tarifas_cliente_idx on public.tarifas (cliente_id, servicio);
drop trigger if exists tarifas_updated on public.tarifas;
create trigger tarifas_updated before update on public.tarifas for each row execute function public.tg_updated_at();

-- ---------------------------------------------------------------------
-- Cotizaciones (RQ) = expediente del servicio
-- ---------------------------------------------------------------------
create table if not exists public.cotizaciones (
  id                uuid primary key default gen_random_uuid(),
  numero            text not null unique,          -- 09-0310-11-2026 (lo asigna el trigger)
  anio              int,
  correlativo       int,
  fecha             date not null default current_date,
  cliente_id        uuid not null references public.clientes(id),
  ruc               text,
  direccion         text,
  sede              text,
  contacto          text,
  correo            text,
  asesor            text,
  motivo_contacto   text,
  servicio          text,
  tipo_comprobante  text not null default 'FACTURADO' check (tipo_comprobante in ('FACTURADO','LIBRE')),
  moneda            text not null default 'PEN' check (moneda in ('PEN','USD')),
  tipo_cambio       numeric(8,4),
  validez_dias      int not null default 7,
  descripcion       text,
  mostrar_detalle   boolean not null default true,
  subtotal          numeric(14,2) not null default 0,   -- facturado (sin IGV)
  total_libre       numeric(14,2) not null default 0,   -- sin comprobante
  detraccion_pct    numeric(5,4) not null default 0,
  detraccion_monto  numeric(14,2) not null default 0,
  condiciones       text,
  gastos_adm_pct    numeric(5,2) not null default 10,
  estado            text not null default 'ENVIADO'
                    check (estado in ('ENVIADO','EN PROCESO','ACEPTADO','RECHAZADO','REEMPLAZADA')),
  motivo_rechazo    text,
  obs_comercial     text,
  version_de        uuid references public.cotizaciones(id),
  reemplazada_por   uuid references public.cotizaciones(id),
  -- Seguimiento
  orden_servicio    text,
  partes            text,
  hes               text,
  condicion_pago    text,
  comprobante       text,
  fecha_comprobante date,
  estado_detraccion text check (estado_detraccion in ('PENDIENTE','CANCELADO','NO APLICA')),
  estado_pago       text check (estado_pago in ('PENDIENTE DE FACTURACIÓN','PENDIENTE DE PAGO','CANCELADO','NEGOCIADA','RECHAZADO')),
  fecha_pago        date,
  monto_pagado      numeric(14,2),
  obs_cobro         text,
  origen            text not null default 'SISTEMA',   -- SISTEMA | EXCEL 2026
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid default auth.uid()
);
create index if not exists cot_fecha_idx   on public.cotizaciones (fecha desc);
create index if not exists cot_cliente_idx on public.cotizaciones (cliente_id);
create index if not exists cot_estado_idx  on public.cotizaciones (estado, estado_pago);
drop trigger if exists cotizaciones_updated on public.cotizaciones;
create trigger cotizaciones_updated before update on public.cotizaciones for each row execute function public.tg_updated_at();

create table if not exists public.cotizacion_items (
  id               uuid primary key default gen_random_uuid(),
  cotizacion_id    uuid not null references public.cotizaciones(id) on delete cascade,
  orden            int not null default 1,
  descripcion      text not null,
  unidad           text not null default 'HORAS',
  cantidad         numeric(12,2) not null default 1,
  precio_unitario  numeric(14,2) not null default 0
);
create index if not exists items_cot_idx on public.cotizacion_items (cotizacion_id, orden);

-- Costeo estimado (interno, no lo ve el cliente)
create table if not exists public.cotizacion_costos (
  id             uuid primary key default gen_random_uuid(),
  cotizacion_id  uuid not null references public.cotizaciones(id) on delete cascade,
  rubro          text not null,
  detalle        text,
  monto          numeric(14,2) not null default 0
);
create index if not exists costos_cot_idx on public.cotizacion_costos (cotizacion_id);

-- ---------------------------------------------------------------------
-- Número de cotización: <años de la empresa>-<correlativo anual>-<mes>-<año>
-- Ej.: 2026 → 09-0310-11-2026. Usa un candado para evitar números repetidos.
-- ---------------------------------------------------------------------
create or replace function public.tg_cotizacion_numero()
returns trigger language plpgsql as $$
declare
  base int;
  m    text[];
begin
  if new.numero is null or new.numero = '' then
    select prefijo_base_anio into base from public.empresa where id = 1;
    new.anio := extract(year from new.fecha)::int;
    perform pg_advisory_xact_lock(hashtext('cotizacion_' || new.anio));
    select coalesce(max(correlativo), 0) + 1 into new.correlativo
      from public.cotizaciones where anio = new.anio;
    new.numero := lpad((new.anio - coalesce(base, 2017))::text, 2, '0') || '-' ||
                  lpad(new.correlativo::text, 4, '0') || '-' ||
                  to_char(new.fecha, 'MM') || '-' || new.anio;
  elsif new.correlativo is null then
    m := regexp_match(new.numero, '^\d{2}-(\d{3,4})-\d{2}-(\d{4})$');
    if m is not null then
      new.correlativo := m[1]::int;
      new.anio := m[2]::int;
    else
      new.anio := coalesce(new.anio, extract(year from new.fecha)::int);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists cotizaciones_numero on public.cotizaciones;
create trigger cotizaciones_numero before insert on public.cotizaciones
for each row execute function public.tg_cotizacion_numero();

-- ---------------------------------------------------------------------
-- Vistas para la web
-- ---------------------------------------------------------------------
create or replace view public.v_cotizaciones with (security_invoker = true) as
select
  c.*,
  cl.razon_social as cliente,
  (c.subtotal + c.total_libre)                                   as venta,
  round(c.subtotal * 0.18, 2)                                    as igv,
  round(c.subtotal * 1.18 + c.total_libre, 2)                    as total,
  case when c.fecha_comprobante is not null and c.condicion_pago ~ '\d+'
       then c.fecha_comprobante + (substring(c.condicion_pago from '\d+'))::int end as fecha_vencimiento,
  case when c.fecha_comprobante is not null and c.condicion_pago ~ '\d+'
       then coalesce(c.fecha_pago, current_date) - (c.fecha_comprobante + (substring(c.condicion_pago from '\d+'))::int) end as dias_atraso
from public.cotizaciones c
join public.clientes cl on cl.id = c.cliente_id;

create or replace view public.v_clientes_resumen with (security_invoker = true) as
select
  cl.*,
  count(c.id)                                                   as cotizaciones,
  count(c.id) filter (where c.estado = 'ACEPTADO')              as aceptadas,
  coalesce(sum(c.subtotal + c.total_libre) filter (where c.estado = 'ACEPTADO' and c.moneda = 'PEN'), 0) as venta_pen,
  max(c.fecha)                                                  as ultima_cotizacion,
  (select array_agg(distinct t.servicio) from public.tarifas t where t.cliente_id = cl.id and t.activo) as servicios_tarifa
from public.clientes cl
left join public.cotizaciones c on c.cliente_id = cl.id
group by cl.id;

-- ---------------------------------------------------------------------
-- Guardar una cotización completa (cabecera + ítems + costos) en una sola transacción.
-- p: json con los campos de la cotización, "items": [...], "costos": [...]
-- Si viene "cliente_nombre" sin "cliente_id", crea el cliente.
-- Si viene "version_de", marca la cotización anterior como REEMPLAZADA.
-- ---------------------------------------------------------------------
create or replace function public.guardar_cotizacion(p jsonb)
returns uuid language plpgsql security invoker set search_path = public as $$
declare
  v_id      uuid := nullif(p->>'id','')::uuid;
  v_cliente uuid := nullif(p->>'cliente_id','')::uuid;
  it        jsonb;
  i         int := 0;
begin
  if not public.puede_editar_comercial() then
    raise exception 'No tienes permiso para registrar cotizaciones';
  end if;

  if v_cliente is null then
    if coalesce(trim(p->>'cliente_nombre'),'') = '' then
      raise exception 'Falta el cliente';
    end if;
    select id into v_cliente from public.clientes
     where upper(razon_social) = upper(trim(p->>'cliente_nombre'))
        or (nullif(p->>'ruc','') is not null and ruc = p->>'ruc')
     limit 1;
    if v_cliente is null then
      insert into public.clientes (razon_social, ruc, direccion)
      values (upper(trim(p->>'cliente_nombre')), nullif(p->>'ruc',''), nullif(p->>'direccion',''))
      returning id into v_cliente;
    end if;
  end if;

  if v_id is null then
    insert into public.cotizaciones (
      fecha, cliente_id, ruc, direccion, sede, contacto, correo, asesor, motivo_contacto, servicio,
      tipo_comprobante, moneda, tipo_cambio, validez_dias, descripcion, mostrar_detalle,
      subtotal, total_libre, detraccion_pct, detraccion_monto, condiciones, gastos_adm_pct, version_de)
    values (
      coalesce((p->>'fecha')::date, current_date), v_cliente, p->>'ruc', p->>'direccion', p->>'sede',
      p->>'contacto', p->>'correo', p->>'asesor', p->>'motivo_contacto', p->>'servicio',
      coalesce(p->>'tipo_comprobante','FACTURADO'), coalesce(p->>'moneda','PEN'), nullif(p->>'tipo_cambio','')::numeric,
      coalesce((p->>'validez_dias')::int, 7), p->>'descripcion', coalesce((p->>'mostrar_detalle')::boolean, true),
      coalesce((p->>'subtotal')::numeric,0), coalesce((p->>'total_libre')::numeric,0),
      coalesce((p->>'detraccion_pct')::numeric,0), coalesce((p->>'detraccion_monto')::numeric,0),
      p->>'condiciones', coalesce((p->>'gastos_adm_pct')::numeric,10), nullif(p->>'version_de','')::uuid)
    returning id into v_id;

    if nullif(p->>'version_de','') is not null then
      update public.cotizaciones set estado = 'REEMPLAZADA', reemplazada_por = v_id
       where id = (p->>'version_de')::uuid;
    end if;
  else
    update public.cotizaciones set
      fecha = coalesce((p->>'fecha')::date, fecha), cliente_id = v_cliente, ruc = p->>'ruc', direccion = p->>'direccion',
      sede = p->>'sede', contacto = p->>'contacto', correo = p->>'correo', asesor = p->>'asesor',
      motivo_contacto = p->>'motivo_contacto', servicio = p->>'servicio',
      tipo_comprobante = coalesce(p->>'tipo_comprobante','FACTURADO'), moneda = coalesce(p->>'moneda','PEN'),
      tipo_cambio = nullif(p->>'tipo_cambio','')::numeric, validez_dias = coalesce((p->>'validez_dias')::int, 7),
      descripcion = p->>'descripcion', mostrar_detalle = coalesce((p->>'mostrar_detalle')::boolean, true),
      subtotal = coalesce((p->>'subtotal')::numeric,0), total_libre = coalesce((p->>'total_libre')::numeric,0),
      detraccion_pct = coalesce((p->>'detraccion_pct')::numeric,0), detraccion_monto = coalesce((p->>'detraccion_monto')::numeric,0),
      condiciones = p->>'condiciones', gastos_adm_pct = coalesce((p->>'gastos_adm_pct')::numeric,10)
    where id = v_id;
    delete from public.cotizacion_items  where cotizacion_id = v_id;
    delete from public.cotizacion_costos where cotizacion_id = v_id;
  end if;

  for it in select * from jsonb_array_elements(coalesce(p->'items','[]'::jsonb)) loop
    i := i + 1;
    insert into public.cotizacion_items (cotizacion_id, orden, descripcion, unidad, cantidad, precio_unitario)
    values (v_id, i, coalesce(it->>'descripcion',''), coalesce(it->>'unidad','HORAS'),
            coalesce((it->>'cantidad')::numeric,0), coalesce((it->>'precio_unitario')::numeric,0));
  end loop;

  for it in select * from jsonb_array_elements(coalesce(p->'costos','[]'::jsonb)) loop
    insert into public.cotizacion_costos (cotizacion_id, rubro, detalle, monto)
    values (v_id, coalesce(it->>'rubro','OTROS'), it->>'detalle', coalesce((it->>'monto')::numeric,0));
  end loop;

  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Seguridad por filas (RLS)
--   gerencia: todo · administracion/comercial: comercial · operaciones: lectura
-- ---------------------------------------------------------------------
alter table public.perfiles          enable row level security;
alter table public.empresa           enable row level security;
alter table public.clientes          enable row level security;
alter table public.tarifas           enable row level security;
alter table public.cotizaciones      enable row level security;
alter table public.cotizacion_items  enable row level security;
alter table public.cotizacion_costos enable row level security;

drop policy if exists perfiles_leer on public.perfiles;
create policy perfiles_leer on public.perfiles for select to authenticated
  using (id = auth.uid() or public.mi_rol() = 'gerencia');
drop policy if exists perfiles_gerencia on public.perfiles;
create policy perfiles_gerencia on public.perfiles for all to authenticated
  using (public.mi_rol() = 'gerencia') with check (public.mi_rol() = 'gerencia');

drop policy if exists empresa_leer on public.empresa;
create policy empresa_leer on public.empresa for select to authenticated using (public.mi_rol() is not null);
drop policy if exists empresa_editar on public.empresa;
create policy empresa_editar on public.empresa for update to authenticated
  using (public.mi_rol() in ('gerencia','administracion')) with check (public.mi_rol() in ('gerencia','administracion'));

do $$
declare t text;
begin
  foreach t in array array['clientes','tarifas','cotizaciones','cotizacion_items','cotizacion_costos'] loop
    execute format('drop policy if exists %1$s_leer on public.%1$s', t);
    execute format('create policy %1$s_leer on public.%1$s for select to authenticated using (public.mi_rol() is not null)', t);
    execute format('drop policy if exists %1$s_insertar on public.%1$s', t);
    execute format('create policy %1$s_insertar on public.%1$s for insert to authenticated with check (public.puede_editar_comercial())', t);
    execute format('drop policy if exists %1$s_editar on public.%1$s', t);
    execute format('create policy %1$s_editar on public.%1$s for update to authenticated using (public.puede_editar_comercial()) with check (public.puede_editar_comercial())', t);
    execute format('drop policy if exists %1$s_borrar on public.%1$s', t);
    execute format('create policy %1$s_borrar on public.%1$s for delete to authenticated using (public.mi_rol() = ''gerencia'' or (%2$s and public.puede_editar_comercial()))',
                   t, case when t in ('cotizacion_items','cotizacion_costos') then 'true' else 'false' end);
  end loop;
end $$;

grant select on public.v_cotizaciones, public.v_clientes_resumen to authenticated;
grant execute on function public.guardar_cotizacion(jsonb) to authenticated;
grant execute on function public.mi_rol() to authenticated;

-- >>>>>>>>>>>>>>>>>>>> migrations/0002_operaciones_finanzas.sql
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

-- >>>>>>>>>>>>>>>>>>>> migrations/0003_historico.sql
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

-- >>>>>>>>>>>>>>>>>>>> seed/seed_2026.sql
-- Datos importados de los Excel de MARC (2026). Generado 2026-11-14.
-- Ejecutar DESPUÉS de las migraciones, con un usuario con permisos (SQL Editor de Supabase).
begin;
insert into public.clientes (id, razon_social, ruc) values
  ('2fd8d87e-9b83-56a2-bafa-654f906e2d81', 'AGRICOLA CORDILLERA', null),
  ('8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'AGRICOLA INTERANDINA SAC', null),
  ('06c7e010-0ddb-5767-83c7-3749b7b74826', 'AGRICOLA SANTA AZUL SRL', null),
  ('854e6948-343b-56a7-a0c9-41e74e6a4a13', 'AGROEXPORTADORA BRISAS DEL CAMPO S.A.C.', null),
  ('26024478-2588-5c0b-87a8-0c09b8a1475f', 'ALCAS NEGOCIOS S.A.C.', null),
  ('2f19a704-1cbc-50fa-85cb-5d685ac6f51e', 'ARCO IRIS MAQUISERVICIOS E.I.R.L.', null),
  ('bd469c6e-9ad7-5473-974c-de8d69045d3a', 'ARELLAN TARAZONA JULIO CESAR', null),
  ('4e0ceeeb-5448-560a-b5c3-37f0373a4153', 'ARIS INDUSTRIAL S.A.', null),
  ('bd3eb801-5fdf-514c-9ef9-28e98998266a', 'ASIMOV KAS S.R.L.', null),
  ('2a6edcfa-ef6c-5c80-a9cc-990c98fb81fb', 'ATI GROUP', null),
  ('f3580583-1978-579a-a7cd-6cfd1d44da9f', 'AVALEZA S.A.', null),
  ('75c1286c-0bdd-529c-89b0-788be9a13bd8', 'AVEBIOL S.A.C.', null),
  ('6397e53d-b3cd-56ad-87ac-35ed74014728', 'AYB COLD TECNOLOGY S.A.C.', null),
  ('7b6c76a3-8733-548a-a4ee-858dbbcab6cd', 'BLACK SWAN MINERALS S.A.C.', null),
  ('8f11eae4-3b75-54a5-9cce-14f6cb76e73d', 'CC COURIER', null),
  ('acbae08d-63cf-5e12-99c9-a61630f9d9db', 'CICEMETAL S.A.', null),
  ('cea208fc-df7b-50a0-9ca3-a794b05af0c2', 'COLPEX INTERNATIONAL SAC', null),
  ('c26ce603-d4b3-5f13-bf62-f8b1ed199df3', 'COMERC. JEREMY AIMAR E.I.R.L.', null),
  ('e209d667-1fa0-547f-bd1e-7c24d0337c17', 'CONSTRUC. & ACABADOS V.S. S.A.C.', null),
  ('12d3f00d-122d-5c26-af92-a0ed2df98093', 'CONTRATISTA GENERALES G.M', null),
  ('baa57998-ffb4-5d4c-9011-107a0e94a1bd', 'CORPORACION AKELA S.A.C.', null),
  ('e1b2d1e2-1ec4-552c-aa35-8d719a0ca65a', 'CORPORACION EMPRESARIAL PROSPECTIVA S.A.C.', null),
  ('f8e159c4-f059-5152-9196-7bdcf4b84d4a', 'CORPORACION PESQUERA INCA S.A.C.', null),
  ('a86f9290-d305-5120-bffb-96623bc6d28c', 'CORPORATIVA MAIDEN E.I.R.L', null),
  ('3717ef3b-c5b8-501c-80a6-67f80c34b9a1', 'COSMOS AGENCIA MARITIMA S.A.C.', null),
  ('f0d90778-2016-5a46-80ff-0c4471954da3', 'DATA ONLINE S.A.C.', null),
  ('e946cead-68f1-541f-b4b9-7a589681602b', 'DEMEXO S.A.C', null),
  ('70717265-26b5-535f-a97c-b79bcfe69a3a', 'ELECTRO COSTA NORTE', null),
  ('3d9e42cf-d6e7-5f65-bd3d-c960d1bd476f', 'ELECTROCONS MINING S.A.C.', null),
  ('4b05993f-f9e4-5f2c-b800-ff5e8552fe9c', 'EMPRESA AYB SAC', null),
  ('86cc280f-6895-5548-948c-f2ba9255f47f', 'EMPRESA DE SERV. GRALES. SIPROING S.A.C.', '20602450491'),
  ('596a62f0-acfa-5282-ae91-a89d90db40d8', 'FABRICACION Y MONTAJE DE EQUIPOS INDUSTRIALES CALLAO S.A.C.- FMEI CALLAO S.A.C.', null),
  ('bf8cc556-3df2-584d-a7bf-f75b8c41b914', 'FABRISER E.R.L.', null),
  ('388ad6b3-244d-5639-a0ac-1e85137c0565', 'FACTORIA PANANA', null),
  ('4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'FAMEGI SA', '20542106124'),
  ('167d8ef2-bbb1-58c6-9d6d-5eda2335b198', 'FAMIN S.A', null),
  ('36ffb193-565b-5563-9e7f-768b0428236c', 'FERNANDO BRAVO', null),
  ('a40e7fb9-6138-5f41-9649-4afaca400cd0', 'FIERROS Y METALES TONY SAC', null),
  ('092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'FJ MANTENIMIENTO S.A.C.', null),
  ('7894d29b-be15-5468-bc7c-c0d548393f41', 'FORDAIS GROUP S.A.C.', null),
  ('ab5d137d-798b-52e1-8659-f7a646002cc9', 'GASOCENTROS Y ESTRUCTURAS METALICAS H.C SOCIEDAD ANONIMA CERRADA - GEMETAL H.C S.A.C', null),
  ('b437920b-e976-57ed-ba17-031d0c17371c', 'GCA CONSTRUCTORES S.A.C.', null),
  ('42d979f0-c278-559a-af55-4de61d546577', 'GERMAN ENGINEERRING & CIE. S.A.C.', null),
  ('750b33dc-943f-5308-ac4f-adf1e0bb0d94', 'GPC INGENIEROS S.A.C', null),
  ('d5666fe5-e144-5390-a6fb-bd0e9ca19e9c', 'GRUPO AGAMA S.A.C.', null),
  ('9186f708-5dca-590d-891b-c83c12481f78', 'GRUPO INSERCOM CONTRATISTAS S.A.C.', null),
  ('5e5c97ae-fc83-5129-aca0-abb7aecd1b30', 'GRUPO O''CONNOR S.A.', null),
  ('2d788c48-b27e-53df-8e6c-950efe69a9bd', 'GRUPO RYR S.A.C.', null),
  ('8bd21fa0-6e20-5c75-bc83-f4f96d14cf6f', 'H.A.C. PROYECTOS ACEDO S.A.C', null),
  ('d6877aa6-ce2a-5fdb-ab05-8a6b9fe10ded', 'HAUG S.A.', null),
  ('42d740e8-9898-580c-8bf8-2940e54c9cf8', 'HENRY GARCIA', null),
  ('1c3c01a2-0f97-57f8-aa66-117fe13e6b99', 'HGD CONTRATISTAS SAC', null),
  ('46b542d5-dbaf-5fa5-9790-d981fdd45e3d', 'INDUSTRIA TECNICA METALURGICA Y SERVICIOS ALVITRES PERU S.A.C.', null),
  ('4da5a7ea-86e4-5266-8c08-b6e5c3699955', 'INDUSTRIAS ESQUIVEL SAC', null),
  ('55c0b249-7490-5d80-85ad-c542a54b5159', 'INGENIERIA FABRICACION Y MONTAJE SAC', null),
  ('6aa0df0c-d51f-53f1-b0a0-51d35aca69f9', 'INGENIERÍA R&J E.I.R.L.', null),
  ('68d6dde6-064d-562d-821a-11f96855e214', 'INGENIERÍA Y CONSTRUCCIÓN ABSA S.A.C.', null),
  ('c6d1db65-1716-5453-b7d7-12cf7d7eec6e', 'INVERSIONES JORE JAUJA PERU SAC', null),
  ('0364fb61-3244-57a1-87b4-30b80d3a1ad2', 'INVERSIONES Y SERVICIOS GENERALES KYFE', null),
  ('f69dec83-3b89-5f05-973f-593ec0862fd7', 'IPS INGENIEROS S.A.C.', null),
  ('f476656a-7c45-5a5a-90d4-ca6f2f66c2f4', 'J.A. INDUSTRIAS MONTAJES Y SUMINISTROS S.A.C.', null),
  ('2efbc9cc-c182-53f0-a1a8-70395b294841', 'JACOB PALOMINO', null),
  ('c30c4879-d74c-5a53-8670-fcb6b1229886', 'JB BURGOS E.I.R.L', null),
  ('f38c46c3-176c-5574-a069-f6ed7a26484b', 'JDA INDUSTRIAS', null),
  ('0d561a4f-7fcd-53a6-9276-db11ca68643f', 'JOAQUIN LOPEZ', null),
  ('913aeefe-c619-5be4-9d83-bc1e2cb1883b', 'JORGE', null),
  ('7fb861f5-37fe-57f3-9816-0b8c02759124', 'JUNTA DE USUARIOS DEL VALLE PATIVILCA', null),
  ('48f69284-dbf2-5a97-9fee-991e628b4c94', 'JUSTO QUICHIZ', null),
  ('18d64625-efdf-542e-b2f0-04083a664489', 'KROST INGENIERIA S.A.C.', null),
  ('25a5c164-0eae-5345-b080-30023dc0edf4', 'LOS HALCONES S.A.', null),
  ('39239554-b7fc-50af-8834-8241ffe2e88e', 'LUIS NORABUENA', null),
  ('e6df09f2-6185-5c4c-9ed1-d63048a8b6e0', 'MAQUINARIAS IRUN SAC', null),
  ('1f2e949d-e46c-5564-84cd-69ecae4f8c66', 'MEGAN SMART TECHNOLOGY S.A.', null),
  ('f8620314-43b4-5b46-91db-484be70e87eb', 'MERO CUNZA', null),
  ('e1a45986-9920-573b-8469-e3caafae4958', 'METAL METALICO E.I.R. L', null),
  ('74253ffb-ab53-5953-9682-5c5ebd8992a3', 'MEZA TAFUR', null),
  ('992547a8-1c0b-54d2-8a68-a5fec8f7d740', 'MILTON', null),
  ('8527dce6-de10-5b1d-a18d-aa0d6dfc5974', 'MINERA VICUS S.A.C.', null),
  ('c15451ca-b309-54eb-b2eb-e0c2c062bca4', 'MULTISERVICIOS FALVY E.I.R.L.', null),
  ('3e6f1239-ace9-5b21-8a96-a397b15a420d', 'MUNICIPALIDAD DISTRITAL DE PARARIN', null),
  ('3a542a4f-bc91-55c3-9433-2b484e0ed13c', 'PEPAS TROPICALES DEL PERÚ S.A.C.', null),
  ('b4908510-2e97-57b3-a5e2-44fc96b485c7', 'PERUVIAN DIVER Y CO S.A.C.', null),
  ('9d0dffcf-94e9-500a-a49f-88ab88828a62', 'PESQUERA DIAMANTE S.A.', null),
  ('0deaaf9e-144a-507f-b982-22da3984755a', 'PESQUERA ESTRELLITA DEL SUR S.A.', null),
  ('c73b9cdd-5970-542b-96c2-97913d076ec8', 'PESQUERA EXALMAR S.A.A', null),
  ('5eabf785-0989-5fe8-ad26-840b54b78e1d', 'PESQUERA HAYDUK S.A.', null),
  ('5ec233c8-9688-55cc-a0ea-d84bf5d1cd11', 'PESQUERA PELAYO S.A.C.', null),
  ('2af70902-9008-5ce6-a0d9-acf370f5adb4', 'PESQUERA TASA S.A', null),
  ('256a54c0-f63c-52e5-9f3c-53c469387064', 'PROFESORA LILA', null),
  ('cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'QUIMPAC S.A', null),
  ('20320171-ba80-544e-97de-fa78dd28efd1', 'QUINGUA S.A.C', null),
  ('8787b6b5-363b-55bc-9bff-4092294d4a11', 'RASMIN MINERA Y CONSTRUCCION SAC', null),
  ('9237b4d3-8227-5562-892c-6b9353e84721', 'REDONDOS S.A.', null),
  ('edd6571d-faf7-5fdf-b74a-d73061a4070f', 'RICHARD MONTORO', null),
  ('302f007e-757f-55fd-9e25-a5355c8020bf', 'RONALD CALERO', null),
  ('616fbddd-bb2c-5c53-8d81-24dcc6edba58', 'RONALD UTRILLA', null),
  ('93b4846f-c6e4-5516-96b0-a7b6596c00c4', 'SANTA GREGORIA S.R.L.', null),
  ('1cdc8de5-f808-5c77-8bd6-a9bc9fd8d805', 'SEAMAR DIVER INTERNATIONAL S.A.C.', null),
  ('88c56133-2ff3-5699-83d1-62df1e851688', 'SEGEMIND', null),
  ('07a505c6-8328-579d-bc93-193021e23a90', 'SEIMCORR S.A.C. SERVICIOS INTEGRALES DE MANTENIMIENTO CONTRA LA CORROSION - SEIMCORR S.A.C.', null),
  ('129313df-4e73-5d12-9a6c-00564e3acd54', 'SERGEZUBE EIRL', null),
  ('4eaf3051-aaf9-5a32-8cbb-170b104902b9', 'SERVICIOS CACERES SAC', null),
  ('ae8ff2f9-bb68-5047-924f-e950d7161796', 'SERVICIOS SUBMARINOS ROMAN ORDOÑEZ E.I.R.L.', null),
  ('a390e377-1551-54a4-a0e4-c87004b6e5a7', 'SEÑOR COLCA', null),
  ('5646e73f-8f29-5e92-b670-1881365cf47a', 'SEÑOR HUAMANI', null),
  ('b5fe0337-ffa3-5950-90aa-945d3b1474ae', 'SEÑOR PROSPERO', null),
  ('d5354909-2ea2-50a3-8fde-a20e06d4240b', 'SEÑOR VICTOR CORAHUA', null),
  ('11017afb-e5b4-535e-99e8-4c095e63d606', 'SINERGIA AMC SAC', null),
  ('f202991e-35e1-5f72-8a51-521d6d52e6ce', 'SOCACY SERVICIOS GENERALES E.I.R.L.', null),
  ('6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'SOCIEDAD AGRÍCOLA DROKASA S.A.', null),
  ('c8abb4e3-9c5f-5167-8da3-e6f343a28614', 'SOLUCIONES GENERALES ORDOÑEZ E.I.R.L.', null),
  ('5ae6406e-c0ae-5d79-a3cb-8d595ca7d7fa', 'SOLUCIONES HDP EIRL', null),
  ('6e217704-6012-5760-a9ca-11aea6391b6e', 'SOLUCIONES INDUSTRIALES PFA E.I.R.L.', null),
  ('d7cea69c-5b07-5e4d-be6b-fa5dc3de0a93', 'SOLUCIONES METALICAS Y PUBLICITARIAS E.I.R.L', null),
  ('b8fc85aa-260a-534d-aacf-757e0a246a3c', 'SR ABEL NAVENTA', null),
  ('829dfa19-3c1f-5868-9be1-a1ead2aa3878', 'SR CRUZ', null),
  ('16f19f2a-b716-564a-a4a9-53b1284f4e5a', 'SR EITEL PRIETO', null),
  ('6986e544-f226-5be1-a484-8ceabbf58852', 'SR GUSTAVO COLCA', null),
  ('3d50542a-dcb5-5270-9c5c-c96b3e2e1b02', 'SR JOSE COLCA', null),
  ('80ce17ac-4554-55fc-9986-428be123dc9a', 'SR OSORIO', null),
  ('981128eb-c5ca-5523-b63a-1d7cf3e4dd70', 'SR PEDRO BRAVO', null),
  ('7e91af49-4ac3-5be1-84bf-d6e87f0ae639', 'SR SAUL', null),
  ('da7dfbee-a328-5e8e-87ec-18ef7de7822f', 'SR VALENCIA', null),
  ('be3ab2f4-8bf0-5b25-a684-764d7f127f01', 'SUPERGEN S.A', null),
  ('ec2192c3-da0c-5e44-879d-8f64ff3bad46', 'TALLER Y REPARACIONES MARCELO COCHACHI E.I.R.L.', null),
  ('5b4ad009-c5b8-5fe2-97f4-9db420572b42', 'TECNOLOGÍA DE FLUIDOS S.A.C.', null),
  ('8ec8c47b-98b5-5ac6-9c97-c43a09440df0', 'TECNOMETALES PERU EIRL', null),
  ('5099519a-d50d-54ee-9724-73e0ef729590', 'TRABAJO MARÍTIMO CELENDÍN S.A.C.', null),
  ('5e18003c-c7dd-5a26-87be-b9b356e6f6fc', 'UNNA TRANSPORTES S.A.C.', null),
  ('70d15013-8b35-55b7-accd-3bedf3319347', 'VAPORTEC S.A.C.', null),
  ('89f39c9e-c039-53c3-996f-2bde171e229c', 'VASQUEZ CALERO RONALD', null),
  ('2e09852b-f141-51b9-bcc3-4aa6c7c0caba', 'VIRGEN DE LA MERCED MINING', null),
  ('30622846-4bd4-5b87-b8f2-e7345bdf78a8', 'WOLF INTERNATIONAL TRAIDING S.A.C.', null)
on conflict do nothing;

insert into public.tarifas (id, cliente_id, servicio, horas_minimas, tarifa, cobra_recorrido, incluye_almuerzo, incluye_igv, horas_jornada, tarifa_jornada, descripcion, origen, destino) values
  ('758b0ab7-8c4b-560b-8f20-71bcfa4d8fd7', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'RETROEXCAVADORA', 8.0, 90.0, false, false, false, 8.0, 90.0, null, null, null),
  ('3c768a65-afa0-5fa9-b06b-66d2cd324bb5', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'RETROEXCAVADORA', 6.0, 90.0, true, false, false, 8.0, 90.0, null, null, null),
  ('cb04d664-e019-5949-9cac-9d1e4a4d4edb', '26024478-2588-5c0b-87a8-0c09b8a1475f', 'RETROEXCAVADORA', 6.0, 120.0, true, false, false, 8.0, 120.0, null, null, null),
  ('ca2ef214-3b6b-562a-930d-fa8016312225', 'f3580583-1978-579a-a7cd-6cfd1d44da9f', 'RETROEXCAVADORA', 8.0, 90.0, true, false, false, 8.0, 90.0, null, null, null),
  ('63904f3e-a3a5-5bb7-8e7d-ac73a13c056f', '1c3c01a2-0f97-57f8-aa66-117fe13e6b99', 'RETROEXCAVADORA', 6.0, 110.0, true, false, false, 8.0, 110.0, null, null, null),
  ('92ea5c16-2463-54e5-9681-f9cc4798643d', 'acbae08d-63cf-5e12-99c9-a61630f9d9db', 'RETROEXCAVADORA', 6.0, 120.0, true, false, false, 8.0, 120.0, null, null, null),
  ('5677ed9f-23a7-5574-801f-c1f9edf3b6c9', 'e209d667-1fa0-547f-bd1e-7c24d0337c17', 'RETROEXCAVADORA', 4.5, 120.0, true, false, false, 8.0, 100.0, null, null, null),
  ('fb42ac6a-9da7-50f9-b5cf-2a5ec146963e', 'a86f9290-d305-5120-bffb-96623bc6d28c', 'RETROEXCAVADORA', 6.0, 110.0, true, false, false, 8.0, 110.0, null, null, null),
  ('3db5ffa8-14be-5c3b-a8eb-a5d5ba8153e6', '7fb861f5-37fe-57f3-9816-0b8c02759124', 'RETROEXCAVADORA', 6.0, 120.0, true, false, false, 8.0, 120.0, null, null, null),
  ('490cb9d6-fc0f-5294-95c0-5f1b40e63dba', '1f2e949d-e46c-5564-84cd-69ecae4f8c66', 'RETROEXCAVADORA', 5.0, 100.0, true, false, false, 8.0, 90.0, null, null, null),
  ('f366ffb4-43c3-5baf-b23a-4782fc5bd13b', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'RETROEXCAVADORA', 4.0, 130.0, true, false, false, 8.0, 120.0, null, null, null),
  ('6e314b9e-eaea-5f27-b72f-aec1d6245172', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'RETROEXCAVADORA', 8.5, 120.0, true, false, false, 8.0, 120.0, null, null, null),
  ('2b6c0960-9c7d-5090-8d25-211023ca34a3', '2af70902-9008-5ce6-a0d9-acf370f5adb4', 'RETROEXCAVADORA', 8.0, 120.0, true, false, false, 8.0, 120.0, null, null, null),
  ('d0ae155d-6992-502b-92cf-09a50511b213', '9237b4d3-8227-5562-892c-6b9353e84721', 'RETROEXCAVADORA', 8.0, 120.0, true, true, false, 8.0, 120.0, null, null, null),
  ('2386e610-5e6e-558e-9fc4-68009512a78e', 'c8abb4e3-9c5f-5167-8da3-e6f343a28614', 'RETROEXCAVADORA', 8.0, 110.0, true, true, false, 8.0, 110.0, null, null, null),
  ('cdda7840-eae4-54ae-b34f-8fb26524d1ae', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'CAMION GRUA', 6.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('a32d9730-e0f3-5c06-9a86-2dd3292b336d', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'CAMION GRUA', 4.0, 190.0, true, false, false, 8.0, 190.0, null, null, null),
  ('05e47848-3df5-5fcd-babf-05edae843693', '26024478-2588-5c0b-87a8-0c09b8a1475f', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('9b1f6e18-204e-58c6-8b83-dbbe070a20e3', 'bd3eb801-5fdf-514c-9ef9-28e98998266a', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('a3d52294-f650-5a76-9fae-4f3a9604dc12', 'f3580583-1978-579a-a7cd-6cfd1d44da9f', 'CAMION GRUA', 4.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('e960e54c-8854-594b-8110-4f3446c2e4e9', 'acbae08d-63cf-5e12-99c9-a61630f9d9db', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('f6dc24f6-d057-5e79-ab8b-36c1e3bf94e0', 'c26ce603-d4b3-5f13-bf62-f8b1ed199df3', 'CAMION GRUA', 4.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('022a2653-29e3-59a8-8b2b-6c9130a0992e', 'e209d667-1fa0-547f-bd1e-7c24d0337c17', 'CAMION GRUA', 4.0, 190.0, true, false, false, 8.0, 190.0, null, null, null),
  ('3cef7b66-627e-58bc-8843-da388e5979ff', 'f8e159c4-f059-5152-9196-7bdcf4b84d4a', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('816fa160-bd80-50d1-881b-b86494c6071d', '3717ef3b-c5b8-501c-80a6-67f80c34b9a1', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('d5b730fe-3959-5590-b792-a6f96e797631', 'cea208fc-df7b-50a0-9ca3-a794b05af0c2', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('95e07715-59f7-53b3-88c4-2f8075e4166f', '12d3f00d-122d-5c26-af92-a0ed2df98093', 'CAMION GRUA', 4.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('2348c9bf-7895-5bfe-930f-27823a79cb5b', 'e946cead-68f1-541f-b4b9-7a589681602b', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('cb05c300-3fd0-5f97-8f8f-a8d7d826a632', 'f0d90778-2016-5a46-80ff-0c4471954da3', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 170.0, null, null, null),
  ('2986ae96-a8f4-528d-a3bd-9bf8bee37472', '70717265-26b5-535f-a97c-b79bcfe69a3a', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 180.0, null, null, null),
  ('6f6b8c92-acc1-5018-a907-3a774c878226', '86cc280f-6895-5548-948c-f2ba9255f47f', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('67969e10-959f-5382-9cdd-a0c1fba11d2d', '388ad6b3-244d-5639-a0ac-1e85137c0565', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('ed393a4a-a303-5a94-9695-a43e3d88800f', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'CAMION GRUA', 3.0, 180.0, true, false, false, 6.0, 160.0, null, null, null),
  ('fb559c6d-a61b-51e0-b1b9-2f99843e8c51', 'a40e7fb9-6138-5f41-9649-4afaca400cd0', 'CAMION GRUA', 7.0, 200.0, true, false, false, 8.0, 180.0, null, null, null),
  ('89ac7223-1df5-56d1-8939-a86ea9355312', '596a62f0-acfa-5282-ae91-a89d90db40d8', 'CAMION GRUA', 4.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('ae603523-a6a3-532b-960a-4d495350efeb', '42d979f0-c278-559a-af55-4de61d546577', 'CAMION GRUA', 6.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('94f8b2ef-d848-5bd9-8233-313c73555e4c', '9186f708-5dca-590d-891b-c83c12481f78', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('94394aeb-f49f-57ca-864e-82d6da76f36b', 'ab5d137d-798b-52e1-8659-f7a646002cc9', 'CAMION GRUA', 3.0, 250.0, true, false, false, 8.0, 200.0, null, null, null),
  ('75092815-9d4a-524d-8be0-15ce6b7090dc', 'b437920b-e976-57ed-ba17-031d0c17371c', 'CAMION GRUA', 5.5, 170.0, true, false, false, 8.0, 170.0, null, null, null),
  ('4a4d6eb9-56d7-51e5-b9bc-2953fb3b3213', '8bd21fa0-6e20-5c75-bc83-f4f96d14cf6f', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('2a716def-71cd-5d65-bf13-a5a1ccea41ac', '4da5a7ea-86e4-5266-8c08-b6e5c3699955', 'CAMION GRUA', 5.5, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('6ee4fd5f-dec4-575c-a000-40e2adfa8fd9', '46b542d5-dbaf-5fa5-9790-d981fdd45e3d', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('1cbcdf70-2a83-5a46-965f-1949adbf1334', '55c0b249-7490-5d80-85ad-c542a54b5159', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('70124501-f788-5571-bf7b-79e4341096b4', 'c30c4879-d74c-5a53-8670-fcb6b1229886', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('ff6a494b-26f5-59e3-b9d9-d0b8a20fab31', '18d64625-efdf-542e-b2f0-04083a664489', 'CAMION GRUA', 4.0, 250.0, true, false, false, 8.0, 250.0, null, null, null),
  ('5ded8658-1213-5a19-acde-e88150deaf11', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('49e62d39-e406-5f27-bf5c-68220ac65bd5', '0deaaf9e-144a-507f-b982-22da3984755a', 'CAMION GRUA', 3.0, 220.0, true, false, false, 8.0, 220.0, null, null, null),
  ('d73319e2-0ef5-5a80-9b8e-25a11d31e355', 'c73b9cdd-5970-542b-96c2-97913d076ec8', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('a9842249-aa56-52b4-97a2-7df394b2ed79', '5ec233c8-9688-55cc-a0ea-d84bf5d1cd11', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('96f0f6ce-4a1a-5c10-8983-8da6fa6c01c6', '2af70902-9008-5ce6-a0d9-acf370f5adb4', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('b89b8926-d7cb-598a-b502-33086049d3d0', '3a542a4f-bc91-55c3-9433-2b484e0ed13c', 'CAMION GRUA', 4.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('fb9b963a-4bf6-5e4a-a2cf-8fe685679419', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('8a4eaacc-b87a-56da-bf40-ebfa68034e4b', '20320171-ba80-544e-97de-fa78dd28efd1', 'CAMION GRUA', 5.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('e6143575-6c7f-5f01-9b20-0dd0ee0f63ff', '9237b4d3-8227-5562-892c-6b9353e84721', 'CAMION GRUA', 3.5, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('36f4931f-4b5c-5b45-86ac-19ae4e528672', '11017afb-e5b4-535e-99e8-4c095e63d606', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 190.0, null, null, null),
  ('2a6d5c1c-01a9-5772-b2c8-6afd1d33be10', '129313df-4e73-5d12-9a6c-00564e3acd54', 'CAMION GRUA', 5.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('1c04d55e-34c6-51db-b428-2a196bf2575f', '88c56133-2ff3-5699-83d1-62df1e851688', 'CAMION GRUA', 3.0, 200.0, true, false, false, 8.0, 180.0, null, null, null),
  ('84660d78-610c-5dd3-8403-c8e5553c914c', '4eaf3051-aaf9-5a32-8cbb-170b104902b9', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('4e5e5fe1-8791-51c6-9b41-df1d6108149a', 'd7cea69c-5b07-5e4d-be6b-fa5dc3de0a93', 'CAMION GRUA', 6.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('b9cbb206-ebb4-59c2-9bbb-aff4c531bfbc', 'c8abb4e3-9c5f-5167-8da3-e6f343a28614', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('cc1f8c0c-f933-5d5c-b345-3bd7e0d6cfd4', '6e217704-6012-5760-a9ca-11aea6391b6e', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('5c9e6919-dead-5576-b97e-b5480d17327c', '5ae6406e-c0ae-5d79-a3cb-8d595ca7d7fa', 'CAMION GRUA', 4.0, 190.0, true, false, false, 8.0, 180.0, null, null, null),
  ('4d350c3c-6255-5a47-9939-b72b489c6a16', '129313df-4e73-5d12-9a6c-00564e3acd54', 'CAMION GRUA', 5.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('f1a9baa6-0c34-5730-82a7-384fc9aa8408', '8527dce6-de10-5b1d-a18d-aa0d6dfc5974', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('7b151510-f00e-5b04-ae9d-c112dbe66ef9', 'e6df09f2-6185-5c4c-9ed1-d63048a8b6e0', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('c34248f5-cbc9-5287-bb6d-346d8b4e0c75', 'e1a45986-9920-573b-8469-e3caafae4958', 'CAMION GRUA', 5.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('867cfcb1-1cb6-5b1b-8a6e-708c8a51fb2c', 'c15451ca-b309-54eb-b2eb-e0c2c062bca4', 'CAMION GRUA', 4.5, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('7cc37ce9-c9d6-514b-a5ba-6cc45ea26929', '25a5c164-0eae-5345-b080-30023dc0edf4', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('3a163488-4df3-5aef-bc96-f7b6cc03b0c7', '8ec8c47b-98b5-5ac6-9c97-c43a09440df0', 'CAMION GRUA', 4.5, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('2397bbc0-9dad-5a73-ad02-5f3062845d9d', '5099519a-d50d-54ee-9724-73e0ef729590', 'CAMION GRUA', 6.0, 190.0, true, false, false, 8.0, 190.0, null, null, null),
  ('0ddc47bb-7ed2-5861-809d-098a90eb6b48', '5e18003c-c7dd-5a26-87be-b9b356e6f6fc', 'CAMION GRUA', 4.0, 200.0, true, false, false, 8.0, 200.0, null, null, null),
  ('36eb46b3-2902-524c-8a4f-222a67a85e30', '2e09852b-f141-51b9-bcc3-4aa6c7c0caba', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('f539f1f2-641f-562d-97e1-dd31b16a759e', '70d15013-8b35-55b7-accd-3bedf3319347', 'CAMION GRUA', 3.0, 180.0, true, false, false, 8.0, 180.0, null, null, null),
  ('d781246d-544f-523e-bda0-09b9076dbe31', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'TRASLADO', null, 650.0, false, false, false, null, null, 'TRASLADO DE CAMIONETA', 'SAN TELMO', 'BARRANCA'),
  ('9ecb0325-2fee-5a05-9ed9-f20fcbd15ee4', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'TRASLADO', null, 1800.0, false, false, false, null, null, 'TRASLADO DE UNA CARPA CON PLATAFORMA', 'ANCON', 'CARAL')
on conflict do nothing;

insert into public.cotizaciones (id, numero, fecha, cliente_id, sede, asesor, motivo_contacto, servicio, tipo_comprobante, estado, moneda, descripcion, subtotal, total_libre, detraccion_pct, detraccion_monto, estado_detraccion, orden_servicio, hes, comprobante, fecha_comprobante, fecha_pago, estado_pago, monto_pagado, obs_cobro, origen) values
  ('01cf5976-ae2b-5333-ba73-90227cb7b658', '09-0001-01-2026', '2026-01-05', 'f8e159c4-f059-5152-9196-7bdcf4b84d4a', 'SUPE PUERTO', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE ALQUILER DE CAMION GRUA - EMBARQUE DE COMPRESOR', 1200.0, 0, 0.1, 94.0, 'CANCELADO', '4500666986', '1000806344', 'F001-1766 - 1767', '2026-02-16', '2026-05-16', 'CANCELADO', 1211.0, null, 'EXCEL 2026'),
  ('25fc5cde-61e5-5f07-afb4-36500559ea12', '09-0002-01-2026', '2026-01-08', 'be3ab2f4-8bf0-5b25-a684-764d7f127f01', 'LIMA', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'TRASLADO', 'FACTURADO', 'ACEPTADO', 'PEN', 'TRASLADO DE MATERIALES DE LIMA A HUARMEY', 1750.0, 0, 0.04, 83.0, 'CANCELADO', '3100000344', '3100000344', 'F001 -1741', '2026-01-19', '2026-01-19', 'CANCELADO', 1982.0, null, 'EXCEL 2026'),
  ('3a4e135d-7b4b-5639-9c9d-a8a1bc50c0eb', '09-0003-01-2026', '2026-01-09', '2af70902-9008-5ce6-a0d9-acf370f5adb4', 'MALABRIGO', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERVICIO DE TERMOFUSION DE 630MM', 19000.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('d125a490-a484-52fa-ac1b-68eeaf6bdd06', '09-0004-01-2026', '2026-01-09', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'MAQUINARIA PESADA', 'FACTURADO', 'ACEPTADO', 'PEN', 'CAMBIO DE LASTRES EN TUBERIAS SUBMARINAS', 52183.79, 0, 0.12, 6794.0, 'CANCELADO', '4500420639', '1000493254/1000493255/1000493256', 'F001-1810', '2026-04-08', '2026-04-20', 'CANCELADO', 48729.21, null, 'EXCEL 2026'),
  ('1738c3a4-d26a-5a05-be55-7ce2f44e9ac3', '09-0005-01-2026', '2026-01-12', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE ALQUILER DE CAMION GRUA - EMBARQUE DE MATERIALES', 800.0, 0, 0.1, 94.0, 'CANCELADO', '4500129489', '1000214823', 'F001-1749', '2026-01-28', '2026-03-28', 'CANCELADO', 794.5, null, 'EXCEL 2026'),
  ('4d900c3e-c7a8-5084-911a-77fb6e66e23e', '09-0006-01-2026', '2026-01-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'FUNDO LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 50', 1242.0, 0, 0.1, 147.0, 'CANCELADO', '4000021979', '4000021979', 'F001-1737', '2026-01-17', '2026-02-01', 'CANCELADO', 1318.56, null, 'EXCEL 2026'),
  ('84b75b8d-e0c8-5466-8f30-769119fdc9e8', '09-0007-01-2026', '2026-01-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'FUNDO LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 51', 3951.0, 0, 0.1, 466.0, 'CANCELADO', '4000021982', '4000021982', 'F001-1739', '2026-01-17', '2026-02-01', 'CANCELADO', 4196.18, null, 'EXCEL 2026'),
  ('c36b3b19-ada7-5434-a633-d8655e1d065d', '09-0008-01-2026', '2026-01-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'FUNDO LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 52', 2745.0, 0, 0.1, 324.0, 'CANCELADO', '4000021983', '4000021983', 'F001-1738', '2026-01-17', '2026-02-01', 'CANCELADO', 2915.1, null, 'EXCEL 2026'),
  ('3bbfe432-bc76-5efe-b651-240146714329', '09-0009-01-2026', '2026-01-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'FUNDO LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 01', 6327.0, 0, 0.1, 747.0, 'CANCELADO', '4000021984', '4000021984', 'F001-1736', '2026-01-17', '2026-02-01', 'CANCELADO', 6718.86, null, 'EXCEL 2026'),
  ('eecb17c2-56dd-5bdb-b6fb-515dbf33a813', '09-0010-01-2026', '2026-01-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'FUNDO LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQ. DE CAMION GRUA IZAJE DE MOTOR', 1440.0, 0, 0.1, 170.0, 'CANCELADO', '4000023859', '1000021657', 'F001-1765', '2026-02-16', '2026-03-04', 'CANCELADO', 1529.2, null, 'EXCEL 2026'),
  ('fd67651b-6951-5174-9a21-2735c073fb1e', '09-0011-01-2026', '2026-01-15', 'c73b9cdd-5970-542b-96c2-97913d076ec8', 'CARQUIN', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'OTRO', 'FACTURADO', 'RECHAZADO', 'PEN', 'TUBERÍA DE DESCARGA TK CONDENSADOR BAROMÉTRICO DE PAC WHE N° 02', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('7ba6f44e-5c23-5b47-9d98-481efb6e6195', '09-0012-01-2026', '2026-01-15', 'c73b9cdd-5970-542b-96c2-97913d076ec8', 'CARQUIN', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'OTRO', 'FACTURADO', 'RECHAZADO', 'PEN', 'MODIFICACIÓN DE LA TUBERÍA DE DESCARGA DE TK CONDENSADOR BAROMÉTRICO PAC 1', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('cdb90631-2d95-592e-9e41-e92f84600542', '09-0013-01-2026', '2026-01-17', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'SUPE PUERTO', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE ALQUILER DE CAMION GRUA - IZAJE DE MATERIALES', 550.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1740', '2026-01-17', '2026-01-25', 'CANCELADO', 649.0, null, 'EXCEL 2026'),
  ('e360c7f3-7177-5466-a8ab-2dcb670f6db2', '09-0014-01-2026', '2026-01-19', 'f8e159c4-f059-5152-9196-7bdcf4b84d4a', 'SUPE PUERTO', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE ALQUILER DE CAMION GRUA - EMBARQUE DE COMPRESOR', 1200.0, 0, 0.1, 142.0, 'CANCELADO', '4500666651', '1000801985', 'F001-1748', '2026-01-27', '2026-04-27', 'CANCELADO', 1218.5, null, 'EXCEL 2026'),
  ('1223551e-2ba3-58a7-bc54-cb942c965ad1', 'NRO DE PARTE 694 (2026)', '2026-01-22', '388ad6b3-244d-5639-a0ac-1e85137c0565', 'HUARMEY', 'FATIMA FONSECA', 'CONFIANZA', 'TRASLADO', 'LIBRE', 'ACEPTADO', 'PEN', 'TRASLADO DE SILO', 0, 900.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('51d487ee-22e8-5c39-bcd0-bf0ab06bcfaf', '09-0015-01-2026', '2026-01-23', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'MAQUINARIA PESADA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQUILER MAQ. PESADA REACOMODO ENROCADO', 202190.4, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('eec40430-4c02-578b-a4c0-87ecc48a2a59', 'NRO DE PARTE 695 (2026)', '2026-01-23', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'ICA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA - MOVIMIENTO INTERNO DE CILOS', 0, 3940.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('007398d1-b871-52a7-b0ce-0247ff873083', '09-0016-01-2026', '2026-01-27', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'MAQUINARIA PESADA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER MAQ. PESADA REACOMODO ENROCADO', 188690.4, 0, 0.1, 22265.0, 'CANCELADO', '4500420494', '1000492214', 'F001-1803', '2026-03-30', '2026-05-30', 'CANCELADO', 195594.06, null, 'EXCEL 2026'),
  ('46f60ab8-8e36-5c8a-afd9-4ee1b5682ac0', 'NRO DE PARTE 696 (2026)', '2026-01-29', '2efbc9cc-c182-53f0-a1a8-70395b294841', 'SUPE', 'FATIMA FONSECA', 'PUBLICIDAD', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA- IZAJE DE PORTON', 0, 200.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('9ac592d1-3986-523c-a890-efa7fd034282', '09-0017-01-2026', '2026-01-30', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'CHIMBOTE', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'TRASLADO', 'FACTURADO', 'RECHAZADO', 'PEN', 'TRASLADO DE 01 UND MANGUERON DE SUPE (PLANTA DIAMANTE) A CHIMBOTE', 5700.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('d6e879a6-352a-5b2c-9891-80e3f5e9e4d8', '09-0018-01-2026', '2026-01-30', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. DE TERMOFUSION DE TUBERÍA DE HDPE 315MM', 5530.0, 0, 0.12, 783.0, 'CANCELADO', '4500135975', '1000224058', 'F001-1834', '2026-04-24', '2026-06-25', 'CANCELADO', 5742.4, null, 'EXCEL 2026'),
  ('5fbe1d21-a2fa-5cb2-908e-229491fe545e', '09-0019-02-2026', '2026-02-02', '7894d29b-be15-5468-bc7c-c0d548393f41', 'LIMA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'TRASLADO', 'FACTURADO', 'ACEPTADO', 'PEN', 'TRASLADO DE UNA CAMIONETA DE SUPE A LIMA (SURQUILLO)', 1016.95, 283.05, 0.04, 48.0, 'CANCELADO', null, null, 'F001-1750', '2026-02-02', '2026-02-02', 'CANCELADO', 1200.0, null, 'EXCEL 2026'),
  ('2e048826-bdc9-5fc7-9622-e80e51760c3c', '09-0020-02-2026', '2026-02-03', 'be3ab2f4-8bf0-5b25-a684-764d7f127f01', 'HUARMEY', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA', 1260.0, 0, 0.1, 149.0, 'CANCELADO', null, null, 'F001-1759', '2026-02-09', '2026-02-20', 'CANCELADO', 1337.8, null, 'EXCEL 2026'),
  ('f2bc718e-22af-5506-b450-1418d2b431be', '09-0021-02-2026', '2026-02-04', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA LIQ.01', 10935.0, 0, 0.1, 1325.0, 'CANCELADO', '4000023713', '4000023713', 'F001-1755', '2026-02-06', '2026-02-20', 'CANCELADO', 11924.51, null, 'EXCEL 2026'),
  ('eb4ee990-2fd3-5a86-9a6c-b9c583ce04e4', '09-0022-02-2026', '2026-02-04', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA LIQ.02', 9247.5, 0, 0.1, 1091.0, 'CANCELADO', '4000023739', '4000023739', 'F001-1754', '2026-02-06', '2026-02-20', 'CANCELADO', 9821.05, null, 'EXCEL 2026'),
  ('76a7fbb1-0c1d-544e-8f79-54bdc19f19dc', '09-0023-02-2026', '2026-02-04', '30622846-4bd4-5b87-b8f2-e7345bdf78a8', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA', 720.0, 0, 0.1, 85.0, 'CANCELADO', null, null, 'F001-1751', '2026-02-05', '2026-02-05', 'CANCELADO', 764.6, null, 'EXCEL 2026'),
  ('2c540a00-712e-5432-aa3a-b1583f8e2687', '09-0024-02-2026', '2026-02-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 02', 7785.0, 0, 0.1, 919.0, 'CANCELADO', '4000023496', '1000021525', 'F001-1758', '2026-02-09', '2026-02-24', 'CANCELADO', 8267.3, null, 'EXCEL 2026'),
  ('1c77c85c-afa5-5963-ae86-5720e92c8a5a', '09-0025-02-2026', '2026-02-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LIMA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA - IZAJE DE TRANSFORMADORES', 900.0, 0, 0.1, 106.0, 'CANCELADO', '4000025759', '1000024212', 'F001-1783', '2026-03-20', '2026-04-03', 'CANCELADO', 955.35, null, 'EXCEL 2026'),
  ('f8b7cca9-eda8-55e1-97fb-890a7a7256eb', '09-0026-02-2026', '2026-02-06', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'OTRO', 'FACTURADO', 'RECHAZADO', 'PEN', 'LIMPIEZA Y ORDENAMIENTO DE ZONA EXTERNA DE PLANTA - HAYDUK VEGUETA', 13852.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('cb77c196-639d-5cb7-81de-6ab007fbca83', '09-0027-02-2026', '2026-02-10', '6aa0df0c-d51f-53f1-b0a0-51d35aca69f9', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'ANDAMIOS', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE 03 CUERPOS DE ANDAMIO', 400.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1761', '2026-02-10', '2026-02-10', 'CANCELADO', 472.0, null, 'EXCEL 2026'),
  ('dbb56e43-c611-59b6-9102-f1e251921adf', '09-0028-02-2026', '2026-02-10', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - MOVIMIENTO DE PLANCHAS', 630.0, 0, 0, 0, 'NO APLICA', null, null, '1753 / 1757 / 1760', '2026-02-09', '2026-02-10', 'CANCELADO', 703.4, null, 'EXCEL 2026'),
  ('f948b2af-e571-5c55-8eda-5bbc4a23a679', '09-0029-02-2026', '2026-02-10', '89f39c9e-c039-53c3-996f-2bde171e229c', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'TRASLADO', 'LIBRE', 'ACEPTADO', 'PEN', 'TRASLADO DE MOBILIARIO DEL HOGAR Y ENSERES DOMÉSTICOS VARIOS DE LIMA A SUPE PUERTO', 0, 1800.0, 0, 0, 'NO APLICA', null, null, 'B001-05', '2026-02-06', '2026-02-06', 'CANCELADO', 1800.0, null, 'EXCEL 2026'),
  ('f43fc5f6-9fc1-5004-8888-848f7955d9a2', '09-0030-02-2026', '2026-02-11', 'c73b9cdd-5970-542b-96c2-97913d076ec8', 'MALABRIGO', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'ACEPTADO', 'USD', 'SERVICIO DE TERMOFUSION DE 500MM', 4078.68, 0, 0.12, 1748.0, 'CANCELADO', '4500891788', '1000646213', 'F001-1780', '2026-03-06', '2026-04-06', 'CANCELADO', 3735.35, null, 'EXCEL 2026'),
  ('7ac05dfe-5dcf-5acd-a128-06297cba6293', '09-0030-02-2026 (2)', '2026-02-11', 'c73b9cdd-5970-542b-96c2-97913d076ec8', 'MALABRIGO', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'ACEPTADO', 'USD', 'SERVICIO DE TERMOFUSION DE 500MM', 481.46, 0, 0.12, 232.0, 'CANCELADO', '4500897112', '1000648113', 'F001- 1813', '2026-04-09', '2026-05-09', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('1147e4cc-7876-5d7c-8489-6096a251e7c8', '09-0031-02-2026', '2026-02-12', '6aa0df0c-d51f-53f1-b0a0-51d35aca69f9', 'PUERTO SUPE', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'ANDAMIOS', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE ANDAMIO NORMADO', 150.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1763', '2026-02-11', '2026-02-12', 'CANCELADO', 150.0, null, 'EXCEL 2026'),
  ('fa7133e5-1106-5684-8ccc-db7b3bd1d369', '09-0032-02-2026', '2026-02-13', '2f19a704-1cbc-50fa-85cb-5d685ac6f51e', 'PUERTO SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRÚA', 600.0, 0, 0, 71.0, 'CANCELADO', '000015787', null, 'F001-1764', '2026-02-14', '2026-02-14', 'CANCELADO', 637.2, null, 'EXCEL 2026'),
  ('28044343-1991-5b9b-8d69-2754fcacd056', '09-0033-02-2026', '2026-02-13', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'PUERTO SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA - IZAJE DE MANGUERON', 800.0, 0, 0.1, 94.0, 'CANCELADO', '4500132075', '1000220116', 'F001-1791', '2026-03-23', '2026-04-20', 'CANCELADO', 794.5, null, 'EXCEL 2026'),
  ('5f680d6c-fbdf-5a48-8aee-c8f8fdf6088b', '09-0034-02-2026', '2026-02-17', 'c73b9cdd-5970-542b-96c2-97913d076ec8', 'PUERTO SUPE', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'OTRO', 'FACTURADO', 'ACEPTADO', 'PEN', 'FABRICACION DE CARRETE DE 450MM', 5900.0, 0, 0.1, 696.0, 'CANCELADO', '4500895813', '1000649938', 'F001-1825', '2026-04-18', '2026-05-18', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('982fde76-d47a-5ca8-b299-6facee89c7d9', '09-0035-02-2026', '2026-02-18', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PUERTO SUPE', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE IZAJE DE MATERIALES DIA 18/02', 550.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1771', '2026-02-18', '2026-02-25', 'CANCELADO', 649.0, null, 'EXCEL 2026'),
  ('3c9c9669-172a-5798-a859-d595ca8bb4db', '09-0036-02-2026', '2026-02-20', '2f19a704-1cbc-50fa-85cb-5d685ac6f51e', 'PUERTO SUPE', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRÚA', 400.0, 0, 0, 0, 'NO APLICA', '000015834', null, 'F001-1772', '2026-02-19', '2026-02-19', 'CANCELADO', 472.0, null, 'EXCEL 2026'),
  ('2c7eef4c-693d-5d6b-959d-0a19cc3ddfc1', '09-0037-02-2026', '2026-02-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQ. DE RETROEXCAVADORA - MEZCLA DE SUSTRATO PROYECTO ARÁNDANO', 1305.0, 0, 0.1, 154.0, 'CANCELADO', '4000024092', '4000024092', 'F001-1768', '2026-02-16', '2026-05-16', 'CANCELADO', 1385.9, null, 'EXCEL 2026'),
  ('1bd1b288-141e-5e17-8418-2d2ff6a270dc', '09-0038-02-2026', '2026-02-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'OTRO', 'FACTURADO', 'ACEPTADO', 'PEN', 'HORAS DE ALQUILER DE RET. - MEZCLA DE HUANO CON ARENA PROY. PALTO SEM. 05', 1282.5, 0, 0.1, 151.0, 'CANCELADO', '4000024258', '4000024258', 'F001-1770', '2026-02-18', '2026-03-05', 'CANCELADO', 1362.35, null, 'EXCEL 2026'),
  ('3bf4b98a-948c-5a6c-9fb4-eadb23f37b37', '09-0039-02-2026', '2026-02-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 03', 7632.0, 0, 0.1, 901.0, 'CANCELADO', '4000024261', '1000022388', 'F001-1773', '2026-02-20', '2026-03-07', 'CANCELADO', 8104.76, null, 'EXCEL 2026'),
  ('20c26e3a-da25-5912-8ddf-56569304fdd7', '09-0040-02-2026', '2026-02-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 04', 8019.0, 0, 0.1, 946.0, 'CANCELADO', '4000024262', '1000022387', 'F001-1774', '2026-02-20', '2026-03-07', 'CANCELADO', 8516.42, null, 'EXCEL 2026'),
  ('7aaaf252-5d93-500b-8f69-ea2cd00282d8', '09-0041-02-2026', '2026-02-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 05 Y SEM. 06', 13491.0, 0, 0.1, 1592.0, 'CANCELADO', '4000024372', '1000022479/1000022480', 'F001-1775', '2026-02-20', '2026-03-07', 'CANCELADO', 14327.38, null, 'EXCEL 2026'),
  ('de22fe09-fd50-5647-9fe2-7ac81ad3f6f3', '09-0042-02-2026', '2026-02-24', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 07', 8415.0, 0, 0.1, 993.0, 'CANCELADO', '4000024744', '1000022877', 'F001-1776', '2026-02-24', '2026-02-11', 'CANCELADO', 8936.7, null, 'EXCEL 2026'),
  ('60c17a43-5240-5460-8747-293d914818cc', '09-0043-02-2026', '2026-02-25', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - TRASLADO DE TUBERÍAS', 600.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1778', '2026-02-27', '2026-02-27', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('be17bca4-cc4b-58fa-96e2-fdfae6881613', '09-0043-02-2026 (2)', '2026-02-25', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - TRASLADO DE TUBERÍAS', 450.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1779', '2026-03-02', '2026-03-02', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('6892169e-3ab0-539c-9bbe-3785c16f2e5f', '09-0044-02-2026', '2026-02-25', '2af70902-9008-5ce6-a0d9-acf370f5adb4', 'MALABRIGO', 'FATIMA FONSECA', 'CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERVICIO DE TERMOFUSION DE 630MM - INSTALACION DE UN FLUJÓMETRO', 41600.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('59e81ca2-251e-5e45-960c-781390f84810', '09-0045-02-2026', '2026-02-26', '3d9e42cf-d6e7-5f65-bd3d-c960d1bd476f', 'BARRANCA', 'MARÍA ORDOÑEZ', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQUILER DE CAMION GRUA', 540.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('fb269414-7cf5-5e48-86b8-cb045bd8fc89', '09-0046-02-2026', '2026-02-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA SEM. 08', 8334.0, 0, 0.1, 983.0, 'CANCELADO', '4000024744', '1000022877', 'F001-1777', '2026-02-27', '2026-03-14', 'CANCELADO', 8851.12, null, 'EXCEL 2026'),
  ('e1d35885-7af2-5567-be22-41b65a08fce1', '09-0047-02-2026', '2026-02-27', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'PUERTO SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA - MOVIMIENTO DE TUBERÍAS', 500.0, 0, 0.1, 0, 'NO APLICA', '4500134394', '1000221778', 'F001-1809', '2026-04-08', '2026-04-20', 'CANCELADO', 534.5, null, 'EXCEL 2026'),
  ('4f4ae7be-b851-5787-b57e-3a6973221cd6', '09-0048-03-2026', '2026-03-02', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'TAMBO DE MORA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. DE TERMOFUSIÓN DE TUBERÍA DE HDPE 450MM', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('e1197065-b827-5222-a729-283dc3adf2d2', '09-0049-03-2026', '2026-03-02', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - TRASLADO DE TUBERÍAS', 450.0, 0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 531.0, null, 'EXCEL 2026'),
  ('404ed565-a463-5e98-9bae-c34a0895cd63', '09-0050-03-2026', '2026-03-04', '9237b4d3-8227-5562-892c-6b9353e84721', 'PUENTE PIEDRA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'ANDAMIOS', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. DE ALQUILER DE 03 CUERPOS DE ANDAMIO', 0, 0, 0.12, 722.0, 'CANCELADO', '4200162063', '1000229677', 'F001-1793', '2026-03-24', '2026-04-24', 'CANCELADO', 5296.0, null, 'EXCEL 2026'),
  ('3418b5ec-fcaf-5c89-82dc-a6359361660f', '09-0051-03-2026', '2026-03-04', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE RÁPIDA', 360.0, 0, 0, 0, 'NO APLICA', '4000025278', '1000023620', 'F001-1782', '2026-03-11', '2026-03-27', 'CANCELADO', 424.8, null, 'EXCEL 2026'),
  ('ef992929-a897-5d2f-ae84-697f16fcc216', '09-0052-03-2026', '2026-03-04', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE RÁPIDA', 450.0, 0, 0, 0, 'NO APLICA', '4000025313', '1000023622', 'F001-1781', '2026-03-11', '2026-03-27', 'CANCELADO', 531.0, null, 'EXCEL 2026'),
  ('b283be42-71a3-5a8f-ad77-b07d93ba1022', '09-0053-03-2026', '2026-03-06', 'c8abb4e3-9c5f-5167-8da3-e6f343a28614', 'SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - TRASLADO DE MATERIALES', 4300.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('e795aa7e-72f1-56cc-a6aa-7de2028d85d6', '09-0054-03-2026', '2026-03-06', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA', 120.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('21fd59bf-2fac-521f-bd45-533152483f5f', 'NRO DE PARTE 706 (2026)', '2026-03-10', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'MEDIO MUNDO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE SILOS', 0, 2007.2, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 2007.2, null, 'EXCEL 2026'),
  ('20300353-4c74-554f-a702-2795eb3a3ce3', '09-0055-03-2026', '2026-03-11', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'LIMPIEZA DE MALEZA DE CANAL CON RETROEXCAVADORA', 14956.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('0c3a9d42-ac6a-53f2-830d-55fb33681f20', '09-0056-03-2026', '2026-03-11', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'LIMPIEZA DE MALEZA DE CANAL CON EXCAVADORA', 6354.0, 0, 0.1, 750.0, 'CANCELADO', '4500426336', '1000492216', 'F001-1812', '2026-04-09', '2026-04-20', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('28b442cb-6f3f-58dc-a5e2-dd53349dcf49', 'NRO DE PARTE 707 (2026)', '2026-03-12', '388ad6b3-244d-5639-a0ac-1e85137c0565', 'PAMPA COLORADA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE SILOS', 0, 630.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 630.0, null, 'EXCEL 2026'),
  ('cfdc2fa7-8b09-5c80-aa9b-fad71d69107d', '09-0057-03-2026', '2026-03-13', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE ASR', 800.0, 0, 0.1, 94.0, 'CANCELADO', '4500134394', '1000224065', 'F001-1831', '2026-04-24', '2026-06-25', 'CANCELADO', 850.0, null, 'EXCEL 2026'),
  ('d5d36ce4-a83a-55a9-bf48-f20b3b80744d', '09-0058-03-2026', '2026-03-17', 'bd469c6e-9ad7-5473-974c-de8d69045d3a', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE TANQUES', 5760.0, 0, 0.1, 113.0, 'CANCELADO', null, null, 'F001-1792 / 1798', '2026-03-23', '2026-03-23', 'CANCELADO', 2548.9, null, 'EXCEL 2026'),
  ('4ced00c1-73ec-53b5-b5b0-d8b174f6b27f', 'NRO DE PARTE 708 (2026)', '2026-03-17', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'BARRANCA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE PLANCHAS Y TECHOS', 0, 720.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-03-30', 'CANCELADO', 720.0, null, 'EXCEL 2026'),
  ('7c8a536c-d3c4-59e6-98d5-b7667f46ce9b', 'NRO DE PARTE 709 (2026)', '2026-03-18', '167d8ef2-bbb1-58c6-9d6d-5eda2335b198', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TANQUES', 0, 1020.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 1020.0, null, 'EXCEL 2026'),
  ('213549ce-e3db-54ea-ac05-c4a2e53f0ca1', '09-0059-03-2026', '2026-03-19', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - SEM. 09', 7859.7, 0, 0.1, 927.0, 'CANCELADO', '4000026077', '4000026077', 'F001-1785', '2026-03-21', '2026-04-04', 'CANCELADO', 8347.45, null, 'EXCEL 2026'),
  ('4342d496-65f9-5790-b985-55f625cd2e75', '09-0060-03-2026', '2026-03-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE RÁPIDA', 315.0, 0, 0, 0, 'NO APLICA', '4000026278', '1000024598', 'F001-1787', '2026-03-23', '2026-04-07', 'CANCELADO', 357.76, null, 'EXCEL 2026'),
  ('8f8a95b2-88f3-5861-a860-cb40fb5fd3b0', '09-0061-03-2026', '2026-03-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE RÁPIDA', 405.0, 0, 0, 0, 'NO APLICA', '4000026279', '1000024597', 'F001-1788', '2026-03-23', '2026-04-07', 'CANCELADO', 463.96, null, 'EXCEL 2026'),
  ('d8af1bae-72eb-51c3-bb9e-04ef59117041', '09-0062-03-2026', '2026-03-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE RÁPIDA', 450.0, 0, 0, 0, 'NO APLICA', '4000026075', '1000024525', 'F001-1786', '2026-03-23', '2026-04-07', 'CANCELADO', 517.06, null, 'EXCEL 2026'),
  ('5e2c95ff-16bd-576d-94ab-31169ffdd1de', '09-0063-03-2026', '2026-03-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE RÁPIDA', 405.0, 0, 0, 0, 'NO APLICA', '4000026076', '1000024526', 'F001-1789', '2026-03-23', '2026-04-07', 'CANCELADO', 463.96, null, 'EXCEL 2026'),
  ('4bfc2855-e7bb-52f9-9425-d79d42823753', '09-0064-03-2026', '2026-03-23', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESCARGA DE PLANCHAS', 900.0, 0, 0.1, 106.0, 'CANCELADO', null, null, 'F001-1790', '2026-03-23', '2026-03-23', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('41827d84-7c06-5960-8ce6-749ac8a437bc', 'NRO DE PARTE 3183 (2026)', '2026-03-23', '5646e73f-8f29-5e92-b670-1881365cf47a', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - LIMPIEZA DE TERRENO', 0, 840.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 840.0, null, 'EXCEL 2026'),
  ('6af0b097-921c-5981-8ecb-9c165a8a3ba5', 'NRO DE PARTE 3184 (2026)', '2026-03-24', 'd5354909-2ea2-50a3-8fde-a20e06d4240b', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02- EXCAVACION', 0, 360.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 360.0, null, 'EXCEL 2026'),
  ('c96de8e9-c928-5b6b-a0bb-80c08b858688', 'NRO DE PARTE 3185 (2026)', '2026-03-24', 'a390e377-1551-54a4-a0e4-c87004b6e5a7', null, null, null, 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - ELIMINACION DE CAUCHO', 0, 120.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('91a35219-f0ed-537d-9b0d-5afd86a6ce87', '09-0065-03-2026', '2026-03-25', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE TUBERÍAS Y MATERIALES', 300.0, 0, 0, 0, 'NO APLICA', '4500135628', '1000224068', 'F001-1832', '2026-04-24', '2026-06-25', 'CANCELADO', 354.0, null, 'EXCEL 2026'),
  ('cb524289-976f-5ffe-be0c-2c4065b3af90', '09-0066-03-2026', '2026-03-25', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PARAMONGA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - TRASLADO Y DESCARGA DE MATERIALES Y EQUIPOS', 1170.0, 0, 0.1, 166.0, 'CANCELADO', null, null, 'F001-1799/1800', '2026-03-26', '2026-04-02', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('c02e53a1-7c8c-5eb8-971d-5f857abbb921', 'NRO DE PARTE 3186 (2026)', '2026-03-25', 'a390e377-1551-54a4-a0e4-c87004b6e5a7', null, null, null, 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - ELIMINACION DE CAUCHO', 0, 840.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('8952a7e2-a000-5a53-a5be-6945c3379634', '09-0067-03-2026', '2026-03-26', 'be3ab2f4-8bf0-5b25-a684-764d7f127f01', 'HUARMEY', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESCARGA DE EQUIPO CHILLER', 1260.0, 0, 0.1, 149.0, 'CANCELADO', null, null, 'F001-1805', '2026-03-31', '2026-04-03', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('60104ec9-3bd3-5eed-a3ca-96b3ad012494', 'NRO DE PARTE 3204 (2026)', '2026-03-26', 'bd469c6e-9ad7-5473-974c-de8d69045d3a', 'CARQUIN', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - EXCAVACION DE ZANJAS', 0, 960.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-03-26', 'CANCELADO', 960.0, null, 'EXCEL 2026'),
  ('3abdf730-4a69-592f-84b6-f4fca7454042', 'NRO DE PARTE 3187 (2026)', '2026-03-26', 'a390e377-1551-54a4-a0e4-c87004b6e5a7', null, null, null, 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - ELIMINACION DE CAUCHO', 0, 600.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('5f24fd31-7600-5d61-ad67-426564e972d1', 'NRO DE PARTE 3188 (2026)', '2026-03-27', 'a390e377-1551-54a4-a0e4-c87004b6e5a7', null, null, null, 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - ELIMINACION DE CAUCHO', 0, 960.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('5aad7a2f-0962-5267-aecb-9f2c958fe436', '09-0068-03-2026', '2026-03-27', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESCARGA DE GENERADOR', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('38d5e475-0103-5aec-9437-3219e1aa19df', '09-0069-03-2026', '2026-03-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESCARGA DE CARRETAS Y EQUIPOS', 810.0, 0, 0.1, 96.0, 'CANCELADO', '4000028085', '4000028085', 'F001-1828', '2026-04-22', '2026-05-07', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('bc5fa632-3e95-5f1f-84cd-824e82df7ecd', '09-0070-03-2026', '2026-03-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - ELIMINACION DE PLANTAS - SEM 10-11', 7389.0, 0, 0.1, 684.0, 'CANCELADO', '4000026580', '4000026580', 'F001-1801', '2026-03-28', '2026-04-11', 'CANCELADO', 6155.28, null, 'EXCEL 2026'),
  ('0a09212f-3b00-53f0-9572-a511fe12abe2', '09-0071-03-2026', '2026-03-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - ELIMINACION DE PLANTAS - SEM 10-11', 5796.0, 0, 0.1, 872.0, 'CANCELADO', '4000026581', '4000026581', 'F001-1802', '2026-03-28', '2026-04-11', 'CANCELADO', 7847.02, null, 'EXCEL 2026'),
  ('75b8aa87-053a-5992-b82c-467f6d4be283', '09-0072-03-2026', '2026-03-28', '6aa0df0c-d51f-53f1-b0a0-51d35aca69f9', 'VEGUETA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'ANDAMIOS', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE ANDAMIO NORMADO', 100.0, 0, 0, 0, 'NO APLICA', null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('90f5ad5c-1f96-520a-969c-f3349e8cc389', 'NRO DE PARTE 3205 (2026)', '2026-03-27', 'bd469c6e-9ad7-5473-974c-de8d69045d3a', 'CARQUIN', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - EXCAVACION DE ZANJAS', 0, 1200.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-03-27', 'CANCELADO', 1200.0, null, 'EXCEL 2026'),
  ('01114d06-4721-578c-b659-40c9604b15df', 'NRO DE PARTE 3208 (2026)', '2026-03-28', 'bd469c6e-9ad7-5473-974c-de8d69045d3a', 'CARQUIN', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - EXCAVACION DE ZANJAS', 0, 960.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-03-28', 'CANCELADO', 960.0, null, 'EXCEL 2026'),
  ('099cc681-559d-5fe8-8b45-1e5d9e08de8e', 'NRO DE PARTE 3207 (2026)', '2026-03-29', 'bd469c6e-9ad7-5473-974c-de8d69045d3a', 'CARQUIN', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03- EXCAVACION DE ZANJAS', 0, 650.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 650.0, null, 'EXCEL 2026'),
  ('d286fdf3-d5e8-5b44-8930-be0f31d92d5e', '09-0073-03-2026', '2026-03-30', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE GENERADOR', 1300.0, 0, 0.1, 118.0, 'CANCELADO', '4500135975', '1000224057', 'F001-1833', '2026-04-24', '2026-06-25', 'CANCELADO', 1062.0, null, 'EXCEL 2026'),
  ('a08abcd8-79e6-5588-8636-bf5e53035d5c', '09-0074-03-2026', '2026-03-30', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE GENERADOR', 800.0, 0, 0.1, 94.0, 'CANCELADO', '4500135975', '1000224069', 'F001-1835', '2026-04-25', '2026-06-25', 'CANCELADO', 94.0, null, 'EXCEL 2026'),
  ('bcb8cf68-84dc-563e-b6d0-0ce893be3ef6', 'NRO DE PARTE 717 (2026)', '2026-03-30', 'ec2192c3-da0c-5e44-879d-8f64ff3bad46', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE TANQUE', 0, 800.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-03-30', 'CANCELADO', 800.0, null, 'EXCEL 2026'),
  ('e891da0f-6f9d-5d49-8f26-fe98183ceea7', '09-0075-03-2026', '2026-04-01', '750b33dc-943f-5308-ac4f-adf1e0bb0d94', 'PARAMONGA', 'FATIMA FONSECA', 'DOCUMENTACIÓN', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE VIGAS', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('f8faeff7-dfb4-5462-8830-2949d6c24dc4', 'SN-ABRIL-96 (2026)', '2026-04-01', 'f8620314-43b4-5b46-91db-484be70e87eb', 'CARQUIN', 'FATIMA FONSECA', 'CONFIANZA', 'TERMOFUSION', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA DE TERMOFUSION DE 90MM X 1 DIA', 0, 90.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-01', 'CANCELADO', 90.0, null, 'EXCEL 2026'),
  ('144a9228-96c2-5fc9-a0ae-0abba04e9e77', '09-0076-03-2026', '2026-04-01', 'c73b9cdd-5970-542b-96c2-97913d076ec8', 'CARQUIN', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'SUMINISTRO', 'FACTURADO', 'RECHAZADO', 'PEN', 'SUMINISTRO DE FLANGE ADAPTER 400MM', 850.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('38c165df-b257-5546-b7e9-51bee3448f46', '09-0077-03-2026', '2026-04-01', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE', 'FATIMA FONSECA', 'CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'ACEPTADO', 'USD', 'ALQUILER DE MAQUINA DE TERMOFUSIÓN', 390.0, 0, 0.1, 156.0, 'CANCELADO', null, null, 'F001-1816', '2026-04-13', '2026-04-13', 'CANCELADO', 460.2, null, 'EXCEL 2026'),
  ('197e22e5-bae8-55e0-82ed-b6da22218f65', 'NRO DE PARTE 719 (2026)', '2026-04-01', '167d8ef2-bbb1-58c6-9d6d-5eda2335b198', 'SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TUBERIA', 0, 630.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-01', 'CANCELADO', 630.0, null, 'EXCEL 2026'),
  ('d48659ee-076a-52f6-822a-921f5ccfa4f5', '09-0078-03-2026', '2026-04-04', '2a6edcfa-ef6c-5c80-a9cc-990c98fb81fb', 'CARQUIN', null, null, 'TERMOFUSION', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE MAQUINA DE TERMOFUSION DE 400MM', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('28ac0ee4-df20-5457-9370-3d58d55711be', '09-0079-04-2026', '2026-04-04', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE TUBOS DE FIERRO', 800.0, 0, 0.1, 94.0, 'CANCELADO', null, null, 'F001-1806', '2026-04-01', '2026-04-01', 'CANCELADO', 944.0, null, 'EXCEL 2026'),
  ('1324a859-6fd5-5fd0-b377-d245413e27dc', 'NRO DE PARTE 3193 (2026)', '2026-04-04', 'b5fe0337-ffa3-5950-90aa-945d3b1474ae', 'VENADO MUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA NRO 03 - NIVELACION', 0, 960.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'PENDIENTE DE PAGO', 420.0, null, 'EXCEL 2026'),
  ('874754f8-1133-5a06-87e1-9d6aa388b858', 'NRO DE PARTE 721 (2026)', '2026-04-05', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'CAÑETE', null, 'DOCUMENTACIÓN Y CONFIANZA', 'TRASLADO', 'LIBRE', 'ACEPTADO', 'PEN', 'TRASLADO DE SILO DE PARAMONGA A CAÑETE', 0, 1900.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-05', 'CANCELADO', 1900.0, null, 'EXCEL 2026'),
  ('f84c359a-90f3-5de1-8e5c-3129978a98e7', '09-0080-04-2026', '2026-04-06', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESCARGA DE TUBOS Y PLANCHAS', 1100.0, 0, 0.1, 130.0, 'CANCELADO', null, null, 'F001-1807', '2026-04-03', '2026-04-06', 'CANCELADO', 1298.0, null, 'EXCEL 2026'),
  ('04c9c90d-c023-5870-acc5-833c96b76956', 'SN-ABRIL-105 (2026)', '2026-04-06', 'f8620314-43b4-5b46-91db-484be70e87eb', 'CARQUIN', 'FATIMA FONSECA', 'CONFIANZA', 'TERMOFUSION', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA DE TERMOFUSION DE 500MM X 1 DIA', 0, 600.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-06', 'CANCELADO', 600.0, null, 'EXCEL 2026'),
  ('ccbca037-a757-536c-9c95-0e1f1200f59a', 'NRO DE PARTE 3194 (2026)', '2026-04-06', 'a390e377-1551-54a4-a0e4-c87004b6e5a7', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA RETROEXCAVADORA #03 - EXCAVACION', 0, 360.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-06', 'CANCELADO', 360.0, null, 'EXCEL 2026'),
  ('5938f051-84bb-5a4b-959b-f790b220d247', 'NRO DE PARTE 3195 (2026)', '2026-04-06', '981128eb-c5ca-5523-b63a-1d7cf3e4dd70', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA RETROEXCAVADORA #03 - EXCAVACION', 0, 420.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-06', 'CANCELADO', 420.0, null, 'EXCEL 2026'),
  ('f737efb6-8e65-5b42-b480-34e79a440ba5', 'NRO DE PARTE 3198 (2026)', '2026-04-07', '981128eb-c5ca-5523-b63a-1d7cf3e4dd70', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA RETROEXCAVADORA #03 - ELIMINACION DE PIEDRA', 0, 840.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-07', 'CANCELADO', 840.0, null, 'EXCEL 2026'),
  ('8c1672fb-08fc-5347-bcdc-953289123ed2', '09-0081-04-2026', '2026-04-08', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - ELIMINACION DE PLANTAS - SEMANA 12', 2988.0, 0, 0.1, 353.0, 'CANCELADO', '4000027207', '4000027207', 'F001-1808', '2026-04-08', '2026-04-24', 'CANCELADO', 3173.26, null, 'EXCEL 2026'),
  ('a7a1233d-52bb-5507-9b0c-00441fe23908', '09-0082-04-2026', '2026-04-08', '8f11eae4-3b75-54a5-9cce-14f6cb76e73d', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - TRASLADO DE MATERIALES', 0, 600.0, 0, 0, 'NO APLICA', null, null, null, '2026-04-15', '2026-04-15', 'CANCELADO', 600.0, null, 'EXCEL 2026'),
  ('c564a4ad-9c17-52c9-a98b-e928d034e4cc', '09-0083-04-2026', '2026-04-08', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'CAÑETE', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - TRASLADO DE SILO', 1200.0, 1900.0, 0.04, 57.0, 'CANCELADO', null, null, 'F001-1811', '2026-04-08', '2026-04-09', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('205bfaed-f8f3-508a-a180-5a22227161c1', 'NRO DE PARTE 3197 (2026)', '2026-04-09', '3d50542a-dcb5-5270-9c5c-c96b3e2e1b02', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - LIMPIEZA DE TERRENO', 0, 720.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-09', 'CANCELADO', 720.0, null, 'EXCEL 2026'),
  ('a13605a0-1cf0-5043-84f9-6fd897464c70', 'NRO DE PARTE 3198 (2026) (2)', '2026-04-09', '256a54c0-f63c-52e5-9f3c-53c469387064', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - CARGA DE MATERIAL', 0, 200.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-09', 'CANCELADO', 200.0, null, 'EXCEL 2026'),
  ('5accdb3a-0c66-586e-bdae-dd4568dc3f30', '09-0084-04-2026', '2026-04-10', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESCARGA DE GENERADOR', 1800.0, 0, 0.1, 212.0, 'CANCELADO', '4500137066', '1000226548', 'F001-1851', '2026-05-15', '2026-07-16', 'CANCELADO', 1912.0, null, 'EXCEL 2026'),
  ('0002c2f7-3739-586a-9677-0f845f4fb6e5', '09-0085-04-2026', '2026-04-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE GENERADOR', 1530.0, 0, 0.1, 181.0, 'CANCELADO', '4000029539', '1000027459', 'F001-1858', '2026-06-13', '2026-07-13', 'CANCELADO', 1624.4, null, 'EXCEL 2026'),
  ('ec269255-7cb6-5364-a55b-beded8a708cd', '09-0086-04-2026', '2026-04-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE TOTEMS', 360.0, 0, 0, 0, 'NO APLICA', '4000028966', '4000028966', 'F001-1844', '2026-05-07', '2026-06-05', 'CANCELADO', 424.8, null, 'EXCEL 2026'),
  ('f43cae94-dffe-5113-9cb4-3c013df8c460', '09-0087-04-2026', '2026-04-10', '9237b4d3-8227-5562-892c-6b9353e84721', 'HUACHO', null, null, 'OTRO', 'FACTURADO', 'RECHAZADO', 'PEN', 'CAMBIO DE LINEA DE AGUA Y DESAGÜE', 213500.16, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('e044db53-52c0-56b5-bdc0-7b706f837fb4', '09-0088-04-2026', '2026-04-10', '70d15013-8b35-55b7-accd-3bedf3319347', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TUBERIAS', 1100.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1814', '2026-04-09', '2026-04-09', 'CANCELADO', 708.0, null, 'EXCEL 2026'),
  ('0bda16ff-6f7d-5956-8d08-483a32a3ad90', '09-0089-04-2026', '2026-04-10', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - TRASLADO DE TUBERÍAS', 600.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1815', '2026-04-10', '2026-04-10', 'CANCELADO', 708.0, null, 'EXCEL 2026'),
  ('bfc3b688-61ed-5b62-8222-5b12af1d7b5c', 'NRO DE PARTE 3200 (2026)', '2026-04-11', '829dfa19-3c1f-5868-9be1-a1ead2aa3878', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA RETROEXCAVADORA #03 - EXCAVACION', 0, 840.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-11', 'CANCELADO', 840.0, null, 'EXCEL 2026'),
  ('5bf24be4-8f3e-5b30-b918-2d84b939e4f5', '09-0090-04-2026', '2026-04-13', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - EMBARQUE Y DESEMBARQUE DE MACACO', 880.0, 0, 0.1, 104.0, 'CANCELADO', '4500136749', '1000223988', 'F001-1827', '2026-04-21', '2026-06-21', 'CANCELADO', 934.4, null, 'EXCEL 2026'),
  ('c4bd54d0-b6d8-555d-811d-939fba00bedd', '09-0091-04-2026', '2026-04-13', 'f8e159c4-f059-5152-9196-7bdcf4b84d4a', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA -EMBARQUE DE MANGUERON', 880.0, 0, 0.1, 91.0, 'CANCELADO', '4500686058', '1000837220', 'F001-1874', '2026-06-18', '2026-09-15', 'CANCELADO', 817.6, null, 'EXCEL 2026'),
  ('f89b1674-7d0b-54d7-ac64-49ff6dfbe733', '09-0092-04-2026', '2026-04-13', 'f8e159c4-f059-5152-9196-7bdcf4b84d4a', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - EMBARQUE Y DESEMBARQUE DE MACACO', 880.0, 0, 0.1, 104.0, 'CANCELADO', '4500686059', '1000837219', 'F001-1873', '2026-06-18', '2026-09-15', 'CANCELADO', 899.0, null, 'EXCEL 2026'),
  ('04eb7df4-db6f-5a93-8ce9-54b0e2670673', '09-0093-04-2026', '2026-04-17', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE PLANCHAS', 1700.0, 0, 0.1, 201.0, 'CANCELADO', null, null, 'F001-1818', '2026-04-15', '2026-04-16', 'CANCELADO', 2006.0, null, 'EXCEL 2026'),
  ('b26be9dd-9cb6-5b72-bc3a-0647bcdf4796', '09-0094-04-2026', '2026-04-17', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', null, null, 'TERMOFUSION', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. DE TERMOFUSIÓN DE TUBERÍA DE HDPE 180MM', 8131.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('6317f012-ea9e-5bf0-a72e-f841c913bc40', '09-0095-04-2026', '2026-04-20', 'acbae08d-63cf-5e12-99c9-a61630f9d9db', 'PARAMONGA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE MOTOR', 880.0, 0, 0.1, 104.0, 'CANCELADO', null, null, 'F001-1826', '2026-04-20', '2026-04-20', 'CANCELADO', 1038.4, null, 'EXCEL 2026'),
  ('a406ba5b-eb15-53a5-ab6a-1000d8432b5a', '09-0096-04-2026', '2026-04-22', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PARAMONGA', null, null, 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE, TRASLADO Y DESCARGA DE MATERIALES Y EQUIPOS', 1540.0, 0, 0.1, 94.0, 'CANCELADO', null, null, 'F001-1845/ 1846', '2026-05-07', '2026-05-15', 'CANCELADO', 1888.0, null, 'EXCEL 2026'),
  ('a5c1903d-85c5-5255-a8e5-8a2578e5eb2f', '09-0097-04-2026', '2026-04-22', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', null, null, 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - CONSTRUCIION DE RESERVORIO - SEMANA 16', 3888.0, 0, 0.1, 459.0, 'CANCELADO', '0001/0014362', '0001/0014362', 'F001-1838', '2026-04-28', '2026-06-08', 'CANCELADO', 4026.0, null, 'EXCEL 2026'),
  ('d508005f-d1d0-5194-84aa-04c5dc42d1c0', '09-0098-04-2026', '2026-04-22', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', null, null, 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - LIMPIEZA DE MALEZA EN CAMPO - SEMANA 15', 1620.0, 0, 0.1, 722.16, 'CANCELADO', '0001/0014285', '0001/0014285', 'F001-1830', '2026-04-23', '2026-06-08', 'CANCELADO', 634.03, null, 'EXCEL 2026'),
  ('84f24758-2065-5dd4-8a45-dd7e3dcdc4c7', '09-0099-04-2026', '2026-04-23', 'f3580583-1978-579a-a7cd-6cfd1d44da9f', 'BARRANCA', null, null, 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - EXCAVACION DE ZANJAS', 2870.0, 0, 0.1, 339.0, 'CANCELADO', '4200297747', '1000601445', 'F001-1849', '2026-05-13', '2026-06-26', 'CANCELADO', 3047.6, null, 'EXCEL 2026'),
  ('82f93c81-20d6-59fa-a8d7-22c865955cf6', 'SN-ABRIL-131 (2026)', '2026-04-23', '39239554-b7fc-50af-8834-8241ffe2e88e', 'BARRANCA', 'MARÍA ORDOÑEZ', 'RECOMENDACIÓN', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. DE IZAJE Y CARGA DE TANQUE DE COMBUSTIBLE', 0, 600.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-23', 'CANCELADO', 600.0, null, 'EXCEL 2026'),
  ('1e9682da-e2b7-5827-9696-a385c4d225ca', 'SN-ABRIL-132 (2026)', '2026-04-23', 'c8abb4e3-9c5f-5167-8da3-e6f343a28614', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - SEMANA 15', 0, 1010.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-04-23', 'CANCELADO', 1010.0, null, 'EXCEL 2026'),
  ('b6053b0d-8adf-533f-9fd4-9a35f4d7a828', '09-0100-04-2026', '2026-04-24', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - CARGA,TRASLADO Y DESCARGA DE CAMIONETA', 1491.95, 0, 0.1, 176.0, 'CANCELADO', null, null, 'F001 -1842', '2026-04-30', '2026-05-28', 'CANCELADO', 1760.5, null, 'EXCEL 2026'),
  ('4a8ec1cd-844f-5693-8039-61773818317e', '09-0101-04-202 (2026)', '2026-04-24', 'acbae08d-63cf-5e12-99c9-a61630f9d9db', 'PARAMONGA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE MOTOR', 1100.0, 0, 0.1, 156.0, 'CANCELADO', null, null, 'F001-1836', '2026-04-25', '2026-04-25', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('70e6ce8a-29b1-51ac-8241-2cd1585cbccf', '09-0102-04-2026', '2026-04-24', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - EMBARQUE DE MATERIALES', 880.0, 0, 0.1, 104.0, 'CANCELADO', '4500138719', '1000227197', 'F001-1852', '2026-05-15', '2026-07-16', 'CANCELADO', 934.4, null, 'EXCEL 2026'),
  ('940ecc63-8775-55ce-9ca5-1fcb90e9ec5c', '09-0103-04-2026', '2026-04-24', '9d0dffcf-94e9-500a-a49f-88ab88828a62', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - EMBARQUE DE MATERIALES', 880.0, 0, 0.1, 104.0, 'CANCELADO', '4500138719', '1000227200', 'F001-1853', '2026-05-15', '2026-07-16', 'CANCELADO', 934.4, null, 'EXCEL 2026'),
  ('656eecaa-bf2b-5d8f-9917-d488dc43fd68', '09-0104-04-2026', '2026-04-25', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE PLANCHAS', 900.0, 0, 0.1, 106.0, 'CANCELADO', null, null, 'F001-1837', '2026-04-25', '2026-04-25', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('6a83c75e-821b-5911-88e4-271cde8e3afa', '09-0105-04-2026', '2026-04-28', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y CARGADO DE TUBERIA - SEMANA 17', 4644.0, 0, 0.1, 548.0, 'CANCELADO', '0001/0014512', null, 'F001-1843', '2026-05-07', '2026-06-08', 'CANCELADO', 4809.54, null, 'EXCEL 2026'),
  ('75e6f95c-9dcc-5f1a-90fa-9da88b3f2550', '09-0106-04-2026', '2026-04-30', '2d788c48-b27e-53df-8e6c-950efe69a9bd', 'LAS MERCEDES', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE ESTRUCTURAS METÁLICAS', 26400.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('2c053e5b-92ea-555d-92bc-df3bab1b6fc9', '09-0107-05-2026', '2026-05-04', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE PLANCHAS', 700.0, 0, 0.1, 83.0, 'CANCELADO', null, null, 'F001-1841', '2026-04-30', '2026-05-01', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('49c20270-3c5b-5a9f-b533-4ff69d6a4e09', '09-0108-05-2026', '2026-05-06', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y CARGADO DE TUBERIA - SEMANA 18', 2871.0, 0, 0.1, 339.0, 'CANCELADO', '0001/0014587', null, 'F001-1847', '2026-05-12', '2026-06-08', 'CANCELADO', 2973.13, null, 'EXCEL 2026'),
  ('6b6e9c5e-71e1-54b8-bab9-677b7eb7989b', '09-0109-05-2026', '2026-05-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE TOTEMS', 1140.0, 0, 0.1, 146.0, 'CANCELADO', '4000029385', '4000029385', 'F001-1865', '2026-06-05', '2026-06-20', 'CANCELADO', 1311.0, null, 'EXCEL 2026'),
  ('ffe76e42-6be5-5f7c-8cea-28e765d42f96', '09-0110-05-2026', '2026-05-08', 'd5666fe5-e144-5390-a6fb-bd0e9ca19e9c', 'ACAS', 'FATIMA FONSECA', null, 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE PIEZA', 3500.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('6453f3b5-e2d6-5d7f-be5b-0c441642cfef', '09-0111-05-2026', '2026-05-11', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y CARGADO DE TUBERIA - SEMANA 19', 4185.0, 0, 0.1, 494.0, 'CANCELADO', '0001/0014623', null, 'F001-1854', '2026-05-20', '2026-06-08', 'CANCELADO', 4334.0, null, 'EXCEL 2026'),
  ('c74d658b-46ac-57f1-affa-dacfcfd6de02', '09-0112-05-2026', '2026-05-13', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'TRASLADO', 'FACTURADO', 'RECHAZADO', 'PEN', 'TRASLADO DE BOYAS DE CHINCHA A SUPE Y VICEVERSA', 7000.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('b573cdbe-01e8-53cc-976d-5821b6cfeedf', '09-0113-05-2026', '2026-05-13', '2af70902-9008-5ce6-a0d9-acf370f5adb4', null, 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'MAQUINARIA PESADA', 'FACTURADO', 'RECHAZADO', 'USD', 'SUMINISTRO Y TRASLADO DE LASTRE DE CONCRETO DE 10TN', 6680.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('486be1e0-0650-5134-8a08-e0fdcedf8d23', '09-0114-05-2026', '2026-05-13', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQ. DE CAMIÓN GRUA - DESMONTAJE DE TUBERÍA', 600.0, 0, 0.1, 106.0, 'CANCELADO', null, null, 'F001-1879', '2026-06-24', '2026-06-24', 'CANCELADO', 1062.0, null, 'EXCEL 2026'),
  ('d9b83ac3-5593-58d6-84e3-249bf464bcc2', '09-0115-05-2026', '2026-05-15', 'd6877aa6-ce2a-5fdb-ab05-8a6b9fe10ded', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQ. DE CAMIÓN GRUA - DESCARGA DE PLANCHAS', 600.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('20d63959-8337-5a5a-95c4-d8b88b999d81', '09-0116-05-2026', '2026-05-15', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE BRAZO', 570.0, 0, 0.1, 212.0, 'CANCELADO', '4000030498', '1000028769', 'F001-1880', '2026-06-26', '2026-07-17', 'CANCELADO', 1911.6, null, 'EXCEL 2026'),
  ('fbdf7387-6970-5bba-9c59-04c5949e94a9', '09-0117-05-2026', '2026-05-18', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TRANSFORMADOR', 1140.0, 0, 0.1, 0, 'CANCELADO', '4000030498', '1000028769', null, '2026-06-26', '2026-07-17', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('f3d70962-8873-5a42-8b20-5f1809320b60', '09-0118-05-2026', '2026-05-18', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TUBERÍA DE HDPE', 900.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1878', '2026-06-24', '2026-06-24', 'CANCELADO', 708.0, null, 'EXCEL 2026'),
  ('6232bedf-26e4-5c79-bc15-8c0f38c98337', '09-0119-05-2026', '2026-05-18', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTORES', 1140.0, 0, 0.1, 561.0, 'CANCELADO', '4000030513', '1000028770', 'F001-1877', '2026-06-24', '2026-07-10', 'CANCELADO', 5044.0, null, 'EXCEL 2026'),
  ('d3fdbd31-cb65-5b67-8f6c-24469186857a', '09-0120-05-2026', '2026-05-18', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION PARA INSTALACIÓN DE TUBERÍAS - SEMANA 20', 4185.0, 0, 0.1, 494.0, 'CANCELADO', '0001/0014714', null, 'F001-1856', '2026-05-29', '2026-06-15', 'CANCELADO', 4332.17, null, 'EXCEL 2026'),
  ('f311e4ae-8fca-5d76-bc85-0c59a571ff0b', '09-0121-05-2026', '2026-05-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - LIMPIEZA DE POZAS DE ALIVIO - SEMANA 20', 3300.0, 0, 0.1, 389.0, 'CANCELADO', '4000031192', '1000029078', 'F001-1869', '2026-06-17', '2026-07-03', 'CANCELADO', 3505.0, null, 'EXCEL 2026'),
  ('a96a028c-d1ca-5c50-a8ae-507b01be0629', '09-0122-05-2026', '2026-05-23', '3e6f1239-ace9-5b21-8a96-a397b15a420d', 'PARARIN', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE VIGAS', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('d049cc4d-8051-5c7a-ab1d-2d5839296ab4', '09-0123-05-2026', '2026-05-23', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTORES', 1425.0, 0, 0.1, 561.0, 'CANCELADO', '4000030513', '1000028770', 'F001-1877', '2026-06-24', '2026-07-10', 'CANCELADO', 5044.0, null, 'EXCEL 2026'),
  ('4fc3e4de-2ccf-5b7f-9c31-27ac4b0a8f7d', '09-0124-05-2026', '2026-05-23', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - TRASLADO INTERNO DE PODADORAS', 1140.0, 0, 0.1, 0, 'CANCELADO', '4000030513', '1000028770', 'F001-1877', '2026-06-24', '2026-07-10', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('eba1c1ae-4454-597c-a734-2997b8a46cfd', '09-0125-05-2026', '2026-05-23', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1045.0, 0, 0.1, 0, 'CANCELADO', '4000030513', '1000028770', 'F001-1877', '2026-06-24', '2026-07-10', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('f9377393-15e3-53bd-9118-42ec0b0e6330', '09-0126-05-2026', '2026-05-25', '2fd8d87e-9b83-56a2-bafa-654f906e2d81', 'VENADO MUERTO', 'FATIMA FONSECA', 'PUBLICIDAD', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA', 110.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('205b5c0f-74c9-503b-b71b-92ab86986ebe', '09-0127-05-2026', '2026-05-25', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION PARA INSTALACIÓN DE TUBERÍAS - SEMANA 21', 4239.0, 0, 0.1, 500.0, 'CANCELADO', '0001/0014836', null, 'F0011-1859', '2026-05-29', '2026-06-15', 'CANCELADO', 4388.43, null, 'EXCEL 2026'),
  ('a3f39f6c-ff94-555c-9770-8f92c3a45ffa', '09-0128-05-2026', '2026-05-26', 'baa57998-ffb4-5d4c-9011-107a0e94a1bd', 'PUCUSANA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TIJERALES', 8250.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('8becb5ed-0d16-5566-be3a-bd8a7cee2d09', '09-0129-05-2026', '2026-05-27', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE PLANCHAS', 900.0, 0, 0.1, 94.0, 'CANCELADO', null, null, 'F001-1855', '2026-05-26', '2026-05-27', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('018f7fcc-9dd5-5b0a-82e2-df91a9f3313f', '09-0130-05-2026', '2026-05-29', 'f3580583-1978-579a-a7cd-6cfd1d44da9f', 'BARRANCA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE CANAL', 4767.0, 0, 0.1, 563.0, 'CANCELADO', '4200298268', null, 'F001-1857', '2026-05-29', '2026-07-03', 'CANCELADO', 5062.06, null, 'EXCEL 2026'),
  ('bee25509-75da-5a01-9535-449e20fb7ff5', '09-0131-06-2026', '2026-06-02', '5e5c97ae-fc83-5129-aca0-abb7aecd1b30', 'SAN TELMO', 'FATIMA FONSECA', 'DOCUMENTACIÓN', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESCARGA DE PERFILES METALICOS', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('ff7b19ac-24a5-5c3a-b602-fbdf8b36d26d', '09-0132-06-2026', '2026-06-02', 'f476656a-7c45-5a5a-90d4-ca6f2f66c2f4', 'HUACHO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV, ALQUILER DE CAMION GRUA', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('86c2fc64-de4b-5f44-b9dc-3f740303268b', '09-0133-06-2026', '2026-06-03', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - LIMPIEZA DE CANAL RANRAHIRCA', 500.0, 0, 0, 0, 'NO APLICA', '4000030617', '1000028288', 'F001-1861', '2026-06-03', '2026-07-03', 'CANCELADO', 590.0, null, 'EXCEL 2026'),
  ('29831822-ec2d-58f4-80dd-56b9b3b4bfd8', '09-0134-06-2026', '2026-06-03', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PARAMONGA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE ALQUILER DE CAMIONGRUA - IZAJE DE MATERIALES DIA 03/06/2026', 550.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1862', '2026-06-03', '2026-06-03', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('79c6e511-f414-59aa-9f0d-14b1260da9a0', '09-0135-06-2026', '2026-06-03', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE MATERIALES Y USO DE CANASTILLA', 1800.0, 0, 0.1, 213.0, 'CANCELADO', null, null, 'F001-1860 / 1863', null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('d531fc14-91f8-5e7a-a9e6-feaafd8278d1', 'NRO DE PARTE 559 (2026)', '2026-06-03', 'f38c46c3-176c-5574-a069-f6ed7a26484b', 'HUACHO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE EQUIPOS', 0, 1200.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('fc3c584a-bd24-57c6-a694-81483979ca68', 'NRO DE PARTE 3292 (2026)', '2026-06-06', '74253ffb-ab53-5953-9682-5c5ebd8992a3', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACION DE POZOS', 0, 2100.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('45971b2d-707f-5c98-af4b-5e2dcf1689a4', '09-0136-06-2026', '2026-06-05', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - LIMPIEZA DE RÁPIDA', 550.0, 0, 0, 0, 'NO APLICA', '4000030842', '1000028454', 'F001-1864', '2026-06-05', '2026-06-20', 'CANCELADO', 649.0, null, 'EXCEL 2026'),
  ('83fb3ae3-a767-5ef9-8990-ff644f7d60b3', '09-0137-06-2026', '2026-06-05', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION PARA INSTALACIÓN DE TUBERÍAS - SEMANA 22', 2097.0, 0, 0.1, 247.0, 'CANCELADO', '0001/0014982', '0001/0014982', 'F001-1866', '2026-06-10', '2026-06-22', 'CANCELADO', 2171.26, null, 'EXCEL 2026'),
  ('bc351ce4-f1d4-5366-87ed-a3ad870b5086', '09-0138-06-2026', '2026-06-08', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION PARA INSTALACIÓN DE TUBERÍAS - SEMANA 23', 6174.0, 0, 0.1, 729.0, 'CANCELADO', '0001/0015036', '0001/0015036', 'F001-1872', '2026-06-17', '2026-06-30', 'CANCELADO', 6393.63, null, 'EXCEL 2026'),
  ('028cf1a9-e4c7-5325-b132-79172ccd1ee9', 'NRO DE PARTE 3294 (2026)', '2026-06-08', '16f19f2a-b716-564a-a4a9-53b1284f4e5a', 'PORVENIR', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA CON CUCHARA - EXCAVACION DE ZANJA', 0, 600.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('78fbf404-4af2-55c5-ad3d-643c29770143', 'NRO DE PARTE 3295 (2026)', '2026-06-08', '16f19f2a-b716-564a-a4a9-53b1284f4e5a', 'PORVENIR', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA CON ROTOMARTILLO - EXCAVACION DE ZANJA', 0, 360.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('29f30742-3bb3-525b-8caa-7fdc857cf368', 'NRO DE PARTE 3297 (2026)', '2026-06-09', '16f19f2a-b716-564a-a4a9-53b1284f4e5a', 'PORVENIR', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA CON ROTOMARTILLO - EXCAVACION DE ZANJA', 0, 585.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('5e054cfd-e8e3-5076-b892-b2077bb10268', 'NRO DE PARTE 3298 (2026)', '2026-06-09', '16f19f2a-b716-564a-a4a9-53b1284f4e5a', 'PORVENIR', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACION DE ZANJA', 0, 510.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('e3165232-4cdf-5813-abd0-6aed066aa55c', 'NRO DE PARTE 3298 (2026) (2)', '2026-06-10', '16f19f2a-b716-564a-a4a9-53b1284f4e5a', 'PORVENIR', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACION DE ZANJA', 0, 360.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('287d377a-0f09-53b1-beba-2943ad25e3d1', 'NRO DE PARTE 3299 (2026)', '2026-06-10', '7e91af49-4ac3-5be1-84bf-d6e87f0ae639', 'SANTA ELENA SUR', null, null, 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - NIVELACION', 0, 280.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('f7501d0d-7f7d-529c-8cf1-b5d60f5f62e1', '09-0139-06-2026', '2026-06-12', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE TOTEMS', 1805.0, 0, 0.1, 213.0, 'CANCELADO', '4000031517', '4000031517', 'F001-1881', '2026-06-26', '2026-07-10', 'CANCELADO', 1916.0, null, 'EXCEL 2026'),
  ('03a9d946-0ac2-54eb-bf1e-31a1e95fbceb', '09-0140-06-2026', '2026-06-12', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - EXCAVACIÓN DE ZANJA', 900.0, 0, 0.1, 106.0, 'CANCELADO', '4000030747', '1000028957', 'F001-1871', '2026-06-17', '2026-07-07', 'CANCELADO', 956.0, null, 'EXCEL 2026'),
  ('ebfb1725-d736-588f-9db5-496e0bdcaa28', '09-0141-06-2026', '2026-06-15', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE TUBERÍAS - SEMANA 24', 4023.0, 0, 0.1, 475.0, 'CANCELADO', '0001/0015134', '0001/0015134', 'F001-1876', '2026-06-24', '2026-08-24', 'CANCELADO', 4166.13, null, 'EXCEL 2026'),
  ('6aa7c3ee-c470-50b8-8bc6-7e8580245400', '09-0142-06-2026', '2026-06-17', '86cc280f-6895-5548-948c-f2ba9255f47f', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TUBERÍA Y PINTADO DE CANASTILLA', 1100.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1867', '2026-06-16', '2026-06-16', 'CANCELADO', 708.0, null, 'EXCEL 2026'),
  ('c61bf3c4-0810-505c-b579-aba6dc663e27', '09-0143-06-2026', '2026-06-17', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - ENTERRADO DE PALTA', 2150.0, 0, 0.1, 254.0, 'CANCELADO', '4000031449', '4000031449', 'F001-1870', '2026-06-17', '2026-07-03', 'CANCELADO', 2283.0, null, 'EXCEL 2026'),
  ('83e9ff35-4793-56a9-ab08-e4daa7b9ae7c', '09-0144-06-2026', '2026-06-17', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - EXCAVACIÓN DE ZANJA', 2800.0, 0, 0.1, 330.0, 'CANCELADO', '4000030749', '1000029077', 'F001-1868', '2026-06-17', '2026-07-03', 'CANCELADO', 2974.0, null, 'EXCEL 2026'),
  ('706fddef-82f5-5397-a5bf-6c426c19efb4', '09-0145-06-2026', '2026-06-19', '3e6f1239-ace9-5b21-8a96-a397b15a420d', 'PARARIN', null, 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE VIGAS', 0, 5700.0, 0, 0, null, null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('5eff2d62-09ed-53da-bb9c-8668f93030ec', '09-0146-06-2026', '2026-06-19', '4e0ceeeb-5448-560a-b5c3-37f0373a4153', 'SUPE PUERTO', 'MARÍA ORDOÑEZ', 'CONFIANZA', 'TRASLADO', 'FACTURADO', 'RECHAZADO', 'PEN', 'DESMONTAJE, LIMPIEZA Y TRASLADO DE TANQUE DE SULFATO FÉRRICO', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('2ca3453d-28c4-56ce-b18a-12e542b73de8', '09-0147-06-2026', '2026-06-22', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SAN TELMO', 'MARÍA ORDOÑEZ', 'DOCUMENTACIÓN Y CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE TUBERÍAS - SEMANA 25', 3132.0, 0, 0.1, 370.0, 'CANCELADO', '0001/0015231', '0001/0015231', 'F001-1882', '2026-07-02', '2026-07-20', 'CANCELADO', 3286.2, null, 'EXCEL 2026'),
  ('2405c169-f52a-5f65-8545-d956afe42f72', '09-0148-06-2026', '2026-06-26', 'f8e159c4-f059-5152-9196-7bdcf4b84d4a', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TABLEROS Y TK DE DIESEL', 1100.0, 0, 0.1, 156.0, 'CANCELADO', '4500690530', '1000839762', 'F001 1883', '2026-07-06', '2027-01-06', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('db04d5cf-00e5-58b1-8654-567d2f478288', 'NRO DE PARTE 3362 (2026)', '2026-06-27', '0d561a4f-7fcd-53a6-9276-db11ca68643f', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - NIVELACION', 0, 360.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-06-26', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('4828e4c8-9fee-591b-8276-c4c7ed9fe949', 'NRO DE PARTE 868 (2026)', '2026-06-27', 'edd6571d-faf7-5fdf-b74a-d73061a4070f', 'ALCANTARILLA', 'RICARDO RUIZ', 'CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TIJERALES', 0, 1080.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-06-27', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('48512f61-9589-56c6-b2d7-c0534cd33d6d', 'NRO DE PARTE 3465 (2026)', '2026-06-27', '992547a8-1c0b-54d2-8a68-a5fec8f7d740', 'PATIVILCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #03 - NIVELACION', 0, 840.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-06-27', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('61c9037c-7622-574d-846b-6a72b53f02d8', 'NRO DE PARTE 3344 (2026)', '2026-06-27', '0d561a4f-7fcd-53a6-9276-db11ca68643f', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - NIVELACION', 0, 1200.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-06-27', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('85aee969-7b88-5c65-90a8-d4df6504b8bc', 'NRO DE PARTE 3345 (2026)', '2026-06-28', '0d561a4f-7fcd-53a6-9276-db11ca68643f', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - NIVELACION', 0, 1080.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-06-27', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('ebc333c3-36ca-5bbf-84e9-d05a482fe823', '09-0149-07-2026', '2026-07-03', 'be3ab2f4-8bf0-5b25-a684-764d7f127f01', 'HUARMEY', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'OTRO', 'FACTURADO', 'ACEPTADO', 'PEN', 'DESCARGA DE EQUIPOS', 2000.0, 0, 0.1, 236.0, 'CANCELADO', null, null, 'F001-1884', '2026-07-06', '2026-07-10', 'CANCELADO', 2124.0, null, 'EXCEL 2026'),
  ('85b87b9f-be99-592f-95ce-4c953f1bdfcc', '09-0150-07-2026', '2026-07-06', 'be3ab2f4-8bf0-5b25-a684-764d7f127f01', 'LIMA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'TRASLADO', 'FACTURADO', 'ACEPTADO', 'PEN', 'TRASLADO DE MATERIALES DE LIMA A HUARMEY', 2100.0, 0, 0.04, 99.0, 'CANCELADO', '3100000980', null, 'F001-1887', '2026-07-13', '2026-07-17', 'CANCELADO', 2379.0, null, 'EXCEL 2026'),
  ('272b7674-47ee-511c-9b26-de54b3d8b6c0', '09-0151-07-2026', '2026-07-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - LIMPIEZA DE POZAS, EXCAVACIÓN Y NIVELACIÓN', 4800.0, 0, 0.1, 566.0, 'CANCELADO', '4000033021', '1000030605', 'F001-1889', '2026-07-14', '2026-07-31', 'CANCELADO', 5098.0, null, 'EXCEL 2026'),
  ('a7498ee7-642d-579f-ad6a-71fadfde751c', '09-0152-07-2026', '2026-07-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - LIMPIEZA DE POZAS', 5430.0, 0, 0.1, 560.0, 'CANCELADO', '4000033018', '1000030604', 'F001-1890', '2026-07-14', '2026-07-31', 'CANCELADO', 5042.64, null, 'EXCEL 2026'),
  ('c33e0203-3edf-557e-b7e5-4ea9bb42bb98', '09-0153-07-2026', '2026-07-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - RETIRADO DE MATERIAL', 4200.0, 0, 0.1, 496.0, 'CANCELADO', '4000033019', '1000030603', 'F001-1888', '2026-07-14', '2026-07-31', 'CANCELADO', 4160.0, null, 'EXCEL 2026'),
  ('7a45b609-1301-556f-91d0-fa3ce62f8a13', '09-0154-07-2026', '2026-07-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 02 - LIMPIEZA DE POZAS', 1200.0, 0, 0.1, 142.0, 'CANCELADO', '4000032750', '1000030225', 'F001-1885', '2026-07-08', '2026-07-31', 'CANCELADO', 1274.0, null, 'EXCEL 2026'),
  ('3b866d19-5ed7-555e-aa4b-2aec1f5b716c', '09-0155-07-2026', '2026-07-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE PODADORAS', 1045.0, 0, 0.1, 123.0, 'CANCELADO', '400003371', '1000031078', 'F001-1893', '2026-07-21', '2026-08-07', 'CANCELADO', 1109.79, null, 'EXCEL 2026'),
  ('140007e4-2a22-5b2f-8522-d9084eb6fa46', '09-0156-07-2026', '2026-07-08', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTORES Y BOMBAS', 1900.0, 0, 0.1, 224.0, 'CANCELADO', '4000036267', '1000034156 - 1000034157 1000034158', 'F001-1923', '2026-09-04', '2026-09-18', 'CANCELADO', 2018.0, null, 'EXCEL 2026'),
  ('c2fd267b-a1b3-5d5c-813a-64c5239c2284', '09-0157-07-2026', '2026-07-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TRANSFORMADORES', 950.0, 0, 0.1, 112.0, 'CANCELADO', '4000036267', '1000034156 - 1000034157 1000034158', 'F001-1923', '2026-09-04', '2026-09-18', 'CANCELADO', 1009.0, null, 'EXCEL 2026'),
  ('6200174d-b2da-5282-866b-ba62083ee7e8', '09-0158-07-2026', '2026-07-10', '75c1286c-0bdd-529c-89b0-788be9a13bd8', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - CARGA Y DESCARGA DE CAMIONETA', 600.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1886', '2026-07-10', '2026-07-10', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('bf7a07bd-68d4-50a8-b453-674b6cf4a57a', '09-0159-07-2026', '2026-07-14', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'SANTA AZUL', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE ZANJAS - SEMANA 27', 720.0, 0, 0.1, 85.0, 'CANCELADO', '0001/0046149', null, 'F001-1894', '2026-07-30', '2026-09-30', 'CANCELADO', 285.46, null, 'EXCEL 2026'),
  ('1317c28d-3952-51a9-b620-89dcd7893e77', '09-0160-07-2026', '2026-07-14', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SANTA AZUL', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE ZANJAS - SEMANA 28', 4086.0, 0, 0.1, 482.0, 'CANCELADO', '0001/0015412', null, 'F001-1896', '2026-07-31', '2026-08-17', 'CANCELADO', 4307.55, null, 'EXCEL 2026'),
  ('f693b86f-4940-56c3-b387-81104dd81ba4', '09-0161-07-2026', '2026-07-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTORES Y BOMBAS', 1900.0, 0, 0.1, 225.0, 'CANCELADO', '4000034851', '1000032952', 'F001-1916', '2026-08-21', '2026-09-04', 'CANCELADO', 2242.0, null, 'EXCEL 2026'),
  ('e52c42b7-9398-5399-bc3e-369fea22e65c', '09-0162-07-2026', '2026-07-17', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'SUMINISTRO', 'FACTURADO', 'ACEPTADO', 'PEN', 'SUMINISTRO DE FLANGE ADAPTER 450MM', 3150.0, 0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 3717.0, null, 'EXCEL 2026'),
  ('4c078bfe-3769-512e-9b92-600efcffddf7', '09-0163-07-2026', '2026-07-17', '1cdc8de5-f808-5c77-8bd6-a9bc9fd8d805', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE CADENAS', 600.0, 0, 0.1, 94.0, 'CANCELADO', null, null, 'F001-1891', '2026-07-17', '2026-07-17', 'CANCELADO', 944.0, null, 'EXCEL 2026'),
  ('9a6a919f-e9d9-5d6c-a9cc-928f6acf9b99', '09-0164-07-2026', '2026-07-20', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SANTA AZUL', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE ZANJAS - SEMANA 29', 2691.0, 0, 0.1, 318.0, 'CANCELADO', '0001/0015418', null, 'F001-1897', '2026-08-01', '2026-08-17', 'CANCELADO', 2825.6, null, 'EXCEL 2026'),
  ('bcad2f38-c8f8-54be-8528-952f38cbbe7e', '09-0165-07-2026', '2026-07-20', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PUERTO SUPE', 'ANGIE ZELAYA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE IZAJE DE MATERIALES DIA 16/07', 550.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1892', '2026-07-20', '2026-07-27', 'CANCELADO', 649.0, null, 'EXCEL 2026'),
  ('a6a03c24-a641-5747-b775-caa905189c1d', '09-0166-07-2026', '2026-07-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA -IZAJE DE PODADORA', 760.0, 0, 0.1, 90.0, 'CANCELADO', '4000034450', '1000032163', 'F001-1901', '2026-08-07', '2026-08-22', 'CANCELADO', 806.8, null, 'EXCEL 2026'),
  ('7c3cc3d8-d510-5e89-a912-fd6192c467f8', '09-0167-07-2026', '2026-07-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE TANQUE', 380.0, 0, 0, 0, 'NO APLICA', '4000034547', '1000035680', 'F001-1938', '2026-09-25', '2026-10-09', 'CANCELADO', 448.4, null, 'EXCEL 2026'),
  ('1a8d8bc6-ddc7-5e58-a126-48eb52baa925', '09-0168-07-2026', '2026-07-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TRANSFORMADORES', 950.0, 0, 0.1, 112.0, 'CANCELADO', '4000034851', '1000032952', 'F001-1916', '2026-08-21', '2026-09-04', 'CANCELADO', 1121.0, null, 'EXCEL 2026'),
  ('c3745f3d-3d3a-529d-8a58-6acb314c3f71', '09-0169-07-2026', '2026-07-22', '8f11eae4-3b75-54a5-9cce-14f6cb76e73d', 'SUPE PUERTO', 'FATIMA FONSECA', 'DOCUMENTACIÓN', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE TUBERÍAS', 600.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('900f7460-e724-5122-9d96-9c4fb88a543d', '09-0170-07-2026', '2026-07-22', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TRANSFORMADORES', 1140.0, 0, 0.1, 135.0, 'CANCELADO', '4000034851', '1000032952', 'F001-1916', '2026-08-21', '2026-09-04', 'CANCELADO', 1345.2, null, 'EXCEL 2026'),
  ('ba4b46a6-b77e-5559-bd6c-5bc0c7bcbdf4', '09-0171-07-2026', '2026-07-22', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE Y DESMONTAJE DE BOMBAS Y MOTORES', 1330.0, 0, 0, 156.0, 'CANCELADO', '4000034851', '1000032952', 'F001-1916', '2026-08-21', '2026-09-04', 'CANCELADO', 1569.4, null, 'EXCEL 2026'),
  ('898a9147-a26a-5720-8243-6c2f72a63b7a', 'NRO DE PARTE 882 (2026)', '2026-07-22', '80ce17ac-4554-55fc-9986-428be123dc9a', 'ACCOS', null, 'CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE TIJERALES', 0, 4400.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-07-22', 'CANCELADO', 4400.0, null, 'EXCEL 2026'),
  ('405b0e1c-b36d-5d3b-8af2-bca79ddac38b', '09-0172-07-2026', '2026-07-30', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE ZANJAS - SEMANA 27', 432.0, 0, 0, 0, 'NO APLICA', '0001/ 001542', null, 'F001-1895', '2026-07-30', '2026-08-17', 'CANCELADO', 477.98, null, 'EXCEL 2026'),
  ('09d8da03-ba77-5f14-a545-c5594ae315d6', '09-0173-07-2026', '2026-07-30', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE', 'FATIMA FONSECA', 'CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'ACEPTADO', 'USD', 'ALQUILER DE MAQUINA DE TERMOFUSIÓN450mm', 400.0, 0, 0.1, 159.0, 'CANCELADO', null, null, 'F001-1936', '2026-09-23', '2026-09-30', 'CANCELADO', 472.0, null, 'EXCEL 2026'),
  ('69128df0-662e-54ba-968d-8af6f9337cc9', 'NRO DE PARTE 885 (2026)', '2026-07-30', '42d740e8-9898-580c-8bf8-2940e54c9cf8', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA - DESMONTAJE DE MASTIL', 0, 300.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-07-30', 'CANCELADO', 300.0, null, 'EXCEL 2026'),
  ('2059a51a-f761-5c07-9fa7-c48722910c8e', '09-0174-07-2026', '2026-07-31', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SANTA AZUL', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA - SEMANA 29', 1368.0, 0, 0.1, 569.0, 'CANCELADO', '0001/0015525', null, 'F001-1902', '2026-08-08', '2026-08-26', 'CANCELADO', 5064.28, null, 'EXCEL 2026'),
  ('2093f2b4-0d28-5ca5-aae3-6c613c4e127b', '09-0175-07-2026', '2026-07-31', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'SANTA AZUL', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE ZANJAS - SEMANA 30', 3456.0, 0, 0, 0, null, '0001/0015525', null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('8811d3b0-9b14-5a35-bccf-eda97b5214f8', '09-0176-07-2026', '2026-07-31', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA -MOVIMIENTO DE TOTEMS', 1425.0, 0, 0.1, 168.0, 'CANCELADO', '4000034404', null, 'F001-1905', '2026-08-10', '2026-08-28', 'CANCELADO', 1513.5, null, 'EXCEL 2026'),
  ('73551e5d-e21a-565f-8c84-01dab0c34a64', '09-0177-07-2026', '2026-07-31', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA -MONTAJE DE BOMBA Y MOTOR', 855.0, 0, 0.1, 101.0, 'CANCELADO', '4000036267', '1000034156 - 1000034157 1000034158', 'F001-1923', '2026-09-04', '2026-09-18', 'CANCELADO', 908.0, null, 'EXCEL 2026'),
  ('2edee321-5ac7-5454-b8d2-138be2671964', '09-0178-07-2026', '2026-07-31', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA -EXCAVACION DE ZANJAS', 4800.0, 0, 0.1, 566.0, 'CANCELADO', '4000034827', '1000032630', 'F001-1912', '2026-08-18', '2026-09-04', 'CANCELADO', 5098.0, null, 'EXCEL 2026'),
  ('87a8d23d-4492-5271-90c0-c7999f404c83', '09-0179-07-2026', '2026-07-31', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'TARIFA OFERTA DE RETROEXCAVADORA', 90.0, 0, 0, 0, 'NO APLICA', null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('e3fd953f-e966-5336-b573-21b1d683b400', '09-0180-07-2026', '2026-07-31', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA -MONTAJE DE MOTOR Y BOMBA', 1330.0, 0, 0.1, 157.0, 'CANCELADO', '4000036267', '1000034156 - 1000034157 1000034158', 'F001-1923', '2026-09-04', '2026-09-18', 'CANCELADO', 1412.4, null, 'EXCEL 2026'),
  ('2217365f-dbbe-559d-8427-def4fe37d2f8', '09-0181-08-2026', '2026-08-01', '0364fb61-3244-57a1-87b4-30b80d3a1ad2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'ANDAMIOS', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE ANDAMIO NORMADO 3 CUERPOS + BARANDA', 600.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1899-1900-1904-1907', '2026-08-01', '2026-08-13', 'CANCELADO', 1947.0, null, 'EXCEL 2026'),
  ('3074d725-806d-5d28-97f1-190e33929f09', 'NRO DE PARTE 588 (2026)', '2026-08-01', 'da7dfbee-a328-5e8e-87ec-18ef7de7822f', 'SUPE PUERTO', 'ANGIE ZELAYA', 'PUBLICIDAD', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMION GRUA - REMOLQUE DE CAMION', 0, 300.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-08-01', 'CANCELADO', 300.0, null, 'EXCEL 2026'),
  ('5a5aba58-17ab-5731-a253-3db17fd7728d', 'NRO DE PARTE 3495 (2026)', '2026-08-01', 'b8fc85aa-260a-534d-aacf-757e0a246a3c', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA #03 - RETIRO DE PLANTAS', 0, 520.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-08-01', 'CANCELADO', 520.0, null, 'EXCEL 2026'),
  ('d4cc22b9-6c3a-5a03-b2c1-cfab17a390e4', 'NRO DE PARTE 3496 (2026)', '2026-08-01', '6986e544-f226-5be1-a484-8ceabbf58852', 'VENADO MUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'LIBRE', 'ACEPTADO', 'PEN', 'ALQUILER DE RETROEXCAVADORA #03 - EXCAVACION DE POZA', 0, 390.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', null, null, 'EXCEL 2026'),
  ('01781477-32b0-5881-bf65-e9a23ffddbf4', '09-0182-08-2026', '2026-08-04', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'SUMINISTRO', 'FACTURADO', 'ACEPTADO', 'PEN', 'SUMINISTRO DE BRIDA SLIP ON 20"', 680.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1925', '2026-09-04', '2026-09-04', 'CANCELADO', 802.4, null, 'EXCEL 2026'),
  ('3be64816-53b1-513f-baa5-86169110fb73', '09-0183-08-2026', '2026-08-04', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - POZAS PLUVIALES', 4800.0, 0, 0.1, 566.0, 'CANCELADO', '4000034425', '1000032211', 'F001-1903', '2026-08-08', '2026-08-22', 'CANCELADO', 5098.0, null, 'EXCEL 2026'),
  ('53244553-a40c-5041-aee7-bb667fb23b94', '09-0184-08-2026', '2026-08-04', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - REUBICACIÓN DE TUBERÍAS', 700.0, 0, 0.1, 83.0, 'CANCELADO', '4000034417', '1000032473', 'F001-1908', '2026-08-13', '2026-08-28', 'CANCELADO', 743.0, null, 'EXCEL 2026'),
  ('39e44e44-6dfe-5c05-98a1-9bbf92ca15e7', '09-0185-08-2026', '2026-08-05', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'AGRICOLA INTERANDINA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION Y TAPADO DE ZANJAS - SEMANA 31', 2529.0, 0, 0.1, 290.0, 'CANCELADO', '0001/0015678', null, 'F001-1920', '2026-08-28', '2026-09-14', 'CANCELADO', 2576.99, null, 'EXCEL 2026'),
  ('16a69765-d7b3-50a0-817f-21e631c6b6e9', '09-0186-08-2026', '2026-08-05', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE MOTOR Y BOMBA', 570.0, 0, 0.1, 67.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 605.6, null, 'EXCEL 2026'),
  ('dc8ee1ae-19de-5d14-bc21-895d2bbc7df6', '09-0187-08-2026', '2026-08-05', '3a542a4f-bc91-55c3-9433-2b484e0ed13c', 'VEGUETA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - CARGA Y DESCARGA DE MOTORES Y BOMBAS', 2000.0, 0, 0.04, 94.0, 'CANCELADO', '0001-0001-0013350', null, 'F001-1906', '2026-08-11', '2026-08-14', 'CANCELADO', 2265.6, null, 'EXCEL 2026'),
  ('844eaf30-5add-5646-a676-22c3791616df', '09-0188-08-2026', '2026-08-07', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y MONTAJE DE MOTOR Y BOMBA', 1140.0, 0, 0.1, 135.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 1210.2, null, 'EXCEL 2026'),
  ('1b289c84-d4de-5a9a-a553-dc6cad365040', '09-0189-08-2026', '2026-08-07', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 570.0, 0, 0.1, 67.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 605.6, null, 'EXCEL 2026'),
  ('e2607ca9-aec7-575e-b387-3d6a5ecfd0d7', '09-0190-08-2026', '2026-08-08', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1140.0, 0, 0.1, 135.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 1210.2, null, 'EXCEL 2026'),
  ('67feae91-7293-5b4f-8675-3ce498ba661c', '09-0191-08-2026', '2026-08-11', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - MEJORAMIENTO DE CAMINO', 4800.0, 0, 0.1, 566.0, 'CANCELADO', '4000034762', '1000032666', 'F001-1909', '2026-08-14', '2026-08-28', 'CANCELADO', 5098.0, null, 'EXCEL 2026'),
  ('65036579-564c-51ed-9033-51db71d30312', '09-0192-08-2026', '2026-08-11', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - EXCAVACIÓN DE ZANJAS', 3600.0, 0, 0.1, 425.0, 'CANCELADO', '4000035524', '1000033008', 'F001-1915', '2026-08-20', '2026-09-04', 'CANCELADO', 3823.0, null, 'EXCEL 2026'),
  ('b26e3783-3512-5807-ad69-c6a2d856331b', '09-0193-08-2026', '2026-08-13', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 665.0, 0, 0.1, 67.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 605.6, null, 'EXCEL 2026'),
  ('e4fd9fe3-f422-53eb-b48d-0f3b55400639', '09-0194-08-2026', '2026-08-13', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1140.0, 0, 0.1, 135.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 1210.2, null, 'EXCEL 2026'),
  ('ca66cda1-e87c-5317-95b3-047990250b08', '09-0195-08-2026', '2026-08-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 570.0, 0, 0.1, 67.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 605.6, null, 'EXCEL 2026'),
  ('008607c8-b63b-5326-947e-39dd5a40cf78', '09-0196-08-2026', '2026-08-15', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1140.0, 0, 0.1, 135.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 1210.2, null, 'EXCEL 2026'),
  ('59e117d6-13dd-5706-a5c8-b1e4cd4a029e', '09-0197-08-2026', '2026-08-15', '86cc280f-6895-5548-948c-f2ba9255f47f', 'BARRANCA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MOVIMIENTO DE PLANCHAS', 600.0, 0, 0.1, 78.0, 'CANCELADO', null, null, 'F001-1911', '2026-08-15', '2026-08-18', 'CANCELADO', 826.0, null, 'EXCEL 2026'),
  ('afbc3918-d270-5af0-b947-41da73bbd2c6', '09-0198-08-2026', '2026-08-18', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 570.0, 0, 0.1, 78.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 706.7, null, 'EXCEL 2026'),
  ('c2fd491d-e7ce-521a-8d99-ebd65fa10657', '09-0199-08-2026', '2026-08-18', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'AGRICOLA INTERANDINA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION PARA REPARACIÓN - SEMANA 32', 1971.0, 0, 0.1, 233.0, 'CANCELADO', '0001/0046759', null, 'F001-1926', '2026-09-07', '2026-09-21', 'CANCELADO', 2040.85, null, 'EXCEL 2026'),
  ('4b6eb087-6712-5ccd-9a0a-cb96c1def7c0', '09-0200-08-2026', '2026-08-18', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'AGRICOLA INTERANDINA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION PARA DRENAJES - SEMANA 33', 3006.0, 0, 0.1, 355.0, 'CANCELADO', '0001/0015751', null, 'F001-1927', '2026-09-07', '2026-09-21', 'CANCELADO', 3151.21, null, 'EXCEL 2026'),
  ('5cbde08b-01e8-5939-8287-ea028632d551', '09-0201-08-2026', '2026-08-18', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ENVIADO', 'PEN', 'TARIFA COMERCIAL CAMIÓN GRÚA', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('ba30e41c-bf49-544e-8ac2-baa68e8d6369', '09-0202-08-2026', '2026-08-18', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ENVIADO', 'PEN', 'TARIFA COMERCIAL RETROEXCAVADORA', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('52f2ff7d-3a15-5241-bc38-ee0b4416f9b3', '09-0203-08-2026', '2026-08-19', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1140.0, 0, 0.1, 135.0, 'CANCELADO', '4000036018', '1000033759', 'F001-1919', '2026-08-27', '2026-09-11', 'CANCELADO', 1210.2, null, 'EXCEL 2026'),
  ('2e4feddc-8a7a-5ffd-b412-8b094a11fe74', '09-0204-08-2026', '2026-08-19', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - LIMPIEZA Y AMPLIACIÓN DE POZAS', 4320.0, 0, 0.1, 510.0, 'CANCELADO', '4000036017', '1000033702', 'F001-1922', '2026-08-31', '2026-09-18', 'CANCELADO', 4587.6, null, 'EXCEL 2026'),
  ('3da27b46-5c5c-54be-977f-7f9a8e13dfda', '09-0205-08-2026', '2026-08-19', '7b6c76a3-8733-548a-a4ee-858dbbcab6cd', 'VENADO MUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'OTRO', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. ALQUILER DE MAQUINARIA', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('9b0022e0-2a96-534f-be67-dda205ffc705', '09-0206-02-2026', '2026-08-19', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - MOVIMIENTO DE PLANCHAS', 600.0, 0, 0, 0, null, '0027-26', null, 'F001-1918', '2026-08-25', '2026-08-25', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('5c76151b-75f6-5350-8edc-e560a6764d6b', '09-0207-08-2026', '2026-08-21', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 760.0, 0, 0.1, 90.0, 'CANCELADO', '4000037061', '1000034955', 'F001-1931', null, '2026-09-25', 'CANCELADO', 806.8, null, 'EXCEL 2026'),
  ('4896ed82-2994-5e9d-a312-f1c661c63ecc', '09-0208-08-2026', '2026-08-21', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1330.0, 0, 0.1, 157.0, 'CANCELADO', '4000037061', '1000034955', 'F001-1931', '2026-09-11', '2026-09-25', 'CANCELADO', 1412.4, null, 'EXCEL 2026'),
  ('8c79cac7-4cc5-5f95-bea0-1e94605e87c8', '09-0209-08-2026', '2026-08-25', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'AGRICOLA INTERANDINA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA #02 - EXCAVACION PARA DRENAJES - SEMANA 34', 3375.0, 0, 0.1, 398.0, 'CANCELADO', '0001/0015795', null, 'F001-1928', '2026-09-08', '2026-09-21', 'CANCELADO', 3543.63, null, 'EXCEL 2026'),
  ('59be268d-e97d-54bc-9343-8a1cd1101f15', '09-0210-08-2026', '2026-08-25', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA 03 - EXCAVACIÓN DE POZAS', 4320.0, 0, 0.1, 510.0, 'CANCELADO', '4000037232', '1000034981', 'F001-1930', '2026-09-10', '2026-09-25', 'CANCELADO', 4587.6, null, 'EXCEL 2026'),
  ('982b4d97-adce-531c-90d1-3562fb96401a', '09-0211-08-2026', '2026-08-25', 'f69dec83-3b89-5f05-973f-593ec0862fd7', 'CHANCAY', 'MARÍA ORDOÑEZ', 'RECOMENDACIÓN', 'ANDAMIOS', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQUILER DE ANDAMIO NORMADO 3 CUERPOS + BARANDA', 5400.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('6eb2120f-5ffd-5aee-802c-559c40c684e5', '09-0212-08-2026', '2026-08-25', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 760.0, 0, 0.1, 90.0, 'CANCELADO', '4000037061', '1000034955', 'F001-1931', '2026-09-11', '2026-09-25', 'CANCELADO', 806.8, null, 'EXCEL 2026'),
  ('0bb8e62b-917a-53c1-aad6-3d2bd082dcca', '09-0213-08-2026', '2026-08-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 950.0, 0, 0.1, 112.0, 'CANCELADO', '4000037061', '1000034955', 'F001-1931', '2026-09-11', '2026-09-25', 'CANCELADO', 1009.0, null, 'EXCEL 2026'),
  ('7b438503-b689-5578-beb6-7dbcaf6aa3a7', '09-0214-08-2026', '2026-08-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 760.0, 0, 0.1, 90.0, 'CANCELADO', '4000037061', '1000034955', 'F001-1931', '2026-09-11', '2026-09-25', 'CANCELADO', 806.9, null, 'EXCEL 2026'),
  ('04202aca-84b3-5e77-8632-6b54c5141752', '09-0215-08-2026', '2026-08-27', 'd6877aa6-ce2a-5fdb-ab05-8a6b9fe10ded', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQ. DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS', 130.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('cb8ef1e4-8f6d-5ab9-8d8c-389e58f4d502', '09-0216-08-2026', '2026-08-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1045.0, 0, 0.1, 123.0, 'CANCELADO', '4000037061', '1000034955', 'F001-1931', '2026-09-11', '2026-09-25', 'CANCELADO', 1110.1, null, 'EXCEL 2026'),
  ('7ec34464-8bb3-511e-8cbb-fd61e1686939', '09-0217-08-2026', '2026-08-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTIERRO DE ARÁNDANOS', 700.0, 0, 0.1, 83.0, 'CANCELADO', '4000036246', null, 'F001-1921', '2026-08-28', '2026-09-11', 'CANCELADO', 743.0, null, 'EXCEL 2026'),
  ('95dd8f2d-e2a3-5e84-9d3e-f9ec694d2f67', '09-0218-08-2026', '2026-08-31', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - REMOLQUE DE PODADORA', 1000.0, 0, 0.1, 118.0, 'CANCELADO', '4000036764', '1000034320', 'F001-1924', '2026-09-04', '2026-09-18', 'CANCELADO', 1062.0, null, 'EXCEL 2026'),
  ('326c813d-2cf3-5748-8b45-3871e894188d', '09-0219-09-2026', '2026-09-01', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 760.0, 0, 0.1, 0, null, '4000038592', '1000038403', 'F001-1951', '2026-10-13', '2026-10-30', 'CANCELADO', 807.8, null, 'EXCEL 2026'),
  ('c1f5d2c2-2b9b-59ec-bd21-12a45e7b826c', '09-0220-09-2026', '2026-09-01', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 950.0, 0, 0, 0, null, '4000038592', '1000038403', 'F001-1951', '2026-10-13', '2026-10-27', 'CANCELADO', 1009.0, null, 'EXCEL 2026'),
  ('64d35ba5-a80f-5d73-a371-09c7b29eaf34', '09-0221-09-2026', '2026-09-01', '5e18003c-c7dd-5a26-87be-b9b356e6f6fc', 'HUACHO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA CON CANASTILLA - COLOCACIÓN DE LETREROS', 2250.0, 0, 0, 0, null, '400000022197', null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('c7ea3ac2-82d2-5abf-aecc-139b50850ad0', '09-0222-09-2026', '2026-09-02', 'bf8cc556-3df2-584d-a7bf-f75b8c41b914', 'SUPE', 'MARÍA ORDOÑEZ', null, 'ANDAMIOS', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE ANDAMION NORMADO ( 02 CUERPOS)', 680.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('4f3b35c5-1904-5559-988c-f99c8e98cc20', '09-0223-09-2026', '2026-09-03', '5e18003c-c7dd-5a26-87be-b9b356e6f6fc', 'HUACHO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA CON CANASTILLA - COLOCACIÓN DE LETREROS', 1440.0, 0, 0.1, 170.0, 'CANCELADO', '40000022197', '40000028483', 'F001-1933', '2026-09-19', '2026-10-19', 'CANCELADO', 1529.2, null, 'EXCEL 2026'),
  ('6f7daf0c-793e-5f08-bd3e-317c8bd7c0d8', '09-0224-09-2026', '2026-09-04', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'MAQUINARIA PESADA', 'FACTURADO', 'ACEPTADO', 'USD', 'SUMINISTRO DE 02 LASTRES DE CONCRETO DE 18"', 420.0, 0, 0, 0, null, null, null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('660eea8a-50b2-5c86-b735-286118573a40', '09-0225-09-2026', '2026-09-04', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 1520.0, 0, 0, 0, null, '4000038592', '1000038403', 'F001-1951', '2026-10-13', '2026-10-27', 'CANCELADO', 1614.0, null, 'EXCEL 2026'),
  ('43f17478-893c-552c-b951-2a19e35d93c2', 'SN-SETIEMBRE-277 (2026)', '2026-09-05', 'f8620314-43b4-5b46-91db-484be70e87eb', 'SUPE', 'ANGIE ZELAYA', 'CONFIANZA', 'TERMOFUSION', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA DE TERMOFUSION DE 160MM (6") SIN OPERADOR', 0, 100.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-09-05', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('911c1002-98f3-5f66-9282-9e0f0cec9f79', 'NRO DE PARTE 0919 (2026)', '2026-09-05', '913aeefe-c619-5be4-9d83-bc1e2cb1883b', 'SANTO DOMINGO', 'ANGIE ZELAYA', 'RECOMENDACIÓN', 'OTRO', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. DESCARGA DE CONTENEDORES', 0, 1000.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-09-05', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('04b29b2b-1de0-5d5b-9f40-1f39c23e0c8b', 'SN-SETIEMBRE-279 (2026)', '2026-09-07', 'f8620314-43b4-5b46-91db-484be70e87eb', 'SUPE', 'ANGIE ZELAYA', 'CONFIANZA', 'TERMOFUSION', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE MAQUINA DE TERMOFUSION DE 160MM (6") SIN OPERADOR', 0, 100.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-09-07', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('de41a75e-43e8-5a99-8fbc-1c331fd9cd2d', '09-0226-09-2026', '2026-09-07', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'CARAL', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA SEMANA 34 - II', 513.0, 0, 0, 0, 'NO APLICA', '0001/0046696', null, 'F001-1929', '2026-09-08', '2026-09-21', 'CANCELADO', 590.32, null, 'EXCEL 2026'),
  ('1d9c6027-a2b8-54dc-bb83-b1d72e63b48a', '09-0227-09-2026', '2026-09-08', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 1330.0, 0, 0, 0, null, '4000038592', '1000038403', 'F001-1951', '2026-10-13', '2026-10-27', 'CANCELADO', 1412.4, null, 'EXCEL 2026'),
  ('d35a57f0-7f9e-5b44-8b39-fa9e1d7d0633', 'NRO DE PARTE 0920 (2026)', '2026-09-09', '302f007e-757f-55fd-9e25-a5355c8020bf', 'BARRANCA', 'MARÍA ORDOÑEZ', 'CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA, CARGA Y DESCARGA DE LAVADORA', 0, 0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 300.0, null, 'EXCEL 2026'),
  ('a287f84a-59a7-5398-bf04-010955712ef4', 'NRO DE PARTE 0916 (2026)', '2026-09-09', '616fbddd-bb2c-5c53-8d81-24dcc6edba58', 'HUACHO', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 0, 1800.0, 0, 0, 'NO APLICA', null, null, null, null, null, 'CANCELADO', 1800.0, null, 'EXCEL 2026'),
  ('be1aa39f-8192-5644-a0a4-10b48d02df05', 'NRO DE PARTE 0918 (2026)', '2026-09-10', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'TIROLER', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE TRANSFORMADORES', 0, 700.0, 0, 0, 'NO APLICA', null, null, null, null, '2026-09-10', 'CANCELADO', 700.0, null, 'EXCEL 2026'),
  ('6594906b-f18f-50d4-9f84-dc04340710c8', '09-0228-09-2026', '2026-09-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 950.0, 0, 0, 0, null, '4000038592', '1000038403', 'F001-1951', '2026-10-13', '2026-10-27', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('08d33ce8-2054-598b-b473-9af1b82b87af', '09-0229-09-2026', '2026-09-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - ENTERRADO DE MACETAS SEM. 35', 2155.5, 0, 0.1, 254.0, 'CANCELADO', '4000037281', null, 'F001-1939', '2026-09-25', '2026-10-09', 'CANCELADO', 2289.49, null, 'EXCEL 2026'),
  ('640a329f-4c93-535a-a669-ca946a0bd7f4', '09-0230-09-2026', '2026-09-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - ENTERRADO DE MACETAS SEM. 36', 5467.5, 0, 0.1, 645.0, 'CANCELADO', '4000037722', null, 'F001-1940', '2026-09-25', '2026-10-09', 'CANCELADO', 5806.65, null, 'EXCEL 2026'),
  ('698b7b61-bbc8-57b4-b704-e5bd7ccf391c', '09-0231-09-2026', '2026-09-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. DE ALQUILER DE RETROEXCAVADORA 03 (LIMPIEZA DE POZAS DEL 21/08 AL 29/08)', 4320.0, 0, 0, 510.0, 'CANCELADO', '4000038144', '1000036947', 'F001-1943', '2026-09-29', '2026-10-13', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('8b3ff927-5c21-57a4-bd29-c86a285882e3', '09-0232-09-2026', '2026-09-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. DE ALQUILER DE RETROEXCAVADORA 03 (LIMPIEZA DE POZAS DEL 29/08 AL 07/09)', 4320.0, 0, 0.1, 510.0, 'PENDIENTE', '4000038582', '100037770', 'F001-1945', '2026-10-05', '2026-10-20', 'CANCELADO', 4587.6, null, 'EXCEL 2026'),
  ('1778d799-e0da-59cb-bd69-5efd8679227d', '09-0233-09-2026', '2026-09-12', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1330.0, 0, 0, 0, null, '4000038592', '1000038403', 'F001-1951', '2026-10-13', '2026-10-27', 'CANCELADO', 1412.1, null, 'EXCEL 2026'),
  ('dd061bca-a048-5f2a-a4b4-47d8dfa5c73c', '09-0234-09-2026', '2026-09-14', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 950.0, 0, 0.1, 157.0, 'PENDIENTE', '4000038592', '1000038403', 'F001-1956', '2026-10-15', '2026-10-30', 'CANCELADO', 1569.1, null, 'EXCEL 2026'),
  ('a38dbdba-55b6-5db0-b857-c67d6ffb8c2a', '09-0235-09-2026', '2026-09-15', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - MOVIMIENTO DE PLANCHAS', 300.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1934', '2026-09-19', '2026-09-19', 'CANCELADO', 1412.1, null, 'EXCEL 2026'),
  ('22d9256f-e292-5a9e-a719-d109a7220c7d', '09-0236-09-2026', '2026-09-16', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'SANTA AZUL', 'FATIMA FONSECA', 'CONFIANZA', 'TRASLADO', 'FACTURADO', 'RECHAZADO', 'PEN', 'TRASLADO DE CAMIONETA DE AGRICOLA SANTA AZUL A AUTONORT', 1000.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('cd788b45-dfbf-5a49-a30f-251a3cc61925', '09-0237-09-2026', '2026-09-16', '93b4846f-c6e4-5516-96b0-a7b6596c00c4', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - DESCARGA DE MATERIALES', 600.0, 0, 0.1, 130.0, 'CANCELADO', null, null, 'F001-1935', '2026-09-23', '2026-09-23', 'CANCELADO', 1168.0, null, 'EXCEL 2026'),
  ('b1f893cd-79cb-5773-8b6f-749a6a71f207', '09-0238-09-2026', '2026-09-17', '5099519a-d50d-54ee-9724-73e0ef729590', 'PARAMONGA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE, TRASLADO Y DESCARGA DE MATERIALES Y EQUIPOS', 1000.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('36866375-ce10-5037-9b32-5c19f5091ee3', '09-0239-09-2026', '2026-09-19', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PUERTO SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERVICIO DE IZAJE DE MATERIALES DIA 17/09', 550.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1932', '2026-09-19', '2026-09-22', 'CANCELADO', 649.0, null, 'EXCEL 2026'),
  ('12130397-9fa6-5249-94da-c1c63e7677bd', '09-0240-09-2026', '2026-09-22', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1425.0, 0, 0.1, 168.0, 'PENDIENTE', '4000038592', '1000038403', 'F001-1956', '2026-10-15', '2026-10-29', 'CANCELADO', 1513.5, null, 'EXCEL 2026'),
  ('a9544706-193a-563a-9831-f001a468c5ab', '09-0241-09-2026', '2026-09-22', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 1045.0, 0, 0.1, 123.0, 'PENDIENTE', '4000038592', '1000038403', 'F001-1956', '2026-10-15', '2026-10-29', 'CANCELADO', 1110.1, null, 'EXCEL 2026'),
  ('2422164b-da4d-567b-b47f-a885e17e37c1', '09-0242-09-2026', '2026-09-22', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - MOVIMIENTO DE TUBERÍA', 600.0, 0, 0.1, 71.0, 'CANCELADO', null, null, 'F001-1937', '2026-09-25', '2026-09-23', 'CANCELADO', 708.0, null, 'EXCEL 2026'),
  ('7d01f582-0925-5e0a-a179-75bd6bc726e8', '09-0243-09-2026', '2026-09-23', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'CARAL', 'FATIMA FONSECA', 'CONFIANZA', 'ELECTROFUSION', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. DE ELECTROFUSIÓN', 7600.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('ce45932c-ec79-580d-ac3e-0ce5cc4a920d', '09-0244-09-2026', '2026-09-23', '93b4846f-c6e4-5516-96b0-a7b6596c00c4', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - DESCARGA DE MATERIALES', 500.0, 0, 0.1, 130.0, 'CANCELADO', null, null, 'F001-1935', '2026-09-23', '2026-09-23', 'CANCELADO', 1168.0, null, 'EXCEL 2026'),
  ('1fe92d8e-5b72-5056-ad5f-1423aca0c700', '09-0245-09-2026', '2026-09-23', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', 'FUNDO ALTO - SUPE', 'MARÍA ORDOÑEZ', 'RECOMENDACIÓN', 'TERMOFUSION', 'FACTURADO', 'ENVIADO', 'PEN', 'SERVICIO DE TERMOFUSION DE TUBERIA 110MM SDR11 ( 2 PEGAS)', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('aa804d40-52ae-5b12-9139-8240c0ee67ed', '09-0246-09-2026', '2026-09-23', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRALADO DE TOTEMS', 1140.0, 0, 0.1, 135.0, 'PENDIENTE', '4000039239', '4000039239', 'F001-1959', '2026-10-19', '2026-11-02', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('ca025109-dedf-5a19-8813-bc2782453e23', '09-0247-09-2026', '2026-09-24', '6397e53d-b3cd-56ad-87ac-35ed74014728', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'ANDAMIOS', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQUILER DE ANDAMIO NORMADO 3 CUERPOS + BARANDA', 4500.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('adac3ab7-3089-5192-9d60-005d6e6bae89', '09-0248-09-2026', '2026-09-24', '5eabf785-0989-5fe8-ad26-840b54b78e1d', 'VEGUETA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'OTRO', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. DE CAMBIO DE TUB. DE FE A TUB. DE HDPE TK DE PETROLEO', 7380.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('380c3198-4fa9-5320-907c-558615c9e9c3', '09-0249-09-2026', '2026-09-25', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - IZAJE DE MATERIALES', 600.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('ccbeb3ba-70d5-5b37-a680-f48e3161c265', '09-0250-09-2026', '2026-09-25', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - EXCAVACACIÓN DE ZANJAS', 6240.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('c51ced73-fb06-5f77-9938-030f885fa26c', '09-0251-09-2026', '2026-09-25', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 1425.0, 0, 0.1, 168.0, 'PENDIENTE', '4000038592', '1000038403', 'F001-1956', '2026-10-15', '2026-10-29', 'CANCELADO', 1513.5, null, 'EXCEL 2026'),
  ('a0f62bf0-f6b9-523a-b946-14ccc6aa95b3', '09-0252-09-2026', '2026-09-26', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 36/37', 4244.4, 0, 0.1, 501.0, 'CANCELADO', null, null, 'F001-1941', '2026-09-26', '2026-10-12', 'CANCELADO', 4507.39, null, 'EXCEL 2026'),
  ('0265c0e7-f3ca-52cf-a544-66abb5534baa', '09-0253-09-2026', '2026-09-26', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'ALQUILER DE CAMIÓN GRUA - MOVIMIENTO DE TUBERÍA', 900.0, 0, 0.1, 106.0, 'CANCELADO', null, null, 'F001-1942', '2026-09-25', '2026-09-30', 'CANCELADO', 1062.0, null, 'EXCEL 2026'),
  ('32d79cc7-7695-5a7e-851b-3818b8f0de14', '09-0254-09-2026', '2026-09-28', 'ae8ff2f9-bb68-5047-924f-e950d7161796', 'SUPE PUERTO', 'FATIMA FONSECA', 'CONFIANZA', 'MAQUINARIA PESADA', 'FACTURADO', 'ENVIADO', 'USD', 'SUMINISTRO DE 12 LASTRES DE CONCRETO DE 24"', 5400.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('0cb47bd7-6826-543f-be07-82a914e3b049', '09-0255-09-2026', '2026-09-28', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE Y DESMONTAJE DE MOTOR Y BOMBA', 1330.0, 0, 0.1, 157.0, 'PENDIENTE', '4000038592', '1000038403', 'F001-1956', '2026-10-15', '2026-10-29', 'CANCELADO', 1412.4, null, 'EXCEL 2026'),
  ('fa9a164a-a872-5e5e-af78-f589eb58739a', '09-0256-09-2026', '2026-09-29', 'f202991e-35e1-5f72-8a51-521d6d52e6ce', 'SAYAN', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS', 130.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('c4bd4baf-9d4f-5b7c-a023-5ae7e4c70227', '09-0257-09-2026', '2026-09-29', 'f202991e-35e1-5f72-8a51-521d6d52e6ce', 'CARAL', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA CON MARTILLO - EXCAVACIÓN DE ZANJAS', 200.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('7d1b4c86-4d1a-50af-9367-359e366999d8', '09-0258-09-2026', '2026-09-29', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS', 2160.0, 0, 0.1, 255.0, 'PENDIENTE', '4000038205', '1000037767', 'F001-1946', '2026-10-05', '2026-10-20', 'CANCELADO', 2293.8, null, 'EXCEL 2026'),
  ('d96f0bd5-e8e2-5436-81bd-9567dbf1b52a', '09-0259-09-2026', '2026-09-29', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE POZAS', 3600.0, 0, 0.1, 425.0, 'PENDIENTE', '4000038575', '1000038402', 'F001-1950', '2026-10-13', '2026-10-27', 'CANCELADO', 3823.0, null, 'EXCEL 2026'),
  ('cdbea9dd-a01f-5932-9121-858471664244', '09-0260-09-2026', '2026-09-29', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 38', 1575.0, 0, 0.1, 186.0, 'PENDIENTE', '4000039077', '1000038977', 'F001-1958', '2026-10-17', '2026-10-31', 'CANCELADO', 1672.5, null, 'EXCEL 2026'),
  ('46a65a8a-21cd-5112-862f-f6d1d6b20092', '09-0261-09-2026', '2026-09-29', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 38', 4600.8, 0, 0.1, 1101.0, 'PENDIENTE', '4000040260', '4000040260', 'F001-1966', '2026-10-27', '2026-11-10', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('85e36621-76ea-5600-b139-148ad9630ed8', '09-0262-09-2026', '2026-09-29', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 39', 5513.4, 0, 0, 0, 'PENDIENTE', '4000040260', '4000040260', 'F001-1966', '2026-10-27', '2026-11-10', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('223629af-2a22-5a31-b8f3-c71e991fb1db', '09-0263-10-2026', '2026-10-01', '8d69619b-9bc8-5cc9-b6e5-2401dfbe7273', null, null, null, 'TERMOFUSION', 'FACTURADO', 'RECHAZADO', 'PEN', 'IMPERMEABILIZACION DE RESERVORIOS / TERMOFUSION', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('1a372846-ef61-5610-87cc-c19990590c0d', '09-0264-10-2026', '2026-10-01', '4c2a0995-4f46-566a-8b63-e28ecd9465d8', 'BARRANCA', 'ANGIE ZELAYA', 'CONFIANZA', 'TRASLADO', 'FACTURADO', 'ACEPTADO', 'PEN', 'TRASLADO DE SILO DE ALIMENTO DE HUARMEY (CRUZ DE AREVALO) A CAÑETE', 1800.0, 1600.0, 0.04, 85.0, 'CANCELADO', null, null, 'F001-1944', '2026-10-02', '2026-10-02', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('e2e34284-c809-5785-8347-c6cf59eaeffa', '09-0265-10-2026', '2026-10-02', '48f69284-dbf2-5a97-9fee-991e628b4c94', 'PUERTO SUPE', 'FATIMA FONSECA', 'CONFIANZA', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQ. DE RETROEXCAVADORA - NIVELACIÓN DE TERRENO', 5450.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('1ba96d47-9ccb-5015-ba6b-dfa93ca12412', '09-0266-10-2026', '2026-10-05', 'be3ab2f4-8bf0-5b25-a684-764d7f127f01', 'SUPE', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'ALQ. DE CAMION GRUA - IZAJE DE GENERADOR', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('4b261a69-f704-5c79-a5c0-3ac1957e87fe', '09-0267-10-2026', '2026-10-06', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE MATERIALES', 950.0, 0, 0.1, 112.0, 'PENDIENTE', '4000038592', '1000038403', 'F001-1956', '2026-10-15', '2026-10-29', 'CANCELADO', 1009.0, null, 'EXCEL 2026'),
  ('784bacf0-0475-599a-9da4-e3e17450dd54', '09-0268-10-2026', '2026-10-07', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE CARRETAS HADRAULICAS', 1330.0, 0, 0.1, 157.0, 'PENDIENTE', '4000040177', '1000040723', 'F001-1969', '2026-11-05', '2026-11-20', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('2fc03113-0357-5884-a239-2799cc73dc79', '09-0269-10-2026', '2026-10-07', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 39', 4140.0, 0, 0.1, 489.0, 'PENDIENTE', '40000039081', '1000038978', 'F001-1957', '2026-10-17', '2026-10-31', 'CANCELADO', 4396.2, null, 'EXCEL 2026'),
  ('53ed8615-c099-54e5-a9f4-a0d785ac086b', '09-0270-10-2026', '2026-10-09', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 40', 6322.5, 0, 0, 0, null, null, null, null, null, null, 'CANCELADO', 6714.5, null, 'EXCEL 2026'),
  ('64e566f5-2f88-5b97-835a-25adfb63b3fe', '09-0271-10-2026', '2026-10-09', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 40', 4005.0, 0, 0.1, 435.5, 'PENDIENTE', null, null, 'F001-1967', '2026-10-28', '2026-11-11', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('fac6516b-f4cf-5ba7-9b0f-57d68ed570dc', '09-0272-10-2026', '2026-10-10', 'e1b2d1e2-1ec4-552c-aa35-8d719a0ca65a', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - MOVIMIENTO DE BLOQUETAS', 800.0, 0, 0.1, 94.0, 'CANCELADO', null, null, 'F001-1947', '2026-10-10', '2026-10-10', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('e752cc4e-06e5-5132-a2ad-682e73c0ad96', '09-0273-10-2026', '2026-10-12', 'e1b2d1e2-1ec4-552c-aa35-8d719a0ca65a', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - MOVIMIENTO DE BLOQUETAS', 2500.0, 0, 0.1, 295.0, 'PENDIENTE', null, null, 'F001-1948', '2026-10-12', '2026-10-12', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('be65092a-1a60-5e81-b033-0edd2f7aeaa6', '09-0274-10-2026', '2026-10-13', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 41', 3375.0, 0, 0.1, 435.5, 'PENDIENTE', null, null, 'F001-1967', '2026-10-28', '2026-11-11', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('5de7d9db-1334-5173-8f7a-1720ff84e0ee', '09-0275-10-2026', '2026-10-13', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 41', 3690.9, 0, 0.1, 436.0, 'PENDIENTE', null, null, 'F001-1964', '2026-10-27', '2026-11-10', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('0edef2c5-1ae5-5583-8429-9b02d0ccef1c', '09-0276-10-2026', '2026-10-13', 'e1b2d1e2-1ec4-552c-aa35-8d719a0ca65a', null, null, null, 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - MOVIMIENTO DE BLOQUETAS', 1200.0, 0, 0.1, 142.0, 'PENDIENTE', null, null, 'F001-1953', '2026-10-13', '2026-10-13', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('82aa0750-c69e-5287-9152-a02f796addc1', '09-0277-10-2026', '2026-10-13', '092fd340-0ae7-53aa-bb3b-c3184f4f54b2', null, null, null, 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - MOVIMIENTO DE BLOQUETAS', 1100.0, 0, 0.1, 134.0, 'CANCELADO', null, null, 'F001-1954', '2026-10-14', '2026-10-14', 'CANCELADO', 1298.0, null, 'EXCEL 2026'),
  ('8cb78570-8c0b-5f7a-8a79-c527f4019894', '09-0277-10-2026 (2)', '2026-10-15', '854e6948-343b-56a7-a0c9-41e74e6a4a13', null, null, null, 'CAMION GRUA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y MOVIMIENTO DE TUBERIAS', 600.0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('96407b33-44f7-5402-88e1-4a8c82f0bc4e', '09-0278-10-2026', '2026-10-16', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PUERTO SUPE', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE, CARGA Y DESCARGA DE MANGAS', 800.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('168ab82c-a656-53cf-a083-cc4027b6ade3', '09-0279-10-2026', '2026-10-19', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE MOTOR Y BOMBA', 1520.0, 0, 0, 0, null, '4000040669', null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('8076d26c-9f83-5021-b05f-1c2c7ef178a0', '09-0280-10-2026', '2026-10-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 42', 4275.0, 0, 0, 0, null, '4000041163', null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('9ce13b45-b316-5e8d-87b5-21abc5f6f312', '09-0281-10-2026', '2026-10-20', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 42', 4245.3, 0, 0.1, 501.0, 'PENDIENTE', '4000040193', '4000040193', 'F001-1961', '2026-10-27', '2026-11-10', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('83b06206-6ecc-5936-91ee-4d4e8be12345', '09-0282-10-2026', '2026-10-21', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PARAMONGA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'TRASLADO', 'FACTURADO', 'ACEPTADO', 'PEN', 'TRASLADO DE MATERIALES', 550.0, 0, 0, 0, 'NO APLICA', null, null, 'F001-1960', '2026-10-21', '2026-10-21', 'CANCELADO', 649.0, null, 'EXCEL 2026'),
  ('a569c027-d376-500e-a48f-96171ea64c4a', '09-0283-10-2026', '2026-10-22', '36ffb193-565b-5563-9e7f-768b0428236c', 'VIRGEN DEL ROSARIO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'RECHAZADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN Y NIVELACIÓN', 0, 0, 0, 0, null, null, null, null, null, null, 'RECHAZADO', null, null, 'EXCEL 2026'),
  ('f1903da1-13b5-5733-923a-b7e92f7c6441', '09-0284-10-2026', '2026-10-23', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE MOTOR Y BOMBA', 1235.0, 0, 0, 0, null, '4000040669', null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('c925a382-bc63-5d07-a71a-91e74d2bdab2', '09-0285-10-2026', '2026-10-24', '5b4ad009-c5b8-5fe2-97f4-9db420572b42', 'HUARMEY', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE DE TORNILLO TAMIZ', 1100.0, 0, 0.1, 130.0, 'PENDIENTE', '0000202600177', null, 'F001-1968', '2026-10-28', '2026-10-28', 'CANCELADO', 1168.0, null, 'EXCEL 2026'),
  ('cb3c273f-4919-53e5-86e3-5f53b38fed95', '09-0286-10-2026', '2026-10-24', '06c7e010-0ddb-5767-83c7-3749b7b74826', 'BARRANCA', 'FATIMA FONSECA', 'CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE ANTENA', 760.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('b88ab426-0df8-5285-99d8-5571e71e2faa', '09-0287-10-2026', '2026-10-24', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR', 1140.0, 0, 0, 0, null, '4000040669', null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('ac327d63-c7b7-5759-bedd-fed2f36dbc04', '09-0288-10-2026', '2026-10-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 43', 4275.0, 0, 0, 0, null, '4000041163', null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('96351079-811a-56be-86c5-6366ba65e308', '09-0289-10-2026', '2026-10-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 43', 2296.15, 0, 0.1, 183.0, 'PENDIENTE', '4000040792', null, 'F001-1970', '2026-11-05', '2026-11-20', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('65151137-b3e8-5232-9f9e-b19eb5a1a69c', '09-0290-10-2026', '2026-10-27', 'b4908510-2e97-57b3-a5e2-44fc96b485c7', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE DE MANGUERON', 800.0, 0, 0.1, 94.0, 'CANCELADO', null, null, 'F001-1962', '2026-10-27', '2026-10-27', 'CANCELADO', 944.0, null, 'EXCEL 2026'),
  ('07632b8c-d7e5-5879-b560-c7d95cda72ba', '09-0291-10-2026', '2026-10-27', 'b4908510-2e97-57b3-a5e2-44fc96b485c7', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - EMBARQUE DE MANGA', 800.0, 0, 0.1, 94.0, 'CANCELADO', null, null, 'F001-1963', '2026-10-27', '2026-10-27', 'CANCELADO', 944.0, null, 'EXCEL 2026'),
  ('ac9787f3-19d4-5122-b2e5-dd90e8e0c359', '09-0292-10-2026', '2026-10-27', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN PARA POZAS DE DRENAJE', 760.0, 0, 0.1, 90.0, 'PENDIENTE', null, null, 'F001-1965', '2026-10-27', '2026-10-27', 'PENDIENTE DE PAGO', null, null, 'EXCEL 2026'),
  ('e5e6cc17-1041-5d10-8ea4-dee0a08a3a5d', '09-0293-10-2026', '2026-10-28', 'b4908510-2e97-57b3-a5e2-44fc96b485c7', 'SUPE PUERTO', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - IZAJE DE MANGA', 1000.0, 0, 0, 0, null, null, null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('a574b9a4-d0b2-503e-9781-ff63c9ac8f89', '09-0294-11-2026', '2026-11-02', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 44', 2042.5, 0, 0, 0, null, '4000041163', null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('0fd3c18b-8b98-5b6d-8360-9dd386c797a3', '09-0295-11-2026', '2026-11-02', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - POZAS PARA TUNELES SEM. 44', 7885.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('43827a76-7268-5692-8495-d6918679af51', '09-0296-11-2026', '2026-11-02', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - DESMONTAJE DE MOTOR Y BOMBA', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('5fdad526-6e18-5362-b575-3e31743de86e', '09-0297-11-2026', '2026-11-06', '68d6dde6-064d-562d-821a-11f96855e214', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'TERMOFUSION', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. ALQUILER DE MÁQUINA DE TERMOFUSIÓN CON OPERADOR', 1200.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('7773db80-9a8f-59d1-97f1-fda184b2e5c3', '09-0298-11-2026', '2026-11-06', '68d6dde6-064d-562d-821a-11f96855e214', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'TERMOFUSION', 'FACTURADO', 'ENVIADO', 'PEN', 'TRASLADO DE MÁQUINA DE TERMOFUSIÓN A HUARMEY', 700.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('2f9b1591-a912-5d21-ac22-829b6c157795', '09-0299-11-2026', '2026-11-06', 'cb72b53e-c58c-5200-ab9e-7e4a7bc035ec', 'PARAMONGA', 'FATIMA FONSECA', 'DOCUMENTACIÓN Y CONFIANZA', 'CAMION GRUA', 'FACTURADO', 'ENVIADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA', 800.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('f241d78a-a79e-5188-9a4b-c227307971ae', '09-0300-11-2026', '2026-11-07', '07a505c6-8328-579d-bc93-193021e23a90', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ENVIADO', 'PEN', 'TARIFARIO - ALQUILER DE CAMION GRUA', 800.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('7f88f344-d745-5d7a-8ac7-2aac8f87d28f', '09-0301-11-2026', '2026-11-09', 'c6d1db65-1716-5453-b7d7-12cf7d7eec6e', 'SUPE PUEBLO', 'FATIMA FONSECA', 'DOCUMENTACIÓN', 'TRASLADO', 'FACTURADO', 'ACEPTADO', 'PEN', 'TRASLADO DE COMPRESOR DE SUPE A AMBAR', 1500.0, 0, 0, 71.0, 'PENDIENTE', null, null, 'F001-1972', '2026-11-10', '2026-11-10', 'CANCELADO', null, null, 'EXCEL 2026'),
  ('6ee07472-d135-559e-8816-446129265611', '09-0302-11-2026', '2026-11-09', '8787b6b5-363b-55bc-9bff-4092294d4a11', 'OYON', 'ANGIE ZELAYA', 'CONFIANZA', 'TERMOFUSION', 'FACTURADO', 'ENVIADO', 'PEN', 'SERVICIO DE TERMOFUSION DE TUBERIA DE HDPE', 4182.0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('2f8a7744-d80b-532f-8ed5-06c840438dfa', '09-0303-11-2026', '2026-11-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE POZA PARA DRENAJE', 760.0, 0, 0, 0, null, '4000040255', '10000421', 'F001-1971', '2026-11-10', '2026-11-24', 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('c0a2e3ee-0925-5e9a-9183-5010dd4cc6dd', '09-0304-11-2026', '2026-11-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - LIMPIEZA DE CANAL', 570.0, 0, 0, 0, null, '4000041072', null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('9c278edc-d24a-5006-b4bc-2f2ee7951d54', 'NRO DE PARTE 955 (2026)', '2026-11-10', '4b05993f-f9e4-5f2c-b800-ff5e8552fe9c', 'HUAURA', 'ANGIE ZELAYA', 'CONFIANZA', 'CAMION GRUA', 'LIBRE', 'ACEPTADO', 'PEN', 'SERVICIO DE ALQUILER DE CAMION GRUA - TRASLADO DE PRENSA', 0, 600.0, 0, 0, null, null, null, null, null, null, 'CANCELADO', 600.0, null, 'EXCEL 2026'),
  ('56b7d386-b9b3-5e6c-889e-fba7ff50436a', '09-0305-11-2026', '2026-11-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - MONTAJE DE MOTOR Y BOMBA', 950.0, 0, 0, 0, null, null, null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('3f88e2de-1f0a-5039-9c3e-ef9763a8895b', '09-0306-11-2026', '2026-11-10', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'CAMION GRUA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE CAMION GRUA - IZAJE Y TRASLADO DE TOTTEMS', 950.0, 0, 0, 0, null, null, null, null, null, null, 'PENDIENTE DE FACTURACIÓN', null, null, 'EXCEL 2026'),
  ('223cb400-2f1f-5048-a475-dbd586d9ec3a', '09-0307-11-2026', '2026-11-12', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - EXCAVACIÓN DE ZANJAS SEM. 45', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('de544fc5-0eb8-557d-8969-5086c638ab6f', '09-0308-11-2026', '2026-11-12', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - ENTERRADO DE MACETAS SEM. 45', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026'),
  ('91d1de44-6151-5462-8a11-35a2a6200036', '09-0309-11-2026', '2026-11-12', '6cf6d8be-e7d4-564f-9a0a-3ec784da76ac', 'BARRANCA', 'FATIMA FONSECA', 'RECOMENDACIÓN', 'RETROEXCAVADORA', 'FACTURADO', 'ACEPTADO', 'PEN', 'SERV. ALQUILER DE RETROEXCAVADORA - POZAS PARA TUNELES SEM. 45', 0, 0, 0, 0, null, null, null, null, null, null, null, null, null, 'EXCEL 2026')
on conflict do nothing;

commit;

-- Verificación rápida (debe mostrar 2026 con 368 cotizaciones)
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

select * from public.v_anios;
