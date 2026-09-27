CREATE OR REPLACE FUNCTION public.proteger_costos_boleta_pagados()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_pagado numeric; v_order public.ordenes_compra%rowtype;
begin
  select o.* into v_order from public.boletas_entrada b join public.ordenes_compra o on o.id=b.orden_compra_id
    where b.id=case when tg_op='DELETE' then old.boleta_id else new.boleta_id end;
  if not found or v_order.producto in ('Ñampí','Cabeza de ñampí') or v_order.tipo_compra<>'En pie' then raise exception 'El costo requiere una boleta de compra en pie con entradas programadas'; end if;
  if v_order.en_pie_finalizada_en is not null and tg_op='INSERT' then raise exception 'La compra en pie ya está finalizada'; end if;
  if tg_op='INSERT' then return new; end if;
  select coalesce(sum(a.monto),0) into v_pagado from public.aplicaciones_bancarias a
    where a.origen=case when old.tipo='planilla' then 'planilla_compra' else 'flete_compra' end and a.origen_id=old.id;
  if tg_op='DELETE' then
    if v_pagado>0 then raise exception 'Este costo tiene pagos y no puede eliminarse'; end if;
    return old;
  end if;
  if new.id<>old.id or new.boleta_id<>old.boleta_id or new.tipo<>old.tipo then raise exception 'No cambie la identidad del costo'; end if;
  if v_pagado>0 and (new.proveedor_id is distinct from old.proveedor_id or new.monto<v_pagado) then
    raise exception 'El costo ya tiene pagos: no cambie el beneficiario ni reduzca el monto bajo lo pagado';
  end if;
  return new;
end;
$function$
;
