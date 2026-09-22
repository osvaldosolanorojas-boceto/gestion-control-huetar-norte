-- Una boleta de entrada por recepción, asociada a una orden de compra.
alter table public.boletas_entrada
  add column if not exists fecha_labor date,
  add column if not exists inicio_proceso timestamptz,
  add column if not exists fin_proceso timestamptz,
  add column if not exists turno text check (turno in ('Día','Noche')),
  add column if not exists clima text,
  add column if not exists encargado_banda text;
alter table public.boletas_entrada drop constraint if exists boletas_entrada_encargado_check;

create table public.boleta_trabajos (
  id uuid primary key default gen_random_uuid(),
  boleta_id uuid not null references public.boletas_entrada(id) on delete cascade,
  trabajador_id uuid not null references public.trabajadores(id),
  labor text not null check (labor in ('Selección de producto','Pelucado','Selección de empaque','Pesaje','Tapado','Flejado')),
  unique (boleta_id,trabajador_id,labor)
);
alter table public.boleta_trabajos enable row level security;
revoke all on public.boleta_trabajos from anon, authenticated;
grant select,insert,update,delete on public.boleta_trabajos to authenticated;
create policy ingreso_planta on public.boleta_trabajos for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')))
  with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));
create index boleta_trabajos_boleta_idx on public.boleta_trabajos(boleta_id);

-- Una paleta puede mezclar rendimientos de varias boletas, clientes o pedidos.
create table public.boleta_rendimientos (
  id uuid primary key default gen_random_uuid(),
  boleta_id uuid not null references public.boletas_entrada(id) on delete cascade,
  producto text not null,
  calidad text not null,
  presentacion_kg numeric(8,2) check (presentacion_kg > 0),
  cajas integer not null default 0 check (cajas >= 0),
  kg_manual numeric(14,2) check (kg_manual > 0),
  kg_resultado numeric(14,2) generated always as (coalesce(kg_manual,cajas*presentacion_kg)) stored,
  orden_venta_linea_id uuid references public.ordenes_venta_lineas(id),
  posicion_paleta smallint check (posicion_paleta between 1 and 22),
  observaciones text,
  creado_en timestamptz not null default now(),
  check (cajas > 0 or kg_manual > 0)
);
alter table public.boleta_rendimientos enable row level security;
revoke all on public.boleta_rendimientos from anon, authenticated;
grant select,insert,update,delete on public.boleta_rendimientos to authenticated;
create policy ingreso_planta on public.boleta_rendimientos for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')))
  with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));
create index boleta_rendimientos_boleta_idx on public.boleta_rendimientos(boleta_id);
create index boleta_rendimientos_venta_idx on public.boleta_rendimientos(orden_venta_linea_id);

-- Solo nombres y datos operativos visibles desde la sección de planta.
create function public.ordenes_compra_para_planta()
returns table(id uuid,codigo text,fecha date,productor_nombre text,producto text,boleta_campo_referencia text,proveedor_id uuid,chofer text,placa text)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select o.id,o.codigo,o.fecha,o.productor_nombre,o.producto,o.boleta_campo_referencia,o.proveedor_id,o.chofer,o.placa
  from public.ordenes_compra o order by o.fecha desc,o.creado_en desc limit 200;
end;
$$;
revoke all on function public.ordenes_compra_para_planta() from public,anon;
grant execute on function public.ordenes_compra_para_planta() to authenticated;

create function public.pedidos_para_planta()
returns table(linea_id uuid,orden_id uuid,codigo text,contenedor text,cliente text,producto text,presentacion_kg numeric,cantidad_cajas integer,carton text)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select l.id,o.id,o.codigo,o.contenedor,c.nombre,l.producto,l.presentacion_kg,l.cantidad_cajas,l.carton_marca
  from public.ordenes_venta_lineas l join public.ordenes_venta o on o.id=l.orden_venta_id
  left join public.clientes c on c.id=o.cliente_id
  order by o.fecha desc,o.creado_en desc limit 500;
end;
$$;
revoke all on function public.pedidos_para_planta() from public,anon;
grant execute on function public.pedidos_para_planta() to authenticated;

create function public.colaboradores_para_planta()
returns table(id uuid,nombre text,genero text)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select t.id,t.nombre,t.genero from public.trabajadores t where t.activo order by t.genero,t.nombre;
end;
$$;
revoke all on function public.colaboradores_para_planta() from public,anon;
grant execute on function public.colaboradores_para_planta() to authenticated;

create function public.agregar_colaborador_planta(p_nombre text,p_genero text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  if length(trim(p_nombre))<2 or p_genero not in ('Hombres','Mujeres') then raise exception 'Nombre y género requeridos'; end if;
  insert into public.trabajadores(nombre,genero) values (trim(p_nombre),p_genero) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.agregar_colaborador_planta(text,text) from public,anon;
grant execute on function public.agregar_colaborador_planta(text,text) to authenticated;
