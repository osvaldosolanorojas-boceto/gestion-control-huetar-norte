create table public.movimientos_cartones (
  id uuid primary key default gen_random_uuid(),
  carton_id uuid not null references public.inventario_cartones(id),
  tipo text not null check (tipo in ('entrada')),
  cantidad integer not null check (cantidad > 0),
  observaciones text,
  registrado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default now()
);
alter table public.movimientos_cartones enable row level security;
revoke all on public.movimientos_cartones from anon, authenticated;
grant select, insert on public.movimientos_cartones to authenticated;
create policy gestion_oficina on public.movimientos_cartones for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create index movimientos_cartones_carton_idx on public.movimientos_cartones(carton_id,creado_en desc);

-- Suma existencias sin sobrescribir cambios concurrentes; registra quién ingresó cartones.
create function public.registrar_entrada_cartones(p_carton_id uuid,p_cantidad integer,p_observaciones text default null)
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_existencia integer;
begin
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'La cantidad debe ser positiva'; end if;
  update public.inventario_cartones set existencia=existencia+p_cantidad where id=p_carton_id returning existencia into v_existencia;
  if v_existencia is null then raise exception 'No se encontró la marca o no tiene permiso'; end if;
  insert into public.movimientos_cartones(carton_id,tipo,cantidad,observaciones,registrado_por)
  values (p_carton_id,'entrada',p_cantidad,p_observaciones,(select auth.uid()));
  return v_existencia;
end;
$$;
revoke all on function public.registrar_entrada_cartones(uuid,integer,text) from public, anon;
grant execute on function public.registrar_entrada_cartones(uuid,integer,text) to authenticated;
