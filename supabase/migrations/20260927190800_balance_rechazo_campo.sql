alter table public.ordenes_compra
  add column if not exists rechazo_campo_kg numeric(14,3) check (rechazo_campo_kg >= 0),
  add column if not exists rechazo_campo_sacos integer check (rechazo_campo_sacos >= 0);

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
  if v_disponible is null or v_disponible <= 0 then
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
    if round(new.kg_brutos*(1-new.castigo_pct/100)/46*new.precio_quintal,2)<v_cobrado then
      raise exception 'La venta corregida no puede ser menor que lo ya cobrado';
    end if;
  end if;
  return new;
end $$;
