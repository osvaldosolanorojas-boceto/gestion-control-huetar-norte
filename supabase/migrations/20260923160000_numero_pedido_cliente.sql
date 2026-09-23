alter table public.ordenes_venta add column if not exists numero_cliente integer;
with numeradas as (
  select id, row_number() over (partition by cliente_id, fecha_salida order by creado_en, id)::integer as numero
  from public.ordenes_venta where numero_cliente is null and fecha_salida is not null
)
update public.ordenes_venta o set numero_cliente=n.numero from numeradas n where o.id=n.id;
alter table public.ordenes_venta add constraint ordenes_venta_numero_cliente_positivo check (numero_cliente is null or numero_cliente > 0);
create unique index if not exists ordenes_venta_cliente_salida_numero_idx on public.ordenes_venta(cliente_id, fecha_salida, numero_cliente) where numero_cliente is not null;

create or replace function public.guardar_orden_venta_identificada(
  p_orden_id uuid, p_codigo text, p_fecha date, p_fecha_salida date,
  p_cliente_id uuid, p_mercado text, p_pais_destino text, p_contenedor text,
  p_observaciones text, p_lineas jsonb, p_numero_cliente integer
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_id uuid;
begin
  if p_numero_cliente is null or p_numero_cliente < 1 then
    raise exception 'Indique un número de pedido válido para el cliente';
  end if;
  v_id := public.guardar_orden_venta(p_orden_id,p_codigo,p_fecha,p_fecha_salida,
    p_cliente_id,p_mercado,p_pais_destino,p_contenedor,p_observaciones,p_lineas);
  update public.ordenes_venta set numero_cliente=p_numero_cliente where id=v_id;
  return v_id;
end;
$$;
revoke all on function public.guardar_orden_venta_identificada(uuid,text,date,date,uuid,text,text,text,text,jsonb,integer) from public,anon;
grant execute on function public.guardar_orden_venta_identificada(uuid,text,date,date,uuid,text,text,text,text,jsonb,integer) to authenticated;
