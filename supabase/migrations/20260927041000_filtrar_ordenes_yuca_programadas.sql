create or replace function public.ordenes_compra_para_planta(p_orden_compra_id uuid default null,p_incluir_vinculadas boolean default false)
returns table(id uuid,codigo text,fecha date,productor_nombre text,producto text,boleta_campo_referencia text,proveedor_id uuid,chofer text,placa text,tipo_compra text,en_pie_finalizada_en timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select o.id,o.codigo,o.fecha,o.productor_nombre,o.producto,o.boleta_campo_referencia,o.proveedor_id,o.chofer,o.placa,o.tipo_compra,o.en_pie_finalizada_en
  from public.ordenes_compra o
  where coalesce(o.estado,'')<>'Anulada' and (o.en_pie_finalizada_en is null or p_incluir_vinculadas or o.id=p_orden_compra_id)
    and (p_incluir_vinculadas
      or o.id=p_orden_compra_id
      or (o.producto in ('Yuca','Ñampí','Cabeza de ñampí') and o.tipo_compra='En pie')
      or not exists (select 1 from public.boletas_entrada b where b.orden_compra_id=o.id))
    and (p_incluir_vinculadas or o.id=p_orden_compra_id or o.producto<>'Yuca' or o.tipo_compra<>'En pie'
      or exists(select 1 from public.entradas_programadas_en_pie e where e.orden_compra_id=o.id and e.boleta_id is null))
  order by o.fecha desc,o.creado_en desc limit 1000;
end;
$$;

