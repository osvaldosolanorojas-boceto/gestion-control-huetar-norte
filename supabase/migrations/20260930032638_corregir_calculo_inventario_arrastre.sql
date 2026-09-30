create or replace function public.inventario_arrastre_yuca(p_fecha date) returns numeric language plpgsql security definer set search_path='' as $$
declare v_total numeric:=0; x record;
begin
 if not exists(select 1 from public.perfiles where id=(select auth.uid()) and activo and rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
 if p_fecha is null then raise exception 'Falta fecha'; end if;
 for x in select s.id,s.kg_por_caja,s.cajas_origen-coalesce((select sum(m.cajas) from public.salidas_saldo_yuca_eeuu m where m.saldo_id=s.id and m.fecha<=p_fecha),0) cajas from public.saldos_yuca_eeuu s join public.boletas_entrada b on b.id=s.boleta_id where coalesce(b.fecha_labor,(b.fecha_hora at time zone 'America/Costa_Rica')::date)<=p_fecha loop
   v_total:=v_total+x.cajas*x.kg_por_caja*public.costo_saldo_yuca(x.id);
 end loop;
 -- Output stocks not in the export carry-over table: second grades and reserved first grades awaiting dispatch.
 select v_total+coalesce(sum(greatest(0,r.kg_resultado-coalesce((select sum(v.kilos) from public.ventas_segundas v where v.rendimiento_id=r.id and v.fecha<=p_fecha),0))*p.costo_kg_crc),0) into v_total
 from public.reproceso_yuca_partidas p join public.reprocesos_yuca rp on rp.id=p.reproceso_id join public.boleta_rendimientos r on r.id=p.rendimiento_id left join public.ordenes_venta_lineas l on l.id=r.orden_venta_linea_id left join public.ordenes_venta o on o.id=l.orden_venta_id
 where rp.fecha<=p_fecha and r.calidad<>'Desperdicio' and not exists(select 1 from public.saldos_yuca_eeuu s where s.rendimiento_id=r.id) and (r.orden_venta_linea_id is null or o.finalizada_en is null or o.fecha_salida>p_fecha or o.estado='Anulada');
 return round(v_total,2);
end $$;
