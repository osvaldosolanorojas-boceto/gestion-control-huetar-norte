-- Cada entrega de ñampí en pie se puede finalizar sin cerrar el lote ni duplicar la cuenta por pagar.
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
    -- El lote ya figura una sola vez en CxP desde la orden. Cerrar una boleta
    -- sella su resultado, pero no cierra la compra ni crea otra deuda.
    v_amount:=0;
  elsif (v_o.tipo_compra='Puesto en camión' or v_o.tipo_compra='En campo' and v_o.campo_promedio_caja_kg is not null) then
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
