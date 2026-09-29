begin;
alter table public.costos_operativos add column if not exists tipo_detalle text;
alter table public.costos_operativos add column if not exists beneficiario_nombre text;
alter table public.costos_operativos add column if not exists proveedor_id uuid references public.proveedores(id);
alter table public.costos_operativos add column if not exists fecha_vencimiento date;
alter table public.costos_operativos add column if not exists genera_cxp boolean not null default false;
alter table public.costos_operativos add constraint costo_beneficiario_cxp
  check (not genera_cxp or (beneficiario_nombre is not null and length(trim(beneficiario_nombre))>0));
alter table public.cuentas_manuales add column if not exists costo_operativo_id uuid unique references public.costos_operativos(id);

create or replace function public.sincronizar_cxp_costo_operativo()
returns trigger language plpgsql security definer set search_path to '' as $$
declare v_cuenta public.cuentas_manuales%rowtype;v_pagado numeric;
begin
  select * into v_cuenta from public.cuentas_manuales where costo_operativo_id=new.id for update;
  if found then
    select coalesce(sum(monto),0) into v_pagado from public.aplicaciones_bancarias
      where origen='cuenta_manual_pagar' and origen_id=v_cuenta.id;
  else v_pagado:=0; end if;
  if new.anulado_en is not null or not new.genera_cxp then
    if v_cuenta.id is not null then
      if v_pagado>0 then raise exception 'El gasto tiene pagos: registre una reversión antes de anular la cuenta'; end if;
      delete from public.cuentas_manuales where id=v_cuenta.id;
    end if;
    return new;
  end if;
  if v_pagado>new.monto then raise exception 'El nuevo gasto es menor que lo ya pagado'; end if;
  if v_pagado>0 and (v_cuenta.moneda<>new.moneda or v_cuenta.contraparte<>new.beneficiario_nombre)
    then raise exception 'No cambie moneda o beneficiario después de pagar'; end if;
  if v_cuenta.id is null then
    insert into public.cuentas_manuales(codigo,tipo,fecha,fecha_vencimiento,contraparte,proveedor_id,moneda,monto,concepto,referencia,costo_operativo_id,registrado_por)
    values('GASTO-'||left(new.id::text,8),'pagar',new.fecha,coalesce(new.fecha_vencimiento,new.fecha),new.beneficiario_nombre,new.proveedor_id,new.moneda,new.monto,new.concepto,new.referencia,new.id,new.registrado_por);
  else
    update public.cuentas_manuales set fecha=new.fecha,fecha_vencimiento=coalesce(new.fecha_vencimiento,new.fecha),
      contraparte=new.beneficiario_nombre,proveedor_id=new.proveedor_id,moneda=new.moneda,monto=new.monto,
      concepto=new.concepto,referencia=new.referencia where id=v_cuenta.id;
  end if;
  return new;
end $$;
drop trigger if exists sincronizar_cxp_contenedor on public.costos_operativos;
create trigger sincronizar_cxp_contenedor after insert or update on public.costos_operativos
for each row execute function public.sincronizar_cxp_costo_operativo();

create table if not exists public.revision_gastos_contenedor(
  orden_venta_id uuid primary key references public.ordenes_venta(id),
  confirmado_en timestamptz not null default now(),
  confirmado_por uuid not null default auth.uid()
);
alter table public.revision_gastos_contenedor enable row level security;
create policy oficina_revision_gastos on public.revision_gastos_contenedor
for all to authenticated using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
grant select,insert,update,delete on public.revision_gastos_contenedor to authenticated;
commit;
