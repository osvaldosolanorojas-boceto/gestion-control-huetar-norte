CREATE OR REPLACE FUNCTION public.validar_venta_segunda()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_r public.boleta_rendimientos%rowtype; v_vendido numeric;
begin
  select * into v_r from public.boleta_rendimientos where id=new.rendimiento_id for update;
  if not found or v_r.orden_venta_linea_id is not null or
     (v_r.calidad not in ('Segunda','Segunda gruesa','Segunda menuda','Rechazo','Rechazo grueso','Rechazo menuda')
      and not (v_r.calidad='Primera' and v_r.producto in ('Ñampí','Cabeza de ñampí')))
  then raise exception 'Rendimiento no disponible para venta local'; end if;
  if v_r.cajas>0 then
    select coalesce(sum(cajas),0) into v_vendido from public.ventas_segundas where rendimiento_id=new.rendimiento_id;
    if new.kilos<>0 or v_vendido+new.cajas>v_r.cajas then raise exception 'La venta supera las cajas disponibles'; end if;
  else
    select coalesce(sum(kilos),0) into v_vendido from public.ventas_segundas where rendimiento_id=new.rendimiento_id;
    if new.cajas<>0 or v_vendido+new.kilos>v_r.kg_resultado then raise exception 'La venta supera los kilos disponibles'; end if;
  end if;
  return new;
end;
$function$;
