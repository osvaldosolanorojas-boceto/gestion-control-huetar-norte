-- Compra por carga en camión: costo fijo de ingreso, rendimiento informativo y flete separado.
alter table public.proveedores drop constraint proveedores_tipo_check;
alter table public.proveedores add constraint proveedores_tipo_check
  check (tipo in ('Agricultor','Intermediario','Propio','Transportista'));
alter table public.ordenes_compra
  add column peso_caja_camion_kg numeric(10,3) check (peso_caja_camion_kg>0),
  add column precio_puesto_camion numeric(14,2) check (precio_puesto_camion>0),
  add column flete_proveedor_id uuid references public.proveedores(id);
alter table public.ordenes_compra add constraint compra_camion_detalle_check
  check (tipo_compra is distinct from 'Puesto en camión' or
    (unidad='Cajas' and cantidad_comprada>0 and cantidad_comprada=trunc(cantidad_comprada)
      and peso_caja_camion_kg>0 and precio_puesto_camion>0));
alter table public.ordenes_compra add constraint flete_compra_pagador_check
  check (tipo_compra is distinct from 'Puesto en camión' or coalesce(flete,0)=0 or flete_proveedor_id is not null);
alter table public.aplicaciones_bancarias drop constraint aplicaciones_bancarias_origen_check;
alter table public.aplicaciones_bancarias add constraint aplicaciones_bancarias_origen_check
  check (origen in ('venta_exportacion','venta_local','compra_campo','flete_compra'));

create or replace function public.finalizar_boleta_entrada(p_boleta_id uuid) returns numeric
language plpgsql security definer set search_path='' as $$
declare v_b public.boletas_entrada%rowtype; v_o public.ordenes_compra%rowtype; v_r record; v_price numeric; v_amount numeric:=0;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar boletas'; end if;
  select * into v_b from public.boletas_entrada where id=p_boleta_id for update;
  if not found then raise exception 'No se encontró la boleta'; end if;
  if v_b.finalizada_en is not null then raise exception 'Esta boleta ya está finalizada'; end if;
  if v_b.orden_compra_id is null then raise exception 'Enlace la orden de compra antes de finalizar'; end if;
  select * into v_o from public.ordenes_compra where id=v_b.orden_compra_id for update;
  if v_b.fin_proceso is null then raise exception 'Registre el final del proceso antes de finalizar'; end if;
  if not exists(select 1 from public.boleta_rendimientos where boleta_id=p_boleta_id) then raise exception 'Registre al menos un rendimiento antes de finalizar'; end if;
  if v_o.producto='Ñampí' and v_o.tipo_compra='En pie' then
    raise exception 'El ñampí en pie se paga por lote desde la orden; sus boletas permanecen abiertas para registrar todo el rendimiento';
  end if;
  if v_o.tipo_compra='Puesto en camión' then
    -- La deuda se registra al guardar la orden, nunca por rendimiento.
    v_amount:=0;
  elsif v_o.tipo_compra='En pie' then
    if v_o.precio_en_pie is null or v_o.precio_en_pie<=0 then raise exception 'Falta el precio de compra en pie'; end if;
    if exists(select 1 from public.boletas_entrada where orden_compra_id=v_o.id and finalizada_en is not null) then
      raise exception 'Esta compra en pie ya tiene una boleta cerrada; revise su liquidación';
    end if;
    v_amount:=v_o.precio_en_pie;
  else
    for v_r in select calidad,kg_resultado,paga_productor from public.boleta_rendimientos where boleta_id=p_boleta_id loop
      if v_r.paga_productor then
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when v_o.producto='Ñampí' then v_o.precio_campo
          when v_r.calidad='Exportable Europa' then v_o.precio_europa
          when v_r.calidad='Exportable estadounidense' then v_o.precio_eeuu
          when v_r.calidad='Segunda gruesa' then v_o.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then v_o.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then v_o.precio_rechazo
          else v_o.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+v_r.kg_resultado/46*v_price;
      end if;
    end loop;
  end if;
  update public.boletas_entrada set finalizada_en=now(),finalizada_por=(select auth.uid()),monto_cxp=round(v_amount,2) where id=p_boleta_id;
  return round(v_amount,2);
end;
$$;
create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  greatest(0,coalesce(sum(b.monto_cxp),0)-o.rebaja_planilla_flete)::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa
from public.ordenes_compra o join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra is distinct from 'Puesto en camión' and not (o.producto='Ñampí' and o.tipo_compra='En pie')
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,o.precio_en_pie-o.rebaja_planilla_flete)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)::numeric(16,2),
  'Ñampí en pie · rendimiento abierto'::text
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.producto='Ñampí' and o.tipo_compra='En pie' and o.precio_en_pie>0
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,round(o.cantidad_comprada*o.peso_caja_camion_kg/46*o.precio_puesto_camion,2)-o.rebaja_planilla_flete)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)::numeric(16,2),
  'Puesto en camión · precio fijo'::text
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.tipo_compra='Puesto en camión'
union all
select 'flete_compra'::text,o.id,o.codigo,o.fecha,
  t.nombre,'CRC'::text,o.flete::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='flete_compra' and a.origen_id=o.id),0)::numeric(16,2),
  'Flete de compra'::text
from public.ordenes_compra o join public.proveedores t on t.id=o.flete_proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.flete>0;

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
    if v_origen in ('venta_exportacion','venta_local') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxc_operativa where origen=v_origen and origen_id=v_id;
      if p_tipo<>'ingreso' then raise exception 'Un cobro debe ser un ingreso'; end if;
    elsif v_origen in ('compra_campo','flete_compra') then
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
  if new.origen in ('venta_exportacion','venta_local') then
    if v_m.tipo<>'ingreso' then raise exception 'Una venta solo puede aplicarse a un ingreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxc_operativa where origen=new.origen and origen_id=new.origen_id;
  elsif new.origen in ('compra_campo','flete_compra') then
    if v_m.tipo<>'egreso' then raise exception 'Una compra solo puede aplicarse a un egreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxp_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Faltan precios';
  end if;
  if v_origen_moneda is null or v_origen_moneda<>v_moneda or new.monto>v_due then raise exception 'Documento sin saldo suficiente o moneda distinta'; end if;
  select coalesce(sum(monto),0) into v_used from public.aplicaciones_bancarias where movimiento_id=new.movimiento_id;
  if v_used+new.monto>v_m.monto then raise exception 'Aplicaciones superiores al movimiento bancario'; end if;
  return new;
end;
$$;
create or replace function public.anular_orden_compra(p_orden_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_o public.ordenes_compra%rowtype;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then
    raise exception 'Solo administración u oficina puede anular compras';
  end if;
  select * into v_o from public.ordenes_compra where id=p_orden_id for update;
  if not found then raise exception 'No se encontró la orden de compra'; end if;
  if v_o.estado='Anulada' then raise exception 'La orden ya está anulada'; end if;
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=p_orden_id) then
    raise exception 'La compra tiene boletas; no puede anularla';
  end if;
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen in ('compra_campo','flete_compra') and a.origen_id=p_orden_id) then
    raise exception 'La compra tiene pagos aplicados; no puede anularla';
  end if;
  update public.ordenes_compra set estado='Anulada',anulada_en=now(),anulada_por=(select auth.uid()) where id=p_orden_id;
end;
$$;
-- Congelar importes y beneficiarios cuando ya se aplicó un pago.
create function public.proteger_importes_compra_pagada() returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=old.id)
     and (old.cantidad_comprada is distinct from new.cantidad_comprada
       or old.peso_caja_camion_kg is distinct from new.peso_caja_camion_kg
       or old.precio_puesto_camion is distinct from new.precio_puesto_camion
       or old.precio_en_pie is distinct from new.precio_en_pie
       or old.rebaja_planilla_flete is distinct from new.rebaja_planilla_flete
       or old.proveedor_id is distinct from new.proveedor_id
       or old.tipo_compra is distinct from new.tipo_compra) then
    raise exception 'La compra tiene pagos aplicados; no puede cambiar el monto ni el productor';
  end if;
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen='flete_compra' and a.origen_id=old.id)
     and (old.flete is distinct from new.flete or old.flete_proveedor_id is distinct from new.flete_proveedor_id) then
    raise exception 'El flete tiene pagos aplicados; no puede cambiar el monto ni el beneficiario';
  end if;
  return new;
end;
$$;
create trigger proteger_importes_compra_pagada before update on public.ordenes_compra
for each row execute function public.proteger_importes_compra_pagada();

