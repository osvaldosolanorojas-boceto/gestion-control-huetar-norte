-- El dinero de las dos sociedades se separa en cuentas distintas.
alter table public.cuentas_bancarias add column empresa text not null default 'exportadora'
check(empresa in ('exportadora','agro_solano'));
grant insert on public.cuentas_bancarias to authenticated;
alter table public.cuentas_bancarias drop constraint cuentas_bancarias_banco_moneda_key;
alter table public.cuentas_bancarias add constraint cuentas_bancarias_empresa_banco_moneda_key unique(empresa,banco,moneda);
insert into public.cuentas_bancarias(banco,moneda,tipo_cuenta,saldo_confirmado,empresa)
values ('Caja Agro Solano','CRC','efectivo',true,'agro_solano')
on conflict(empresa,banco,moneda) do nothing;
create table public.transferencias_entre_empresas (
 id uuid primary key default gen_random_uuid(), orden_compra_id uuid not null references public.ordenes_compra(id),
 movimiento_salida_id uuid not null unique references public.movimientos_bancarios(id),
 movimiento_entrada_id uuid not null unique references public.movimientos_bancarios(id),
 monto numeric(16,2) not null check(monto>0), fecha date not null,
 creado_en timestamptz not null default now()
);
alter table public.transferencias_entre_empresas enable row level security;
revoke all on public.transferencias_entre_empresas from anon,authenticated;
grant select,insert on public.transferencias_entre_empresas to authenticated;
create policy gestion_oficina on public.transferencias_entre_empresas for all to authenticated
using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.transferir_pago_agro_solano(p_orden_id uuid,p_origen_id uuid,p_destino_id uuid,p_fecha date,p_monto numeric,p_referencia text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_o public.ordenes_compra%rowtype; v_from public.cuentas_bancarias%rowtype; v_to public.cuentas_bancarias%rowtype;
  v_out uuid; v_in uuid; v_due numeric;
begin
  if p_fecha is null or p_monto is null or p_monto<=0 or p_monto<>round(p_monto,2) then raise exception 'Monto o fecha de transferencia inválidos'; end if;
  select * into v_o from public.ordenes_compra where id=p_orden_id for update;
  if not found or coalesce(v_o.estado,'')='Anulada' or
    not exists(select 1 from public.proveedores p where p.id=v_o.proveedor_id and p.tipo='Propio') then
    raise exception 'Seleccione una orden vigente de Agro Solano';
  end if;
  perform 1 from public.cuentas_bancarias where id in (p_origen_id,p_destino_id) order by id for update;
  select * into v_from from public.cuentas_bancarias where id=p_origen_id;
  select * into v_to from public.cuentas_bancarias where id=p_destino_id;
  if v_from.empresa<>'exportadora' or v_to.empresa<>'agro_solano' or v_from.moneda<>'CRC' or v_to.moneda<>'CRC'
    or not v_from.activo or not v_to.activo then raise exception 'Seleccione cuentas activas en colones de cada empresa'; end if;
  select monto-aplicado into v_due from public.cxp_operativa where origen='compra_campo' and origen_id=p_orden_id;
  if v_due is null or p_monto>v_due then raise exception 'La transferencia supera el saldo por pagar a Agro Solano'; end if;
  v_out:=public.registrar_movimiento_bancario(p_origen_id,p_fecha,'egreso',p_monto,
    'Pago por producto propio · '||v_o.codigo,p_referencia,
    jsonb_build_array(jsonb_build_object('origen','compra_campo','origen_id',p_orden_id,'monto',p_monto)));
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
  values(p_destino_id,p_fecha,'ingreso',p_monto,'Ingreso de exportadora · '||v_o.codigo,nullif(trim(p_referencia),''),(select auth.uid())) returning id into v_in;
  insert into public.transferencias_entre_empresas(orden_compra_id,movimiento_salida_id,movimiento_entrada_id,monto,fecha)
  values(p_orden_id,v_out,v_in,p_monto,p_fecha);
  return v_out;
end;
$$;
revoke all on function public.transferir_pago_agro_solano(uuid,uuid,uuid,date,numeric,text) from public,anon;
grant execute on function public.transferir_pago_agro_solano(uuid,uuid,uuid,date,numeric,text) to authenticated;
