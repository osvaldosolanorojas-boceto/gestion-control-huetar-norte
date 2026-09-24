-- Los maestros se desactivan; las ventas se anulan; solo una boleta pendiente sin ventas se elimina.
alter table public.ordenes_venta add column if not exists anulada_en timestamptz;
alter table public.ordenes_venta add column if not exists anulada_por uuid references public.perfiles(id);
alter table public.ordenes_venta add column if not exists anulacion_motivo text;

create function public.retirar_registro(p_tipo text,p_id uuid,p_motivo text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_venta public.ordenes_venta%rowtype; v_boleta public.boletas_entrada%rowtype;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then
    raise exception 'Solo administración u oficina puede retirar registros';
  end if;
  if p_tipo='proveedor' then
    update public.proveedores set activo=false where id=p_id and activo=true;
    if not found then raise exception 'Proveedor no encontrado o ya retirado'; end if;
  elsif p_tipo='cliente' then
    update public.clientes set activo=false where id=p_id and activo=true;
    if not found then raise exception 'Cliente no encontrado o ya retirado'; end if;
  elsif p_tipo='venta' then
    select * into v_venta from public.ordenes_venta where id=p_id for update;
    if not found or v_venta.estado='Anulada' then raise exception 'Orden no encontrada o ya anulada'; end if;
    if v_venta.finalizada_en is not null then raise exception 'La orden está finalizada; su venta y cobro deben conservarse'; end if;
    if exists(select 1 from public.boleta_rendimientos r join public.ordenes_venta_lineas l on l.id=r.orden_venta_linea_id where l.orden_venta_id=p_id) then
      raise exception 'La orden ya tiene cajas asignadas en planta. Desasígnelas en sus boletas antes de anularla';
    end if;
    if exists(select 1 from public.aplicaciones_bancarias a where a.origen='venta_exportacion' and a.origen_id=p_id)
      or exists(select 1 from public.notas_credito_ventas n where n.orden_venta_id=p_id)
      or exists(select 1 from public.costos_operativos c where c.orden_venta_id=p_id) then
      raise exception 'La orden tiene cobros, notas de crédito o costos asociados; revise esos movimientos antes de anularla';
    end if;
    update public.ordenes_venta set estado='Anulada',anulada_en=now(),anulada_por=(select auth.uid()),anulacion_motivo=nullif(btrim(p_motivo),'') where id=p_id;
  elsif p_tipo='boleta' then
    select * into v_boleta from public.boletas_entrada where id=p_id for update;
    if not found then raise exception 'No se encontró la boleta'; end if;
    if v_boleta.finalizada_en is not null then raise exception 'La boleta finalizada conserva pagos y trazabilidad; no se puede eliminar'; end if;
    if exists(select 1 from public.ventas_externas_en_pie v where v.boleta_id=p_id) then
      raise exception 'La boleta tiene ventas directas asociadas; no se puede eliminar';
    end if;
    if exists(select 1 from public.boleta_rendimientos r join public.ordenes_venta_lineas l on l.id=r.orden_venta_linea_id join public.ordenes_venta v on v.id=l.orden_venta_id where r.boleta_id=p_id and v.finalizada_en is not null) then
      raise exception 'La boleta tiene cajas ligadas a una venta finalizada; no se puede eliminar';
    end if;
    delete from public.boletas_entrada where id=p_id;
  else
    raise exception 'Tipo de registro no admitido';
  end if;
end;
$$;
revoke all on function public.retirar_registro(text,uuid,text) from public,anon;
grant execute on function public.retirar_registro(text,uuid,text) to authenticated;

create or replace function public.pedidos_mapa_para_planta()
returns table(linea_id uuid,orden_id uuid,codigo text,contenedor text,cliente text,producto text,presentacion_kg numeric,cantidad_cajas integer,paletas integer,cajas_por_paleta integer,carton text,numero_cliente integer,fecha_salida date)
language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  return query select l.id,o.id,o.codigo,o.contenedor,c.nombre,l.producto,l.presentacion_kg,
    l.cantidad_cajas,l.paletas,l.cajas_por_paleta,l.carton_marca,o.numero_cliente,o.fecha_salida
  from public.ordenes_venta_lineas l join public.ordenes_venta o on o.id=l.orden_venta_id
  left join public.clientes c on c.id=o.cliente_id
  where o.estado is distinct from 'Anulada'
  order by o.fecha_salida desc,o.creado_en desc,l.id limit 1000;
end;
$$;
revoke all on function public.pedidos_mapa_para_planta() from public,anon;
grant execute on function public.pedidos_mapa_para_planta() to authenticated;

create or replace view public.cxc_operativa with (security_invoker=true) as
select 'venta_exportacion'::text origen,o.id origen_id,o.codigo,o.fecha,c.nombre contraparte,o.moneda::text moneda,
  greatest(0,case when o.finalizada_en is null then coalesce((select sum(l.total) from public.ordenes_venta_lineas l where l.orden_venta_id=o.id),0) else coalesce(o.monto_cxc,0) end
    -coalesce((select sum(n.monto) from public.notas_credito_ventas n where n.orden_venta_id=o.id),0))::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_exportacion' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  case when o.finalizada_en is null then 'Pedido previsto' else 'Pedido finalizado' end::text etapa,
  o.fecha_salida,(coalesce(o.fecha_salida,o.fecha)+o.plazo_pago_dias)::date fecha_vencimiento,
  o.plazo_pago_dias,
  coalesce((select sum(n.monto) from public.notas_credito_ventas n where n.orden_venta_id=o.id),0)::numeric(16,2) notas_credito
from public.ordenes_venta o left join public.clientes c on c.id=o.cliente_id
where o.estado is distinct from 'Anulada'
union all
select 'venta_local',v.id,v.codigo,v.fecha,v.comprador,v.moneda,
  coalesce((select sum(s.subtotal) from public.ventas_segundas s where s.venta_local_id=v.id),0)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_local' and a.origen_id=v.id),0)::numeric(16,2),
  'Venta registrada',v.fecha,v.fecha,0,0::numeric(16,2)
from public.ventas_locales v
union all
select 'saldo_productor',o.id,o.codigo,o.fecha,coalesce(o.productor_nombre,p.nombre,'Productor'), 'CRC',
  greatest(0,coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)
    +coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)-cx.monto)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='saldo_productor' and a.origen_id=o.id),0)::numeric(16,2),
  'Adelanto superior a compra',o.fecha,o.fecha,0,0::numeric(16,2)
from public.ordenes_compra o join public.cxp_operativa cx on cx.origen='compra_campo' and cx.origen_id=o.id
left join public.proveedores p on p.id=o.proveedor_id
where coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0)
    +coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)>cx.monto
union all
select case when m.tipo='cobrar' then 'cuenta_manual_cobrar' else 'cuenta_manual_pagar' end,
 m.id,m.codigo,m.fecha,m.contraparte,m.moneda,m.monto,
 coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen=case when m.tipo='cobrar' then 'cuenta_manual_cobrar' else 'cuenta_manual_pagar' end and a.origen_id=m.id),0)::numeric(16,2),
 'Registro manual',m.fecha,m.fecha_vencimiento,0,0::numeric(16,2)
from public.cuentas_manuales m where m.tipo='cobrar';
