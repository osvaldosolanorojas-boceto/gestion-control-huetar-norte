drop function if exists public.pedidos_mapa_para_planta();
create function public.pedidos_mapa_para_planta()
returns table(linea_id uuid,orden_id uuid,codigo text,contenedor text,cliente text,
  producto text,presentacion_kg numeric,cantidad_cajas integer,paletas integer,cajas_por_paleta integer,carton text,
  numero_cliente integer,fecha_salida date)
language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  return query select l.id,o.id,o.codigo,o.contenedor,c.nombre,l.producto,l.presentacion_kg,
    l.cantidad_cajas,l.paletas,l.cajas_por_paleta,l.carton_marca,o.numero_cliente,o.fecha_salida
  from public.ordenes_venta_lineas l join public.ordenes_venta o on o.id=l.orden_venta_id
  left join public.clientes c on c.id=o.cliente_id
  order by o.fecha_salida desc,o.creado_en desc,l.id limit 1000;
end;
$$;
revoke all on function public.pedidos_mapa_para_planta() from public,anon;
grant execute on function public.pedidos_mapa_para_planta() to authenticated;
