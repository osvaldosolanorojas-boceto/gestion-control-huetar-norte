-- Catálogo con unidades de inventario y presentación de compra. Las referencias
-- de precio no son compras ni crean existencia.
alter table public.insumos add column presentacion_compra text;
alter table public.insumos add column unidades_por_presentacion numeric(14,3) check (unidades_por_presentacion>0);
alter table public.insumos add column precio_referencia numeric(16,2) check (precio_referencia>=0);
alter table public.insumos add column moneda_referencia text check (moneda_referencia in ('CRC','USD'));
alter table public.insumos add column especificacion text;
alter table public.insumos add constraint precio_referencia_moneda check ((precio_referencia is null and moneda_referencia is null) or (precio_referencia is not null and moneda_referencia is not null));

insert into public.insumos(nombre,categoria,unidad,existencia,minimo,activo,presentacion_compra,unidades_por_presentacion,precio_referencia,moneda_referencia,especificacion) values
('Parafina','Parafina','kg',0,0,true,'caja',25,50,'USD','Precio de referencia editable; 25 kg por caja'),
('Cera','Cera','kg',0,0,true,'caja',25,28,'USD','Precio de referencia editable; 25 kg por caja'),
('Cloro al 12%','Cloro','litros',0,0,true,'litro',1,null,null,'Concentración 12%'),
('Esquineros plásticos','Esquineros','unidades',0,0,true,'unidad',1,null,null,null),
('Esquineros de cartón','Esquineros','unidades',0,0,true,'unidad',1,null,null,null),
('Grapas para fleje','Grapas','unidades',0,0,true,'unidad',1,null,null,null),
('Grapas para cartón','Grapas para cartón','unidades',0,0,true,'unidad',1,null,null,null),
('Papel para envolver ñame','Papel','kg',0,0,true,'kg',1,null,null,null),
('Productos de limpieza de sanitarios','Limpieza','unidades',0,0,true,'unidad',1,null,null,null),
('Papel higiénico','Limpieza','rollos',0,0,true,'rollo',1,null,null,null),
('Desinfectante','Limpieza','litros',0,0,true,'litro',1,null,null,null),
('Jabón en polvo','Limpieza','kg',0,0,true,'kg',1,null,null,null),
('Alcohol en gel','Higiene','litros',0,0,true,'litro',1,null,null,null),
('Jabón para manos','Higiene','litros',0,0,true,'litro',1,null,null,null),
('Aceite hidráulico para perras','Mantenimiento','litros',0,0,true,'litro',1,null,null,null),
('Fleje','Fleje','rollos',0,0,true,'rollo',1,null,null,null),
('Guantes','Guantes','pares',0,0,true,'par',1,null,null,null),
('Etiquetas','Etiquetas','unidades',0,0,true,'unidad',1,null,null,null)
on conflict do nothing;

create table public.ordenes_insumos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique default ('OI-'||to_char(now(),'YYYYMMDDHH24MISS')||'-'||substr(gen_random_uuid()::text,1,6)),
  fecha date not null,
  proveedor_nombre text not null check (length(trim(proveedor_nombre))>0),
  proveedor_id uuid references public.proveedores(id),
  moneda text not null check (moneda in ('CRC','USD')),
  estado text not null default 'Abierta' check (estado in ('Abierta','Recibida','Anulada')),
  observaciones text,
  registrado_por uuid not null default auth.uid() references public.perfiles(id),
  creado_en timestamptz not null default now()
);
create index ordenes_insumos_fecha_idx on public.ordenes_insumos(fecha desc);
create table public.ordenes_insumos_lineas (
  id uuid primary key default gen_random_uuid(),
  orden_id uuid not null references public.ordenes_insumos(id),
  insumo_id uuid not null references public.insumos(id),
  presentacion text not null,
  unidades_por_presentacion numeric(14,3) not null check (unidades_por_presentacion>0),
  cantidad_presentaciones numeric(14,3) not null check (cantidad_presentaciones>0),
  precio_presentacion numeric(16,2) not null check (precio_presentacion>=0),
  recibido_presentaciones numeric(14,3) not null default 0 check (recibido_presentaciones>=0 and recibido_presentaciones<=cantidad_presentaciones),
  creado_en timestamptz not null default now()
);
create index ordenes_insumos_lineas_orden_idx on public.ordenes_insumos_lineas(orden_id);
create table public.lotes_insumos (
  id uuid primary key default gen_random_uuid(),
  linea_id uuid not null references public.ordenes_insumos_lineas(id),
  insumo_id uuid not null references public.insumos(id),
  fecha date not null,
  cantidad_original numeric(14,3) not null check (cantidad_original>0),
  disponible numeric(14,3) not null check (disponible>=0 and disponible<=cantidad_original),
  moneda text not null check (moneda in ('CRC','USD')),
  precio_por_unidad numeric(18,6) not null check (precio_por_unidad>=0),
  referencia text,
  movimiento_id uuid unique references public.movimientos_insumos(id),
  creado_en timestamptz not null default now()
);
create index lotes_insumos_insumo_idx on public.lotes_insumos(insumo_id,fecha) where disponible>0;

alter table public.ordenes_insumos enable row level security;
alter table public.ordenes_insumos_lineas enable row level security;
alter table public.lotes_insumos enable row level security;
revoke all on public.ordenes_insumos,public.ordenes_insumos_lineas,public.lotes_insumos from anon,authenticated;
grant select,insert,update on public.ordenes_insumos,public.ordenes_insumos_lineas,public.lotes_insumos to authenticated;
create policy oficina_ordenes_insumos on public.ordenes_insumos for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy oficina_lineas_insumos on public.ordenes_insumos_lineas for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy oficina_lotes_insumos on public.lotes_insumos for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create function public.crear_orden_insumos(p_fecha date,p_proveedor_nombre text,p_proveedor_id uuid,p_moneda text,p_observaciones text,p_lineas jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid; v_linea jsonb; v_insumo public.insumos%rowtype; v_qty numeric; v_factor numeric; v_precio numeric;
begin
  if p_fecha is null or nullif(trim(p_proveedor_nombre),'') is null or p_moneda not in ('CRC','USD') or jsonb_typeof(p_lineas)<>'array' or jsonb_array_length(p_lineas)=0 then
    raise exception 'Complete fecha, proveedor, moneda y al menos un insumo'; end if;
  if p_proveedor_id is not null and not exists(select 1 from public.proveedores where id=p_proveedor_id and nombre=p_proveedor_nombre and activo) then
    raise exception 'El proveedor no coincide con la ficha seleccionada'; end if;
  insert into public.ordenes_insumos(fecha,proveedor_nombre,proveedor_id,moneda,observaciones)
    values (p_fecha,trim(p_proveedor_nombre),p_proveedor_id,p_moneda,nullif(trim(p_observaciones),'')) returning id into v_id;
  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    select * into v_insumo from public.insumos where id=(v_linea->>'insumo_id')::uuid and activo;
    if not found then raise exception 'Insumo no disponible'; end if;
    v_qty:=(v_linea->>'cantidad')::numeric; v_factor:=(v_linea->>'factor')::numeric; v_precio:=(v_linea->>'precio')::numeric;
    if v_qty is null or v_qty<=0 or v_qty<>round(v_qty,3) or v_factor is null or v_factor<=0 or v_factor<>round(v_factor,3)
       or v_precio is null or v_precio<0 or v_precio<>round(v_precio,2) or nullif(trim(v_linea->>'presentacion'),'') is null then
      raise exception 'Revise cantidad, presentación y precio de cada insumo'; end if;
    insert into public.ordenes_insumos_lineas(orden_id,insumo_id,presentacion,unidades_por_presentacion,cantidad_presentaciones,precio_presentacion)
      values (v_id,v_insumo.id,trim(v_linea->>'presentacion'),v_factor,v_qty,v_precio);
  end loop;
  return v_id;
end;
$$;
revoke all on function public.crear_orden_insumos(date,text,uuid,text,text,jsonb) from public,anon;
grant execute on function public.crear_orden_insumos(date,text,uuid,text,text,jsonb) to authenticated;

create function public.recibir_orden_insumos(p_linea_id uuid,p_cantidad numeric,p_fecha date,p_referencia text default null)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_linea public.ordenes_insumos_lineas%rowtype; v_orden public.ordenes_insumos%rowtype; v_base numeric; v_mov uuid; v_lote uuid;
begin
  if p_fecha is null or p_cantidad is null or p_cantidad<=0 or p_cantidad<>round(p_cantidad,3) then raise exception 'Cantidad y fecha inválidas'; end if;
  select * into v_linea from public.ordenes_insumos_lineas where id=p_linea_id for update;
  if not found then raise exception 'Línea no encontrada'; end if;
  select * into v_orden from public.ordenes_insumos where id=v_linea.orden_id for update;
  if v_orden.estado<>'Abierta' or p_cantidad>v_linea.cantidad_presentaciones-v_linea.recibido_presentaciones then raise exception 'La entrega supera la cantidad pendiente'; end if;
  v_base:=round(p_cantidad*v_linea.unidades_por_presentacion,3);
  if v_base<=0 then raise exception 'Cantidad convertida inválida'; end if;
  update public.ordenes_insumos_lineas set recibido_presentaciones=recibido_presentaciones+p_cantidad where id=p_linea_id;
  update public.insumos set existencia=existencia+v_base where id=v_linea.insumo_id and activo;
  if not found then raise exception 'Insumo inactivo'; end if;
  insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
    values (v_linea.insumo_id,'entrada',v_base,coalesce(nullif(trim(p_referencia),''),v_orden.codigo),'Recepción de orden de insumos',(select auth.uid())) returning id into v_mov;
  insert into public.lotes_insumos(linea_id,insumo_id,fecha,cantidad_original,disponible,moneda,precio_por_unidad,referencia,movimiento_id)
    values (p_linea_id,v_linea.insumo_id,p_fecha,v_base,v_base,v_orden.moneda,v_linea.precio_presentacion/v_linea.unidades_por_presentacion,nullif(trim(p_referencia),''),v_mov) returning id into v_lote;
  if not exists(select 1 from public.ordenes_insumos_lineas where orden_id=v_orden.id and recibido_presentaciones<cantidad_presentaciones) then
    update public.ordenes_insumos set estado='Recibida' where id=v_orden.id;
  end if;
  return v_lote;
end;
$$;
revoke all on function public.recibir_orden_insumos(uuid,numeric,date,text) from public,anon;
grant execute on function public.recibir_orden_insumos(uuid,numeric,date,text) to authenticated;

create function public.consumir_lote_insumo(p_lote_id uuid,p_cantidad numeric,p_fecha date,p_producto text default null,p_linea smallint default null,p_boleta_id uuid default null,p_orden_venta_id uuid default null,p_referencia text default null,p_observaciones text default null)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_lote public.lotes_insumos%rowtype; v_insumo public.insumos%rowtype; v_mov uuid; v_costo uuid; v_monto numeric;
begin
  if p_fecha is null or p_cantidad is null or p_cantidad<=0 or p_cantidad<>round(p_cantidad,3) then raise exception 'Cantidad y fecha inválidas'; end if;
  update public.lotes_insumos set disponible=disponible-p_cantidad where id=p_lote_id and disponible>=p_cantidad returning * into v_lote;
  if not found then raise exception 'Lote sin existencia suficiente'; end if;
  update public.insumos set existencia=existencia-p_cantidad where id=v_lote.insumo_id and existencia>=p_cantidad returning * into v_insumo;
  if not found then raise exception 'Inventario insuficiente'; end if;
  v_monto:=round(p_cantidad*v_lote.precio_por_unidad,2);
  if v_monto<=0 then raise exception 'El lote no tiene costo positivo; use un ajuste valorado'; end if;
  insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
    values (v_insumo.id,'consumo',p_cantidad,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid())) returning id into v_mov;
  insert into public.costos_produccion(categoria,concepto,periodo_inicio,periodo_fin,moneda,monto,cantidad,unidad,producto,linea_proceso,boleta_id,orden_venta_id,insumo_id,movimiento_insumo_id,referencia,observaciones)
    values (case when v_insumo.categoria in ('Parafina','Cera') then 'tratamiento' when v_insumo.categoria in ('Cloro','Limpieza','Higiene') then 'limpieza' when v_insumo.categoria='Mantenimiento' then 'mantenimiento' else 'empaque' end,
      'Consumo · '||v_insumo.nombre,p_fecha,p_fecha,v_lote.moneda,v_monto,p_cantidad,v_insumo.unidad,nullif(trim(p_producto),''),p_linea,p_boleta_id,p_orden_venta_id,v_insumo.id,v_mov,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),'')) returning id into v_costo;
  return v_costo;
end;
$$;
revoke all on function public.consumir_lote_insumo(uuid,numeric,date,text,smallint,uuid,uuid,text,text) from public,anon;
grant execute on function public.consumir_lote_insumo(uuid,numeric,date,text,smallint,uuid,uuid,text,text) to authenticated;

-- Las existencias recibidas por orden deben salir de un lote para conservar su precio.
create or replace function public.consumir_insumo_costeado(
  p_insumo_id uuid,p_cantidad numeric,p_fecha date,p_moneda text,p_monto numeric,
  p_producto text default null,p_linea smallint default null,p_boleta_id uuid default null,
  p_orden_venta_id uuid default null,p_referencia text default null,p_observaciones text default null
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_insumo public.insumos%rowtype; v_movimiento uuid; v_costo uuid;
begin
  if p_fecha is null or p_moneda not in ('CRC','USD') or p_monto is null or p_monto<=0 or p_monto<>round(p_monto,2)
     or p_cantidad is null or p_cantidad<=0 or p_cantidad<>round(p_cantidad,3) then raise exception 'Complete fecha, cantidad, moneda y costo válidos'; end if;
  if exists(select 1 from public.lotes_insumos where insumo_id=p_insumo_id and disponible>0) then
    raise exception 'Seleccione el lote de compra para calcular el costo según su precio'; end if;
  update public.insumos set existencia=existencia-p_cantidad where id=p_insumo_id and activo and existencia>=p_cantidad returning * into v_insumo;
  if not found then raise exception 'Insumo no disponible o existencia insuficiente'; end if;
  insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
    values (p_insumo_id,'consumo',p_cantidad,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid())) returning id into v_movimiento;
  insert into public.costos_produccion(categoria,concepto,periodo_inicio,periodo_fin,moneda,monto,cantidad,unidad,producto,linea_proceso,boleta_id,orden_venta_id,insumo_id,movimiento_insumo_id,referencia,observaciones)
    values (case when v_insumo.categoria in ('Parafina','Cera') then 'tratamiento' when v_insumo.categoria in ('Cloro','Limpieza','Higiene') then 'limpieza' when v_insumo.categoria='Mantenimiento' then 'mantenimiento' else 'empaque' end,
      'Consumo · '||v_insumo.nombre,p_fecha,p_fecha,p_moneda,p_monto,p_cantidad,v_insumo.unidad,nullif(trim(p_producto),''),p_linea,p_boleta_id,p_orden_venta_id,p_insumo_id,v_movimiento,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),'')) returning id into v_costo;
  return v_costo;
end;
$$;
