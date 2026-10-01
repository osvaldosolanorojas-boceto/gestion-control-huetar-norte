alter table public.cuentas_manuales add column categoria text not null default 'Otros' check(btrim(categoria)<>'');
grant update on public.cuentas_manuales to authenticated;
create or replace function public.validar_edicion_cuenta_manual() returns trigger
language plpgsql security invoker set search_path='' as $$
declare aplicado numeric; v_origen text;
begin
 v_origen:=case when old.tipo='cobrar' then 'cuenta_manual_cobrar' else 'cuenta_manual_pagar' end;
 select coalesce(sum(a.monto),0) into aplicado from public.aplicaciones_bancarias a where a.origen=v_origen and a.origen_id=old.id;
 if new.tipo is distinct from old.tipo then raise exception 'No cambie el tipo de una cuenta existente'; end if;
 if new.monto<aplicado then raise exception 'El monto no puede ser menor que lo ya pagado o cobrado'; end if;
 if aplicado>0 and (new.moneda is distinct from old.moneda or new.contraparte is distinct from old.contraparte) then
 raise exception 'No cambie moneda o persona de una cuenta con pagos o cobros aplicados'; end if;
 return new;
end $$;
create trigger validar_edicion_cuenta_manual before update on public.cuentas_manuales for each row execute function public.validar_edicion_cuenta_manual();
