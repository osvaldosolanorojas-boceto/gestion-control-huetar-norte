CREATE OR REPLACE FUNCTION public.liquidar_venta_saldo_yuca_eeuu(p_venta_id uuid, p_kg_primera numeric, p_kg_rechazo numeric, p_kg_merma numeric, p_precio_final_qq numeric, p_referencia text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_sale public.ventas_saldo_yuca_eeuu%rowtype; v_difference numeric; v_amount numeric(16,2); v_account uuid;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
  select * into v_sale from public.ventas_saldo_yuca_eeuu where id=p_venta_id for update;
  if not found then raise exception 'Venta no encontrada'; end if;
  if v_sale.liquidada_en is not null then raise exception 'Esta venta ya fue liquidada'; end if;
  if p_kg_primera is null or p_kg_rechazo is null or p_kg_merma is null or p_precio_final_qq is null or least(p_kg_primera,p_kg_rechazo,p_kg_merma,p_precio_final_qq)<0 then raise exception 'Ingrese kilos de primera, rechazo, merma y precio final no negativos'; end if;
  v_difference:=v_sale.kg_enviados-p_kg_primera-p_kg_rechazo-p_kg_merma;
  update public.ventas_saldo_yuca_eeuu set kg_primera=p_kg_primera,kg_rechazo_devuelto=p_kg_rechazo,kg_merma=p_kg_merma,precio_final_qq=p_precio_final_qq,referencia=coalesce(nullif(pg_catalog.btrim(p_referencia),''),referencia) where id=p_venta_id;
  if abs(v_difference)>0.01 then return 'Diferencia de kilos pendiente'; end if;
  v_amount:=pg_catalog.round(p_kg_primera/46*p_precio_final_qq,2);
  if v_amount>0 then
    insert into public.cuentas_manuales(codigo,tipo,fecha,fecha_vencimiento,contraparte,moneda,monto,concepto,referencia,registrado_por)
    values(v_sale.codigo,'cobrar',v_sale.fecha,v_sale.fecha,v_sale.comprador,v_sale.moneda,v_amount,'Yuca '||v_sale.calidad||' liquidada a rendimiento: '||v_sale.cajas||' cajas enviadas',coalesce(nullif(pg_catalog.btrim(p_referencia),''),v_sale.referencia), (select auth.uid())) returning id into v_account;
  end if;
  update public.ventas_saldo_yuca_eeuu set liquidada_en=now(),cuenta_cobrar_id=v_account where id=p_venta_id;
  return 'Liquidada';
end;
$function$
;
create or replace function public.corregir_fecha_venta_saldo_yuca(p_venta_id uuid,p_fecha date)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
  if p_fecha is null then raise exception 'Ingrese una fecha de salida'; end if;
  update public.ventas_saldo_yuca_eeuu set fecha=p_fecha
   where id=p_venta_id and liquidada_en is null;
  if not found then raise exception 'La venta no existe o ya fue liquidada'; end if;
end $$;
grant execute on function public.corregir_fecha_venta_saldo_yuca(uuid,date) to authenticated;
