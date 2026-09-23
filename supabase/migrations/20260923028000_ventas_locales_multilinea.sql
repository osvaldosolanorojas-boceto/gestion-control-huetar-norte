-- Una venta local agrupa partidas de distintas boletas y productos.
create table public.ventas_locales (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  fecha date not null,
  comprador text not null check (length(trim(comprador))>0),
  referencia text,
  moneda text not null check (moneda in ('CRC','USD')),
  observaciones text,
  registrado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default now()
);
alter table public.ventas_locales enable row level security;
revoke all on public.ventas_locales from anon,authenticated;
grant select,insert on public.ventas_locales to authenticated;
create policy gestion_oficina on public.ventas_locales for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

alter table public.ventas_segundas
  add column venta_local_id uuid references public.ventas_locales(id),
  add column peso_caja_kg numeric(10,3) check (peso_caja_kg>0),
  add column precio_unitario numeric(14,4) check (precio_unitario>=0),
  add column unidad_precio text check (unidad_precio in ('caja','kg')),
  add column subtotal numeric(16,2) check (subtotal>=0);
create index ventas_segundas_venta_local_idx on public.ventas_segundas(venta_local_id);

create function public.registrar_venta_local(p_codigo text,p_fecha date,p_comprador text,p_referencia text,p_moneda text,p_observaciones text,p_lineas jsonb)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid; v_line jsonb; v_r public.boleta_rendimientos%rowtype; v_qty numeric; v_peso numeric; v_precio numeric; v_unidad text; v_sold numeric; v_line_id uuid;
begin
  if nullif(trim(p_codigo),'') is null or p_fecha is null or nullif(trim(p_comprador),'') is null or p_moneda not in ('CRC','USD') or p_lineas is null or jsonb_typeof(p_lineas)<>'array' or jsonb_array_length(p_lineas)=0 then raise exception 'Complete fecha, comprador, moneda y partidas'; end if;
  -- Se bloquean los rendimientos antes de insertar para impedir ventas simultáneas del mismo saldo.
  perform 1 from public.boleta_rendimientos r where r.id in (select (value->>'rendimiento_id')::uuid from jsonb_array_elements(p_lineas)) order by r.id for update;
  insert into public.ventas_locales(codigo,fecha,comprador,referencia,moneda,observaciones,registrado_por)
  values(trim(p_codigo),p_fecha,trim(p_comprador),nullif(trim(p_referencia),''),p_moneda,nullif(trim(p_observaciones),''),(select auth.uid())) returning id into v_id;
  for v_line in select value from jsonb_array_elements(p_lineas) loop
    select * into v_r from public.boleta_rendimientos where id=(v_line->>'rendimiento_id')::uuid;
    if not found or v_r.orden_venta_linea_id is not null or v_r.calidad not in ('Segunda','Segunda gruesa','Segunda menuda','Rechazo','Rechazo grueso','Rechazo menuda') then raise exception 'Partida no disponible para venta local'; end if;
    v_qty:=(v_line->>'cantidad')::numeric;
    v_peso:=nullif(v_line->>'peso_caja_kg','')::numeric;
    v_precio:=(v_line->>'precio_unitario')::numeric;
    v_unidad:=v_line->>'unidad_precio';
    if v_qty is null or v_qty<=0 or v_precio is null or v_precio<0 or v_unidad not in ('caja','kg') then raise exception 'Revise cantidad, unidad de precio y precio'; end if;
    if v_r.cajas>0 then
      if v_qty<>trunc(v_qty) or v_peso is null or v_peso<=0 then raise exception 'Cada partida en cajas necesita cajas enteras y peso por caja'; end if;
      select coalesce(sum(cajas),0) into v_sold from public.ventas_segundas where rendimiento_id=v_r.id;
      if v_sold+v_qty>v_r.cajas then raise exception 'La venta supera las cajas disponibles en la boleta %',v_r.boleta_id; end if;
      insert into public.ventas_segundas(venta_local_id,rendimiento_id,fecha,comprador,cajas,peso_caja_kg,precio_unitario,unidad_precio,subtotal,referencia,registrado_por)
      values(v_id,v_r.id,p_fecha,trim(p_comprador),v_qty::integer,v_peso,v_precio,v_unidad,round(v_precio*(case when v_unidad='kg' then v_qty*v_peso else v_qty end),2),nullif(trim(p_referencia),''),(select auth.uid())) returning id into v_line_id;
    else
      if v_unidad<>'kg' then raise exception 'Las partidas medidas en kilos se cobran por kilo'; end if;
      select coalesce(sum(kilos),0) into v_sold from public.ventas_segundas where rendimiento_id=v_r.id;
      if v_sold+v_qty>v_r.kg_resultado then raise exception 'La venta supera los kilos disponibles'; end if;
      insert into public.ventas_segundas(venta_local_id,rendimiento_id,fecha,comprador,kilos,precio_unitario,unidad_precio,subtotal,referencia,registrado_por)
      values(v_id,v_r.id,p_fecha,trim(p_comprador),v_qty,v_precio,v_unidad,round(v_precio*v_qty,2),nullif(trim(p_referencia),''),(select auth.uid())) returning id into v_line_id;
    end if;
  end loop;
  return v_id;
end;
$$;
revoke all on function public.registrar_venta_local(text,date,text,text,text,text,jsonb) from public,anon;
grant execute on function public.registrar_venta_local(text,date,text,text,text,text,jsonb) to authenticated;
