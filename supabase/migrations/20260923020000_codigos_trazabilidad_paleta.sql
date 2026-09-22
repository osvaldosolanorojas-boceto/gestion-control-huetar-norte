alter table public.boleta_rendimientos add column codigo_trazabilidad text;
update public.boleta_rendimientos r set codigo_trazabilidad=b.codigo from public.boletas_entrada b where b.id=r.boleta_id;
alter table public.boleta_rendimientos alter column codigo_trazabilidad set not null;
create index boleta_rendimientos_codigo_idx on public.boleta_rendimientos(codigo_trazabilidad);

create or replace function private.guardar_boleta_planta(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_producto text; v_proveedor_id uuid; v_finca text; v_chofer text; v_placa text;
  v_trabajo jsonb; v_rendimiento jsonb; v_pedido record; v_asignado integer;
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  select o.producto,o.proveedor_id,o.lugar,o.chofer,o.placa into v_producto,v_proveedor_id,v_finca,v_chofer,v_placa from public.ordenes_compra o where o.id=p_orden_compra_id;
  if v_producto is null then raise exception 'Seleccione una orden de compra válida'; end if;
  if p_inicio_proceso is not null and p_fin_proceso is not null and p_fin_proceso<p_inicio_proceso then raise exception 'El fin del proceso debe ser posterior al inicio'; end if;
  if p_boleta_id is null then
    insert into public.boletas_entrada(codigo,fecha_hora,fecha_labor,orden_compra_id,proveedor_id,finca_lugar,chofer,placa,condicion,producto,cantidad_recipientes,tipo_recipiente,promedio_peso,kg_estimados,linea_proceso,encargado,encargado_banda,inicio_proceso,fin_proceso,turno,clima,observaciones,tratamiento_cera)
    values(p_codigo,p_fecha_hora,p_fecha_labor,p_orden_compra_id,v_proveedor_id,v_finca,v_chofer,v_placa,p_condicion,v_producto,p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,p_cantidad_recipientes*p_promedio_peso,p_linea_proceso,p_encargado,p_encargado_banda,p_inicio_proceso,p_fin_proceso,p_turno,p_clima,p_observaciones,p_tratamiento_cera) returning id into v_id;
  else
    update public.boletas_entrada b set fecha_hora=p_fecha_hora,fecha_labor=p_fecha_labor,orden_compra_id=p_orden_compra_id,proveedor_id=v_proveedor_id,finca_lugar=v_finca,chofer=v_chofer,placa=v_placa,condicion=p_condicion,producto=v_producto,cantidad_recipientes=p_cantidad_recipientes,tipo_recipiente=p_tipo_recipiente,promedio_peso=p_promedio_peso,kg_estimados=p_cantidad_recipientes*p_promedio_peso,linea_proceso=p_linea_proceso,encargado=p_encargado,encargado_banda=p_encargado_banda,inicio_proceso=p_inicio_proceso,fin_proceso=p_fin_proceso,turno=p_turno,clima=p_clima,observaciones=p_observaciones,tratamiento_cera=p_tratamiento_cera where b.id=p_boleta_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la boleta'; end if;
    delete from public.boleta_trabajos where boleta_id=v_id;
    delete from public.boleta_rendimientos where boleta_id=v_id;
  end if;
  for v_trabajo in select value from pg_catalog.jsonb_array_elements(coalesce(p_trabajos,'[]'::jsonb)) loop
    if not exists (select 1 from public.trabajadores t where t.id=(v_trabajo->>'trabajador_id')::uuid and t.activo) then raise exception 'El colaborador seleccionado no está activo'; end if;
    insert into public.boleta_trabajos(boleta_id,trabajador_id,labor) values(v_id,(v_trabajo->>'trabajador_id')::uuid,v_trabajo->>'labor');
  end loop;
  for v_rendimiento in select value from pg_catalog.jsonb_array_elements(coalesce(p_rendimientos,'[]'::jsonb)) loop
    if v_rendimiento->>'producto'<>v_producto then raise exception 'El rendimiento debe corresponder al producto recibido'; end if;
    if nullif(v_rendimiento->>'orden_venta_linea_id','') is not null then
      select l.producto,l.presentacion_kg,l.cantidad_cajas into v_pedido from public.ordenes_venta_lineas l where l.id=(v_rendimiento->>'orden_venta_linea_id')::uuid for update;
      if not found or v_pedido.producto<>v_producto or v_pedido.presentacion_kg<>(v_rendimiento->>'presentacion_kg')::numeric then raise exception 'La línea del pedido no coincide con el producto y peso'; end if;
      select coalesce(sum(r.cajas),0) into v_asignado from public.boleta_rendimientos r where r.orden_venta_linea_id=(v_rendimiento->>'orden_venta_linea_id')::uuid;
      if v_asignado+coalesce((v_rendimiento->>'cajas')::integer,0)>v_pedido.cantidad_cajas then raise exception 'La cantidad supera las cajas solicitadas en la orden de venta'; end if;
    end if;
    if nullif(v_rendimiento->>'posicion_paleta','') is not null and nullif(v_rendimiento->>'orden_venta_linea_id','') is null then raise exception 'Para asignar una paleta seleccione primero la orden de venta'; end if;
    insert into public.boleta_rendimientos(boleta_id,producto,calidad,presentacion_kg,cajas,kg_manual,orden_venta_linea_id,posicion_paleta,observaciones,paga_productor,codigo_trazabilidad)
    values(v_id,v_producto,v_rendimiento->>'calidad',nullif(v_rendimiento->>'presentacion_kg','')::numeric,coalesce(nullif(v_rendimiento->>'cajas','')::integer,0),nullif(v_rendimiento->>'kg_manual','')::numeric,nullif(v_rendimiento->>'orden_venta_linea_id','')::uuid,nullif(v_rendimiento->>'posicion_paleta','')::smallint,v_rendimiento->>'observaciones',coalesce((v_rendimiento->>'paga_productor')::boolean,true),coalesce(nullif(pg_catalog.btrim(v_rendimiento->>'codigo_trazabilidad'),''),p_codigo));
  end loop;
  return v_id;
end;
$$;
