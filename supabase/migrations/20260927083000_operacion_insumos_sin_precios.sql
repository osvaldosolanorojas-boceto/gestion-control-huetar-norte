-- La planta ve existencias y movimientos sin columnas monetarias.
drop policy if exists acceso_bodega on public.insumos;
create view public.inventario_insumos_operacion with (security_barrier=true) as
select i.id,i.nombre,i.categoria,i.unidad,i.existencia,i.minimo,i.activo,i.presentacion_compra,i.unidades_por_presentacion
from public.insumos i
where exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta','bodega'));
create view public.pendientes_insumos_operacion with (security_barrier=true) as
select l.id as linea_id,i.nombre,i.unidad,l.presentacion,l.unidades_por_presentacion,
       l.cantidad_presentaciones-l.recibido_presentaciones as pendiente_presentaciones,o.codigo,o.fecha
from public.ordenes_insumos_lineas l join public.ordenes_insumos o on o.id=l.orden_id
join public.insumos i on i.id=l.insumo_id
where o.estado='Abierta' and l.cantidad_presentaciones>l.recibido_presentaciones
  and exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta','bodega'));
revoke all on public.inventario_insumos_operacion,public.pendientes_insumos_operacion from public,anon;
grant select on public.inventario_insumos_operacion,public.pendientes_insumos_operacion to authenticated;

create function public.recibir_insumo_operacion(p_linea_id uuid,p_cantidad numeric,p_fecha date,p_referencia text default null)
returns uuid language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta','bodega')) then raise exception 'Acceso denegado'; end if;
  return public.recibir_orden_insumos(p_linea_id,p_cantidad,p_fecha,p_referencia);
end;
$$;
revoke all on function public.recibir_insumo_operacion(uuid,numeric,date,text) from public,anon;
grant execute on function public.recibir_insumo_operacion(uuid,numeric,date,text) to authenticated;

-- FIFO: el usuario registra sólo cantidad. Cada lote genera su costo de manera interna.
-- El stock heredado sin precio se conserva como consumo pendiente de valorar.
create function public.consumir_insumo_operacion(p_insumo_id uuid,p_cantidad numeric,p_fecha date,p_boleta_id uuid default null,p_referencia text default null,p_observaciones text default null)
returns numeric language plpgsql security definer set search_path='' as $$
declare v_lote record; v_resto numeric; v_usar numeric; v_insumo public.insumos%rowtype; v_mov uuid; v_valor numeric; v_categoria text;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta','bodega')) then raise exception 'Acceso denegado'; end if;
  if p_fecha is null or p_cantidad is null or p_cantidad<=0 or p_cantidad<>round(p_cantidad,3) then raise exception 'Fecha o cantidad inválida'; end if;
  select * into v_insumo from public.insumos where id=p_insumo_id and activo for update;
  if not found or v_insumo.existencia<p_cantidad then raise exception 'Existencia insuficiente'; end if;
  if p_boleta_id is not null and not exists(select 1 from public.boletas_entrada where id=p_boleta_id) then raise exception 'Boleta inválida'; end if;
  v_resto:=p_cantidad;
  v_categoria:=case when v_insumo.categoria in ('Parafina','Cera') then 'tratamiento' when v_insumo.categoria in ('Cloro','Limpieza','Higiene') then 'limpieza' when v_insumo.categoria='Mantenimiento' then 'mantenimiento' else 'empaque' end;
  for v_lote in select * from public.lotes_insumos where insumo_id=p_insumo_id and disponible>0 order by fecha,creado_en,id for update loop
    exit when v_resto=0;
    v_usar:=least(v_resto,v_lote.disponible);
    v_valor:=round(v_usar*v_lote.precio_por_unidad,2);
    if v_valor<=0 then raise exception 'El consumo de este lote no alcanza el centavo mínimo; ajuste la cantidad'; end if;
    update public.lotes_insumos set disponible=disponible-v_usar where id=v_lote.id;
    update public.insumos set existencia=existencia-v_usar where id=p_insumo_id;
    insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
      values (p_insumo_id,'consumo',v_usar,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid())) returning id into v_mov;
    insert into public.costos_produccion(categoria,concepto,periodo_inicio,periodo_fin,moneda,monto,cantidad,unidad,producto,linea_proceso,boleta_id,insumo_id,movimiento_insumo_id,referencia,observaciones)
      values (v_categoria,'Consumo · '||v_insumo.nombre,p_fecha,p_fecha,v_lote.moneda,v_valor,v_usar,v_insumo.unidad,
       (select b.producto from public.boletas_entrada b where b.id=p_boleta_id),
       (select b.linea_proceso from public.boletas_entrada b where b.id=p_boleta_id),p_boleta_id,p_insumo_id,v_mov,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''));
    v_resto:=v_resto-v_usar;
  end loop;
  if v_resto>0 then
    update public.insumos set existencia=existencia-v_resto where id=p_insumo_id;
    insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
      values (p_insumo_id,'consumo',v_resto,nullif(trim(p_referencia),''),concat_ws(' · ',nullif(trim(p_observaciones),''),'Sin precio de adquisición: pendiente de valorar'),(select auth.uid()));
  end if;
  return v_insumo.existencia-p_cantidad;
end;
$$;
revoke all on function public.consumir_insumo_operacion(uuid,numeric,date,uuid,text,text) from public,anon;
grant execute on function public.consumir_insumo_operacion(uuid,numeric,date,uuid,text,text) to authenticated;
