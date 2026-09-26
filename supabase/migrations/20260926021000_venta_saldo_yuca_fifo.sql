-- Salidas comerciales de yuca estadounidense: una venta puede usar varias boletas FIFO.
create table public.ventas_saldo_yuca_eeuu (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  fecha date not null,
  comprador text not null check (length(btrim(comprador))>0),
  cajas integer not null check (cajas>0),
  kg_enviados numeric(14,2) not null check (kg_enviados>0),
  moneda text not null check (moneda in ('CRC','USD')),
  precio_estimado_qq numeric(14,2) check (precio_estimado_qq>=0),
  precio_final_qq numeric(14,2) check (precio_final_qq>=0),
  kg_primera numeric(14,2) check (kg_primera>=0),
  kg_rechazo_devuelto numeric(14,2) check (kg_rechazo_devuelto>=0),
  kg_merma numeric(14,2) check (kg_merma>=0),
  referencia text,
  observaciones text,
  liquidada_en timestamptz,
  cuenta_cobrar_id uuid unique references public.cuentas_manuales(id),
  registrado_por uuid references auth.users(id),
  creado_en timestamptz not null default now(),
  check (liquidada_en is null or (kg_primera is not null and kg_rechazo_devuelto is not null and kg_merma is not null and precio_final_qq is not null))
);
alter table public.salidas_saldo_yuca_eeuu add column venta_id uuid references public.ventas_saldo_yuca_eeuu(id);
create index salidas_yuca_venta_idx on public.salidas_saldo_yuca_eeuu(venta_id);
alter table public.ventas_saldo_yuca_eeuu enable row level security;
revoke all on public.ventas_saldo_yuca_eeuu from anon,authenticated;
grant select on public.ventas_saldo_yuca_eeuu to authenticated;
create policy ventas_yuca_lectura on public.ventas_saldo_yuca_eeuu for select to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create function public.vender_saldo_yuca_eeuu(p_fecha date,p_cajas integer,p_comprador text,p_moneda text,p_precio_estimado_qq numeric,p_referencia text default null,p_observaciones text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_lot public.saldos_yuca_eeuu%rowtype; v_available integer; v_take integer; v_left integer; v_id uuid; v_kg numeric(14,2):=0; v_code text;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
  if p_fecha is null or p_cajas is null or p_cajas<=0 or nullif(pg_catalog.btrim(p_comprador),'') is null or p_moneda not in ('CRC','USD') or p_precio_estimado_qq is null or p_precio_estimado_qq<0 then raise exception 'Revise fecha, comprador, cajas, moneda y precio estimado por quintal'; end if;
  v_left:=p_cajas;
  v_code:='YEU-'||pg_catalog.replace(pg_catalog.gen_random_uuid()::text,'-','');
  insert into public.ventas_saldo_yuca_eeuu(codigo,fecha,comprador,cajas,kg_enviados,moneda,precio_estimado_qq,referencia,observaciones,registrado_por)
  values(v_code,p_fecha,pg_catalog.btrim(p_comprador),p_cajas,1,p_moneda,p_precio_estimado_qq,nullif(pg_catalog.btrim(p_referencia),''),nullif(pg_catalog.btrim(p_observaciones),''),(select auth.uid())) returning id into v_id;
  -- Bloquear las partidas en el mismo orden para impedir doble salida concurrente.
  for v_lot in select * from public.saldos_yuca_eeuu order by creado_en,id for update loop
    select v_lot.cajas_origen-coalesce(sum(s.cajas),0) into v_available from public.salidas_saldo_yuca_eeuu s where s.saldo_id=v_lot.id;
    v_take:=least(v_left,v_available);
    if v_take>0 then
      insert into public.salidas_saldo_yuca_eeuu(saldo_id,fecha,cajas,destinatario,codigo_salida,detalle,registrado_por,venta_id)
      values(v_lot.id,p_fecha,v_take,pg_catalog.btrim(p_comprador),v_code,'Venta de saldo FIFO',(select auth.uid()),v_id);
      v_left:=v_left-v_take;
      v_kg:=v_kg+v_take*v_lot.kg_por_caja;
    end if;
    exit when v_left=0;
  end loop;
  if v_left>0 then raise exception 'Saldo insuficiente: faltan % cajas',v_left; end if;
  update public.ventas_saldo_yuca_eeuu set kg_enviados=v_kg where id=v_id;
  return v_id;
end;
$$;
revoke all on function public.vender_saldo_yuca_eeuu(date,integer,text,text,numeric,text,text) from public,anon;
grant execute on function public.vender_saldo_yuca_eeuu(date,integer,text,text,numeric,text,text) to authenticated;

create function public.liquidar_venta_saldo_yuca_eeuu(p_venta_id uuid,p_kg_primera numeric,p_kg_rechazo numeric,p_kg_merma numeric,p_precio_final_qq numeric,p_referencia text default null)
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
    values(v_sale.codigo,'cobrar',current_date,current_date,v_sale.comprador,v_sale.moneda,v_amount,'Yuca EE. UU. liquidada a rendimiento: '||v_sale.cajas||' cajas enviadas',coalesce(nullif(pg_catalog.btrim(p_referencia),''),v_sale.referencia), (select auth.uid())) returning id into v_account;
  end if;
  update public.ventas_saldo_yuca_eeuu set liquidada_en=now(),cuenta_cobrar_id=v_account where id=p_venta_id;
  return 'Liquidada';
end;
$$;
revoke all on function public.liquidar_venta_saldo_yuca_eeuu(uuid,numeric,numeric,numeric,numeric,text) from public,anon;
grant execute on function public.liquidar_venta_saldo_yuca_eeuu(uuid,numeric,numeric,numeric,numeric,text) to authenticated;
