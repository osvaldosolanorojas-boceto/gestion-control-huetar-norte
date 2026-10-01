alter table public.ventas_rechazo_campo
 alter column kg_brutos drop not null,
 alter column precio_quintal drop not null,
 add column boleta_id uuid references public.boletas_entrada(id),
 add column fecha_vencimiento date;
create or replace function public.validar_rechazo_campo() returns trigger
language plpgsql set search_path to '' as $$
declare v_tipo text; v_producto text; v_disponible numeric; v_vendido numeric; v_cobrado numeric;
begin
  select tipo_compra,producto,
    case when tipo_compra='En campo'
      then coalesce(campo_sacos,0)*coalesce(campo_promedio_saco_kg,0)
      else rechazo_campo_kg end
    into v_tipo,v_producto,v_disponible
    from public.ordenes_compra
    where id=new.orden_compra_id and estado is distinct from 'Anulada';
  if v_producto is distinct from 'Yuca' or v_tipo not in ('En pie','En campo','Cosecha propia') then
    raise exception 'El rechazo de campo requiere yuca comprada en pie, en campo o de finca propia';
  end if;
  if new.kg_brutos is not null and (v_disponible is null or v_disponible <= 0) then
    raise exception 'Registre primero los kilos de rechazo obtenidos en el campo';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.orden_compra_id::text,2));
  select coalesce(sum(kg_brutos),0) into v_vendido from public.ventas_rechazo_campo
    where orden_compra_id=new.orden_compra_id and id is distinct from new.id;
  if v_vendido+new.kg_brutos>v_disponible+0.001 then
    raise exception 'La venta supera el rechazo pesado en campo: disponible % kg',greatest(0,v_disponible-v_vendido);
  end if;
  if tg_op='UPDATE' then
    select coalesce(sum(monto),0) into v_cobrado from public.aplicaciones_bancarias
      where origen='venta_rechazo_campo' and origen_id=old.id;
    if v_cobrado>0 and (new.moneda is distinct from old.moneda or new.comprador is distinct from old.comprador or new.orden_compra_id is distinct from old.orden_compra_id) then
      raise exception 'No cambie comprador, moneda u orden de una entrega con cobros aplicados';
    end if;
    if coalesce(round(new.kg_brutos*(1-new.castigo_pct/100)/46*new.precio_quintal,2),0)<v_cobrado then
      raise exception 'La venta corregida no puede ser menor que lo ya cobrado';
    end if;
  end if;
  if new.boleta_id is not null and not exists(select 1 from public.boletas_entrada where id=new.boleta_id and orden_compra_id=new.orden_compra_id) then
    raise exception 'La boleta debe pertenecer a la misma orden de compra';
  end if;
  return new;
end $$;

-- Preserve all existing unions and grants, replacing only rejection metadata.
do $$
declare definition text;
begin
 -- Only the rejection source has the new due-date column: scope replacement to its union.
 select pg_get_viewdef('public.cxc_operativa'::regclass,true) into definition;
 definition := replace(definition, '''Rechazo vendido desde campo''::text AS etapa,
    v.fecha AS fecha_salida,
    v.fecha AS fecha_vencimiento,', 'case when v.monto is null then ''Rechazo pendiente de liquidar'' else ''Rechazo vendido desde campo'' end::text AS etapa,
    v.fecha AS fecha_salida,
    coalesce(v.fecha_vencimiento,v.fecha) AS fecha_vencimiento,');
 execute 'create or replace view public.cxc_operativa with (security_invoker=true) as '||definition;
end $$;
