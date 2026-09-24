-- Una compra con boletas finalizadas puede corregirse sin reabrir su trazabilidad.
-- El cambio de precios recalcula todas sus boletas y se revierte si reduce la deuda bajo pagos ya aplicados.
create or replace function public.proteger_orden_compra_cerrada() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' then
    if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id)
      or exists(select 1 from public.aplicaciones_bancarias a where a.origen in ('compra_campo','flete_compra') and a.origen_id=old.id) then
      raise exception 'La compra tiene boletas o pagos y no se puede eliminar';
    end if;
    return old;
  end if;
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is not null) then
    if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then
      raise exception 'Solo administración u oficina puede editar una compra con boletas finalizadas';
    end if;
    if old.producto is distinct from new.producto or old.tipo_compra is distinct from new.tipo_compra
      or old.proveedor_id is distinct from new.proveedor_id or old.estado is distinct from new.estado
      or old.finca_lote_id is distinct from new.finca_lote_id then
      raise exception 'La compra tiene boletas finalizadas: no cambie producto, modalidad, productor, estado ni lote';
    end if;
  end if;
  return new;
end;
$$;

create function public.recalcular_boletas_por_precios_compra() returns trigger
language plpgsql security invoker set search_path='' as $$
declare v_b record; v_r record; v_price numeric; v_amount numeric; v_paid numeric; v_total numeric;
begin
  if (old.precio_europa,old.precio_eeuu,old.precio_segunda_gruesa,old.precio_segunda_menuda,
      old.precio_rechazo,old.precio_campo,old.precio_en_pie)
      is not distinct from
     (new.precio_europa,new.precio_eeuu,new.precio_segunda_gruesa,new.precio_segunda_menuda,
      new.precio_rechazo,new.precio_campo,new.precio_en_pie) then return new; end if;
  if new.tipo_compra='Puesto en camión' then return new; end if;
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
create trigger recalcular_boletas_por_precios_compra after update on public.ordenes_compra
for each row execute function public.recalcular_boletas_por_precios_compra();
