-- Liquidación de campo independiente del rendimiento obtenido después en planta.
alter table public.ordenes_compra
  add column campo_promedio_caja_kg numeric(12,3),
  add column campo_tara_caja_kg numeric(12,3) not null default 0,
  add column campo_tierra_caja_kg numeric(12,3) not null default 0,
  add column campo_muestra_cajas jsonb not null default '[]'::jsonb,
  add column campo_sacos integer not null default 0,
  add column campo_promedio_saco_kg numeric(12,3) not null default 0,
  add column campo_descuento_rechazo_pct numeric(5,2) not null default 10,
  add column campo_precio_rechazo numeric(14,2) not null default 0,
  add column campo_muestra_sacos jsonb not null default '[]'::jsonb,
  add column campo_encargados numeric(14,2) not null default 0,
  add column campo_otros_costos numeric(14,2) not null default 0,
  add column campo_otros_detalle text;
alter table public.ordenes_compra add constraint compra_en_campo_pesos_validos check (
  tipo_compra is distinct from 'En campo' or producto is distinct from 'Yuca' or campo_promedio_caja_kg is null or
  (unidad='Cajas' and cantidad_comprada>0 and cantidad_comprada=trunc(cantidad_comprada)
   and campo_promedio_caja_kg>campo_tara_caja_kg+campo_tierra_caja_kg
   and campo_tara_caja_kg>=0 and campo_tierra_caja_kg>=0 and precio_campo>0
   and campo_sacos>=0 and campo_promedio_saco_kg>=0
   and campo_descuento_rechazo_pct>=0 and campo_descuento_rechazo_pct<100
   and campo_precio_rechazo>=0 and (campo_sacos=0 or campo_promedio_saco_kg>0 and campo_precio_rechazo>0)
   and campo_encargados>=0 and campo_otros_costos>=0
   and rebaja_planilla_flete=coalesce(cuadrilla_arranca,0)+coalesce(flete,0)+campo_encargados+campo_otros_costos)) not valid;

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
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2)-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,round((o.cantidad_comprada*greatest(0,o.campo_promedio_caja_kg-o.campo_tara_caja_kg-o.campo_tierra_caja_kg)/46*o.precio_campo)
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2)-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
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
select 'cuenta_manual_pagar'::text,m.id,m.codigo,m.fecha,m.contraparte,m.moneda,
  m.monto,coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='cuenta_manual_pagar' and a.origen_id=m.id),0)::numeric(16,2),
  'Registro manual'::text,null::text as producto
from public.cuentas_manuales m where m.tipo='pagar';





create or replace function public.recalcular_boletas_por_precios_compra() returns trigger
language plpgsql security invoker set search_path='' as $$
declare v_b record; v_r record; v_price numeric; v_amount numeric; v_paid numeric; v_total numeric;
begin
  if (old.precio_europa,old.precio_eeuu,old.precio_segunda_gruesa,old.precio_segunda_menuda,
      old.precio_rechazo,old.precio_campo,old.precio_en_pie)
      is not distinct from
     (new.precio_europa,new.precio_eeuu,new.precio_segunda_gruesa,new.precio_segunda_menuda,
      new.precio_rechazo,new.precio_campo,new.precio_en_pie) then return new; end if;
  if new.tipo_compra in ('Puesto en camión','En campo') then return new; end if;
  perform set_config('app.corrigiendo_boleta','completa',true);
  for v_b in select id from public.boletas_entrada where orden_compra_id=new.id and finalizada_en is not null order by id for update loop
    v_amount:=0;
    if new.tipo_compra='En pie' then
      if new.precio_en_pie is null or new.precio_en_pie<=0 then raise exception 'Falta el precio de compra en pie'; end if;
      v_amount:=new.precio_en_pie;
    else
      for v_r in select calidad,kg_resultado,paga_productor from public.boleta_rendimientos where boleta_id=v_b.id loop
        if not v_r.paga_productor then continue; end if;
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when new.producto in ('Ñampí','Cabeza de ñampí') then new.precio_campo
          when v_r.calidad='Exportable Europa' then new.precio_europa
          when v_r.calidad='Exportable estadounidense' then new.precio_eeuu
          when v_r.calidad='Segunda gruesa' then new.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then new.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then new.precio_rechazo
          else new.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+v_r.kg_resultado/46*v_price;
      end loop;
    end if;
    update public.boletas_entrada set monto_cxp=round(v_amount,2) where id=v_b.id;
  end loop;
  select coalesce(sum(monto_cxp),0) into v_total from public.boletas_entrada where orden_compra_id=new.id and finalizada_en is not null;
  select coalesce(sum(monto),0) into v_paid from public.aplicaciones_bancarias where origen='compra_campo' and origen_id=new.id;
  if greatest(0,v_total-coalesce(new.rebaja_planilla_flete,0))<v_paid then
    raise exception 'El nuevo total sería menor que los pagos registrados';
  end if;
  perform set_config('app.corrigiendo_boleta','off',true);
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
  return new;
end;
$$;

-- No permitir corregir una compra histórica ya liquidada pasando al cálculo nuevo.
create function public.proteger_liquidacion_campo() returns trigger language plpgsql set search_path='' as $$
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
      +(new.campo_sacos*new.campo_promedio_saco_kg*(1-new.campo_descuento_rechazo_pct/100)/46*new.campo_precio_rechazo),2)-new.rebaja_planilla_flete) then
      raise exception 'El nuevo total sería menor que los pagos y adelantos registrados';
    end if;
  end if;
  return new;
end;
$$;
create trigger proteger_liquidacion_campo before update on public.ordenes_compra
for each row execute function public.proteger_liquidacion_campo();

create or replace function public.finalizar_boleta_entrada(p_boleta_id uuid) returns numeric
language plpgsql security definer set search_path='' as $$
declare v_b public.boletas_entrada%rowtype; v_o public.ordenes_compra%rowtype; v_r record; v_price numeric; v_amount numeric:=0;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar boletas'; end if;
  select * into v_b from public.boletas_entrada where id=p_boleta_id for update;
  if not found then raise exception 'No se encontró la boleta'; end if;
  if v_b.finalizada_en is not null then raise exception 'Esta boleta ya está finalizada'; end if;
  if v_b.orden_compra_id is null then raise exception 'Enlace la orden de compra antes de finalizar'; end if;
  select * into v_o from public.ordenes_compra where id=v_b.orden_compra_id for update;
  if v_b.fin_proceso is null then raise exception 'Registre el final del proceso antes de finalizar'; end if;
  if not exists(select 1 from public.boleta_rendimientos where boleta_id=p_boleta_id) then raise exception 'Registre al menos un rendimiento antes de finalizar'; end if;
  if v_o.producto in ('Ñampí','Cabeza de ñampí') and v_o.tipo_compra='En pie' then
    raise exception 'El ñampí en pie se paga por lote desde la orden; sus boletas permanecen abiertas para registrar todo el rendimiento';
  end if;
  if (v_o.tipo_compra='Puesto en camión' or v_o.tipo_compra='En campo' and v_o.campo_promedio_caja_kg is not null) then
    -- La deuda pactada se registra al guardar la orden, nunca por rendimiento.
    v_amount:=0;
  elsif v_o.tipo_compra='En pie' then
    if v_o.precio_en_pie is null or v_o.precio_en_pie<=0 then raise exception 'Falta el precio de compra en pie'; end if;
    if exists(select 1 from public.boletas_entrada where orden_compra_id=v_o.id and finalizada_en is not null) then
      raise exception 'Esta compra en pie ya tiene una boleta cerrada; revise su liquidación';
    end if;
    v_amount:=v_o.precio_en_pie;
  else
    for v_r in select calidad,kg_resultado,paga_productor from public.boleta_rendimientos where boleta_id=p_boleta_id loop
      if v_r.paga_productor then
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when v_o.producto in ('Ñampí','Cabeza de ñampí') then v_o.precio_campo
          when v_r.calidad='Exportable Europa' then v_o.precio_europa
          when v_r.calidad='Exportable estadounidense' then v_o.precio_eeuu
          when v_r.calidad='Segunda gruesa' then v_o.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then v_o.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then v_o.precio_rechazo
          else v_o.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+v_r.kg_resultado/46*v_price;
      end if;
    end loop;
  end if;
  update public.boletas_entrada set finalizada_en=now(),finalizada_por=(select auth.uid()),monto_cxp=round(v_amount,2) where id=p_boleta_id;
  return round(v_amount,2);
end;
$$;

create or replace function public.corregir_boleta_finalizada_completa(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_b public.boletas_entrada%rowtype; v_o public.ordenes_compra%rowtype;
  v_r record; v_price numeric; v_amount numeric:=0; v_aplicado numeric; v_total numeric;
begin
  if not exists(select 1 from public.perfiles where id=(select auth.uid()) and activo and rol in ('administrador','oficina')) then
    raise exception 'Solo administración u oficina puede corregir boletas finalizadas';
  end if;
  select * into v_b from public.boletas_entrada where id=p_boleta_id for update;
  if not found or v_b.finalizada_en is null then raise exception 'No se encontró la boleta finalizada'; end if;
  if p_codigo is distinct from v_b.codigo then raise exception 'No se puede cambiar el código de la boleta'; end if;
  if p_fin_proceso is null then raise exception 'La boleta finalizada requiere la hora de fin del proceso'; end if;
  if p_orden_compra_id is distinct from v_b.orden_compra_id and exists(
    select 1 from public.aplicaciones_bancarias where origen='compra_campo' and origen_id=v_b.orden_compra_id
  ) then raise exception 'La compra anterior ya tiene pagos: no se puede cambiar su orden de compra'; end if;
  if p_rendimientos is null or jsonb_typeof(p_rendimientos)<>'array' or jsonb_array_length(p_rendimientos)=0 then
    raise exception 'La boleta finalizada debe conservar al menos un rendimiento';
  end if;
  select * into v_o from public.ordenes_compra where id=p_orden_compra_id for update;
  if not found or coalesce(v_o.estado,'')='Anulada' then raise exception 'Seleccione una orden de compra válida'; end if;
  if v_o.producto in ('Ñampí','Cabeza de ñampí') and v_o.tipo_compra='En pie' then
    raise exception 'El ñampí en pie se liquida desde la orden y no permite cerrar esta boleta';
  end if;
  if v_o.tipo_compra='En pie' and p_orden_compra_id is distinct from v_b.orden_compra_id and exists(
    select 1 from public.boletas_entrada where orden_compra_id=v_o.id and finalizada_en is not null
  ) then raise exception 'Esta compra en pie ya tiene una boleta finalizada'; end if;
  perform set_config('app.corrigiendo_boleta','completa',true);
  perform private.guardar_boleta_planta(p_boleta_id,p_codigo,p_orden_compra_id,p_fecha_hora,p_fecha_labor,
    p_inicio_proceso,p_fin_proceso,p_turno,p_clima,p_linea_proceso,p_encargado,p_encargado_banda,
    p_condicion,p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,p_observaciones,p_trabajos,p_rendimientos,p_tratamiento_cera);
  if (v_o.tipo_compra='Puesto en camión' or v_o.tipo_compra='En campo' and v_o.campo_promedio_caja_kg is not null) then
    v_amount:=0;
  elsif v_o.tipo_compra='En pie' then
    if v_o.precio_en_pie is null or v_o.precio_en_pie<=0 then raise exception 'Falta el precio de compra en pie'; end if;
    v_amount:=v_o.precio_en_pie;
  else
    for v_r in select calidad,kg_resultado,paga_productor from public.boleta_rendimientos where boleta_id=p_boleta_id loop
      if v_r.paga_productor then
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when v_o.producto in ('Ñampí','Cabeza de ñampí') then v_o.precio_campo
          when v_r.calidad='Exportable Europa' then v_o.precio_europa
          when v_r.calidad='Exportable estadounidense' then v_o.precio_eeuu
          when v_r.calidad='Segunda gruesa' then v_o.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then v_o.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then v_o.precio_rechazo
          else v_o.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+v_r.kg_resultado/46*v_price;
      end if;
    end loop;
  end if;
  update public.boletas_entrada set monto_cxp=round(v_amount,2) where id=p_boleta_id;
  -- Nunca dejar una cuenta por pagar menor que lo ya pagado.
  select coalesce(sum(monto_cxp),0) - coalesce(v_o.rebaja_planilla_flete,0) into v_total
    from public.boletas_entrada where orden_compra_id=v_o.id and finalizada_en is not null;
  if v_o.tipo_compra='En campo' and v_o.campo_promedio_caja_kg is not null then
    select monto into v_total from public.cxp_operativa where origen='compra_campo' and origen_id=v_o.id;
  end if;
  select coalesce(sum(monto),0) into v_aplicado from public.aplicaciones_bancarias
    where origen='compra_campo' and origen_id=v_o.id;
  if greatest(0,v_total)<v_aplicado then raise exception 'El nuevo total sería menor que los pagos ya registrados; revise la cuenta antes de reducir la boleta'; end if;
  perform set_config('app.corrigiendo_boleta','off',true);
  return p_boleta_id;
end;
$$;
