-- La yuca y el rechazo son deuda al productor; arranca y flete son costos de la exportadora.
alter table public.ordenes_compra add column planilla_proveedor_id uuid references public.proveedores(id);
alter table public.ordenes_compra drop constraint compra_en_campo_pesos_validos;
alter table public.ordenes_compra add constraint compra_en_campo_pesos_validos check (
  tipo_compra is distinct from 'En campo' or producto is distinct from 'Yuca' or campo_promedio_caja_kg is null or
  (unidad='Cajas' and cantidad_comprada>0 and cantidad_comprada=trunc(cantidad_comprada)
   and campo_promedio_caja_kg>campo_tara_caja_kg+campo_tierra_caja_kg
   and campo_tara_caja_kg>=0 and campo_tierra_caja_kg>=0 and precio_campo>0
   and campo_sacos>=0 and campo_promedio_saco_kg>=0
   and campo_descuento_rechazo_pct>=0 and campo_descuento_rechazo_pct<100
   and campo_precio_rechazo>=0 and (campo_sacos=0 or campo_promedio_saco_kg>0 and campo_precio_rechazo>0)
   and campo_encargados>=0 and campo_otros_costos>=0 and rebaja_planilla_flete=0
   and (coalesce(cuadrilla_arranca,0)+campo_encargados+campo_otros_costos=0 or planilla_proveedor_id is not null))) not valid;
alter table public.aplicaciones_bancarias drop constraint aplicaciones_bancarias_origen_check;
alter table public.aplicaciones_bancarias add constraint aplicaciones_bancarias_origen_check
check(origen in ('venta_exportacion','venta_local','compra_campo','flete_compra','planilla_compra','saldo_productor','cuenta_manual_cobrar','cuenta_manual_pagar'));
update public.ordenes_compra set rebaja_planilla_flete=0
where tipo_compra='En campo' and producto='Yuca' and campo_promedio_caja_kg is not null and rebaja_planilla_flete<>0;

create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete)::numeric(16,2) monto,
  least(greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa,o.producto
from public.ordenes_compra o join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra is distinct from 'Puesto en camión' and (o.tipo_compra is distinct from 'En campo' or o.campo_promedio_caja_kg is null) and not (o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,o.precio_en_pie-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,o.precio_en_pie-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
  'Ñampí en pie · rendimiento abierto'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie' and o.precio_en_pie>0
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round(o.cantidad_comprada*o.peso_caja_camion_kg/46*o.precio_puesto_camion,2)-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,round(o.cantidad_comprada*o.peso_caja_camion_kg/46*o.precio_puesto_camion,2)-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
  'Puesto en camión · precio fijo'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='Puesto en camión'
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round((o.cantidad_comprada*greatest(0,o.campo_promedio_caja_kg-o.campo_tara_caja_kg-o.campo_tierra_caja_kg)/46*o.precio_campo)
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2))::numeric(16,2),
  least(greatest(0,round((o.cantidad_comprada*greatest(0,o.campo_promedio_caja_kg-o.campo_tara_caja_kg-o.campo_tierra_caja_kg)/46*o.precio_campo)
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2)),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
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
  p.nombre,'CRC'::text,(coalesce(o.cuadrilla_arranca,0)+o.campo_encargados+o.campo_otros_costos)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='planilla_compra' and a.origen_id=o.id),0)::numeric(16,2),
  'Planilla de arranca'::text,o.producto
from public.ordenes_compra o join public.proveedores p on p.id=o.planilla_proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='En campo' and o.producto='Yuca' and o.campo_promedio_caja_kg is not null and coalesce(o.cuadrilla_arranca,0)+o.campo_encargados+o.campo_otros_costos>0
union all
select 'cuenta_manual_pagar'::text,m.id,m.codigo,m.fecha,m.contraparte,m.moneda,
  m.monto,coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='cuenta_manual_pagar' and a.origen_id=m.id),0)::numeric(16,2),
  'Registro manual'::text,null::text as producto
from public.cuentas_manuales m where m.tipo='pagar';

create or replace function public.registrar_movimiento_bancario(p_cuenta_id uuid,p_fecha date,p_tipo text,p_monto numeric,p_concepto text,p_referencia text,p_aplicaciones jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_moneda text; v_mov uuid; v_app jsonb; v_origen text; v_id uuid; v_amount numeric; v_due numeric; v_used numeric:=0; v_tipo text;
begin
  if p_tipo not in ('ingreso','egreso') or p_monto is null or p_monto<=0 or p_fecha is null or nullif(trim(p_concepto),'') is null then raise exception 'Complete tipo, monto, fecha y concepto'; end if;
  select moneda into v_moneda from public.cuentas_bancarias where id=p_cuenta_id and activo;
  if v_moneda is null then raise exception 'Cuenta bancaria no disponible'; end if;
  if p_aplicaciones is not null and jsonb_typeof(p_aplicaciones)<>'array' then raise exception 'Aplicaciones inválidas'; end if;
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
    values(p_cuenta_id,p_fecha,p_tipo,p_monto,trim(p_concepto),nullif(trim(p_referencia),''),(select auth.uid())) returning id into v_mov;
  for v_app in select value from jsonb_array_elements(coalesce(p_aplicaciones,'[]'::jsonb)) loop
    v_origen:=v_app->>'origen';v_id:=(v_app->>'origen_id')::uuid;v_amount:=(v_app->>'monto')::numeric;
    if v_amount is null or v_amount<=0 or v_amount<>round(v_amount,2) then raise exception 'Monto aplicado inválido'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_origen||v_id::text,0));
    if v_origen in ('venta_exportacion','venta_local','saldo_productor','cuenta_manual_cobrar') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxc_operativa where origen=v_origen and origen_id=v_id and etapa<>'Pedido previsto';
      if p_tipo<>'ingreso' then raise exception 'Un cobro debe ser un ingreso'; end if;
    elsif v_origen in ('compra_campo','flete_compra','planilla_compra','cuenta_manual_pagar') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxp_operativa where origen=v_origen and origen_id=v_id;
      if p_tipo<>'egreso' then raise exception 'Un pago debe ser un egreso'; end if;
    else raise exception 'Origen financiero inválido'; end if;
    if v_tipo is null or v_tipo<>v_moneda or v_amount>v_due then raise exception 'Documento no disponible, moneda distinta o monto superior al saldo'; end if;
    v_used:=v_used+v_amount;
    if v_used>p_monto then raise exception 'Las aplicaciones superan el movimiento bancario'; end if;
    insert into public.aplicaciones_bancarias(movimiento_id,origen,origen_id,monto) values(v_mov,v_origen,v_id,v_amount);
  end loop;
  return v_mov;
end;
$$;

create or replace function public.validar_aplicacion_bancaria() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_m public.movimientos_bancarios%rowtype; v_moneda text; v_origen_moneda text; v_due numeric; v_used numeric;
begin
  -- Bloqueos consultivos evitan requerir permiso UPDATE sobre un movimiento ya registrado.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.movimiento_id::text,1));
  select * into v_m from public.movimientos_bancarios where id=new.movimiento_id;
  if not found then raise exception 'Movimiento bancario no disponible'; end if;
  select moneda into v_moneda from public.cuentas_bancarias where id=v_m.cuenta_id;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.origen||new.origen_id::text,0));
  if new.origen in ('venta_exportacion','venta_local','saldo_productor','cuenta_manual_cobrar') then
    if v_m.tipo<>'ingreso' then raise exception 'Una venta solo puede aplicarse a un ingreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxc_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Pedido previsto';
  elsif new.origen in ('compra_campo','flete_compra','planilla_compra','cuenta_manual_pagar') then
    if v_m.tipo<>'egreso' then raise exception 'Una compra solo puede aplicarse a un egreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxp_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Faltan precios';
  end if;
  if v_origen_moneda is null or v_origen_moneda<>v_moneda or new.monto>v_due then raise exception 'Documento sin saldo suficiente o moneda distinta'; end if;
  select coalesce(sum(monto),0) into v_used from public.aplicaciones_bancarias where movimiento_id=new.movimiento_id;
  if v_used+new.monto>v_m.monto then raise exception 'Aplicaciones superiores al movimiento bancario'; end if;
  return new;
end;
$$;

create or replace function public.proteger_importes_compra_pagada() returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=old.id)
     and (old.campo_promedio_caja_kg is distinct from new.campo_promedio_caja_kg
       or old.campo_tara_caja_kg is distinct from new.campo_tara_caja_kg
       or old.campo_tierra_caja_kg is distinct from new.campo_tierra_caja_kg
       or old.campo_sacos is distinct from new.campo_sacos
       or old.campo_promedio_saco_kg is distinct from new.campo_promedio_saco_kg
       or old.campo_descuento_rechazo_pct is distinct from new.campo_descuento_rechazo_pct
       or old.campo_precio_rechazo is distinct from new.campo_precio_rechazo
       or old.precio_campo is distinct from new.precio_campo
       or old.cantidad_comprada is distinct from new.cantidad_comprada
       or old.peso_caja_camion_kg is distinct from new.peso_caja_camion_kg
       or old.precio_puesto_camion is distinct from new.precio_puesto_camion
       or old.precio_en_pie is distinct from new.precio_en_pie
       or old.rebaja_planilla_flete is distinct from new.rebaja_planilla_flete
       or old.proveedor_id is distinct from new.proveedor_id
       or old.tipo_compra is distinct from new.tipo_compra) then
    raise exception 'La compra tiene pagos aplicados; no puede cambiar el monto ni el productor';
  end if;
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen='flete_compra' and a.origen_id=old.id)
     and (old.flete is distinct from new.flete or old.flete_proveedor_id is distinct from new.flete_proveedor_id) then
    raise exception 'El flete tiene pagos aplicados; no puede cambiar el monto ni el beneficiario';
  end if;
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen='planilla_compra' and a.origen_id=old.id)
     and (old.cuadrilla_arranca is distinct from new.cuadrilla_arranca or old.campo_encargados is distinct from new.campo_encargados or old.campo_otros_costos is distinct from new.campo_otros_costos or old.planilla_proveedor_id is distinct from new.planilla_proveedor_id) then
    raise exception 'La planilla tiene pagos aplicados; no puede cambiar el monto ni el beneficiario';
  end if;
  return new;
end;
$$;


create or replace function public.proteger_liquidacion_campo() returns trigger language plpgsql set search_path='' as $$
declare v_paid numeric;
begin
  if old.tipo_compra='En campo' and old.campo_promedio_caja_kg is null and new.campo_promedio_caja_kg is not null
     and exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is not null) then
    raise exception 'Esta compra de campo ya fue liquidada con el método anterior; no cambie su base de pago';
  end if;
  if new.tipo_compra='En campo' and new.campo_promedio_caja_kg is not null then
    select coalesce(sum(monto),0) into v_paid from public.aplicaciones_bancarias where origen='compra_campo' and origen_id=new.id;
    select v_paid+coalesce(sum(monto),0) into v_paid from public.adelantos_compra where orden_compra_id=new.id;
    if v_paid>greatest(0,round((new.cantidad_comprada*greatest(0,new.campo_promedio_caja_kg-new.campo_tara_caja_kg-new.campo_tierra_caja_kg)/46*new.precio_campo)
      +(new.campo_sacos*new.campo_promedio_saco_kg*(1-new.campo_descuento_rechazo_pct/100)/46*new.campo_precio_rechazo),2)) then
      raise exception 'El nuevo total sería menor que los pagos y adelantos registrados';
    end if;
  end if;
  return new;
end;
$$;
