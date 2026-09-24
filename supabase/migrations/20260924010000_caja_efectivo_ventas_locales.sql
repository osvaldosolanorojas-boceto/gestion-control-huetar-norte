-- La caja usa el mismo libro de movimientos y aplicaciones que los bancos.
-- Así un cobro en efectivo liquida la misma cuenta por cobrar de la venta local.
alter table public.cuentas_bancarias add column tipo_cuenta text not null default 'banco'
  check (tipo_cuenta in ('banco','efectivo'));
insert into public.cuentas_bancarias(banco,moneda,tipo_cuenta,saldo_confirmado)
values ('Caja de efectivo','CRC','efectivo',true),('Caja de efectivo','USD','efectivo',true)
on conflict (banco,moneda) do update set tipo_cuenta='efectivo';

-- Depositar efectivo mueve el saldo entre dos cuentas sin crear ingresos duplicados.
create function public.depositar_efectivo(p_caja_id uuid,p_banco_id uuid,p_fecha date,p_monto numeric,p_referencia text)
returns void language plpgsql security invoker set search_path='' as $$
declare v_caja public.cuentas_bancarias%rowtype; v_banco public.cuentas_bancarias%rowtype; v_neto numeric;
begin
  if p_fecha is null or p_monto is null or p_monto<=0 or p_monto<>round(p_monto,2) then raise exception 'Fecha y monto de depósito inválidos'; end if;
  perform 1 from public.cuentas_bancarias where id in (p_caja_id,p_banco_id) order by id for update;
  select * into v_caja from public.cuentas_bancarias where id=p_caja_id and tipo_cuenta='efectivo' and activo;
  select * into v_banco from public.cuentas_bancarias where id=p_banco_id and tipo_cuenta='banco' and activo;
  if v_caja.id is null or v_banco.id is null or v_caja.moneda<>v_banco.moneda then raise exception 'Seleccione caja y banco de la misma moneda'; end if;
  select neto into v_neto from public.saldos_movimientos_bancarios where cuenta_id=p_caja_id;
  if v_caja.saldo_inicial+coalesce(v_neto,0)<p_monto then raise exception 'No hay suficiente efectivo en caja'; end if;
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
  values(p_caja_id,p_fecha,'egreso',p_monto,'Depósito de efectivo al banco',nullif(trim(p_referencia),''),(select auth.uid()));
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
  values(p_banco_id,p_fecha,'ingreso',p_monto,'Depósito desde caja de efectivo',nullif(trim(p_referencia),''),(select auth.uid()));
end;
$$;
revoke all on function public.depositar_efectivo(uuid,uuid,date,numeric,text) from public,anon;
grant execute on function public.depositar_efectivo(uuid,uuid,date,numeric,text) to authenticated;

-- Venta y cobro ocurren en una misma transacción: ningún cobro queda sin venta.
create function public.registrar_venta_local_con_efectivo(p_codigo text,p_fecha date,p_comprador text,p_referencia text,p_moneda text,p_observaciones text,p_lineas jsonb,p_cobro numeric)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_venta uuid; v_caja uuid;
begin
  if p_cobro is null or p_cobro<=0 or p_cobro<>round(p_cobro,2) then raise exception 'Indique un cobro en efectivo válido'; end if;
  select id into v_caja from public.cuentas_bancarias where tipo_cuenta='efectivo' and moneda=p_moneda and activo;
  if v_caja is null then raise exception 'No hay caja de efectivo disponible para esta moneda'; end if;
  v_venta:=public.registrar_venta_local(p_codigo,p_fecha,p_comprador,p_referencia,p_moneda,p_observaciones,p_lineas);
  perform public.registrar_movimiento_bancario(v_caja,p_fecha,'ingreso',p_cobro,
    'Cobro en efectivo de venta local '||p_codigo,p_referencia,
    jsonb_build_array(jsonb_build_object('origen','venta_local','origen_id',v_venta,'monto',p_cobro)));
  return v_venta;
end;
$$;
revoke all on function public.registrar_venta_local_con_efectivo(text,date,text,text,text,text,jsonb,numeric) from public,anon;
grant execute on function public.registrar_venta_local_con_efectivo(text,date,text,text,text,text,jsonb,numeric) to authenticated;
