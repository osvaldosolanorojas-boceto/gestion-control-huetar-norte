-- Administración prepara cada llegada; planta solo registra el ingreso físico.
create table public.entradas_programadas_en_pie (
  id uuid primary key default gen_random_uuid(),
  orden_compra_id uuid not null references public.ordenes_compra(id),
  numero integer not null check (numero > 0),
  boleta_id uuid unique references public.boletas_entrada(id) on delete set null,
  planilla_monto numeric(14,2) not null default 0 check (planilla_monto >= 0),
  planilla_proveedor_id uuid references public.proveedores(id),
  flete_monto numeric(14,2) not null default 0 check (flete_monto >= 0),
  flete_proveedor_id uuid references public.proveedores(id),
  unique (orden_compra_id, numero),
  check (planilla_monto = 0 or planilla_proveedor_id is not null),
  check (flete_monto = 0 or flete_proveedor_id is not null)
);
create unique index una_entrada_pendiente_en_pie on public.entradas_programadas_en_pie(orden_compra_id) where boleta_id is null;
alter table public.entradas_programadas_en_pie enable row level security;
grant select, insert, update on public.entradas_programadas_en_pie to authenticated;
create policy administrar_entradas_en_pie on public.entradas_programadas_en_pie for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

-- Las boletas anteriores conservan sus costos y su secuencia.
insert into public.entradas_programadas_en_pie(orden_compra_id,numero,boleta_id,planilla_monto,planilla_proveedor_id,flete_monto,flete_proveedor_id)
select b.orden_compra_id,row_number() over(partition by b.orden_compra_id order by b.fecha_hora,b.id),b.id,
  coalesce(max(c.monto) filter(where c.tipo='planilla'),0),(max(c.proveedor_id::text) filter(where c.tipo='planilla'))::uuid,
  coalesce(max(c.monto) filter(where c.tipo='flete'),0),(max(c.proveedor_id::text) filter(where c.tipo='flete'))::uuid
from public.boletas_entrada b join public.ordenes_compra o on o.id=b.orden_compra_id
left join public.costos_boleta_en_pie c on c.boleta_id=b.id
where o.producto='Yuca' and o.tipo_compra='En pie'
group by b.id;

create function public.validar_entrada_programada_en_pie() returns trigger language plpgsql set search_path='' as $$
begin
  if not exists(select 1 from public.ordenes_compra o where o.id=new.orden_compra_id and o.producto='Yuca' and o.tipo_compra='En pie' and o.en_pie_finalizada_en is null) then
    raise exception 'La orden debe ser una compra de yuca en pie abierta';
  end if;
  if new.boleta_id is not null or new.numero<>(select coalesce(max(e.numero),0)+1 from public.entradas_programadas_en_pie e where e.orden_compra_id=new.orden_compra_id) then
    raise exception 'Prepare la siguiente entrada en orden, sin asignar la boleta manualmente';
  end if;
  return new;
end;
$$;
revoke all on function public.validar_entrada_programada_en_pie() from public,anon,authenticated;
create trigger validar_entrada_programada_en_pie before insert on public.entradas_programadas_en_pie
for each row execute function public.validar_entrada_programada_en_pie();


create function public.asignar_entrada_programada_en_pie() returns trigger language plpgsql security definer set search_path='' as $$
declare v_slot public.entradas_programadas_en_pie%rowtype;
begin
  if not exists(select 1 from public.ordenes_compra o where o.id=new.orden_compra_id and o.producto='Yuca' and o.tipo_compra='En pie') then return new; end if;
  select * into v_slot from public.entradas_programadas_en_pie
    where orden_compra_id=new.orden_compra_id and boleta_id is null for update;
  if not found then raise exception 'Administración debe preparar la siguiente entrada en la orden de compra antes de guardar esta boleta'; end if;
  update public.entradas_programadas_en_pie set boleta_id=new.id where id=v_slot.id;
  insert into public.costos_boleta_en_pie(boleta_id,tipo,monto,proveedor_id)
  values(new.id,'planilla',v_slot.planilla_monto,v_slot.planilla_proveedor_id),
        (new.id,'flete',v_slot.flete_monto,v_slot.flete_proveedor_id);
  return new;
end;
$$;
revoke all on function public.asignar_entrada_programada_en_pie() from public,anon,authenticated;
create trigger asignar_entrada_programada_en_pie after insert on public.boletas_entrada
for each row execute function public.asignar_entrada_programada_en_pie();

create function public.sincronizar_costos_entrada_programada() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.orden_compra_id<>old.orden_compra_id or new.numero<>old.numero or new.boleta_id is distinct from old.boleta_id then
    -- La boleta solo se asigna al crearla; ningún cliente puede moverla después.
    if new.boleta_id is distinct from old.boleta_id and old.boleta_id is null and pg_trigger_depth()>1 then return new; end if;
    raise exception 'No se puede cambiar la identidad de esta entrada';
  end if;
  if exists(select 1 from public.ordenes_compra o where o.id=new.orden_compra_id and o.en_pie_finalizada_en is not null) then raise exception 'La compra ya está finalizada'; end if;
  if new.boleta_id is not null then
    update public.costos_boleta_en_pie set monto=new.planilla_monto,proveedor_id=new.planilla_proveedor_id where boleta_id=new.boleta_id and tipo='planilla';
    update public.costos_boleta_en_pie set monto=new.flete_monto,proveedor_id=new.flete_proveedor_id where boleta_id=new.boleta_id and tipo='flete';
  end if;
  return new;
end;
$$;
revoke all on function public.sincronizar_costos_entrada_programada() from public,anon,authenticated;
create trigger sincronizar_costos_entrada_programada before update on public.entradas_programadas_en_pie
for each row execute function public.sincronizar_costos_entrada_programada();

create or replace function public.finalizar_compra_en_pie(p_orden_id uuid) returns void language plpgsql security invoker set search_path='' as $$
declare v_o public.ordenes_compra%rowtype;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar esta compra'; end if;
  select * into v_o from public.ordenes_compra where id=p_orden_id for update;
  if not found or v_o.tipo_compra<>'En pie' or v_o.producto not in ('Yuca','Ñampí','Cabeza de ñampí') then raise exception 'Seleccione una compra en pie de yuca o ñampí'; end if;
  if v_o.en_pie_finalizada_en is not null then raise exception 'Esta compra ya está finalizada'; end if;
  if not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=p_orden_id) then
    raise exception 'Registre al menos una boleta o venta externa antes de finalizar';
  end if;
  if v_o.producto='Yuca' and exists(select 1 from public.entradas_programadas_en_pie e where e.orden_compra_id=p_orden_id and e.boleta_id is null) then
    raise exception 'Hay una entrada preparada pendiente de boleta. Regístrela antes de finalizar la compra';
  end if;
  update public.ordenes_compra set en_pie_finalizada_en=now() where id=p_orden_id;
  if v_o.producto='Yuca' then
    perform public.finalizar_boleta_entrada(b.id) from public.boletas_entrada b where b.orden_compra_id=p_orden_id and b.finalizada_en is null;
  end if;
end;
$$;

