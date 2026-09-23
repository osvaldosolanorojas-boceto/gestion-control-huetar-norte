-- El pedido completo crea su cuenta por cobrar al cerrarse.
alter table public.ordenes_venta add column finalizada_en timestamptz;
alter table public.ordenes_venta add column monto_cxc numeric(16,2) check(monto_cxc>=0);
alter table public.ordenes_venta add column finalizada_por uuid references public.perfiles(id);

create function public.bloquear_pedido_finalizado() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_table_name='ordenes_venta' then
    if old.finalizada_en is not null then raise exception 'El pedido finalizado no se puede modificar'; end if;
  elsif exists(select 1 from public.ordenes_venta o where o.id=case when tg_op='DELETE' then old.orden_venta_id else new.orden_venta_id end and o.finalizada_en is not null) then
    raise exception 'Las líneas del pedido finalizado no se pueden modificar';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
create trigger bloquear_pedido before update or delete on public.ordenes_venta for each row execute function public.bloquear_pedido_finalizado();
create trigger bloquear_lineas_pedido before insert or update or delete on public.ordenes_venta_lineas for each row execute function public.bloquear_pedido_finalizado();

create function public.finalizar_orden_venta(p_orden_id uuid) returns numeric
language plpgsql security definer set search_path='' as $$
declare v_o public.ordenes_venta%rowtype; v_l record; v_monto numeric:=0; v_asignadas integer; v_pendientes integer;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar pedidos'; end if;
  select * into v_o from public.ordenes_venta where id=p_orden_id for update;
  if not found then raise exception 'No se encontró el pedido'; end if;
  if v_o.finalizada_en is not null then raise exception 'Este pedido ya está finalizado'; end if;
  if v_o.cliente_id is null then raise exception 'Seleccione el cliente antes de finalizar'; end if;
  if not exists(select 1 from public.ordenes_venta_lineas where orden_venta_id=p_orden_id) then raise exception 'Agregue líneas al pedido'; end if;
  for v_l in select * from public.ordenes_venta_lineas where orden_venta_id=p_orden_id for update loop
    select coalesce(sum(r.cajas),0),count(*) filter(where b.finalizada_en is null)
      into v_asignadas,v_pendientes from public.boleta_rendimientos r
      join public.boletas_entrada b on b.id=r.boleta_id where r.orden_venta_linea_id=v_l.id;
    if v_asignadas<>v_l.cantidad_cajas then raise exception 'Faltan cajas en %: % de %',v_l.producto,v_asignadas,v_l.cantidad_cajas; end if;
    if v_pendientes>0 then raise exception 'Finalice las boletas que alimentan % antes de cerrar el pedido',v_l.producto; end if;
    if v_l.precio_caja is null or v_l.precio_caja<=0 then raise exception 'Falta precio de venta de %',v_l.producto; end if;
    v_monto:=v_monto+v_l.cantidad_cajas*v_l.precio_caja;
  end loop;
  update public.ordenes_venta set finalizada_en=now(),finalizada_por=(select auth.uid()),monto_cxc=round(v_monto,2) where id=p_orden_id;
  return round(v_monto,2);
end;
$$;
revoke all on function public.finalizar_orden_venta(uuid) from public,anon;
grant execute on function public.finalizar_orden_venta(uuid) to authenticated;

create or replace view public.cxc_operativa with (security_invoker=true) as
select 'venta_exportacion'::text origen,o.id origen_id,o.codigo,o.fecha,c.nombre contraparte,'USD'::text moneda,
  o.monto_cxc::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_exportacion' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  'Pedido finalizado'::text etapa
from public.ordenes_venta o left join public.clientes c on c.id=o.cliente_id where o.finalizada_en is not null
union all
select 'venta_local',v.id,v.codigo,v.fecha,v.comprador,v.moneda,
  coalesce((select sum(s.subtotal) from public.ventas_segundas s where s.venta_local_id=v.id),0)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_local' and a.origen_id=v.id),0)::numeric(16,2),
  'Venta registrada'
from public.ventas_locales v;
