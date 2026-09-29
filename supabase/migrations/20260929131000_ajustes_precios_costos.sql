-- Correcciones trazables de precios y cantidades de insumos/cartones.
begin;
alter table public.costos_produccion add column if not exists lote_insumo_id uuid references public.lotes_insumos(id);
create or replace function public.proteger_costo_produccion()
returns trigger language plpgsql set search_path to '' as $$
begin
  if old.anulado_en is not null then raise exception 'El costo anulado no se puede cambiar'; end if;
  if old.movimiento_insumo_id is not null then
    if current_setting('app.corrigiendo_precio_insumo',true)='1'
      and row(new.categoria,new.concepto,new.periodo_inicio,new.periodo_fin,new.fecha_factura,new.moneda,new.cantidad,new.unidad,new.producto,new.linea_proceso,new.orden_venta_id,new.boleta_id,new.insumo_id,new.movimiento_insumo_id,new.referencia,new.observaciones,new.registrado_por,new.creado_en,new.anulado_en)
      is not distinct from
      row(old.categoria,old.concepto,old.periodo_inicio,old.periodo_fin,old.fecha_factura,old.moneda,old.cantidad,old.unidad,old.producto,old.linea_proceso,old.orden_venta_id,old.boleta_id,old.insumo_id,old.movimiento_insumo_id,old.referencia,old.observaciones,old.registrado_por,old.creado_en,old.anulado_en)
      and new.monto>0 then return new;
    end if;
    raise exception 'El consumo de inventario se corrige con un movimiento de ajuste';
  end if;
  if new.movimiento_insumo_id is distinct from old.movimiento_insumo_id or new.registrado_por<>old.registrado_por or new.creado_en<>old.creado_en then
    raise exception 'No cambie el origen del costo';
  end if;
  if new.anulado_en is not null and new.anulado_en<>old.anulado_en and
    row(new.categoria,new.concepto,new.periodo_inicio,new.periodo_fin,new.fecha_factura,new.moneda,new.monto,new.cantidad,new.unidad,new.producto,new.linea_proceso,new.orden_venta_id,new.boleta_id,new.insumo_id,new.referencia,new.observaciones)
    is distinct from
    row(old.categoria,old.concepto,old.periodo_inicio,old.periodo_fin,old.fecha_factura,old.moneda,old.monto,old.cantidad,old.unidad,old.producto,old.linea_proceso,old.orden_venta_id,old.boleta_id,old.insumo_id,old.referencia,old.observaciones)
  then raise exception 'No cambie el detalle al anular'; end if;
  return new;
end $$;
select set_config('app.corrigiendo_precio_insumo','1',true);
update public.costos_produccion set lote_insumo_id='6ee92a95-5e82-4168-b7cb-59ca0175f048'
where id='13129f4f-68a0-480b-a325-e92036757e33' and lote_insumo_id is null;
select set_config('app.corrigiendo_precio_insumo','',true);

create table if not exists public.ajustes_precios_operativos(
  id uuid primary key default gen_random_uuid(),
  tipo text not null check(tipo in ('insumo','carton')),
  registro_id uuid not null,
  antes jsonb not null,
  despues jsonb not null,
  motivo text not null check(length(trim(motivo))>=8),
  registrado_por uuid not null default auth.uid(),
  registrado_en timestamptz not null default now()
);
alter table public.ajustes_precios_operativos enable row level security;
create policy administracion_ajustes_precios on public.ajustes_precios_operativos
  for select to authenticated using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
grant select on public.ajustes_precios_operativos to authenticated;

create or replace function public.consumir_lote_insumo(p_lote_id uuid,p_cantidad numeric,p_fecha date,p_producto text default null,p_linea smallint default null,p_boleta_id uuid default null,p_orden_venta_id uuid default null,p_referencia text default null,p_observaciones text default null)
returns uuid language plpgsql set search_path to '' as $$
declare v_lote public.lotes_insumos%rowtype;v_insumo public.insumos%rowtype;v_mov uuid;v_costo uuid;v_monto numeric;
begin
  if p_fecha is null or p_cantidad is null or p_cantidad<=0 or p_cantidad<>round(p_cantidad,3) then raise exception 'Cantidad y fecha inválidas'; end if;
  update public.lotes_insumos set disponible=disponible-p_cantidad where id=p_lote_id and disponible>=p_cantidad returning * into v_lote;
  if not found then raise exception 'Lote sin existencia suficiente'; end if;
  update public.insumos set existencia=existencia-p_cantidad where id=v_lote.insumo_id and existencia>=p_cantidad returning * into v_insumo;
  if not found then raise exception 'Inventario insuficiente'; end if;
  v_monto:=round(p_cantidad*v_lote.precio_por_unidad,2);
  if v_monto<=0 then raise exception 'El lote no tiene costo positivo; use un ajuste valorado'; end if;
  insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
  values(v_insumo.id,'consumo',p_cantidad,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid())) returning id into v_mov;
  insert into public.costos_produccion(categoria,concepto,periodo_inicio,periodo_fin,moneda,monto,cantidad,unidad,producto,linea_proceso,boleta_id,orden_venta_id,insumo_id,movimiento_insumo_id,lote_insumo_id,referencia,observaciones)
  values(case when v_insumo.categoria in ('Parafina','Cera') then 'tratamiento' when v_insumo.categoria in ('Cloro','Limpieza','Higiene') then 'limpieza' when v_insumo.categoria='Mantenimiento' then 'mantenimiento' else 'empaque' end,
    'Consumo · '||v_insumo.nombre,p_fecha,p_fecha,v_lote.moneda,v_monto,p_cantidad,v_insumo.unidad,nullif(trim(p_producto),''),p_linea,p_boleta_id,p_orden_venta_id,v_insumo.id,v_mov,v_lote.id,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),'')) returning id into v_costo;
  return v_costo;
end $$;

create or replace function public.corregir_precio_insumo(p_linea_id uuid,p_precio numeric,p_cantidad numeric,p_motivo text)
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_linea public.ordenes_insumos_lineas%rowtype;v_orden public.ordenes_insumos%rowtype;v_pagado numeric;v_total numeric;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
  if p_precio is null or p_precio<0 or p_cantidad is null or p_cantidad<=0 or p_cantidad<>round(p_cantidad,3) or length(trim(coalesce(p_motivo,'')))<8 then raise exception 'Revise precio, cantidad y motivo (mínimo 8 caracteres)'; end if;
  select * into v_linea from public.ordenes_insumos_lineas where id=p_linea_id for update;
  if not found then raise exception 'Línea no encontrada'; end if;
  select * into v_orden from public.ordenes_insumos where id=v_linea.orden_id for update;
  if p_cantidad<v_linea.recibido_presentaciones then raise exception 'La cantidad no puede ser menor que la recibida'; end if;
  select coalesce(sum(monto),0) into v_pagado from public.aplicaciones_bancarias where origen='compra_insumos' and origen_id=v_orden.id;
  select coalesce(sum(case when id=p_linea_id then recibido_presentaciones*p_precio else recibido_presentaciones*precio_presentacion end),0)
    into v_total from public.ordenes_insumos_lineas where orden_id=v_orden.id;
  if v_total<v_pagado then raise exception 'El nuevo total sería menor que lo ya pagado'; end if;
  update public.ordenes_insumos_lineas set precio_presentacion=p_precio,cantidad_presentaciones=p_cantidad where id=p_linea_id;
  update public.lotes_insumos set precio_por_unidad=p_precio/v_linea.unidades_por_presentacion where linea_id=p_linea_id;
  perform set_config('app.corrigiendo_precio_insumo','1',true);
  update public.costos_produccion c set monto=round(c.cantidad*p_precio/v_linea.unidades_por_presentacion,2)
    where c.lote_insumo_id in (select id from public.lotes_insumos where linea_id=p_linea_id) and c.anulado_en is null;
  perform set_config('app.corrigiendo_precio_insumo','',true);
  insert into public.ajustes_precios_operativos(tipo,registro_id,antes,despues,motivo)
    values('insumo',p_linea_id,jsonb_build_object('precio',v_linea.precio_presentacion,'cantidad',v_linea.cantidad_presentaciones),
      jsonb_build_object('precio',p_precio,'cantidad',p_cantidad),trim(p_motivo));
  return p_linea_id;
end $$;
revoke all on function public.corregir_precio_insumo(uuid,numeric,numeric,text) from public,anon;
grant execute on function public.corregir_precio_insumo(uuid,numeric,numeric,text) to authenticated;

create or replace function public.corregir_costo_carton(p_costo_id uuid,p_precio numeric,p_cantidad integer,p_motivo text)
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_costo public.costos_cartones%rowtype;v_pagado numeric;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
  if p_precio is null or p_precio<0 or p_cantidad is null or p_cantidad<=0 or length(trim(coalesce(p_motivo,'')))<8 then raise exception 'Revise precio, cantidad y motivo (mínimo 8 caracteres)'; end if;
  select * into v_costo from public.costos_cartones where id=p_costo_id for update;
  if not found then raise exception 'Costo no encontrado'; end if;
  if v_costo.movimiento_id is not null and p_cantidad<>v_costo.cantidad then raise exception 'La cantidad de una entrada física se corrige mediante inventario; aquí puede ajustar el precio'; end if;
  if v_costo.movimiento_id is null and (select coalesce(sum(cantidad),0) from public.costos_cartones where carton_id=v_costo.carton_id and id<>p_costo_id)+p_cantidad>(select existencia from public.inventario_cartones where id=v_costo.carton_id) then raise exception 'La cantidad con costo supera las existencias'; end if;
  select coalesce(sum(monto),0) into v_pagado from public.aplicaciones_bancarias where origen='compra_cartones' and origen_id=p_costo_id;
  if p_cantidad*p_precio<v_pagado then raise exception 'El nuevo costo sería menor que lo ya pagado'; end if;
  update public.costos_cartones set precio_unitario=p_precio,cantidad=p_cantidad where id=p_costo_id;
  insert into public.ajustes_precios_operativos(tipo,registro_id,antes,despues,motivo)
    values('carton',p_costo_id,jsonb_build_object('precio',v_costo.precio_unitario,'cantidad',v_costo.cantidad),
      jsonb_build_object('precio',p_precio,'cantidad',p_cantidad),trim(p_motivo));
  return p_costo_id;
end $$;
revoke all on function public.corregir_costo_carton(uuid,numeric,integer,text) from public,anon;
grant execute on function public.corregir_costo_carton(uuid,numeric,integer,text) to authenticated;
commit;
