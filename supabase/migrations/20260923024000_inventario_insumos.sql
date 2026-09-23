-- Inventario independiente de cartones, con existencias y movimientos auditables.
create table public.insumos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(trim(nombre)) > 0),
  categoria text not null default 'Otros',
  unidad text not null check (length(trim(unidad)) > 0),
  existencia numeric(14,3) not null default 0 check (existencia >= 0),
  minimo numeric(14,3) not null default 0 check (minimo >= 0),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
create unique index insumos_nombre_unidad_unique on public.insumos (lower(nombre),lower(unidad));
alter table public.insumos enable row level security;
revoke all on public.insumos from anon, authenticated;
grant select, insert, update on public.insumos to authenticated;
create policy gestion_oficina on public.insumos for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create table public.movimientos_insumos (
  id uuid primary key default gen_random_uuid(),
  insumo_id uuid not null references public.insumos(id),
  tipo text not null check (tipo in ('entrada','consumo','ajuste_entrada','ajuste_salida')),
  cantidad numeric(14,3) not null check (cantidad > 0),
  referencia text,
  observaciones text,
  registrado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default now()
);
create index movimientos_insumos_insumo_fecha_idx on public.movimientos_insumos(insumo_id,creado_en desc);
alter table public.movimientos_insumos enable row level security;
revoke all on public.movimientos_insumos from anon, authenticated;
grant select, insert on public.movimientos_insumos to authenticated;
create policy gestion_oficina on public.movimientos_insumos for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create function public.registrar_movimiento_insumo(p_insumo_id uuid,p_tipo text,p_cantidad numeric,p_referencia text default null,p_observaciones text default null)
returns numeric language plpgsql security invoker set search_path = '' as $$
declare v_existencia numeric;
begin
  if p_tipo not in ('entrada','consumo','ajuste_entrada','ajuste_salida') or p_tipo is null then raise exception 'Tipo de movimiento inválido'; end if;
  if p_cantidad is null or p_cantidad <= 0 or p_cantidad > 99999999999.999 or p_cantidad <> round(p_cantidad,3) then raise exception 'Cantidad inválida'; end if;
  update public.insumos set existencia=existencia + case when p_tipo in ('entrada','ajuste_entrada') then p_cantidad else -p_cantidad end
    where id=p_insumo_id and activo and (p_tipo in ('entrada','ajuste_entrada') or existencia >= p_cantidad)
    returning existencia into v_existencia;
  if v_existencia is null then raise exception 'Insumo no disponible, existencia insuficiente o falta de permiso'; end if;
  insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
    values (p_insumo_id,p_tipo,p_cantidad,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid()));
  return v_existencia;
end;
$$;
revoke all on function public.registrar_movimiento_insumo(uuid,text,numeric,text,text) from public, anon;
grant execute on function public.registrar_movimiento_insumo(uuid,text,numeric,text,text) to authenticated;
