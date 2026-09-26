-- Una misma cámara guarda saldos de yuca Europa y EE. UU.; FIFO por ingreso real de boleta.
alter table public.saldos_yuca_eeuu add column calidad text not null default 'Estados Unidos'
  check (calidad in ('Estados Unidos','Europa'));
alter table public.saldos_yuca_eeuu add column fecha_origen timestamptz;
update public.saldos_yuca_eeuu s set fecha_origen=b.fecha_hora
from public.boletas_entrada b where b.id=s.boleta_id;
alter table public.saldos_yuca_eeuu alter column fecha_origen set not null;
create index saldos_yuca_calidad_fecha_idx on public.saldos_yuca_eeuu(calidad,fecha_origen,id);
alter table public.ventas_saldo_yuca_eeuu add column calidad text not null default 'Estados Unidos'
  check (calidad in ('Estados Unidos','Europa'));

create or replace function public.crear_saldo_yuca_eeuu_al_finalizar() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.finalizada_en is null and new.finalizada_en is not null then
    insert into public.saldos_yuca_eeuu(rendimiento_id,boleta_id,boleta_codigo,productor,codigo_trazabilidad,cajas_origen,kg_por_caja,lunes_destino,calidad,fecha_origen)
    select r.id,new.id,new.codigo,coalesce(o.productor_nombre,'Productor'),coalesce(nullif(r.codigo_trazabilidad,''),new.codigo),r.cajas,r.presentacion_kg,
      date_trunc('week',new.finalizada_en at time zone 'America/Costa_Rica')::date+7,
      case r.calidad when 'Exportable Europa' then 'Europa' else 'Estados Unidos' end,new.fecha_hora
    from public.boleta_rendimientos r join public.ordenes_compra o on o.id=new.orden_compra_id
    where r.boleta_id=new.id and r.producto='Yuca' and r.calidad in ('Exportable Europa','Exportable estadounidense') and r.cajas>0 and r.orden_venta_linea_id is null
    on conflict (rendimiento_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.crear_saldo_yuca_eeuu_al_finalizar() from public,anon,authenticated;

insert into public.saldos_yuca_eeuu(rendimiento_id,boleta_id,boleta_codigo,productor,codigo_trazabilidad,cajas_origen,kg_por_caja,lunes_destino,calidad,fecha_origen)
select r.id,b.id,b.codigo,coalesce(o.productor_nombre,'Productor'),coalesce(nullif(r.codigo_trazabilidad,''),b.codigo),r.cajas,r.presentacion_kg,
  date_trunc('week',b.finalizada_en at time zone 'America/Costa_Rica')::date+7,'Europa',b.fecha_hora
from public.boleta_rendimientos r join public.boletas_entrada b on b.id=r.boleta_id join public.ordenes_compra o on o.id=b.orden_compra_id
where b.finalizada_en is not null and r.producto='Yuca' and r.calidad='Exportable Europa' and r.cajas>0 and r.orden_venta_linea_id is null
on conflict (rendimiento_id) do nothing;

-- Conservar la llamada anterior sin riesgo de tomar cajas Europa desde una versión antigua.
create or replace function public.vender_saldo_yuca_eeuu(p_fecha date,p_cajas integer,p_comprador text,p_moneda text,p_precio_estimado_qq numeric,p_referencia text default null,p_observaciones text default null)
returns uuid language plpgsql security definer set search_path='' as $$
begin
  return public.vender_saldo_yuca_por_calidad(p_fecha,p_cajas,p_comprador,p_moneda,p_precio_estimado_qq,'Estados Unidos',p_referencia,p_observaciones);
end;
$$;

create function public.vender_saldo_yuca_por_calidad(p_fecha date,p_cajas integer,p_comprador text,p_moneda text,p_precio_estimado_qq numeric,p_calidad text,p_referencia text default null,p_observaciones text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_lot public.saldos_yuca_eeuu%rowtype; v_available integer; v_take integer; v_left integer; v_id uuid; v_kg numeric(14,2):=0; v_code text;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
  if p_fecha is null or p_cajas is null or p_cajas<=0 or nullif(pg_catalog.btrim(p_comprador),'') is null or p_moneda not in ('CRC','USD') or p_precio_estimado_qq is null or p_precio_estimado_qq<0 or p_calidad not in ('Estados Unidos','Europa') then raise exception 'Revise fecha, comprador, cajas, calidad, moneda y precio estimado por quintal'; end if;
  v_left:=p_cajas;
  v_code:='YPL-'||pg_catalog.replace(pg_catalog.gen_random_uuid()::text,'-','');
  insert into public.ventas_saldo_yuca_eeuu(codigo,fecha,comprador,cajas,kg_enviados,moneda,precio_estimado_qq,referencia,observaciones,registrado_por,calidad)
  values(v_code,p_fecha,pg_catalog.btrim(p_comprador),p_cajas,1,p_moneda,p_precio_estimado_qq,nullif(pg_catalog.btrim(p_referencia),''),nullif(pg_catalog.btrim(p_observaciones),''),(select auth.uid()),p_calidad) returning id into v_id;
  for v_lot in select * from public.saldos_yuca_eeuu where calidad=p_calidad order by fecha_origen,id for update loop
    select v_lot.cajas_origen-coalesce(sum(s.cajas),0) into v_available from public.salidas_saldo_yuca_eeuu s where s.saldo_id=v_lot.id;
    v_take:=least(v_left,v_available);
    if v_take>0 then
      insert into public.salidas_saldo_yuca_eeuu(saldo_id,fecha,cajas,destinatario,codigo_salida,detalle,registrado_por,venta_id)
      values(v_lot.id,p_fecha,v_take,pg_catalog.btrim(p_comprador),v_code,'Venta de saldo en planta FIFO',(select auth.uid()),v_id);
      v_left:=v_left-v_take;
      v_kg:=v_kg+v_take*v_lot.kg_por_caja;
    end if;
    exit when v_left=0;
  end loop;
  if v_left>0 then raise exception 'Saldo insuficiente de yuca %: faltan % cajas',p_calidad,v_left; end if;
  update public.ventas_saldo_yuca_eeuu set kg_enviados=v_kg where id=v_id;
  return v_id;
end;
$$;
revoke all on function public.vender_saldo_yuca_por_calidad(date,integer,text,text,numeric,text,text,text) from public,anon;
grant execute on function public.vender_saldo_yuca_por_calidad(date,integer,text,text,numeric,text,text,text) to authenticated;

create or replace function public.liquidar_venta_saldo_yuca_eeuu(p_venta_id uuid,p_kg_primera numeric,p_kg_rechazo numeric,p_kg_merma numeric,p_precio_final_qq numeric,p_referencia text default null)
returns text language plpgsql security definer set search_path='' as $$
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
    values(v_sale.codigo,'cobrar',current_date,current_date,v_sale.comprador,v_sale.moneda,v_amount,'Yuca '||v_sale.calidad||' liquidada a rendimiento: '||v_sale.cajas||' cajas enviadas',coalesce(nullif(pg_catalog.btrim(p_referencia),''),v_sale.referencia), (select auth.uid())) returning id into v_account;
  end if;
  update public.ventas_saldo_yuca_eeuu set liquidada_en=now(),cuenta_cobrar_id=v_account where id=p_venta_id;
  return 'Liquidada';
end;
$$;
