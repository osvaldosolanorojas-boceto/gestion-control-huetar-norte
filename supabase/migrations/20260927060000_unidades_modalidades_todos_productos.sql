-- Precio por quintal de 46 kg, kilo o caja según producto.
alter table public.ordenes_compra drop constraint if exists compra_camion_detalle_check;
alter table public.ordenes_compra add constraint compra_camion_detalle_check check (
  tipo_compra is distinct from 'Puesto en camión' or
  (cantidad_comprada>0 and precio_puesto_camion>0 and
   ((producto='Yuca' and unidad='Cajas' and cantidad_comprada=trunc(cantidad_comprada) and peso_caja_camion_kg>0)
    or (producto<>'Yuca' and unidad=case when producto='Caña de azúcar' then 'Cajas' when producto in ('Ñampí','Cabeza de ñampí','Malanga lila','Malanga blanca','Malanga taro') then 'Quintales (46 kg)' else 'Kilogramos' end
        and (unidad<>'Cajas' or cantidad_comprada=trunc(cantidad_comprada))))))
not valid;
alter table public.ordenes_compra add constraint compra_unidad_precio_fijo_check check (
  tipo_compra not in ('En campo','Producto listo') or producto='Yuca' and tipo_compra='En campo'
  or cantidad_comprada>0 and precio_campo>0 and unidad=case when producto='Caña de azúcar' then 'Cajas' when producto in ('Ñampí','Cabeza de ñampí','Malanga lila','Malanga blanca','Malanga taro') then 'Quintales (46 kg)' else 'Kilogramos' end
  or tipo_compra='Producto listo' and producto='Yuca' and cantidad_comprada>0 and precio_europa>0 and unidad='Quintales (46 kg)'
) not valid;

CREATE OR REPLACE FUNCTION public.asignar_entrada_programada_en_pie()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_slot public.entradas_programadas_en_pie%rowtype;
begin
  if not exists(select 1 from public.ordenes_compra o where o.id=new.orden_compra_id and o.producto not in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie') then return new; end if;
  select * into v_slot from public.entradas_programadas_en_pie
    where orden_compra_id=new.orden_compra_id and boleta_id is null for update;
  if not found then raise exception 'Administración debe preparar la siguiente entrada en la orden de compra antes de guardar esta boleta'; end if;
  update public.entradas_programadas_en_pie set boleta_id=new.id where id=v_slot.id;
  insert into public.costos_boleta_en_pie(boleta_id,tipo,monto,proveedor_id)
  values(new.id,'planilla',v_slot.planilla_monto,v_slot.planilla_proveedor_id),
        (new.id,'flete',v_slot.flete_monto,v_slot.flete_proveedor_id);
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.corregir_boleta_finalizada_completa(p_boleta_id uuid, p_codigo text, p_orden_compra_id uuid, p_fecha_hora timestamp with time zone, p_fecha_labor date, p_inicio_proceso timestamp with time zone, p_fin_proceso timestamp with time zone, p_turno text, p_clima text, p_linea_proceso smallint, p_encargado text, p_encargado_banda text, p_condicion text, p_cantidad_recipientes numeric, p_tipo_recipiente text, p_promedio_peso numeric, p_observaciones text, p_trabajos jsonb, p_rendimientos jsonb, p_tratamiento_cera text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if v_o.tipo_compra in ('En pie','Puesto en camión','Producto listo') or (v_o.tipo_compra='En campo' and (v_o.producto<>'Yuca' or v_o.campo_promedio_caja_kg is not null)) then
    v_amount:=0;
  else
    for v_r in select calidad,kg_resultado,cajas,paga_productor from public.boleta_rendimientos where boleta_id=p_boleta_id loop
      if v_r.paga_productor then
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when v_o.producto<>'Yuca' then v_o.precio_campo
          when v_r.calidad='Exportable Europa' then v_o.precio_europa
          when v_r.calidad='Exportable estadounidense' then v_o.precio_eeuu
          when v_r.calidad='Segunda gruesa' then v_o.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then v_o.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then v_o.precio_rechazo
          else v_o.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+(case when v_o.producto='Caña de azúcar' then v_r.cajas else v_r.kg_resultado/(case when v_o.producto in ('Yuca','Ñampí','Cabeza de ñampí','Malanga lila','Malanga blanca','Malanga taro') then 46 else 1 end) end)*v_price;
      end if;
    end loop;
  end if;
  update public.boletas_entrada set monto_cxp=round(v_amount,2) where id=p_boleta_id;
  -- Nunca dejar una cuenta por pagar menor que lo ya pagado.
  select coalesce(sum(monto_cxp),0) - coalesce(v_o.rebaja_planilla_flete,0) into v_total
    from public.boletas_entrada where orden_compra_id=v_o.id and finalizada_en is not null;
  if v_o.tipo_compra='En pie' then v_total:=v_o.precio_en_pie; end if;
  select coalesce(sum(monto),0) into v_aplicado from public.aplicaciones_bancarias
    where origen='compra_campo' and origen_id=v_o.id;
  if greatest(0,v_total)<v_aplicado then raise exception 'El nuevo total sería menor que los pagos ya registrados; revise la cuenta antes de reducir la boleta'; end if;
  perform set_config('app.corrigiendo_boleta','off',true);
  return p_boleta_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.finalizar_boleta_entrada(p_boleta_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if v_o.producto not in ('Ñampí','Cabeza de ñampí') and v_o.tipo_compra='En pie' and v_o.en_pie_finalizada_en is null then
    raise exception 'Finalice la compra en pie para cerrar juntas sus boletas';
  end if;
  if v_o.tipo_compra in ('En pie','Puesto en camión','Producto listo') or (v_o.tipo_compra='En campo' and (v_o.producto<>'Yuca' or v_o.campo_promedio_caja_kg is not null)) then
    v_amount:=0;
  else
    for v_r in select calidad,kg_resultado,cajas,paga_productor from public.boleta_rendimientos where boleta_id=p_boleta_id loop
      if v_r.paga_productor then
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when v_o.producto<>'Yuca' then v_o.precio_campo
          when v_r.calidad='Exportable Europa' then v_o.precio_europa
          when v_r.calidad='Exportable estadounidense' then v_o.precio_eeuu
          when v_r.calidad='Segunda gruesa' then v_o.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then v_o.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then v_o.precio_rechazo
          else v_o.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+(case when v_o.producto='Caña de azúcar' then v_r.cajas else v_r.kg_resultado/(case when v_o.producto in ('Yuca','Ñampí','Cabeza de ñampí','Malanga lila','Malanga blanca','Malanga taro') then 46 else 1 end) end)*v_price;
      end if;
    end loop;
  end if;
  update public.boletas_entrada set finalizada_en=now(),finalizada_por=(select auth.uid()),monto_cxp=round(v_amount,2) where id=p_boleta_id;
  return round(v_amount,2);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.finalizar_compra_en_pie(p_orden_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_o public.ordenes_compra%rowtype;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar esta compra'; end if;
  select * into v_o from public.ordenes_compra where id=p_orden_id for update;
  if not found or v_o.tipo_compra<>'En pie'  then raise exception 'Seleccione una compra en pie'; end if;
  if v_o.en_pie_finalizada_en is not null then raise exception 'Esta compra ya está finalizada'; end if;
  if not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=p_orden_id) then
    raise exception 'Registre al menos una boleta o venta externa antes de finalizar';
  end if;
  if v_o.producto not in ('Ñampí','Cabeza de ñampí') and exists(select 1 from public.entradas_programadas_en_pie e where e.orden_compra_id=p_orden_id and e.boleta_id is null) then
    raise exception 'Hay una entrada preparada pendiente de boleta. Regístrela antes de finalizar la compra';
  end if;
  update public.ordenes_compra set en_pie_finalizada_en=now() where id=p_orden_id;
  if v_o.producto not in ('Ñampí','Cabeza de ñampí') then
    perform public.finalizar_boleta_entrada(b.id) from public.boletas_entrada b where b.orden_compra_id=p_orden_id and b.finalizada_en is null;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.ordenes_compra_para_planta(p_orden_compra_id uuid DEFAULT NULL::uuid, p_incluir_vinculadas boolean DEFAULT false)
 RETURNS TABLE(id uuid, codigo text, fecha date, productor_nombre text, producto text, boleta_campo_referencia text, proveedor_id uuid, chofer text, placa text, tipo_compra text, en_pie_finalizada_en timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select o.id,o.codigo,o.fecha,o.productor_nombre,o.producto,o.boleta_campo_referencia,o.proveedor_id,o.chofer,o.placa,o.tipo_compra,o.en_pie_finalizada_en
  from public.ordenes_compra o
  where coalesce(o.estado,'')<>'Anulada' and (o.en_pie_finalizada_en is null or p_incluir_vinculadas or o.id=p_orden_compra_id)
    and (p_incluir_vinculadas
      or o.id=p_orden_compra_id
      or (o.tipo_compra='En pie')
      or not exists (select 1 from public.boletas_entrada b where b.orden_compra_id=o.id))
    and (p_incluir_vinculadas or o.id=p_orden_compra_id or o.producto in ('Ñampí','Cabeza de ñampí') or o.tipo_compra<>'En pie'
      or exists(select 1 from public.entradas_programadas_en_pie e where e.orden_compra_id=o.id and e.boleta_id is null))
  order by o.fecha desc,o.creado_en desc limit 1000;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.recalcular_boletas_por_precios_compra()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_b record; v_r record; v_price numeric; v_amount numeric; v_paid numeric; v_total numeric;
begin
  if (old.precio_europa,old.precio_eeuu,old.precio_segunda_gruesa,old.precio_segunda_menuda,
      old.precio_rechazo,old.precio_campo,old.precio_en_pie)
      is not distinct from
     (new.precio_europa,new.precio_eeuu,new.precio_segunda_gruesa,new.precio_segunda_menuda,
      new.precio_rechazo,new.precio_campo,new.precio_en_pie) then return new; end if;
  if new.tipo_compra in ('Puesto en camión','Producto listo') or (new.tipo_compra='En campo' and (new.producto<>'Yuca' or new.campo_promedio_caja_kg is not null)) then return new; end if;
  perform set_config('app.corrigiendo_boleta','completa',true);
  for v_b in select id from public.boletas_entrada where orden_compra_id=new.id and finalizada_en is not null order by id for update loop
    v_amount:=0;
    if new.tipo_compra='En pie' then
      v_amount:=0;
    else
      for v_r in select calidad,kg_resultado,cajas,paga_productor from public.boleta_rendimientos where boleta_id=v_b.id loop
        if not v_r.paga_productor then continue; end if;
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when new.producto<>'Yuca' then new.precio_campo
          when v_r.calidad='Exportable Europa' then new.precio_europa
          when v_r.calidad='Exportable estadounidense' then new.precio_eeuu
          when v_r.calidad='Segunda gruesa' then new.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then new.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then new.precio_rechazo
          else new.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+(case when new.producto='Caña de azúcar' then v_r.cajas else v_r.kg_resultado/(case when new.producto in ('Yuca','Ñampí','Cabeza de ñampí','Malanga lila','Malanga blanca','Malanga taro') then 46 else 1 end) end)*v_price;
      end loop;
    end if;
    update public.boletas_entrada set monto_cxp=round(v_amount,2) where id=v_b.id;
  end loop;
  select coalesce(sum(monto_cxp),0) into v_total from public.boletas_entrada where orden_compra_id=new.id and finalizada_en is not null;
  if new.tipo_compra='En pie' then v_total:=new.precio_en_pie; end if;
  select coalesce(sum(monto),0) into v_paid from public.aplicaciones_bancarias where origen='compra_campo' and origen_id=new.id;
  if greatest(0,v_total-coalesce(new.rebaja_planilla_flete,0))<v_paid then
    raise exception 'El nuevo total sería menor que los pagos registrados';
  end if;
  perform set_config('app.corrigiendo_boleta','off',true);
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.validar_entrada_programada_en_pie()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if not exists(select 1 from public.ordenes_compra o where o.id=new.orden_compra_id and o.producto not in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie' and o.en_pie_finalizada_en is null) then
    raise exception 'La orden debe ser una compra de yuca en pie abierta';
  end if;
  if new.boleta_id is not null or new.numero<>(select coalesce(max(e.numero),0)+1 from public.entradas_programadas_en_pie e where e.orden_compra_id=new.orden_compra_id) then
    raise exception 'Prepare la siguiente entrada en orden, sin asignar la boleta manualmente';
  end if;
  return new;
end;
$function$
;

create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  greatest(0,coalesce(sum(b.monto_cxp),0)+coalesce((select sum((case when e.unidad='Sacos' then e.cantidad*e.peso_saco_kg else e.cantidad*46 end)/46*o.precio_campo) from public.ventas_externas_boleta e join public.boletas_entrada be on be.id=e.boleta_id where be.orden_compra_id=o.id),0)-o.rebaja_planilla_flete)::numeric(16,2) monto,
  least(greatest(0,coalesce(sum(b.monto_cxp),0)+coalesce((select sum((case when e.unidad='Sacos' then e.cantidad*e.peso_saco_kg else e.cantidad*46 end)/46*o.precio_campo) from public.ventas_externas_boleta e join public.boletas_entrada be on be.id=e.boleta_id where be.orden_compra_id=o.id),0)-o.rebaja_planilla_flete),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa,o.producto
from public.ordenes_compra o left join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra is distinct from 'Puesto en camión' and (o.tipo_compra is distinct from 'En campo' or o.campo_promedio_caja_kg is null) and o.tipo_compra is distinct from 'En pie' and o.tipo_compra is distinct from 'Producto listo' and (o.tipo_compra is distinct from 'En campo' or o.producto='Yuca' and o.campo_promedio_caja_kg is null)
  and (b.id is not null or exists(select 1 from public.ventas_externas_boleta e join public.boletas_entrada be on be.id=e.boleta_id where be.orden_compra_id=o.id))
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,o.precio_en_pie)::numeric(16,2),
  least(greatest(0,o.precio_en_pie),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2),
  (o.producto||' en pie · lote abierto')::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='En pie' and o.precio_en_pie>0
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round((case when o.producto='Yuca' and o.unidad='Cajas' then o.cantidad_comprada*o.peso_caja_camion_kg/46 else o.cantidad_comprada end)*o.precio_puesto_camion,2)-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,round((case when o.producto='Yuca' and o.unidad='Cajas' then o.cantidad_comprada*o.peso_caja_camion_kg/46 else o.cantidad_comprada end)*o.precio_puesto_camion,2)-o.rebaja_planilla_flete),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2),
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
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round(o.cantidad_comprada*o.precio_campo,2)-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,round(o.cantidad_comprada*o.precio_campo,2)-o.rebaja_planilla_flete),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2),
  (case when o.tipo_compra='En campo' then 'En campo · precio pactado' else 'Producto listo · precio pactado' end)::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and ((o.tipo_compra='En campo' and o.producto<>'Yuca') or (o.tipo_compra='Producto listo' and o.producto<>'Yuca'))
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round(o.cantidad_comprada*o.precio_europa,2)-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,round(o.cantidad_comprada*o.precio_europa,2)-o.rebaja_planilla_flete),greatest(coalesce(o.adelanto,0),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)))::numeric(16,2),
  (case when o.tipo_compra='En campo' then 'En campo · precio pactado' else 'Producto listo · precio pactado' end)::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='Producto listo' and o.producto='Yuca'
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
where coalesce(o.estado,'')<>'Anulada' and ((o.tipo_compra='En campo' and (o.producto<>'Yuca' or o.campo_promedio_caja_kg is not null) and coalesce(o.cuadrilla_arranca,0)+o.campo_encargados+o.campo_otros_costos>0) or (o.tipo_compra='En pie' and o.producto in ('Ñampí','Cabeza de ñampí') and coalesce(o.cuadrilla_arranca,0)>0) or (o.tipo_compra='Cosecha propia' and coalesce(o.cuadrilla_arranca,0)>0))
union all
select case when c.tipo='planilla' then 'planilla_compra' else 'flete_compra' end::text,
  c.id,b.codigo||' · '||case when c.tipo='planilla' then 'Planilla' else 'Flete' end,(b.fecha_hora at time zone 'America/Costa_Rica')::date,
  p.nombre,'CRC'::text,c.monto::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen=case when c.tipo='planilla' then 'planilla_compra' else 'flete_compra' end and a.origen_id=c.id),0)::numeric(16,2),
  'Costo de boleta en pie'::text,o.producto
from public.costos_boleta_en_pie c join public.boletas_entrada b on b.id=c.boleta_id
join public.ordenes_compra o on o.id=b.orden_compra_id join public.proveedores p on p.id=c.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and c.monto>0
union all
select 'cuenta_manual_pagar'::text,m.id,m.codigo,m.fecha,m.contraparte,m.moneda,
  m.monto,coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='cuenta_manual_pagar' and a.origen_id=m.id),0)::numeric(16,2),
  'Registro manual'::text,null::text as producto
from public.cuentas_manuales m where m.tipo='pagar';
