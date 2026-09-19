create extension if not exists "pgcrypto";

create type public.app_role as enum ('administrador','oficina','planta','bodega','finca','chofer');
create type public.moneda as enum ('CRC','USD','EUR');

create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text not null,
  rol public.app_role not null default 'oficina',
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table public.proveedores (
  id uuid primary key default gen_random_uuid(), nombre text not null,
  telefono text, residencia text, zona text,
  tipo text check (tipo in ('Agricultor','Intermediario','Propio')),
  productos text[] default '{}', activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table public.clientes (
  id uuid primary key default gen_random_uuid(), nombre text not null,
  pais text, mercado text, contacto text, condiciones text,
  activo boolean not null default true, creado_en timestamptz not null default now()
);

create table public.ordenes_compra (
  id uuid primary key default gen_random_uuid(), codigo text unique not null,
  fecha date not null default current_date, proveedor_id uuid references public.proveedores(id),
  producto text not null, lugar text, tipo_compra text, moneda public.moneda default 'CRC',
  precio_europa numeric(14,2), precio_eeuu numeric(14,2), precio_rechazo numeric(14,2),
  estado text default 'Pendiente', observaciones text, creado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default now()
);

create table public.boletas_entrada (
  id uuid primary key default gen_random_uuid(), codigo text unique not null,
  fecha_hora timestamptz not null default now(), orden_compra_id uuid references public.ordenes_compra(id),
  proveedor_id uuid references public.proveedores(id), finca_lugar text, chofer text, placa text,
  condicion text check (condicion in ('Mojado','Seco')), producto text not null,
  cantidad_recipientes numeric(12,2), tipo_recipiente text, promedio_peso numeric(12,3),
  kg_estimados numeric(14,3), linea_proceso smallint check (linea_proceso in (1,2)),
  encargado text check (encargado in ('Andrés','Javier','Emilio')), observaciones text,
  creado_en timestamptz not null default now()
);

create table public.ordenes_venta (
  id uuid primary key default gen_random_uuid(), codigo text unique not null,
  fecha date not null default current_date, cliente_id uuid references public.clientes(id),
  mercado text, contenedor text, moneda public.moneda not null default 'USD',
  estado text default 'Borrador', observaciones text, creado_en timestamptz not null default now()
);

create table public.ordenes_venta_lineas (
  id uuid primary key default gen_random_uuid(), orden_venta_id uuid not null references public.ordenes_venta(id) on delete cascade,
  producto text not null, presentacion_kg numeric(8,2), paletas integer, cajas_por_paleta integer,
  cantidad_cajas integer not null, precio_caja numeric(12,2) not null,
  total numeric(14,2) generated always as (cantidad_cajas * precio_caja) stored
);

create table public.tipos_cambio (
  id uuid primary key default gen_random_uuid(), fecha date not null, moneda public.moneda not null,
  compra numeric(12,4), venta numeric(12,4), unique(fecha,moneda)
);

alter table public.perfiles enable row level security;
alter table public.proveedores enable row level security;
alter table public.clientes enable row level security;
alter table public.ordenes_compra enable row level security;
alter table public.boletas_entrada enable row level security;
alter table public.ordenes_venta enable row level security;
alter table public.ordenes_venta_lineas enable row level security;
alter table public.tipos_cambio enable row level security;

create policy "usuarios autenticados leen proveedores" on public.proveedores for select to authenticated using (true);
create policy "usuarios autenticados leen clientes" on public.clientes for select to authenticated using (true);
create policy "usuarios autenticados leen operaciones" on public.ordenes_compra for select to authenticated using (true);
create policy "usuarios autenticados leen boletas" on public.boletas_entrada for select to authenticated using (true);
create policy "usuarios autenticados leen ventas" on public.ordenes_venta for select to authenticated using (true);
create policy "usuarios autenticados leen lineas" on public.ordenes_venta_lineas for select to authenticated using (true);
create policy "usuarios autenticados leen tipos de cambio" on public.tipos_cambio for select to authenticated using (true);
