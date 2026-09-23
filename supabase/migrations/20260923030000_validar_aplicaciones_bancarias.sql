-- Protege el saldo aun cuando una aplicación llegue por la API fuera del formulario.
create function public.validar_aplicacion_bancaria() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_m public.movimientos_bancarios%rowtype; v_moneda text; v_origen_moneda text; v_due numeric; v_used numeric;
begin
  select * into v_m from public.movimientos_bancarios where id=new.movimiento_id for update;
  if not found then raise exception 'Movimiento bancario no disponible'; end if;
  select moneda into v_moneda from public.cuentas_bancarias where id=v_m.cuenta_id;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.origen||new.origen_id::text,0));
  if new.origen in ('venta_exportacion','venta_local') then
    if v_m.tipo<>'ingreso' then raise exception 'Una venta solo puede aplicarse a un ingreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxc_operativa where origen=new.origen and origen_id=new.origen_id;
  elsif new.origen='compra_campo' then
    if v_m.tipo<>'egreso' then raise exception 'Una compra solo puede aplicarse a un egreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxp_operativa where origen_id=new.origen_id and etapa<>'Faltan precios';
  end if;
  if v_origen_moneda is null or v_origen_moneda<>v_moneda or new.monto>v_due then raise exception 'Documento sin saldo suficiente o moneda distinta'; end if;
  select coalesce(sum(monto),0) into v_used from public.aplicaciones_bancarias where movimiento_id=new.movimiento_id;
  if v_used+new.monto>v_m.monto then raise exception 'Aplicaciones superiores al movimiento bancario'; end if;
  return new;
end;
$$;
create trigger validar_aplicacion_bancaria before insert on public.aplicaciones_bancarias for each row execute function public.validar_aplicacion_bancaria();
