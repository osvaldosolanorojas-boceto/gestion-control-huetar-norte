-- Captura de costos devengados. Los pagos bancarios no crean una segunda partida de gasto.
create table public.costos_operativos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  categoria text not null check (categoria in ('planilla','inventario','servicios','contenedor','transporte','otros')),
  concepto text not null check (length(trim(concepto))>0),
  moneda text not null check (moneda in ('CRC','USD')),
  monto numeric(16,2) not null check (monto>0),
  trabajador_id uuid references public.trabajadores(id),
  orden_venta_id uuid references public.ordenes_venta(id),
  unidad text,
  cantidad numeric(14,3) check (cantidad>0),
  tarifa numeric(16,4) check (tarifa>=0),
  referencia text,
  observaciones text,
  registrado_por uuid not null references public.perfiles(id) default auth.uid(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  anulado_en timestamptz,
  constraint costo_planilla_trabajador check (categoria<>'planilla' or trabajador_id is not null),
  constraint costo_unidad_cantidad check ((unidad is null and cantidad is null and tarifa is null) or (unidad is not null and cantidad is not null and tarifa is not null))
);
create index costos_operativos_fecha_idx on public.costos_operativos(fecha) where anulado_en is null;
create index costos_operativos_orden_idx on public.costos_operativos(orden_venta_id,fecha) where orden_venta_id is not null and anulado_en is null;
alter table public.costos_operativos enable row level security;
revoke all on public.costos_operativos from anon,authenticated;
grant select,insert,update on public.costos_operativos to authenticated;
create policy gestion_oficina on public.costos_operativos for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.proteger_costo_operativo() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='UPDATE' then
    if old.anulado_en is not null then raise exception 'No se puede modificar un costo anulado'; end if;
    if old.registrado_por<>new.registrado_por or old.creado_en<>new.creado_en then raise exception 'No puede cambiar el origen del registro'; end if;
    if new.anulado_en is not null and new.anulado_en<>old.anulado_en then
      if row(new.fecha,new.categoria,new.concepto,new.moneda,new.monto,new.trabajador_id,new.orden_venta_id,new.unidad,new.cantidad,new.tarifa,new.referencia,new.observaciones)
         is distinct from row(old.fecha,old.categoria,old.concepto,old.moneda,old.monto,old.trabajador_id,old.orden_venta_id,old.unidad,old.cantidad,old.tarifa,old.referencia,old.observaciones) then
        raise exception 'No cambie el detalle al anular el costo';
      end if;
    end if;
    new.actualizado_en:=now();
  end if;
  return new;
end;
$$;
create trigger proteger_costo before update on public.costos_operativos for each row execute function public.proteger_costo_operativo();
