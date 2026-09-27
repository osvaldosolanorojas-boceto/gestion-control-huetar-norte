CREATE OR REPLACE FUNCTION public.finalizar_boleta_entrada(p_boleta_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_b public.boletas_entrada%rowtype; v_o public.ordenes_compra%rowtype; v_r record; v_price numeric; v_amount numeric:=0; v_output numeric:=0;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar boletas'; end if;
  select * into v_b from public.boletas_entrada where id=p_boleta_id for update;
  if not found then raise exception 'No se encontró la boleta'; end if;
  if v_b.finalizada_en is not null then raise exception 'Esta boleta ya está finalizada'; end if;
  if v_b.orden_compra_id is null then raise exception 'Enlace la orden de compra antes de finalizar'; end if;
  select * into v_o from public.ordenes_compra where id=v_b.orden_compra_id for update;
  if v_b.fin_proceso is null then raise exception 'Registre el final del proceso antes de finalizar'; end if;
  if not exists(select 1 from public.boleta_rendimientos where boleta_id=p_boleta_id) then raise exception 'Registre al menos un rendimiento antes de finalizar'; end if;
  select coalesce(sum(r.kg_resultado),0) into v_output from public.boleta_rendimientos r where r.boleta_id=p_boleta_id;
  v_output:=v_output+coalesce((select sum(case when e.unidad='Sacos' then e.cantidad*e.peso_saco_kg else e.cantidad*46 end)
    from public.ventas_externas_boleta e where e.boleta_id=p_boleta_id),0);
  if v_b.kg_estimados is null or v_b.kg_estimados<=0 then raise exception 'Falta el peso de entrada en la boleta'; end if;
  if v_output<=0 then raise exception 'Falta clasificar el producto de la boleta'; end if;
  -- La entrada se estima por muestra: un kilo por recipiente es variación normal.
  -- Las diferencias mayores se permiten con explicación, incluida lluvia o raíz.
  if v_output-v_b.kg_estimados>greatest(0,coalesce(v_b.cantidad_recipientes,0))+0.01
     and nullif(trim(v_b.observaciones),'') is null then
    raise exception 'Explique en Observaciones los % kg de salida sobre el ingreso estimado',v_output-v_b.kg_estimados;
  end if;
  if v_b.kg_estimados-v_output>greatest(20,v_b.kg_estimados*0.02,coalesce(v_b.cantidad_recipientes,0))
     and nullif(trim(v_b.observaciones),'') is null then
    raise exception 'Explique en Observaciones los % kg de diferencia o registre desperdicio',v_b.kg_estimados-v_output;
  end if;
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
