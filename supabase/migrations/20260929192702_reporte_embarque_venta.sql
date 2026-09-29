begin;
create table public.embarques_venta (
 orden_venta_id uuid primary key references public.ordenes_venta(id),
 contenedor text, ryan text, marchamos text, factura text, telefono text,
 tratamiento text, pesos_brutos jsonb not null default '{}'::jsonb,
 actualizado_en timestamptz not null default now(), actualizado_por uuid default auth.uid(),
 constraint pesos_objeto check(jsonb_typeof(pesos_brutos)='object')
);
alter table public.embarques_venta enable row level security;
create policy oficina_embarques on public.embarques_venta for all to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
grant select,insert,update on public.embarques_venta to authenticated;
create function public.guardar_datos_embarque(p_orden_id uuid,p_datos jsonb)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.perfiles where id=auth.uid() and activo and rol in ('administrador','oficina')) then raise exception 'Sin permiso para editar embarques'; end if;
 if not exists(select 1 from public.ordenes_venta where id=p_orden_id and estado<>'Anulada') then raise exception 'Pedido inexistente o anulado'; end if;
 if jsonb_typeof(coalesce(p_datos->'pesos_brutos','{}'::jsonb))<>'object' then raise exception 'Pesos inválidos'; end if;
 if exists(select 1 from jsonb_each_text(coalesce(p_datos->'pesos_brutos','{}'::jsonb)) w where w.value !~ '^[0-9]+([.][0-9]+)?$') then raise exception 'Ingrese pesos positivos'; end if;
 insert into public.embarques_venta(orden_venta_id,contenedor,ryan,marchamos,factura,telefono,tratamiento,pesos_brutos,actualizado_por)
 values(p_orden_id,nullif(trim(p_datos->>'contenedor'),''),nullif(trim(p_datos->>'ryan'),''),nullif(trim(p_datos->>'marchamos'),''),nullif(trim(p_datos->>'factura'),''),nullif(trim(p_datos->>'telefono'),''),nullif(trim(p_datos->>'tratamiento'),''),coalesce(p_datos->'pesos_brutos','{}'::jsonb),auth.uid())
 on conflict(orden_venta_id) do update set contenedor=excluded.contenedor,ryan=excluded.ryan,marchamos=excluded.marchamos,factura=excluded.factura,telefono=excluded.telefono,tratamiento=excluded.tratamiento,pesos_brutos=excluded.pesos_brutos,actualizado_en=now(),actualizado_por=auth.uid();
end $$;
create function public.guardar_orden_venta_embarque(p_orden_id uuid,p_codigo text,p_fecha date,p_fecha_salida date,p_cliente_id uuid,p_mercado text,p_pais_destino text,p_contenedor text,p_observaciones text,p_lineas jsonb,p_numero_cliente integer,p_embarque jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid;
begin
 v_id:=public.guardar_orden_venta_identificada(p_orden_id,p_codigo,p_fecha,p_fecha_salida,p_cliente_id,p_mercado,p_pais_destino,p_contenedor,p_observaciones,p_lineas,p_numero_cliente);
 perform public.guardar_datos_embarque(v_id,p_embarque);
 return v_id;
end $$;
revoke all on function public.guardar_datos_embarque(uuid,jsonb) from public,anon;
revoke all on function public.guardar_orden_venta_embarque(uuid,text,date,date,uuid,text,text,text,text,jsonb,integer,jsonb) from public,anon;
grant execute on function public.guardar_datos_embarque(uuid,jsonb) to authenticated;
grant execute on function public.guardar_orden_venta_embarque(uuid,text,date,date,uuid,text,text,text,text,jsonb,integer,jsonb) to authenticated;
commit;
