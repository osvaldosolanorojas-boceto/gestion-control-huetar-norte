-- Conserva los IDs de líneas de venta cuando hay cajas asignadas a boletas.
create or replace function public.guardar_orden_venta(
  p_orden_id uuid, p_codigo text, p_fecha date, p_fecha_salida date,
  p_cliente_id uuid, p_mercado text, p_pais_destino text, p_contenedor text,
  p_observaciones text, p_lineas jsonb
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  v_orden_id uuid;
  v_linea jsonb;
  v_linea_id uuid;
  v_asignadas integer;
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
    delete from public.ordenes_venta_lineas where orden_venta_id=v_orden_id
      and not id in (select (value->>'id')::uuid from pg_catalog.jsonb_array_elements(p_lineas) where nullif(value->>'id','') is not null);
  end if;
  for v_linea in select value from pg_catalog.jsonb_array_elements(p_lineas) loop
    if (v_linea->>'paletas')::integer < 1 or nullif(v_linea->>'carton_id','') is null then
      raise exception 'Cada línea requiere paletas y una marca de cartón';
    end if;
    v_linea_id:=nullif(v_linea->>'id','')::uuid;
    if v_linea_id is null then
      insert into public.ordenes_venta_lineas
        (orden_venta_id,producto,presentacion_kg,paletas,cajas_por_paleta,cantidad_cajas,precio_caja,carton_id,carton_marca)
      values (v_orden_id,v_linea->>'producto',(v_linea->>'presentacion_kg')::numeric,
        (v_linea->>'paletas')::integer,(v_linea->>'cajas_por_paleta')::integer,
        (v_linea->>'cantidad_cajas')::integer,(v_linea->>'precio_caja')::numeric,
        nullif(v_linea->>'carton_id','')::uuid,v_linea->>'carton_marca');
    else
      select coalesce(sum(r.cajas),0) into v_asignadas from public.boleta_rendimientos r where r.orden_venta_linea_id=v_linea_id;
      if v_asignadas>0 and exists (select 1 from public.boleta_rendimientos r where r.orden_venta_linea_id=v_linea_id and (r.producto<>v_linea->>'producto' or r.presentacion_kg<>(v_linea->>'presentacion_kg')::numeric)) then raise exception 'No puede cambiar el producto o presentación de una línea ya asignada en planta'; end if;
      if v_asignadas>(v_linea->>'cantidad_cajas')::integer then raise exception 'No puede reducir una línea por debajo de las cajas ya asignadas en planta'; end if;
      update public.ordenes_venta_lineas set producto=v_linea->>'producto',presentacion_kg=(v_linea->>'presentacion_kg')::numeric,
        paletas=(v_linea->>'paletas')::integer,cajas_por_paleta=(v_linea->>'cajas_por_paleta')::integer,
        cantidad_cajas=(v_linea->>'cantidad_cajas')::integer,precio_caja=(v_linea->>'precio_caja')::numeric,
        carton_id=nullif(v_linea->>'carton_id','')::uuid,carton_marca=v_linea->>'carton_marca'
      where id=v_linea_id and orden_venta_id=v_orden_id;
      if not found then raise exception 'La línea no pertenece a esta orden de venta'; end if;
    end if;
  end loop;
  return v_orden_id;
end;
$$;
revoke all on function public.guardar_orden_venta(uuid,text,date,date,uuid,text,text,text,text,jsonb) from public,anon;
grant execute on function public.guardar_orden_venta(uuid,text,date,date,uuid,text,text,text,text,jsonb) to authenticated;
