create table public.seguimiento_ejercicio (
  id integer primary key check (id = 1),
  modulo text not null check (modulo in ('Órdenes de venta', 'Órdenes de compra', 'Boletas de entrada')),
  revision bigint not null default 1,
  actualizado_en timestamptz not null default now()
);

alter table public.seguimiento_ejercicio enable row level security;
revoke all on public.seguimiento_ejercicio from anon, authenticated;
grant select on public.seguimiento_ejercicio to authenticated;

create policy seguimiento_administrador on public.seguimiento_ejercicio
  for select to authenticated
  using (exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid()) and p.activo and p.rol = 'administrador'
  ));

insert into public.seguimiento_ejercicio (id, modulo) values (1, 'Órdenes de venta');
