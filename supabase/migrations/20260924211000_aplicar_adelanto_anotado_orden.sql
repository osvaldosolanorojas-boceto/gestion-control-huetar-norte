-- El adelanto anotado como pagado en la orden reduce su saldo sin requerir banco.
-- GREATEST evita contarlo dos veces si después se registra el mismo desembolso.
create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete)::numeric(16,2) monto,
  least(greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa,o.producto
from public.ordenes_compra o join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra is distinct from 'Puesto en camión' and (o.tipo_compra is distinct from 'En campo' or o.campo_promedio_caja_kg is null) and not (o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
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


