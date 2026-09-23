-- Ventas por quintal: precio en CRC y peso neto de 46 kg por quintal.
alter table public.ordenes_venta_lineas add column precio_quintal numeric(14,2);
alter table public.ordenes_venta_lineas add constraint precio_quintal_positivo check (precio_quintal is null or precio_quintal > 0);
alter table public.ordenes_venta_lineas drop column total;
alter table public.ordenes_venta_lineas add column total numeric(16,2) generated always as (
  case when precio_quintal is not null then round(cantidad_cajas * presentacion_kg / 46 * precio_quintal,2)
       else cantidad_cajas * precio_caja end
) stored;

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
        (orden_venta_id,producto,presentacion_kg,paletas,cajas_por_paleta,cantidad_cajas,precio_caja,precio_quintal,carton_id,carton_marca)
      values (v_orden_id,v_linea->>'producto',(v_linea->>'presentacion_kg')::numeric,
        (v_linea->>'paletas')::integer,(v_linea->>'cajas_por_paleta')::integer,
        (v_linea->>'cantidad_cajas')::integer,(v_linea->>'precio_caja')::numeric,
        nullif(v_linea->>'precio_quintal','')::numeric,nullif(v_linea->>'carton_id','')::uuid,v_linea->>'carton_marca');
    else
      select coalesce(sum(r.cajas),0) into v_asignadas from public.boleta_rendimientos r where r.orden_venta_linea_id=v_linea_id;
      if v_asignadas>0 and exists (select 1 from public.boleta_rendimientos r where r.orden_venta_linea_id=v_linea_id and (r.producto<>v_linea->>'producto' or r.presentacion_kg<>(v_linea->>'presentacion_kg')::numeric)) then raise exception 'No puede cambiar el producto o presentación de una línea ya asignada en planta'; end if;
      if v_asignadas>(v_linea->>'cantidad_cajas')::integer then raise exception 'No puede reducir una línea por debajo de las cajas ya asignadas en planta'; end if;
      update public.ordenes_venta_lineas set producto=v_linea->>'producto',presentacion_kg=(v_linea->>'presentacion_kg')::numeric,
        paletas=(v_linea->>'paletas')::integer,cajas_por_paleta=(v_linea->>'cajas_por_paleta')::integer,
        cantidad_cajas=(v_linea->>'cantidad_cajas')::integer,precio_caja=(v_linea->>'precio_caja')::numeric,
        precio_quintal=nullif(v_linea->>'precio_quintal','')::numeric,
        carton_id=nullif(v_linea->>'carton_id','')::uuid,carton_marca=v_linea->>'carton_marca'
      where id=v_linea_id and orden_venta_id=v_orden_id;
      if not found then raise exception 'La línea no pertenece a esta orden de venta'; end if;
    end if;
  end loop;
  return v_orden_id;
end;
$$;
create or replace function public.guardar_orden_venta_identificada(
  p_orden_id uuid, p_codigo text, p_fecha date, p_fecha_salida date,
  p_cliente_id uuid, p_mercado text, p_pais_destino text, p_contenedor text,
  p_observaciones text, p_lineas jsonb, p_numero_cliente integer
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_id uuid;
begin
  if p_numero_cliente is null or p_numero_cliente < 1 then
    raise exception 'Indique un número de pedido válido para el cliente';
  end if;
  if exists (select 1 from pg_catalog.jsonb_array_elements(p_lineas) l
    where coalesce(l->>'moneda','USD') <> coalesce(p_lineas->0->>'moneda','USD')) then
    raise exception 'Todas las líneas de una orden deben tener la misma moneda';
  end if;
  if exists(select 1 from pg_catalog.jsonb_array_elements(p_lineas) l
    where (coalesce(l->>'moneda','USD')='CRC') is distinct from (nullif(l->>'precio_quintal','') is not null)) then
    raise exception 'Las ventas en colones requieren precio por quintal y las ventas en dólares precio por caja';
  end if;
  v_id := public.guardar_orden_venta(p_orden_id,p_codigo,p_fecha,p_fecha_salida,
    p_cliente_id,p_mercado,p_pais_destino,p_contenedor,p_observaciones,p_lineas);
  update public.ordenes_venta set numero_cliente=p_numero_cliente, moneda=case when p_lineas->0->>'moneda'='CRC' then 'CRC'::public.moneda else 'USD'::public.moneda end where id=v_id;
  return v_id;
end;
$$;
create or replace function public.finalizar_orden_venta(p_orden_id uuid) returns numeric
language plpgsql security definer set search_path='' as $$
declare v_o public.ordenes_venta%rowtype; v_l record; v_monto numeric:=0; v_asignadas integer; v_pendientes integer;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar pedidos'; end if;
  select * into v_o from public.ordenes_venta where id=p_orden_id for update;
  if not found then raise exception 'No se encontró el pedido'; end if;
  if v_o.finalizada_en is not null then raise exception 'Este pedido ya está finalizado'; end if;
  if v_o.cliente_id is null then raise exception 'Seleccione el cliente antes de finalizar'; end if;
  if not exists(select 1 from public.ordenes_venta_lineas where orden_venta_id=p_orden_id) then raise exception 'Agregue líneas al pedido'; end if;
  for v_l in select * from public.ordenes_venta_lineas where orden_venta_id=p_orden_id for update loop
    select coalesce(sum(r.cajas),0),count(*) filter(where b.finalizada_en is null)
      into v_asignadas,v_pendientes from public.boleta_rendimientos r
      join public.boletas_entrada b on b.id=r.boleta_id where r.orden_venta_linea_id=v_l.id;
    if v_asignadas<>v_l.cantidad_cajas then raise exception 'Faltan cajas en %: % de %',v_l.producto,v_asignadas,v_l.cantidad_cajas; end if;
    if v_pendientes>0 then raise exception 'Finalice las boletas que alimentan % antes de cerrar el pedido',v_l.producto; end if;
    if v_l.precio_caja is null or v_l.precio_caja<=0 then raise exception 'Falta precio de venta de %',v_l.producto; end if;
    v_monto:=v_monto+v_l.total;
  end loop;
  update public.ordenes_venta set finalizada_en=now(),finalizada_por=(select auth.uid()),monto_cxc=round(v_monto,2) where id=p_orden_id;
  return round(v_monto,2);
end;
$$;
create or replace view public.cxc_operativa with (security_invoker=true) as
select 'venta_exportacion'::text origen,o.id origen_id,o.codigo,o.fecha,c.nombre contraparte,o.moneda::text moneda,
  o.monto_cxc::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_exportacion' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  'Pedido finalizado'::text etapa
from public.ordenes_venta o left join public.clientes c on c.id=o.cliente_id where o.finalizada_en is not null
union all
select 'venta_local',v.id,v.codigo,v.fecha,v.comprador,v.moneda,
  coalesce((select sum(s.subtotal) from public.ventas_segundas s where s.venta_local_id=v.id),0)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_local' and a.origen_id=v.id),0)::numeric(16,2),
  'Venta registrada'
from public.ventas_locales v;
