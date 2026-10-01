alter table public.cuentas_manuales add column empresa text not null default 'exportadora' check(empresa in ('exportadora','agro_solano'));
create or replace function public.validar_empresa_aplicacion() returns trigger
language plpgsql security invoker set search_path='' as $$
declare v_empresa_banco text; v_empresa_documento text:='exportadora';
begin
 select c.empresa into v_empresa_banco from public.movimientos_bancarios m join public.cuentas_bancarias c on c.id=m.cuenta_id where m.id=new.movimiento_id;
 if new.origen in ('cuenta_manual_cobrar','cuenta_manual_pagar') then
  select empresa into v_empresa_documento from public.cuentas_manuales where id=new.origen_id;
 end if;
 if v_empresa_banco is distinct from v_empresa_documento then
  raise exception 'La cuenta bancaria y el documento deben pertenecer a la misma empresa';
 end if;
 return new;
end $$;
create trigger validar_empresa_aplicacion before insert or update on public.aplicaciones_bancarias for each row execute function public.validar_empresa_aplicacion();
create or replace function public.validar_empresa_cuenta_manual() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.empresa is distinct from old.empresa then raise exception 'Una cuenta registrada no puede trasladarse a otra empresa'; end if;
 return new;
end $$;
create trigger validar_empresa_cuenta_manual before update on public.cuentas_manuales for each row execute function public.validar_empresa_cuenta_manual();

create or replace function public.depositar_efectivo(p_caja_id uuid,p_banco_id uuid,p_fecha date,p_monto numeric,p_referencia text)
returns void language plpgsql security invoker set search_path='' as $$
declare v_caja public.cuentas_bancarias%rowtype; v_banco public.cuentas_bancarias%rowtype; v_neto numeric;
begin
  if p_fecha is null or p_monto is null or p_monto<=0 or p_monto<>round(p_monto,2) then raise exception 'Fecha y monto de depósito inválidos'; end if;
  perform 1 from public.cuentas_bancarias where id in (p_caja_id,p_banco_id) order by id for update;
  select * into v_caja from public.cuentas_bancarias where id=p_caja_id and tipo_cuenta='efectivo' and activo;
  select * into v_banco from public.cuentas_bancarias where id=p_banco_id and tipo_cuenta='banco' and activo;
  if v_caja.id is null or v_banco.id is null or v_caja.moneda<>v_banco.moneda or v_caja.empresa<>v_banco.empresa then raise exception 'Seleccione caja y banco de la misma empresa y moneda'; end if;
  select neto into v_neto from public.saldos_movimientos_bancarios where cuenta_id=p_caja_id;
  if v_caja.saldo_inicial+coalesce(v_neto,0)<p_monto then raise exception 'No hay suficiente efectivo en caja'; end if;
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
  values(p_caja_id,p_fecha,'egreso',p_monto,'Depósito de efectivo al banco',nullif(trim(p_referencia),''),(select auth.uid()));
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
  values(p_banco_id,p_fecha,'ingreso',p_monto,'Depósito desde caja de efectivo',nullif(trim(p_referencia),''),(select auth.uid()));
end;
$$;
