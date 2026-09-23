-- Seis cuentas operativas. El saldo inicial se confirma al empezar la conciliación.
create table public.cuentas_bancarias (
  id uuid primary key default gen_random_uuid(),
  banco text not null,
  moneda text not null check(moneda in ('CRC','USD')),
  saldo_inicial numeric(16,2) not null default 0,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  unique(banco,moneda)
);
insert into public.cuentas_bancarias(banco,moneda) values
('Banco Nacional de Costa Rica','CRC'),('Banco Nacional de Costa Rica','USD'),
('Banco de Costa Rica','CRC'),('Banco de Costa Rica','USD'),
('BAC San José','CRC'),('BAC San José','USD');
alter table public.cuentas_bancarias enable row level security;
revoke all on public.cuentas_bancarias from anon,authenticated;
grant select,update on public.cuentas_bancarias to authenticated;
create policy gestion_oficina on public.cuentas_bancarias for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create table public.movimientos_bancarios (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references public.cuentas_bancarias(id),
  fecha date not null,
  tipo text not null check(tipo in ('ingreso','egreso')),
  monto numeric(16,2) not null check(monto>0),
  concepto text not null check(length(trim(concepto))>0),
  referencia text,
  registrado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default now()
);
create index movimientos_bancarios_cuenta_fecha_idx on public.movimientos_bancarios(cuenta_id,fecha desc);
alter table public.movimientos_bancarios enable row level security;
revoke all on public.movimientos_bancarios from anon,authenticated;
grant select,insert on public.movimientos_bancarios to authenticated;
create policy gestion_oficina on public.movimientos_bancarios for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create table public.aplicaciones_bancarias (
  id uuid primary key default gen_random_uuid(),
  movimiento_id uuid not null references public.movimientos_bancarios(id),
  origen text not null check(origen in ('venta_exportacion','venta_local','compra_campo')),
  origen_id uuid not null,
  monto numeric(16,2) not null check(monto>0),
  creado_en timestamptz not null default now(),
  unique(movimiento_id,origen,origen_id)
);
create index aplicaciones_bancarias_origen_idx on public.aplicaciones_bancarias(origen,origen_id);
alter table public.aplicaciones_bancarias enable row level security;
revoke all on public.aplicaciones_bancarias from anon,authenticated;
grant select,insert on public.aplicaciones_bancarias to authenticated;
create policy gestion_oficina on public.aplicaciones_bancarias for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

-- Los saldos se derivan de las órdenes actuales, para reflejar cambios sin duplicar deudas.
create view public.cxc_operativa with (security_invoker=true) as
select 'venta_exportacion'::text origen,o.id origen_id,o.codigo,o.fecha,c.nombre contraparte,'USD'::text moneda,
  coalesce(sum(l.total),0)::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_exportacion' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  'Pedido previsto'::text etapa
from public.ordenes_venta o left join public.clientes c on c.id=o.cliente_id
left join public.ordenes_venta_lineas l on l.orden_venta_id=o.id
group by o.id,o.codigo,o.fecha,c.nombre
union all
select 'venta_local',v.id,v.codigo,v.fecha,v.comprador,v.moneda,
  coalesce((select sum(s.subtotal) from public.ventas_segundas s where s.venta_local_id=v.id),0)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_local' and a.origen_id=v.id),0)::numeric(16,2),
  'Venta registrada'
from public.ventas_locales v;

create view public.cxp_operativa with (security_invoker=true) as
with rendimientos as (
  select o.id orden_id,count(r.id) partidas,
    count(r.id) filter (where r.paga_productor and r.kg_resultado>0 and
      case when r.calidad='Exportable Europa' then o.precio_europa
           when r.calidad='Exportable estadounidense' then o.precio_eeuu
           when r.calidad='Segunda gruesa' then o.precio_segunda_gruesa
           when r.calidad='Segunda menuda' then o.precio_segunda_menuda
           when r.calidad like 'Rechazo%' then o.precio_rechazo
           else o.precio_campo end is null) sin_precio,
    sum(case when r.paga_productor then r.kg_resultado/46 *
      case when r.calidad='Exportable Europa' then o.precio_europa
           when r.calidad='Exportable estadounidense' then o.precio_eeuu
           when r.calidad='Segunda gruesa' then o.precio_segunda_gruesa
           when r.calidad='Segunda menuda' then o.precio_segunda_menuda
           when r.calidad like 'Rechazo%' then o.precio_rechazo
           else o.precio_campo end else 0 end) total
  from public.ordenes_compra o join public.boletas_entrada b on b.orden_compra_id=o.id
  join public.boleta_rendimientos r on r.boleta_id=b.id group by o.id
)
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  round(case when o.tipo_compra='En pie' and o.precio_en_pie is not null then o.precio_en_pie else coalesce(r.total,0) end,2)::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  case when o.tipo_compra='En pie' and o.precio_en_pie is not null then 'Compra estimada'
       when r.sin_precio>0 then 'Faltan precios' else 'Rendimiento estimado' end::text etapa
from public.ordenes_compra o join rendimientos r on r.orden_id=o.id
left join public.proveedores p on p.id=o.proveedor_id;
revoke all on public.cxc_operativa,public.cxp_operativa from anon,authenticated;
grant select on public.cxc_operativa,public.cxp_operativa to authenticated;

create function public.registrar_movimiento_bancario(p_cuenta_id uuid,p_fecha date,p_tipo text,p_monto numeric,p_concepto text,p_referencia text,p_aplicaciones jsonb)
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
    if v_origen in ('venta_exportacion','venta_local') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxc_operativa where origen=v_origen and origen_id=v_id;
      if p_tipo<>'ingreso' then raise exception 'Un cobro debe ser un ingreso'; end if;
    elsif v_origen='compra_campo' then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxp_operativa where origen_id=v_id;
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
revoke all on function public.registrar_movimiento_bancario(uuid,date,text,numeric,text,text,jsonb) from public,anon;
grant execute on function public.registrar_movimiento_bancario(uuid,date,text,numeric,text,text,jsonb) to authenticated;
