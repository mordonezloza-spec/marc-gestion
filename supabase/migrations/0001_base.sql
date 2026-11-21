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
