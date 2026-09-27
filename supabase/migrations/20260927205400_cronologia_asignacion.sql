CREATE OR REPLACE FUNCTION public.validar_cronologia_asignacion()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_origen date; v_salida date; v_codigo text;
begin
  if new.orden_venta_linea_id is null then return new; end if;
  select coalesce(b.fecha_labor,b.fecha_hora::date) into v_origen
  from public.boletas_entrada b where b.id=new.boleta_id;
  select o.fecha_salida,o.codigo into v_salida,v_codigo
  from public.ordenes_venta_lineas l
  join public.ordenes_venta o on o.id=l.orden_venta_id
  where l.id=new.orden_venta_linea_id;
  if v_origen is not null and v_salida is not null and v_origen>v_salida then
    raise exception 'La boleta trabajada el % no puede surtir el pedido % que salió el %',v_origen,v_codigo,v_salida;
  end if;
  return new;
end;
$function$;

CREATE TRIGGER validar_cronologia_asignacion
 BEFORE INSERT OR UPDATE OF orden_venta_linea_id ON public.boleta_rendimientos
 FOR EACH ROW EXECUTE FUNCTION public.validar_cronologia_asignacion();

