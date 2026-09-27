create table if not exists public.pedidos_ejercicio (
  orden_venta_id uuid primary key references public.ordenes_venta(id),
  detalle text not null,
  marcado_en timestamptz not null default now()
);
alter table public.pedidos_ejercicio enable row level security;
revoke all on public.pedidos_ejercicio from anon,authenticated;
grant select on public.pedidos_ejercicio to authenticated;
drop policy if exists leer_pedidos_ejercicio on public.pedidos_ejercicio;
create policy leer_pedidos_ejercicio on public.pedidos_ejercicio for select to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo));
