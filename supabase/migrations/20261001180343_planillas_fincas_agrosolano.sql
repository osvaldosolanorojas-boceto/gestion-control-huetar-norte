create table public.planillas_finca (
 id uuid primary key default gen_random_uuid(),
 lote_id uuid not null references public.lotes_finca(id),
 colaborador text not null check(btrim(colaborador)<>''),
 periodo_inicio date not null,periodo_fin date not null check(periodo_fin>=periodo_inicio),fecha_pago date not null,
 dias numeric(8,2) not null check(dias>0),tarifa_diaria numeric(14,2) not null check(tarifa_diaria>0),
 rebajos numeric(14,2) not null default 0 check(rebajos>=0 and rebajos<round(dias*tarifa_diaria,2)),
 bruto numeric(16,2) generated always as(round(dias*tarifa_diaria,2)) stored,
 neto numeric(16,2) generated always as(round(dias*tarifa_diaria,2)-rebajos) stored,
 observaciones text,registrado_por uuid default auth.uid() references public.perfiles(id),creado_en timestamptz not null default now()
);
alter table public.planillas_finca enable row level security;
grant select,insert,update on public.planillas_finca to authenticated;
create policy gestion_oficina on public.planillas_finca for all to authenticated
using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
alter table public.cuentas_manuales add column planilla_finca_id uuid unique references public.planillas_finca(id);
alter table public.costos_finca add column planilla_finca_id uuid unique references public.planillas_finca(id);
create or replace function public.sincronizar_planilla_finca() returns trigger
language plpgsql security invoker set search_path='' as $$
declare detalle text;
begin
 detalle:='Planilla de finca · '||new.colaborador||' · '||new.periodo_inicio||' a '||new.periodo_fin||coalesce(' · '||new.observaciones,'');
 insert into public.costos_finca(lote_id,fecha,categoria,descripcion,monto,planilla_finca_id)
 values(new.lote_id,new.periodo_fin,'Planilla',detalle,new.bruto,new.id)
 on conflict(planilla_finca_id) do update set lote_id=excluded.lote_id,fecha=excluded.fecha,descripcion=excluded.descripcion,monto=excluded.monto;
 insert into public.cuentas_manuales(codigo,tipo,fecha,fecha_vencimiento,contraparte,moneda,monto,concepto,categoria,empresa,planilla_finca_id)
 values('PF-'||new.id,'pagar',new.periodo_fin,new.fecha_pago,new.colaborador,'CRC',new.neto,detalle,'Planillas de finca','agro_solano',new.id)
 on conflict(planilla_finca_id) do update set fecha=excluded.fecha,fecha_vencimiento=excluded.fecha_vencimiento,contraparte=excluded.contraparte,monto=excluded.monto,concepto=excluded.concepto;
 return new;
end $$;
create trigger sincronizar_planilla_finca after insert or update on public.planillas_finca for each row execute function public.sincronizar_planilla_finca();
