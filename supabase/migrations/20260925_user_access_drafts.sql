-- Preparación de usuarios. Estos registros no crean cuentas de Auth ni conceden acceso.
create table if not exists public.usuarios_preparados (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(btrim(nombre)) between 2 and 150),
  correo text not null check (correo = lower(btrim(correo)) and correo ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
  area text not null check (area in ('planta','oficina','finca','bodega','chofer')),
  modulos text[] not null default '{}',
  observaciones text not null default '',
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (correo),
  check (modulos <@ array[
    'Resumen','Órdenes de compra','Boletas de entrada','Producción y rendimientos',
    'Mapa de carga','Saldo yuca EE. UU.','Segundas y rechazo','Órdenes de venta',
    'Proveedores','Clientes','Colaboradores','Empresas','Inventarios','Finanzas',
    'Efectivo','Bancos','Corte semanal','Fincas'
  ]::text[])
);
alter table public.usuarios_preparados enable row level security;
revoke all on public.usuarios_preparados from anon, authenticated;
grant select, insert, update, delete on public.usuarios_preparados to authenticated;
create policy usuarios_preparados_admin on public.usuarios_preparados
  for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'administrador'))
  with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol = 'administrador'));
