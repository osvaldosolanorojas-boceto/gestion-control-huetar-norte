-- Solo la operación transaccional autorizada permite reabrir temporalmente el contenido.
create or replace function public.bloquear_boleta_finalizada() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_table_name='boletas_entrada' then
    if tg_op='DELETE' and old.finalizada_en is not null then raise exception 'La boleta finalizada no se puede eliminar'; end if;
    if tg_op='UPDATE' and old.finalizada_en is not null and current_setting('app.corrigiendo_boleta',true) is distinct from 'completa' then
      if current_setting('app.corrigiendo_boleta',true) is distinct from 'on' or
        (to_jsonb(old) - array['fecha_labor','condicion','cantidad_recipientes','tipo_recipiente','promedio_peso','kg_estimados','inicio_proceso','fin_proceso','turno','clima','linea_proceso','encargado','encargado_banda','observaciones','tratamiento_cera']) is distinct from
        (to_jsonb(new) - array['fecha_labor','condicion','cantidad_recipientes','tipo_recipiente','promedio_peso','kg_estimados','inicio_proceso','fin_proceso','turno','clima','linea_proceso','encargado','encargado_banda','observaciones','tratamiento_cera']) then
        raise exception 'La boleta finalizada solo permite corregir datos de recepción y proceso';
      end if;
    end if;
  elsif exists(select 1 from public.boletas_entrada b where b.id=case when tg_op='DELETE' then old.boleta_id else new.boleta_id end and b.finalizada_en is not null)
    and current_setting('app.corrigiendo_boleta',true) is distinct from 'completa' then
    raise exception 'Los rendimientos de una boleta finalizada no se pueden modificar';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

create function public.corregir_boleta_finalizada_completa(
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
  if v_o.tipo_compra='Puesto en camión' then
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
  select coalesce(sum(monto),0) into v_aplicado from public.aplicaciones_bancarias
    where origen='compra_campo' and origen_id=v_o.id;
  if greatest(0,v_total)<v_aplicado then raise exception 'El nuevo total sería menor que los pagos ya registrados; revise la cuenta antes de reducir la boleta'; end if;
  perform set_config('app.corrigiendo_boleta','off',true);
  return p_boleta_id;
end;
$$;
revoke all on function public.corregir_boleta_finalizada_completa(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text) from public,anon;
grant execute on function public.corregir_boleta_finalizada_completa(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text) to authenticated;
