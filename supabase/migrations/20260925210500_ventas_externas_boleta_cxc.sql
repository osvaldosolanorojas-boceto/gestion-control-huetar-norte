-- Ventas de ñampí sin pedido, vinculadas a una boleta y cobrables como venta local.
create table public.ventas_externas_boleta (
  id uuid primary key default gen_random_uuid(),
  venta_local_id uuid not null unique references public.ventas_locales(id),
  boleta_id uuid not null references public.boletas_entrada(id),
  producto text not null check (producto in ('Ñampí','Cabeza de ñampí')),
  cantidad numeric(14,3) not null check(cantidad>0),
  unidad text not null check(unidad in ('Sacos','Quintales (46 kg)')),
  peso_saco_kg numeric(12,3) check(peso_saco_kg>0),
  precio_unitario numeric(14,2) not null check(precio_unitario>0),
  subtotal numeric(16,2) not null check(subtotal>0),
  check ((unidad='Sacos' and cantidad=trunc(cantidad) and peso_saco_kg is not null)
    or (unidad='Quintales (46 kg)' and peso_saco_kg is null))
);
create index ventas_externas_boleta_boleta_idx on public.ventas_externas_boleta(boleta_id);
alter table public.ventas_externas_boleta enable row level security;
grant select,insert on public.ventas_externas_boleta to authenticated;
create policy ventas_externas_boleta_oficina on public.ventas_externas_boleta for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create or replace view public.cxc_operativa with (security_invoker=true) as
select 'venta_exportacion'::text origen,o.id origen_id,o.codigo,o.fecha,c.nombre contraparte,o.moneda::text moneda,
  greatest(0,case when o.finalizada_en is null then coalesce((select sum(l.total) from public.ordenes_venta_lineas l where l.orden_venta_id=o.id),0) else coalesce(o.monto_cxc,0) end
    -coalesce((select sum(n.monto) from public.notas_credito_ventas n where n.orden_venta_id=o.id),0))::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_exportacion' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  case when o.finalizada_en is null then 'Pedido previsto' else 'Pedido finalizado' end::text etapa,
  o.fecha_salida,(coalesce(o.fecha_salida,o.fecha)+o.plazo_pago_dias)::date fecha_vencimiento,
  o.plazo_pago_dias,
  coalesce((select sum(n.monto) from public.notas_credito_ventas n where n.orden_venta_id=o.id),0)::numeric(16,2) notas_credito
from public.ordenes_venta o left join public.clientes c on c.id=o.cliente_id
where o.estado is distinct from 'Anulada'
union all
select 'venta_local',v.id,v.codigo,v.fecha,v.comprador,v.moneda,
  (coalesce((select sum(s.subtotal) from public.ventas_segundas s where s.venta_local_id=v.id),0)+coalesce((select sum(e.subtotal) from public.ventas_externas_boleta e where e.venta_local_id=v.id),0))::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_local' and a.origen_id=v.id),0)::numeric(16,2),
  'Venta registrada',v.fecha,v.fecha,0,0::numeric(16,2)
from public.ventas_locales v
union all
select 'saldo_productor',o.id,o.codigo,o.fecha,coalesce(o.productor_nombre,p.nombre,'Productor'), 'CRC',
  greatest(0,coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)
    +coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)-cx.monto)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='saldo_productor' and a.origen_id=o.id),0)::numeric(16,2),
  'Adelanto superior a compra',o.fecha,o.fecha,0,0::numeric(16,2)
from public.ordenes_compra o join public.cxp_operativa cx on cx.origen='compra_campo' and cx.origen_id=o.id
left join public.proveedores p on p.id=o.proveedor_id
where coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)
    +coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)>cx.monto
union all
select case when m.tipo='cobrar' then 'cuenta_manual_cobrar' else 'cuenta_manual_pagar' end,
 m.id,m.codigo,m.fecha,m.contraparte,m.moneda,m.monto,
 coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen=case when m.tipo='cobrar' then 'cuenta_manual_cobrar' else 'cuenta_manual_pagar' end and a.origen_id=m.id),0)::numeric(16,2),
 'Registro manual',m.fecha,m.fecha_vencimiento,0,0::numeric(16,2)
from public.cuentas_manuales m where m.tipo='cobrar';

-- Guardar boleta y ventas externas en la misma transacción: ninguna venta queda huérfana.
create function public.guardar_boleta_con_ventas_externas(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text,
  p_muestra numeric[],p_tara_kg numeric,p_merma_kg numeric,p_ventas_directas jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_line jsonb; v_order public.ordenes_compra%rowtype; v_sale uuid; v_qty numeric; v_price numeric; v_weight numeric; v_unit text; v_product text; v_buyer text; v_currency text;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'No tiene permiso para registrar la boleta y su venta'; end if;
  if p_ventas_directas is null or pg_catalog.jsonb_typeof(p_ventas_directas)<>'array' then raise exception 'Ventas externas inválidas'; end if;
  select * into v_order from public.ordenes_compra where id=p_orden_compra_id for update;
  if not found or v_order.producto not in ('Ñampí','Cabeza de ñampí') or v_order.tipo_compra='En pie' then raise exception 'Seleccione una compra de ñampí a rendimiento'; end if;
  if pg_catalog.jsonb_array_length(p_ventas_directas)>0 and p_boleta_id is not null and exists(select 1 from public.boletas_entrada where id=p_boleta_id and finalizada_en is not null) then raise exception 'La boleta finalizada no admite nuevas ventas'; end if;
  if pg_catalog.jsonb_array_length(p_ventas_directas)>0 and coalesce(v_order.precio_campo,0)<=0 then raise exception 'Falta el precio de compra por quintal para pagar al productor el producto vendido fuera'; end if;
  -- Validar antes de guardar la boleta. Un error revierte toda la transacción.
  for v_line in select value from pg_catalog.jsonb_array_elements(p_ventas_directas) loop
    v_qty:=(v_line->>'cantidad')::numeric; v_price:=(v_line->>'precio_unitario')::numeric;
    v_weight:=nullif(v_line->>'peso_saco_kg','')::numeric; v_unit:=v_line->>'unidad';
    v_product:=v_line->>'producto'; v_buyer:=pg_catalog.btrim(v_line->>'comprador'); v_currency:=v_line->>'moneda';
    if v_product<>v_order.producto or nullif(v_buyer,'') is null or v_qty is null or v_qty<=0 or v_price is null or v_price<=0
      or v_currency not in ('CRC','USD') or (v_line->>'fecha')::date is null
      or not ((v_unit='Sacos' and v_qty=trunc(v_qty) and v_weight>0) or (v_unit='Quintales (46 kg)' and v_weight is null)) then
      raise exception 'Revise producto, comprador, sacos, peso, precio, moneda y fecha';
    end if;
  end loop;
  v_id:=public.guardar_boleta_con_muestra(p_boleta_id,p_codigo,p_orden_compra_id,p_fecha_hora,p_fecha_labor,p_inicio_proceso,p_fin_proceso,
    p_turno,p_clima,p_linea_proceso,p_encargado,p_encargado_banda,p_condicion,p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,
    p_observaciones,p_trabajos,p_rendimientos,p_tratamiento_cera,p_muestra,p_tara_kg,p_merma_kg);
  for v_line in select value from pg_catalog.jsonb_array_elements(p_ventas_directas) loop
    v_qty:=(v_line->>'cantidad')::numeric; v_price:=(v_line->>'precio_unitario')::numeric;
    insert into public.ventas_locales(codigo,fecha,comprador,moneda,observaciones,registrado_por)
      values('VE-'||pg_catalog.replace(pg_catalog.gen_random_uuid()::text,'-',''),(v_line->>'fecha')::date,pg_catalog.btrim(v_line->>'comprador'),v_line->>'moneda',
        'Venta externa de '||(v_line->>'producto')||' · boleta '||p_codigo,(select auth.uid())) returning id into v_sale;
    insert into public.ventas_externas_boleta(venta_local_id,boleta_id,producto,cantidad,unidad,peso_saco_kg,precio_unitario,subtotal)
      values(v_sale,v_id,v_line->>'producto',v_qty,v_line->>'unidad',nullif(v_line->>'peso_saco_kg','')::numeric,v_price,pg_catalog.round(v_qty*v_price,2));
  end loop;
  return v_id;
end;
$$;
revoke all on function public.guardar_boleta_con_ventas_externas(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[],numeric,numeric,jsonb) from public,anon;
grant execute on function public.guardar_boleta_con_ventas_externas(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[],numeric,numeric,jsonb) to authenticated;

-- El productor cobra el peso vendido fuera, incluso antes de finalizar la boleta.
create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  greatest(0,coalesce(sum(b.monto_cxp),0)+coalesce((select sum((case when e.unidad='Sacos' then e.cantidad*e.peso_saco_kg else e.cantidad*46 end)/46*o.precio_campo) from public.ventas_externas_boleta e join public.boletas_entrada be on be.id=e.boleta_id where be.orden_compra_id=o.id),0)-o.rebaja_planilla_flete)::numeric(16,2) monto,
  least(greatest(0,coalesce(sum(b.monto_cxp),0)+coalesce((select sum((case when e.unidad='Sacos' then e.cantidad*e.peso_saco_kg else e.cantidad*46 end)/46*o.precio_campo) from public.ventas_externas_boleta e join public.boletas_entrada be on be.id=e.boleta_id where be.orden_compra_id=o.id),0)-o.rebaja_planilla_flete),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa,o.producto
from public.ordenes_compra o left join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra is distinct from 'Puesto en camión' and (o.tipo_compra is distinct from 'En campo' or o.campo_promedio_caja_kg is null) and not (o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
  and (b.id is not null or exists(select 1 from public.ventas_externas_boleta e join public.boletas_entrada be on be.id=e.boleta_id where be.orden_compra_id=o.id))
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,o.precio_en_pie)::numeric(16,2),
  least(greatest(0,o.precio_en_pie),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2),
  'Ñampí en pie · rendimiento abierto'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie' and o.precio_en_pie>0
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round(o.cantidad_comprada*o.peso_caja_camion_kg/46*o.precio_puesto_camion,2)-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,round(o.cantidad_comprada*o.peso_caja_camion_kg/46*o.precio_puesto_camion,2)-o.rebaja_planilla_flete),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2),
  'Puesto en camión · precio fijo'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='Puesto en camión'
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round((o.cantidad_comprada*greatest(0,o.campo_promedio_caja_kg-o.campo_tara_caja_kg-o.campo_tierra_caja_kg)/46*o.precio_campo)
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2))::numeric(16,2),
  least(greatest(0,round((o.cantidad_comprada*greatest(0,o.campo_promedio_caja_kg-o.campo_tara_caja_kg-o.campo_tierra_caja_kg)/46*o.precio_campo)
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2)),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2),
  'En campo · pesaje pactado'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='En campo' and o.producto='Yuca' and o.campo_promedio_caja_kg is not null
union all
select 'flete_compra'::text,o.id,o.codigo,o.fecha,
  t.nombre,'CRC'::text,o.flete::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='flete_compra' and a.origen_id=o.id),0)::numeric(16,2),
  'Flete de compra'::text,o.producto
from public.ordenes_compra o join public.proveedores t on t.id=o.flete_proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.flete>0
union all
select 'planilla_compra'::text,o.id,o.codigo,o.fecha,
  p.nombre,'CRC'::text,(coalesce(o.cuadrilla_arranca,0)+case when o.tipo_compra='En campo' then o.campo_encargados+o.campo_otros_costos else 0 end)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='planilla_compra' and a.origen_id=o.id),0)::numeric(16,2),
  'Planilla de arranca'::text,o.producto
from public.ordenes_compra o join public.proveedores p on p.id=o.planilla_proveedor_id
where coalesce(o.estado,'')<>'Anulada' and ((o.tipo_compra='En campo' and o.producto='Yuca' and o.campo_promedio_caja_kg is not null and coalesce(o.cuadrilla_arranca,0)+o.campo_encargados+o.campo_otros_costos>0) or (o.tipo_compra='En pie' and o.producto in ('Ñampí','Cabeza de ñampí') and coalesce(o.cuadrilla_arranca,0)>0))
union all
select 'cuenta_manual_pagar'::text,m.id,m.codigo,m.fecha,m.contraparte,m.moneda,
  m.monto,coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='cuenta_manual_pagar' and a.origen_id=m.id),0)::numeric(16,2),
  'Registro manual'::text,null::text as producto
from public.cuentas_manuales m where m.tipo='pagar';

-- Mostrar a planta únicamente las ventas asociadas a la boleta que está editando.
create function public.ventas_externas_de_boleta(p_boleta_id uuid)
returns table(id uuid,fecha date,comprador text,producto text,cantidad numeric,unidad text,peso_saco_kg numeric,precio_unitario numeric,moneda text)
language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  return query select e.id,v.fecha,v.comprador,e.producto,e.cantidad,e.unidad,e.peso_saco_kg,e.precio_unitario,v.moneda
    from public.ventas_externas_boleta e join public.ventas_locales v on v.id=e.venta_local_id
    where e.boleta_id=p_boleta_id order by v.fecha,e.id;
end;
$$;
revoke all on function public.ventas_externas_de_boleta(uuid) from public,anon;
grant execute on function public.ventas_externas_de_boleta(uuid) to authenticated;
