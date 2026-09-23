drop function if exists public.ordenes_compra_para_planta();
create function public.ordenes_compra_para_planta(p_orden_compra_id uuid default null)
returns table(id uuid,codigo text,fecha date,productor_nombre text,producto text,boleta_campo_referencia text,proveedor_id uuid,chofer text,placa text)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select o.id,o.codigo,o.fecha,o.productor_nombre,o.producto,o.boleta_campo_referencia,o.proveedor_id,o.chofer,o.placa
  from public.ordenes_compra o
  where coalesce(o.estado,'')<>'Anulada'
    and (o.id=p_orden_compra_id
      or (o.producto in ('Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
      or not exists (select 1 from public.boletas_entrada b where b.orden_compra_id=o.id))
  order by o.fecha desc,o.creado_en desc limit 200;
end;
$$;
revoke all on function public.ordenes_compra_para_planta(uuid) from public,anon;
grant execute on function public.ordenes_compra_para_planta(uuid) to authenticated;
