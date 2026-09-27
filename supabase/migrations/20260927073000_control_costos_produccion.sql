-- Un costo se registra una sola vez. El período cubierto permite distribuirlo
-- entre semanas sin confundir la fecha de pago con la de consumo.
create table public.costos_produccion (
  id uuid primary key default gen_random_uuid(),
  categoria text not null check (categoria in ('gas','electricidad','agua','carton','empaque','tratamiento','limpieza','proteccion','mantenimiento','carga','puerto','documentacion','alquiler','depreciacion','otros')),
  concepto text not null check (length(trim(concepto))>0),
  periodo_inicio date not null,
  periodo_fin date not null,
  fecha_factura date,
  moneda text not null check (moneda in ('CRC','USD')),
  monto numeric(16,2) not null check (monto>0),
  cantidad numeric(14,3),
  unidad text,
  producto text,
  linea_proceso smallint check (linea_proceso in (1,2)),
  orden_venta_id uuid references public.ordenes_venta(id),
  boleta_id uuid references public.boletas_entrada(id),
  insumo_id uuid references public.insumos(id),
  movimiento_insumo_id uuid unique references public.movimientos_insumos(id),
  referencia text,
  observaciones text,
  registrado_por uuid not null default auth.uid() references public.perfiles(id),
  creado_en timestamptz not null default now(),
  anulado_en timestamptz,
  check (periodo_fin>=periodo_inicio),
  check ((cantidad is null and unidad is null) or (cantidad>0 and unidad is not null and length(trim(unidad))>0)),
  check (movimiento_insumo_id is null or (insumo_id is not null and periodo_inicio=periodo_fin))
);
create index costos_produccion_periodo_idx on public.costos_produccion(periodo_inicio,periodo_fin) where anulado_en is null;
alter table public.costos_produccion enable row level security;
revoke all on public.costos_produccion from anon,authenticated;
grant select,insert,update on public.costos_produccion to authenticated;
create policy gestion_costos_produccion on public.costos_produccion for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.proteger_costo_produccion() returns trigger language plpgsql set search_path='' as $$
begin
  if old.anulado_en is not null then raise exception 'El costo anulado no se puede cambiar'; end if;
  if old.movimiento_insumo_id is not null then raise exception 'El consumo de inventario se corrige con un movimiento de ajuste'; end if;
  if new.movimiento_insumo_id is distinct from old.movimiento_insumo_id or new.registrado_por<>old.registrado_por or new.creado_en<>old.creado_en then
    raise exception 'No cambie el origen del costo';
  end if;
  if new.anulado_en is not null and new.anulado_en<>old.anulado_en and
    row(new.categoria,new.concepto,new.periodo_inicio,new.periodo_fin,new.fecha_factura,new.moneda,new.monto,new.cantidad,new.unidad,new.producto,new.linea_proceso,new.orden_venta_id,new.boleta_id,new.insumo_id,new.referencia,new.observaciones)
    is distinct from
    row(old.categoria,old.concepto,old.periodo_inicio,old.periodo_fin,old.fecha_factura,old.moneda,old.monto,old.cantidad,old.unidad,old.producto,old.linea_proceso,old.orden_venta_id,old.boleta_id,old.insumo_id,old.referencia,old.observaciones)
  then raise exception 'No cambie el detalle al anular'; end if;
  return new;
end;
$$;
create trigger proteger_costo_produccion before update on public.costos_produccion
  for each row execute function public.proteger_costo_produccion();

-- Este RPC registra el movimiento físico y el costo en una sola transacción.
create function public.consumir_insumo_costeado(
  p_insumo_id uuid,p_cantidad numeric,p_fecha date,p_moneda text,p_monto numeric,
  p_producto text default null,p_linea smallint default null,p_boleta_id uuid default null,
  p_orden_venta_id uuid default null,p_referencia text default null,p_observaciones text default null
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_insumo public.insumos%rowtype; v_movimiento uuid; v_costo uuid;
begin
  if p_fecha is null or p_moneda not in ('CRC','USD') or p_monto is null or p_monto<=0 or p_monto<>round(p_monto,2)
     or p_cantidad is null or p_cantidad<=0 or p_cantidad<>round(p_cantidad,3) then
    raise exception 'Complete fecha, cantidad, moneda y costo válidos';
  end if;
  update public.insumos set existencia=existencia-p_cantidad
    where id=p_insumo_id and activo and existencia>=p_cantidad returning * into v_insumo;
  if not found then raise exception 'Insumo no disponible o existencia insuficiente'; end if;
  insert into public.movimientos_insumos(insumo_id,tipo,cantidad,referencia,observaciones,registrado_por)
    values (p_insumo_id,'consumo',p_cantidad,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid()))
    returning id into v_movimiento;
  insert into public.costos_produccion(categoria,concepto,periodo_inicio,periodo_fin,moneda,monto,cantidad,unidad,producto,linea_proceso,boleta_id,orden_venta_id,insumo_id,movimiento_insumo_id,referencia,observaciones)
    values (case when v_insumo.categoria in ('Parafina','Cera') then 'tratamiento' when v_insumo.categoria in ('Cloro') then 'limpieza' else 'empaque' end,
      'Consumo · '||v_insumo.nombre,p_fecha,p_fecha,p_moneda,p_monto,p_cantidad,v_insumo.unidad,
      nullif(trim(p_producto),''),p_linea,p_boleta_id,p_orden_venta_id,p_insumo_id,v_movimiento,
      nullif(trim(p_referencia),''),nullif(trim(p_observaciones),'')) returning id into v_costo;
  return v_costo;
end;
$$;
revoke all on function public.consumir_insumo_costeado(uuid,numeric,date,text,numeric,text,smallint,uuid,uuid,text,text) from public,anon;
grant execute on function public.consumir_insumo_costeado(uuid,numeric,date,text,numeric,text,smallint,uuid,uuid,text,text) to authenticated;

create table public.mermas_produccion (
  id uuid primary key default gen_random_uuid(),
  boleta_id uuid not null references public.boletas_entrada(id),
  categoria text not null check (categoria in ('tierra','humedad','pelado','proceso','danio','desperdicio','otra')),
  kilos numeric(14,3) not null check (kilos>0),
  observaciones text,
  registrado_por uuid not null default auth.uid() references public.perfiles(id),
  creado_en timestamptz not null default now(),
  anulado_en timestamptz
);
create index mermas_produccion_boleta_idx on public.mermas_produccion(boleta_id) where anulado_en is null;
alter table public.mermas_produccion enable row level security;
revoke all on public.mermas_produccion from anon,authenticated;
grant select,insert,update on public.mermas_produccion to authenticated;
create policy gestion_mermas_produccion on public.mermas_produccion for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.proteger_merma_produccion() returns trigger language plpgsql set search_path='' as $$
begin
  if old.anulado_en is not null or new.anulado_en is null or new.registrado_por<>old.registrado_por or new.creado_en<>old.creado_en or
     row(new.boleta_id,new.categoria,new.kilos,new.observaciones) is distinct from row(old.boleta_id,old.categoria,old.kilos,old.observaciones)
  then raise exception 'Solo se permite anular la clasificación conservando el original'; end if;
  return new;
end;
$$;
create trigger proteger_merma_produccion before update on public.mermas_produccion
  for each row execute function public.proteger_merma_produccion();

alter table public.usuarios_preparados drop constraint if exists usuarios_preparados_modulos_check;
alter table public.usuarios_preparados add constraint usuarios_preparados_modulos_check
  check (modulos <@ array['Resumen','Órdenes de compra','Boletas de entrada','Producción y rendimientos','Mapa de carga','Saldo yuca EE. UU.','Segundas y rechazo','Órdenes de venta','Proveedores','Clientes','Colaboradores','Empresas','Inventarios','Finanzas','Efectivo','Bancos','Planilla de planta','Control de costos','Corte semanal','Fincas']::text[]);
