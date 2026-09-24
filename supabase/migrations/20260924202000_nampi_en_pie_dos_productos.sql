-- Un lote de ñampí en pie produce ñampí y cabeza; ambos conservan la misma orden y su único precio de compra.
alter table public.ordenes_compra
  add column en_pie_finalizada_en timestamptz,
  add column precio_nampi_rendimiento numeric(14,2) check (precio_nampi_rendimiento>=0),
  add column precio_cabeza_rendimiento numeric(14,2) check (precio_cabeza_rendimiento>=0);
create table public.ventas_externas_en_pie (
  id uuid primary key default gen_random_uuid(),
  orden_compra_id uuid not null references public.ordenes_compra(id),
  boleta_id uuid not null references public.boletas_entrada(id),
  fecha date not null, producto text not null check(producto in ('Ñampí','Cabeza de ñampí')),
  comprador text not null check(length(trim(comprador))>0),
  cantidad numeric(14,3) not null check(cantidad>0),
  unidad text not null check(unidad in ('Sacos','Quintales (46 kg)')),
  peso_saco_kg numeric(12,3) check(peso_saco_kg>0),
  precio_unitario numeric(14,2) not null check(precio_unitario>=0),
  check ((unidad='Sacos' and cantidad=trunc(cantidad) and peso_saco_kg is not null) or (unidad='Quintales (46 kg)' and peso_saco_kg is null)),
  moneda text not null default 'CRC' check(moneda in ('CRC','USD')),
  observaciones text,
  creado_en timestamptz not null default now()
);
create index ventas_externas_en_pie_orden_idx on public.ventas_externas_en_pie(orden_compra_id);
alter table public.ventas_externas_en_pie enable row level security;
grant select,insert,delete on public.ventas_externas_en_pie to authenticated;
create policy ventas_externas_en_pie_admin on public.ventas_externas_en_pie for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.validar_venta_externa_en_pie() returns trigger language plpgsql set search_path='' as $$
declare v_o public.ordenes_compra%rowtype;
begin
  select * into v_o from public.ordenes_compra where id=case when tg_op='DELETE' then old.orden_compra_id else new.orden_compra_id end for update;
  if v_o.en_pie_finalizada_en is not null then raise exception 'La compra en pie ya está finalizada'; end if;
  if v_o.tipo_compra<>'En pie' or v_o.producto not in ('Ñampí','Cabeza de ñampí') then raise exception 'Esta venta externa requiere una compra de ñampí en pie'; end if;
  if tg_op<>'DELETE' and not exists(select 1 from public.boletas_entrada b where b.id=new.boleta_id and b.orden_compra_id=v_o.id) then raise exception 'La venta debe pertenecer a una boleta de esta compra'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
create trigger validar_venta_externa_en_pie before insert or delete on public.ventas_externas_en_pie
for each row execute function public.validar_venta_externa_en_pie();
create function public.finalizar_compra_en_pie(p_orden_id uuid) returns void language plpgsql security invoker set search_path='' as $$
declare v_o public.ordenes_compra%rowtype;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar esta compra'; end if;
  select * into v_o from public.ordenes_compra where id=p_orden_id for update;
  if not found or v_o.tipo_compra<>'En pie' or v_o.producto not in ('Ñampí','Cabeza de ñampí') then raise exception 'Seleccione una compra de ñampí en pie'; end if;
  if v_o.en_pie_finalizada_en is not null then raise exception 'Esta compra ya está finalizada'; end if;
  if not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=p_orden_id) then
    raise exception 'Registre al menos una boleta o venta externa antes de finalizar';
  end if;
  update public.ordenes_compra set en_pie_finalizada_en=now() where id=p_orden_id;
end;
$$;
revoke all on function public.finalizar_compra_en_pie(uuid) from public,anon;
grant execute on function public.finalizar_compra_en_pie(uuid) to authenticated;
alter table public.ordenes_compra add constraint planilla_nampi_en_pie_beneficiario check
  (tipo_compra is distinct from 'En pie' or producto not in ('Ñampí','Cabeza de ñampí') or coalesce(cuadrilla_arranca,0)=0 or planilla_proveedor_id is not null) not valid;

create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete)::numeric(16,2) monto,
  least(greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa,o.producto
from public.ordenes_compra o join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra is distinct from 'Puesto en camión' and (o.tipo_compra is distinct from 'En campo' or o.campo_promedio_caja_kg is null) and not (o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,o.precio_en_pie)::numeric(16,2),
  least(greatest(0,o.precio_en_pie),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
  'Ñampí en pie · rendimiento abierto'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie' and o.precio_en_pie>0
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round(o.cantidad_comprada*o.peso_caja_camion_kg/46*o.precio_puesto_camion,2)-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,round(o.cantidad_comprada*o.peso_caja_camion_kg/46*o.precio_puesto_camion,2)-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
  'Puesto en camión · precio fijo'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='Puesto en camión'
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round((o.cantidad_comprada*greatest(0,o.campo_promedio_caja_kg-o.campo_tara_caja_kg-o.campo_tierra_caja_kg)/46*o.precio_campo)
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2))::numeric(16,2),
  least(greatest(0,round((o.cantidad_comprada*greatest(0,o.campo_promedio_caja_kg-o.campo_tara_caja_kg-o.campo_tierra_caja_kg)/46*o.precio_campo)
    +(o.campo_sacos*o.campo_promedio_saco_kg*(1-o.campo_descuento_rechazo_pct/100)/46*o.campo_precio_rechazo),2)),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
  'En campo · pesaje pactado'::text,o.producto
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='En campo' and o.producto='Yuca' and o.campo_promedio_caja_kg is not null
union all
select 'flete_compra'::text,o.id,o.codigo,o.fecha,
  t.nombre,'CRC'::text,o.flete::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='flete_compra' and a.origen_id=o.id),0)::numeric(16,2),
  'Flete de compra'::text,o.producto
from public.ordenes_compra o join public.proveedores t on t.id=o.flete_proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.flete>0
union all
select 'planilla_compra'::text,o.id,o.codigo,o.fecha,
  p.nombre,'CRC'::text,(coalesce(o.cuadrilla_arranca,0)+case when o.tipo_compra='En campo' then o.campo_encargados+o.campo_otros_costos else 0 end)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='planilla_compra' and a.origen_id=o.id),0)::numeric(16,2),
  'Planilla de arranca'::text,o.producto
from public.ordenes_compra o join public.proveedores p on p.id=o.planilla_proveedor_id
where coalesce(o.estado,'')<>'Anulada' and ((o.tipo_compra='En campo' and o.producto='Yuca' and o.campo_promedio_caja_kg is not null and coalesce(o.cuadrilla_arranca,0)+o.campo_encargados+o.campo_otros_costos>0) or (o.tipo_compra='En pie' and o.producto in ('Ñampí','Cabeza de ñampí') and coalesce(o.cuadrilla_arranca,0)>0))
union all
select 'cuenta_manual_pagar'::text,m.id,m.codigo,m.fecha,m.contraparte,m.moneda,
  m.monto,coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='cuenta_manual_pagar' and a.origen_id=m.id),0)::numeric(16,2),
  'Registro manual'::text,null::text as producto
from public.cuentas_manuales m where m.tipo='pagar';


create or replace function private.guardar_boleta_planta(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_producto text; v_tipo text; v_cerrada timestamptz; v_proveedor_id uuid; v_finca text; v_chofer text; v_placa text;
  v_trabajo jsonb; v_rendimiento jsonb; v_pedido record; v_asignado integer;
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  select o.producto,o.proveedor_id,o.lugar,o.chofer,o.placa,o.tipo_compra,o.en_pie_finalizada_en into v_producto,v_proveedor_id,v_finca,v_chofer,v_placa,v_tipo,v_cerrada from public.ordenes_compra o where o.id=p_orden_compra_id;
  if v_producto is null then raise exception 'Seleccione una orden de compra válida'; end if;
  if v_cerrada is not null then raise exception 'Esta compra en pie está finalizada; no admite más boletas'; end if;
  if p_inicio_proceso is not null and p_fin_proceso is not null and p_fin_proceso<p_inicio_proceso then raise exception 'El fin del proceso debe ser posterior al inicio'; end if;
  if p_boleta_id is null then
    insert into public.boletas_entrada(codigo,fecha_hora,fecha_labor,orden_compra_id,proveedor_id,finca_lugar,chofer,placa,condicion,producto,cantidad_recipientes,tipo_recipiente,promedio_peso,kg_estimados,linea_proceso,encargado,encargado_banda,inicio_proceso,fin_proceso,turno,clima,observaciones,tratamiento_cera)
    values(p_codigo,p_fecha_hora,p_fecha_labor,p_orden_compra_id,v_proveedor_id,v_finca,v_chofer,v_placa,p_condicion,v_producto,p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,p_cantidad_recipientes*p_promedio_peso,p_linea_proceso,p_encargado,p_encargado_banda,p_inicio_proceso,p_fin_proceso,p_turno,p_clima,p_observaciones,p_tratamiento_cera) returning id into v_id;
  else
    update public.boletas_entrada b set fecha_hora=p_fecha_hora,fecha_labor=p_fecha_labor,orden_compra_id=p_orden_compra_id,proveedor_id=v_proveedor_id,finca_lugar=v_finca,chofer=v_chofer,placa=v_placa,condicion=p_condicion,producto=v_producto,cantidad_recipientes=p_cantidad_recipientes,tipo_recipiente=p_tipo_recipiente,promedio_peso=p_promedio_peso,kg_estimados=p_cantidad_recipientes*p_promedio_peso,linea_proceso=p_linea_proceso,encargado=p_encargado,encargado_banda=p_encargado_banda,inicio_proceso=p_inicio_proceso,fin_proceso=p_fin_proceso,turno=p_turno,clima=p_clima,observaciones=p_observaciones,tratamiento_cera=p_tratamiento_cera where b.id=p_boleta_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la boleta'; end if;
    delete from public.boleta_trabajos where boleta_id=v_id;
    delete from public.boleta_rendimientos where boleta_id=v_id;
  end if;
  for v_trabajo in select value from pg_catalog.jsonb_array_elements(coalesce(p_trabajos,'[]'::jsonb)) loop
    if not exists (select 1 from public.trabajadores t where t.id=(v_trabajo->>'trabajador_id')::uuid and t.activo) then raise exception 'El colaborador seleccionado no está activo'; end if;
    insert into public.boleta_trabajos(boleta_id,trabajador_id,labor) values(v_id,(v_trabajo->>'trabajador_id')::uuid,v_trabajo->>'labor');
  end loop;
  for v_rendimiento in select value from pg_catalog.jsonb_array_elements(coalesce(p_rendimientos,'[]'::jsonb)) loop
    if v_rendimiento->>'producto'<>v_producto and not (v_tipo='En pie' and v_producto in ('Ñampí','Cabeza de ñampí') and v_rendimiento->>'producto' in ('Ñampí','Cabeza de ñampí')) then raise exception 'El rendimiento debe corresponder al producto recibido'; end if;
    if nullif(v_rendimiento->>'orden_venta_linea_id','') is not null then
      select l.producto,l.presentacion_kg,l.cantidad_cajas into v_pedido from public.ordenes_venta_lineas l where l.id=(v_rendimiento->>'orden_venta_linea_id')::uuid for update;
      if not found or v_pedido.producto<>(v_rendimiento->>'producto') or v_pedido.presentacion_kg<>(v_rendimiento->>'presentacion_kg')::numeric then raise exception 'La línea del pedido no coincide con el producto y peso'; end if;
      select coalesce(sum(r.cajas),0) into v_asignado from public.boleta_rendimientos r where r.orden_venta_linea_id=(v_rendimiento->>'orden_venta_linea_id')::uuid;
      if v_asignado+coalesce((v_rendimiento->>'cajas')::integer,0)>v_pedido.cantidad_cajas then raise exception 'La cantidad supera las cajas solicitadas en la orden de venta'; end if;
    end if;
    if nullif(v_rendimiento->>'posicion_paleta','') is not null and nullif(v_rendimiento->>'orden_venta_linea_id','') is null then raise exception 'Para asignar una paleta seleccione primero la orden de venta'; end if;
    insert into public.boleta_rendimientos(boleta_id,producto,calidad,presentacion_kg,cajas,kg_manual,orden_venta_linea_id,posicion_paleta,observaciones,paga_productor,codigo_trazabilidad)
    values(v_id,v_rendimiento->>'producto',v_rendimiento->>'calidad',nullif(v_rendimiento->>'presentacion_kg','')::numeric,coalesce(nullif(v_rendimiento->>'cajas','')::integer,0),nullif(v_rendimiento->>'kg_manual','')::numeric,nullif(v_rendimiento->>'orden_venta_linea_id','')::uuid,nullif(v_rendimiento->>'posicion_paleta','')::smallint,v_rendimiento->>'observaciones',coalesce((v_rendimiento->>'paga_productor')::boolean,true),coalesce(nullif(pg_catalog.btrim(v_rendimiento->>'codigo_trazabilidad'),''),p_codigo));
  end loop;
  return v_id;
end;
$$;
drop function public.ordenes_compra_para_planta(uuid,boolean);
create function public.ordenes_compra_para_planta(p_orden_compra_id uuid default null,p_incluir_vinculadas boolean default false)
returns table(id uuid,codigo text,fecha date,productor_nombre text,producto text,boleta_campo_referencia text,proveedor_id uuid,chofer text,placa text,tipo_compra text,en_pie_finalizada_en timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select o.id,o.codigo,o.fecha,o.productor_nombre,o.producto,o.boleta_campo_referencia,o.proveedor_id,o.chofer,o.placa,o.tipo_compra,o.en_pie_finalizada_en
  from public.ordenes_compra o
  where coalesce(o.estado,'')<>'Anulada' and (o.en_pie_finalizada_en is null or p_incluir_vinculadas or o.id=p_orden_compra_id)
    and (p_incluir_vinculadas
      or o.id=p_orden_compra_id
      or (o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
      or not exists (select 1 from public.boletas_entrada b where b.orden_compra_id=o.id))
  order by o.fecha desc,o.creado_en desc limit 1000;
end;
$$;

revoke all on function public.ordenes_compra_para_planta(uuid,boolean) from public,anon;
grant execute on function public.ordenes_compra_para_planta(uuid,boolean) to authenticated;

-- Guardar boleta y ventas directas dentro de una sola transacción.
create function public.guardar_boleta_con_ventas_en_pie(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text,
  p_muestra numeric[],p_tara_kg numeric,p_merma_kg numeric,p_ventas_directas jsonb
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid; v_line jsonb; v_o public.ordenes_compra%rowtype;
begin
  if p_ventas_directas is null or jsonb_typeof(p_ventas_directas)<>'array' then raise exception 'Ventas directas inválidas'; end if;
  select * into v_o from public.ordenes_compra where id=p_orden_compra_id for update;
  if not found or v_o.tipo_compra<>'En pie' or v_o.producto not in ('Ñampí','Cabeza de ñampí') or v_o.en_pie_finalizada_en is not null then raise exception 'La compra en pie no está abierta'; end if;
  if jsonb_array_length(p_ventas_directas)>0 and not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina registra ventas directas'; end if;
  v_id:=public.guardar_boleta_con_muestra(p_boleta_id,p_codigo,p_orden_compra_id,p_fecha_hora,p_fecha_labor,p_inicio_proceso,p_fin_proceso,
    p_turno,p_clima,p_linea_proceso,p_encargado,p_encargado_banda,p_condicion,p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,
    p_observaciones,p_trabajos,p_rendimientos,p_tratamiento_cera,p_muestra,p_tara_kg,p_merma_kg);
  for v_line in select value from pg_catalog.jsonb_array_elements(p_ventas_directas) loop
    insert into public.ventas_externas_en_pie(orden_compra_id,boleta_id,fecha,producto,comprador,cantidad,unidad,peso_saco_kg,precio_unitario,moneda,observaciones)
    values(p_orden_compra_id,v_id,(v_line->>'fecha')::date,v_line->>'producto',pg_catalog.btrim(v_line->>'comprador'),(v_line->>'cantidad')::numeric,
      v_line->>'unidad',nullif(v_line->>'peso_saco_kg','')::numeric,(v_line->>'precio_unitario')::numeric,coalesce(v_line->>'moneda','CRC'),nullif(pg_catalog.btrim(v_line->>'observaciones'),''));
  end loop;
  return v_id;
end;
$$;
revoke all on function public.guardar_boleta_con_ventas_en_pie(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[],numeric,numeric,jsonb) from public,anon;
grant execute on function public.guardar_boleta_con_ventas_en_pie(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[],numeric,numeric,jsonb) to authenticated;
