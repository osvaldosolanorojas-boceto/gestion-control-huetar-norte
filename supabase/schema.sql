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
  razon_social text, identificacion_fiscal text,
  pais text, ciudad text, mercado text, direccion text, puerto_llegada text,
  contacto text, contacto_cargo text, telefono text, whatsapp text,
  correo text, correo_facturacion text,
  moneda_habitual public.moneda not null default 'USD',
  condiciones text, condiciones_pago text, plazo_pago_dias integer check (plazo_pago_dias >= 0),
  incoterm text, direccion_facturacion text, direccion_entrega text,
  naviera text, logo_url text, observaciones text,
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


revoke all on public.perfiles from anon, authenticated;
grant select on public.perfiles to authenticated;
create policy perfil_propio on public.perfiles for select to authenticated using (id = (select auth.uid()));

revoke all on public.proveedores from anon, authenticated;
grant select, insert, update, delete on public.proveedores to authenticated;
create policy gestion_oficina on public.proveedores for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
revoke all on public.clientes from anon, authenticated;
grant select, insert, update, delete on public.clientes to authenticated;
create policy gestion_oficina on public.clientes for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
revoke all on public.ordenes_compra from anon, authenticated;
grant select, insert, update, delete on public.ordenes_compra to authenticated;
create policy gestion_oficina on public.ordenes_compra for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
revoke all on public.boletas_entrada from anon, authenticated;
grant select, insert, update, delete on public.boletas_entrada to authenticated;
create policy gestion_oficina on public.boletas_entrada for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
revoke all on public.ordenes_venta from anon, authenticated;
grant select, insert, update, delete on public.ordenes_venta to authenticated;
create policy gestion_oficina on public.ordenes_venta for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
revoke all on public.ordenes_venta_lineas from anon, authenticated;
grant select, insert, update, delete on public.ordenes_venta_lineas to authenticated;
create policy gestion_oficina on public.ordenes_venta_lineas for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
revoke all on public.tipos_cambio from anon, authenticated;
grant select, insert, update, delete on public.tipos_cambio to authenticated;
create policy gestion_oficina on public.tipos_cambio for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy lectura_planta on public.proveedores for select to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'planta'));
create policy lectura_planta on public.clientes for select to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'planta'));
create policy lectura_planta on public.boletas_entrada for select to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'planta'));
create policy ingreso_planta on public.boletas_entrada for insert to authenticated with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'planta'));
create policy actualizacion_planta on public.boletas_entrada for update to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'planta')) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'planta'));
create index on public.ordenes_compra(proveedor_id);
create index on public.ordenes_compra(creado_por);
create index on public.boletas_entrada(orden_compra_id);
create index on public.boletas_entrada(proveedor_id);
create index on public.ordenes_venta(cliente_id);
create index on public.ordenes_venta_lineas(orden_venta_id);
