-- Corrige llamadas a expresiones especiales SQL que fallaban al guardar.
create or replace function public.guardar_orden_venta(
  p_orden_id uuid, p_codigo text, p_fecha date, p_fecha_salida date,
  p_cliente_id uuid, p_mercado text, p_pais_destino text, p_contenedor text,
  p_observaciones text, p_lineas jsonb
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  v_orden_id uuid;
  v_linea jsonb;
begin
  if p_lineas is null or jsonb_array_length(p_lineas) = 0 then
    raise exception 'La orden necesita al menos una línea de producto';
  end if;
  if (select coalesce(sum((value->>'paletas')::integer),0) from pg_catalog.jsonb_array_elements(p_lineas)) > 22 then
    raise exception 'El contenedor no puede superar 22 paletas';
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
    if (v_linea->>'paletas')::integer < 1 or nullif(v_linea->>'carton_id','') is null then
      raise exception 'Cada línea requiere paletas y una marca de cartón';
    end if;
    insert into public.ordenes_venta_lineas
      (orden_venta_id,producto,presentacion_kg,paletas,cajas_por_paleta,cantidad_cajas,precio_caja,carton_id,carton_marca)
    values (v_orden_id,v_linea->>'producto',(v_linea->>'presentacion_kg')::numeric,
      (v_linea->>'paletas')::integer,(v_linea->>'cajas_por_paleta')::integer,
      (v_linea->>'cantidad_cajas')::integer,(v_linea->>'precio_caja')::numeric,
      nullif(v_linea->>'carton_id','')::uuid,v_linea->>'carton_marca');
  end loop;
  return v_orden_id;
end;
$$;
revoke all on function public.guardar_orden_venta(uuid,text,date,date,uuid,text,text,text,text,jsonb) from public, anon;
grant execute on function public.guardar_orden_venta(uuid,text,date,date,uuid,text,text,text,text,jsonb) to authenticated;

-- Verificación transaccional: las inserciones y la edición se revierten juntas.
do $$
declare
  v_cliente uuid;
  v_carton uuid;
  v_orden uuid;
  v_lineas integer;
begin
  select id into v_cliente from public.clientes limit 1;
  select id into v_carton from public.inventario_cartones limit 1;
  if v_cliente is null or v_carton is null then
    raise exception 'Se necesita un cliente y una marca para verificar el guardado';
  end if;
  begin
    v_orden := public.guardar_orden_venta(null,'OV-VERIFICACION-REVERSIBLE',current_date,current_date+1,
      v_cliente,'Europa','España',null,null,
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('producto','Yuca','presentacion_kg',18,
      'paletas',2,'cajas_por_paleta',60,'cantidad_cajas',120,'precio_caja',4.5,
      'carton_id',v_carton::text,'carton_marca','Prueba')));
    select count(*) into v_lineas from public.ordenes_venta_lineas where orden_venta_id=v_orden;
    if v_lineas<>1 then raise exception 'No se guardó la línea'; end if;
    v_orden := public.guardar_orden_venta(v_orden,null,current_date,current_date+2,
      v_cliente,'Canadá','Canadá',null,null,
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('producto','Ñampí','presentacion_kg',10,
      'paletas',3,'cajas_por_paleta',72,'cantidad_cajas',216,'precio_caja',7,
      'carton_id',v_carton::text,'carton_marca','Prueba')));
    select count(*) into v_lineas from public.ordenes_venta_lineas where orden_venta_id=v_orden;
    if v_lineas<>1 then raise exception 'No se actualizó la línea'; end if;
    raise exception 'verificacion_revertida';
  exception when others then
    if sqlerrm <> 'verificacion_revertida' then raise; end if;
  end;
end $$;
