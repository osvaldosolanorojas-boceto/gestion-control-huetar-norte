-- Fechas y destino de la orden de venta.
alter table public.ordenes_venta
  add column if not exists fecha_salida date,
  add column if not exists pais_destino text;

-- Existencia física de cartones. Las órdenes reservan su demanda mediante las líneas,
-- sin descontar físicamente el inventario hasta confirmar el despacho.
create table if not exists public.inventario_cartones (
  id uuid primary key default gen_random_uuid(),
  marca text not null,
  descripcion text not null,
  presentacion_kg numeric(8,2),
  existencia integer not null default 0 check (existencia >= 0),
  minimo_alerta integer not null default 0 check (minimo_alerta >= 0),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
alter table public.inventario_cartones enable row level security;
revoke all on public.inventario_cartones from anon, authenticated;
grant select, insert, update, delete on public.inventario_cartones to authenticated;
create policy gestion_oficina on public.inventario_cartones for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

alter table public.ordenes_venta_lineas
  add column if not exists carton_id uuid references public.inventario_cartones(id);
create index if not exists ordenes_venta_lineas_carton_idx on public.ordenes_venta_lineas(carton_id);

-- Una posición sólo puede aparecer una vez en cada contenedor/orden.
create table if not exists public.ordenes_venta_paletas (
  id uuid primary key default gen_random_uuid(),
  orden_venta_id uuid not null references public.ordenes_venta(id) on delete cascade,
  linea_id uuid not null references public.ordenes_venta_lineas(id) on delete cascade,
  posicion smallint not null check (posicion between 1 and 22),
  unique (orden_venta_id,posicion)
);
alter table public.ordenes_venta_paletas enable row level security;
revoke all on public.ordenes_venta_paletas from anon, authenticated;
grant select, insert, update, delete on public.ordenes_venta_paletas to authenticated;
create policy gestion_oficina on public.ordenes_venta_paletas for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create index if not exists ordenes_venta_paletas_linea_idx on public.ordenes_venta_paletas(linea_id);
alter table public.ordenes_venta_lineas add column if not exists carton_marca text;

-- Guardar cabecera, líneas y posiciones en una sola transacción; RLS se aplica al usuario.
create or replace function public.guardar_orden_venta(
  p_orden_id uuid, p_codigo text, p_fecha date, p_fecha_salida date,
  p_cliente_id uuid, p_mercado text, p_pais_destino text, p_contenedor text,
  p_observaciones text, p_lineas jsonb
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  v_orden_id uuid;
  v_linea_id uuid;
  v_linea jsonb;
  v_posicion text;
begin
  if p_lineas is null or jsonb_array_length(p_lineas) = 0 then
    raise exception 'La orden necesita al menos una línea de producto';
  end if;
  if p_orden_id is null then
    insert into public.ordenes_venta (codigo, fecha, fecha_salida, cliente_id, mercado, pais_destino, contenedor, moneda, observaciones)
    values (p_codigo, p_fecha, p_fecha_salida, p_cliente_id, p_mercado, p_pais_destino, p_contenedor, 'USD', p_observaciones)
    returning id into v_orden_id;
  else
    update public.ordenes_venta set fecha=p_fecha, fecha_salida=p_fecha_salida,
      cliente_id=p_cliente_id, mercado=p_mercado, pais_destino=p_pais_destino,
      contenedor=p_contenedor, observaciones=p_observaciones
    where id=p_orden_id returning id into v_orden_id;
    if v_orden_id is null then raise exception 'No se encontró la orden o no tiene permiso para editarla'; end if;
    delete from public.ordenes_venta_paletas where orden_venta_id=v_orden_id;
    delete from public.ordenes_venta_lineas where orden_venta_id=v_orden_id;
  end if;
  for v_linea in select value from pg_catalog.jsonb_array_elements(p_lineas) loop
    if pg_catalog.jsonb_array_length(v_linea->'posiciones') != (v_linea->>'paletas')::integer
      or (v_linea->>'paletas')::integer < 1 then
      raise exception 'Cada paleta debe tener una posición';
    end if;
    insert into public.ordenes_venta_lineas
      (orden_venta_id,producto,presentacion_kg,paletas,cajas_por_paleta,cantidad_cajas,precio_caja,carton_id,carton_marca)
    values (v_orden_id,v_linea->>'producto',(v_linea->>'presentacion_kg')::numeric,
      (v_linea->>'paletas')::integer,(v_linea->>'cajas_por_paleta')::integer,
      (v_linea->>'cantidad_cajas')::integer,(v_linea->>'precio_caja')::numeric,
      pg_catalog.nullif(v_linea->>'carton_id','')::uuid,v_linea->>'carton_marca')
    returning id into v_linea_id;
    for v_posicion in select value from pg_catalog.jsonb_array_elements_text(v_linea->'posiciones') loop
      insert into public.ordenes_venta_paletas(orden_venta_id,linea_id,posicion)
      values (v_orden_id,v_linea_id,v_posicion::smallint);
    end loop;
  end loop;
  return v_orden_id;
end;
$$;
revoke all on function public.guardar_orden_venta(uuid,text,date,date,uuid,text,text,text,text,jsonb) from public, anon;
grant execute on function public.guardar_orden_venta(uuid,text,date,date,uuid,text,text,text,text,jsonb) to authenticated;
