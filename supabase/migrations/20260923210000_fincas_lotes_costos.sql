-- Origen de producción propia: finca física, lote por año y costo operativo.
create table public.fincas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique check (length(trim(nombre)) > 0),
  activa boolean not null default true,
  creado_en timestamptz not null default now()
);

create table public.lotes_finca (
  id uuid primary key default gen_random_uuid(),
  finca_id uuid not null references public.fincas(id),
  anio integer not null check (anio between 2000 and 2100),
  nombre text not null check (length(trim(nombre)) > 0),
  producto text,
  creado_en timestamptz not null default now(),
  unique (finca_id, anio, nombre),
  unique (id, finca_id)
);

alter table public.ordenes_compra
  add column finca_lote_id uuid references public.lotes_finca(id);
create index ordenes_compra_finca_lote_id_idx on public.ordenes_compra(finca_lote_id);

create table public.costos_finca (
  id uuid primary key default gen_random_uuid(),
  lote_id uuid not null references public.lotes_finca(id),
  fecha date not null default current_date,
  categoria text not null check (length(trim(categoria)) > 0),
  descripcion text,
  monto numeric(16,2) not null check (monto > 0),
  creado_en timestamptz not null default now()
);
create index costos_finca_lote_id_idx on public.costos_finca(lote_id);

alter table public.fincas enable row level security;
alter table public.lotes_finca enable row level security;
alter table public.costos_finca enable row level security;
revoke all on public.fincas,public.lotes_finca,public.costos_finca from anon,authenticated;
grant select,insert,update on public.fincas,public.lotes_finca to authenticated;
grant select,insert,update,delete on public.costos_finca to authenticated;
create policy gestion_oficina on public.fincas for all to authenticated
 using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy gestion_oficina on public.lotes_finca for all to authenticated
 using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy gestion_oficina on public.costos_finca for all to authenticated
 using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

insert into public.fincas(nombre) values
 ('El Concho'),('La Unión'),('Copevega'),('El Tanque'),('La Fortuna'),('Agua Azul'),('Muelle')
on conflict (nombre) do nothing;
