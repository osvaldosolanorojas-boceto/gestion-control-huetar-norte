-- El plazo queda fijo en el pedido al escoger cliente; 22 días para fichas sin plazo.
alter table public.ordenes_venta add column plazo_pago_dias integer check(plazo_pago_dias between 0 and 365);
update public.ordenes_venta o set plazo_pago_dias=coalesce(c.plazo_pago_dias,22)
from public.clientes c where c.id=o.cliente_id and o.plazo_pago_dias is null;
update public.ordenes_venta set plazo_pago_dias=22 where plazo_pago_dias is null;
alter table public.ordenes_venta alter column plazo_pago_dias set not null;
create function public.plazo_pedido_cliente() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='INSERT' or new.cliente_id is distinct from old.cliente_id then
    select coalesce(c.plazo_pago_dias,22) into new.plazo_pago_dias from public.clientes c where c.id=new.cliente_id;
    new.plazo_pago_dias:=coalesce(new.plazo_pago_dias,22);
  end if;
  return new;
end;
$$;
create trigger plazo_pedido_cliente before insert or update of cliente_id on public.ordenes_venta
for each row execute function public.plazo_pedido_cliente();

-- Una nota de crédito reduce la factura y figura separada como pérdida comercial.
create table public.notas_credito_ventas (
 id uuid primary key default gen_random_uuid(), orden_venta_id uuid not null references public.ordenes_venta(id),
 fecha date not null, monto numeric(16,2) not null check(monto>0), motivo text not null check(length(trim(motivo))>0),
 referencia text, registrado_por uuid references public.perfiles(id) default auth.uid(), creado_en timestamptz not null default now()
);
create index notas_credito_ventas_orden_idx on public.notas_credito_ventas(orden_venta_id);
alter table public.notas_credito_ventas enable row level security;
revoke all on public.notas_credito_ventas from anon,authenticated;
grant select,insert on public.notas_credito_ventas to authenticated;
create policy gestion_oficina on public.notas_credito_ventas for all to authenticated
using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.validar_nota_credito_venta() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_total numeric; v_acreditado numeric; v_pagado numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('venta_exportacion'||new.orden_venta_id::text,0));
  select monto_cxc into v_total from public.ordenes_venta where id=new.orden_venta_id and finalizada_en is not null for update;
  if v_total is null then raise exception 'Finalice el pedido antes de registrar una nota de crédito'; end if;
  select coalesce(sum(monto),0) into v_acreditado from public.notas_credito_ventas where orden_venta_id=new.orden_venta_id;
  select coalesce(sum(monto),0) into v_pagado from public.aplicaciones_bancarias where origen='venta_exportacion' and origen_id=new.orden_venta_id;
  if new.monto<>round(new.monto,2) or new.monto>v_total-v_acreditado-v_pagado then raise exception 'La nota de crédito supera el saldo pendiente del pedido o tiene decimales inválidos'; end if;
  new.registrado_por:=(select auth.uid());
  return new;
end;
$$;
create trigger validar_nota_credito_venta before insert on public.notas_credito_ventas
for each row execute function public.validar_nota_credito_venta();

-- Los adelantos son dinero efectivamente pagado y no una cifra estimada en la orden.
create table public.adelantos_compra (
 id uuid primary key default gen_random_uuid(), orden_compra_id uuid not null references public.ordenes_compra(id),
 movimiento_id uuid not null unique references public.movimientos_bancarios(id), monto numeric(16,2) not null check(monto>0),
 fecha date not null, registrado_por uuid references public.perfiles(id) default auth.uid(), creado_en timestamptz not null default now()
);
create index adelantos_compra_orden_idx on public.adelantos_compra(orden_compra_id);
alter table public.adelantos_compra enable row level security;
revoke all on public.adelantos_compra from anon,authenticated;
grant select,insert on public.adelantos_compra to authenticated;
create policy gestion_oficina on public.adelantos_compra for all to authenticated
using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.validar_adelanto_compra() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_m public.movimientos_bancarios%rowtype; v_currency text;
begin
  select * into v_m from public.movimientos_bancarios where id=new.movimiento_id;
  select moneda into v_currency from public.cuentas_bancarias where id=v_m.cuenta_id;
  if v_m.id is null or v_m.tipo<>'egreso' or v_m.monto<>new.monto or v_m.fecha<>new.fecha or v_currency<>'CRC'
    or exists(select 1 from public.aplicaciones_bancarias where movimiento_id=new.movimiento_id)
    or not exists(select 1 from public.ordenes_compra where id=new.orden_compra_id and coalesce(estado,'')<>'Anulada') then
    raise exception 'El adelanto debe coincidir con un egreso en colones a una compra vigente';
  end if;
  new.registrado_por:=(select auth.uid());
  return new;
end;
$$;
create trigger validar_adelanto_compra before insert on public.adelantos_compra
for each row execute function public.validar_adelanto_compra();
create function public.registrar_adelanto_compra(p_orden_id uuid,p_cuenta_id uuid,p_fecha date,p_monto numeric,p_referencia text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid; v_codigo text; v_moneda text;
begin
  if p_fecha is null or p_monto is null or p_monto<=0 or p_monto<>round(p_monto,2) then raise exception 'Fecha o importe del adelanto inválido'; end if;
  select codigo into v_codigo from public.ordenes_compra where id=p_orden_id and coalesce(estado,'')<>'Anulada' for update;
  select moneda into v_moneda from public.cuentas_bancarias where id=p_cuenta_id and activo;
  if v_codigo is null or v_moneda<>'CRC' then raise exception 'Seleccione una compra vigente y cuenta en colones'; end if;
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
  values(p_cuenta_id,p_fecha,'egreso',p_monto,'Adelanto a productor · '||v_codigo,nullif(trim(p_referencia),''),(select auth.uid())) returning id into v_id;
  insert into public.adelantos_compra(orden_compra_id,movimiento_id,monto,fecha,registrado_por)
  values(p_orden_id,v_id,p_monto,p_fecha,(select auth.uid()));
  return v_id;
end;
$$;
revoke all on function public.registrar_adelanto_compra(uuid,uuid,date,numeric,text) from public,anon;
grant execute on function public.registrar_adelanto_compra(uuid,uuid,date,numeric,text) to authenticated;

create table public.cuentas_manuales (
 id uuid primary key default gen_random_uuid(), codigo text not null unique,
 tipo text not null check(tipo in ('cobrar','pagar')), fecha date not null, fecha_vencimiento date not null,
 contraparte text not null check(length(trim(contraparte))>0), cliente_id uuid references public.clientes(id),
 proveedor_id uuid references public.proveedores(id), moneda text not null check(moneda in ('CRC','USD')),
 monto numeric(16,2) not null check(monto>0), concepto text not null check(length(trim(concepto))>0),
 referencia text, registrado_por uuid references public.perfiles(id) default auth.uid(), creado_en timestamptz not null default now()
);
alter table public.cuentas_manuales enable row level security;
revoke all on public.cuentas_manuales from anon,authenticated;
grant select,insert on public.cuentas_manuales to authenticated;
create policy gestion_oficina on public.cuentas_manuales for all to authenticated
using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

-- Adelantos reales reducen la deuda hasta el monto liquidado.
create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete)::numeric(16,2) monto,
  least(greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa,o.producto
from public.ordenes_compra o join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra is distinct from 'Puesto en camión' and not (o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,o.precio_en_pie-o.rebaja_planilla_flete)::numeric(16,2),
  least(greatest(0,o.precio_en_pie-o.rebaja_planilla_flete),coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)+coalesce((select sum(ad.monto) from public.adelantos_compra ad where ad.orden_compra_id=o.id),0))::numeric(16,2),
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
select 'flete_compra'::text,o.id,o.codigo,o.fecha,
  t.nombre,'CRC'::text,o.flete::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='flete_compra' and a.origen_id=o.id),0)::numeric(16,2),
  'Flete de compra'::text,o.producto
from public.ordenes_compra o join public.proveedores t on t.id=o.flete_proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.flete>0
union all
select 'cuenta_manual_pagar'::text,m.id,m.codigo,m.fecha,m.contraparte,m.moneda,
  m.monto,coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='cuenta_manual_pagar' and a.origen_id=m.id),0)::numeric(16,2),
  'Registro manual'::text,null::text as producto
from public.cuentas_manuales m where m.tipo='pagar';




-- No se altera el orden de columnas existente: las vistas ya tienen consumidores.
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

alter table public.aplicaciones_bancarias drop constraint aplicaciones_bancarias_origen_check;
alter table public.aplicaciones_bancarias add constraint aplicaciones_bancarias_origen_check
check(origen in ('venta_exportacion','venta_local','compra_campo','flete_compra','saldo_productor','cuenta_manual_cobrar','cuenta_manual_pagar'));

-- La aplicación bancaria acepta nuevas cuentas y bloquea cobros de pedidos previstos.
create or replace function public.registrar_movimiento_bancario(p_cuenta_id uuid,p_fecha date,p_tipo text,p_monto numeric,p_concepto text,p_referencia text,p_aplicaciones jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_moneda text; v_mov uuid; v_app jsonb; v_origen text; v_id uuid; v_amount numeric; v_due numeric; v_used numeric:=0; v_tipo text;
begin
  if p_tipo not in ('ingreso','egreso') or p_monto is null or p_monto<=0 or p_fecha is null or nullif(trim(p_concepto),'') is null then raise exception 'Complete tipo, monto, fecha y concepto'; end if;
  select moneda into v_moneda from public.cuentas_bancarias where id=p_cuenta_id and activo;
  if v_moneda is null then raise exception 'Cuenta bancaria no disponible'; end if;
  if p_aplicaciones is not null and jsonb_typeof(p_aplicaciones)<>'array' then raise exception 'Aplicaciones inválidas'; end if;
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
    values(p_cuenta_id,p_fecha,p_tipo,p_monto,trim(p_concepto),nullif(trim(p_referencia),''),(select auth.uid())) returning id into v_mov;
  for v_app in select value from jsonb_array_elements(coalesce(p_aplicaciones,'[]'::jsonb)) loop
    v_origen:=v_app->>'origen';v_id:=(v_app->>'origen_id')::uuid;v_amount:=(v_app->>'monto')::numeric;
    if v_amount is null or v_amount<=0 or v_amount<>round(v_amount,2) then raise exception 'Monto aplicado inválido'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_origen||v_id::text,0));
    if v_origen in ('venta_exportacion','venta_local','saldo_productor','cuenta_manual_cobrar') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxc_operativa where origen=v_origen and origen_id=v_id and etapa<>'Pedido previsto';
      if p_tipo<>'ingreso' then raise exception 'Un cobro debe ser un ingreso'; end if;
    elsif v_origen in ('compra_campo','flete_compra','cuenta_manual_pagar') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxp_operativa where origen=v_origen and origen_id=v_id;
      if p_tipo<>'egreso' then raise exception 'Un pago debe ser un egreso'; end if;
    else raise exception 'Origen financiero inválido'; end if;
    if v_tipo is null or v_tipo<>v_moneda or v_amount>v_due then raise exception 'Documento no disponible, moneda distinta o monto superior al saldo'; end if;
    v_used:=v_used+v_amount;
    if v_used>p_monto then raise exception 'Las aplicaciones superan el movimiento bancario'; end if;
    insert into public.aplicaciones_bancarias(movimiento_id,origen,origen_id,monto) values(v_mov,v_origen,v_id,v_amount);
  end loop;
  return v_mov;
end;
$$;
create or replace function public.validar_aplicacion_bancaria() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_m public.movimientos_bancarios%rowtype; v_moneda text; v_origen_moneda text; v_due numeric; v_used numeric;
begin
  -- Bloqueos consultivos evitan requerir permiso UPDATE sobre un movimiento ya registrado.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.movimiento_id::text,1));
  select * into v_m from public.movimientos_bancarios where id=new.movimiento_id;
  if not found then raise exception 'Movimiento bancario no disponible'; end if;
  select moneda into v_moneda from public.cuentas_bancarias where id=v_m.cuenta_id;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.origen||new.origen_id::text,0));
  if new.origen in ('venta_exportacion','venta_local','saldo_productor','cuenta_manual_cobrar') then
    if v_m.tipo<>'ingreso' then raise exception 'Una venta solo puede aplicarse a un ingreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxc_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Pedido previsto';
  elsif new.origen in ('compra_campo','flete_compra','cuenta_manual_pagar') then
    if v_m.tipo<>'egreso' then raise exception 'Una compra solo puede aplicarse a un egreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxp_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Faltan precios';
  end if;
  if v_origen_moneda is null or v_origen_moneda<>v_moneda or new.monto>v_due then raise exception 'Documento sin saldo suficiente o moneda distinta'; end if;
  select coalesce(sum(monto),0) into v_used from public.aplicaciones_bancarias where movimiento_id=new.movimiento_id;
  if v_used+new.monto>v_m.monto then raise exception 'Aplicaciones superiores al movimiento bancario'; end if;
  return new;
end;
$$;
