-- Anulación auditable: nunca borrar una compra con boletas o pagos.
alter table public.ordenes_compra add column anulada_en timestamptz;
alter table public.ordenes_compra add column anulada_por uuid references public.perfiles(id);

-- El disparador anterior devolvía OLD también en UPDATE e impedía guardar ediciones.
create or replace function public.proteger_orden_compra_cerrada() returns trigger
language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is not null)
    and not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is null) then
    raise exception 'La orden de compra tiene todas sus boletas finalizadas y está sellada';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create function public.anular_orden_compra(p_orden_id uuid) returns void
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
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=p_orden_id) then
    raise exception 'La compra tiene pagos aplicados; no puede anularla';
  end if;
  update public.ordenes_compra set estado='Anulada',anulada_en=now(),anulada_por=(select auth.uid()) where id=p_orden_id;
end;
$$;
revoke all on function public.anular_orden_compra(uuid) from public,anon;
grant execute on function public.anular_orden_compra(uuid) to authenticated;

create or replace function public.proteger_nuevas_boletas_compra_cerrada() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.orden_compra_id is not null then
    if exists(select 1 from public.ordenes_compra o where o.id=new.orden_compra_id and o.estado='Anulada') then
      raise exception 'La orden de compra está anulada; no puede vincular boletas';
    end if;
    if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=new.orden_compra_id and b.finalizada_en is not null)
      and not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=new.orden_compra_id and b.finalizada_en is null) then
      raise exception 'La orden de compra está sellada; no puede agregar nuevas boletas';
    end if;
  end if;
  return new;
end;
$$;
create trigger proteger_cambio_orden_boleta before update of orden_compra_id on public.boletas_entrada
for each row when (old.orden_compra_id is distinct from new.orden_compra_id)
execute function public.proteger_nuevas_boletas_compra_cerrada();

create or replace function public.ordenes_compra_para_planta()
returns table(id uuid,codigo text,fecha date,productor_nombre text,producto text,boleta_campo_referencia text,proveedor_id uuid,chofer text,placa text)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select o.id,o.codigo,o.fecha,o.productor_nombre,o.producto,o.boleta_campo_referencia,o.proveedor_id,o.chofer,o.placa
  from public.ordenes_compra o where coalesce(o.estado,'')<>'Anulada' order by o.fecha desc,o.creado_en desc limit 200;
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
where coalesce(o.estado,'')<>'Anulada' and not (o.producto='Ñampí' and o.tipo_compra='En pie')
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre
union all
select 'compra_campo'::text,o.id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente'),'CRC'::text,
  greatest(0,o.precio_en_pie-o.rebaja_planilla_flete)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)::numeric(16,2),
  'Ñampí en pie · rendimiento abierto'::text
from public.ordenes_compra o left join public.proveedores p on p.id=o.proveedor_id
where coalesce(o.estado,'')<>'Anulada' and o.producto='Ñampí' and o.tipo_compra='En pie' and o.precio_en_pie>0;
