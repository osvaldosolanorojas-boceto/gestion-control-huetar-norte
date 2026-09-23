-- El inventario de segundas se deriva de cada renglón de rendimiento sin pedido.
-- Una venta puede ser parcial; la boleta puede guardarse antes de conocer comprador.
create table public.ventas_segundas (
  id uuid primary key default gen_random_uuid(),
  rendimiento_id uuid not null references public.boleta_rendimientos(id),
  fecha date not null default current_date,
  comprador text not null check (length(trim(comprador))>0),
  cajas integer not null default 0 check (cajas>=0),
  kilos numeric(14,3) not null default 0 check (kilos>=0),
  referencia text,
  observaciones text,
  registrado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default now(),
  check ((cajas>0 and kilos=0) or (kilos>0 and cajas=0))
);
create index ventas_segundas_rendimiento_idx on public.ventas_segundas(rendimiento_id);
alter table public.ventas_segundas enable row level security;
revoke all on public.ventas_segundas from anon,authenticated;
grant select,insert on public.ventas_segundas to authenticated;
create policy gestion_oficina on public.ventas_segundas for all to authenticated
  using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create function public.registrar_venta_segunda(p_rendimiento_id uuid,p_comprador text,p_cantidad numeric,p_fecha date default current_date,p_referencia text default null,p_observaciones text default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_r public.boleta_rendimientos%rowtype; v_vendido numeric; v_id uuid;
begin
  if nullif(trim(p_comprador),'') is null or p_fecha is null or p_cantidad is null or p_cantidad<=0 then raise exception 'Indique comprador, fecha y cantidad'; end if;
  select * into v_r from public.boleta_rendimientos where id=p_rendimiento_id for update;
  if not found or v_r.orden_venta_linea_id is not null or v_r.calidad not in ('Segunda','Segunda gruesa','Segunda menuda','Rechazo','Rechazo grueso','Rechazo menuda') then raise exception 'Rendimiento no disponible para venta local'; end if;
  if v_r.cajas>0 then
    if p_cantidad<>trunc(p_cantidad) then raise exception 'Las cajas deben ser enteras'; end if;
    select coalesce(sum(cajas),0) into v_vendido from public.ventas_segundas where rendimiento_id=p_rendimiento_id;
    if v_vendido+p_cantidad>v_r.cajas then raise exception 'La venta supera las cajas disponibles'; end if;
    insert into public.ventas_segundas(rendimiento_id,fecha,comprador,cajas,referencia,observaciones,registrado_por)
    values(p_rendimiento_id,p_fecha,trim(p_comprador),p_cantidad::integer,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid())) returning id into v_id;
  else
    select coalesce(sum(kilos),0) into v_vendido from public.ventas_segundas where rendimiento_id=p_rendimiento_id;
    if v_vendido+p_cantidad>v_r.kg_resultado then raise exception 'La venta supera los kilos disponibles'; end if;
    insert into public.ventas_segundas(rendimiento_id,fecha,comprador,kilos,referencia,observaciones,registrado_por)
    values(p_rendimiento_id,p_fecha,trim(p_comprador),0,p_cantidad,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid())) returning id into v_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.registrar_venta_segunda(uuid,text,numeric,date,text,text) from public,anon;
grant execute on function public.registrar_venta_segunda(uuid,text,numeric,date,text,text) to authenticated;

-- También protege inserciones directas por la API, no solo el formulario.
create function public.validar_venta_segunda() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_r public.boleta_rendimientos%rowtype; v_vendido numeric;
begin
  select * into v_r from public.boleta_rendimientos where id=new.rendimiento_id for update;
  if not found or v_r.orden_venta_linea_id is not null or v_r.calidad not in ('Segunda','Segunda gruesa','Segunda menuda','Rechazo','Rechazo grueso','Rechazo menuda') then raise exception 'Rendimiento no disponible para venta local'; end if;
  if v_r.cajas>0 then
    select coalesce(sum(cajas),0) into v_vendido from public.ventas_segundas where rendimiento_id=new.rendimiento_id;
    if new.kilos<>0 or v_vendido+new.cajas>v_r.cajas then raise exception 'La venta supera las cajas disponibles'; end if;
  else
    select coalesce(sum(kilos),0) into v_vendido from public.ventas_segundas where rendimiento_id=new.rendimiento_id;
    if new.cajas<>0 or v_vendido+new.kilos>v_r.kg_resultado then raise exception 'La venta supera los kilos disponibles'; end if;
  end if;
  return new;
end;
$$;
create trigger validar_venta_segunda before insert on public.ventas_segundas for each row execute function public.validar_venta_segunda();

create function public.proteger_rendimiento_vendido() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if exists (select 1 from public.ventas_segundas where rendimiento_id=old.id) then
    if tg_op='DELETE' then raise exception 'Este rendimiento ya tiene ventas locales; no puede quitarlo de la boleta'; end if;
    if new.calidad is distinct from old.calidad or new.cajas is distinct from old.cajas or new.kg_resultado is distinct from old.kg_resultado or new.orden_venta_linea_id is distinct from old.orden_venta_linea_id then
      raise exception 'Este rendimiento ya tiene ventas locales; no puede cambiar su cantidad, calidad o destino';
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
create trigger proteger_rendimiento_vendido before update or delete on public.boleta_rendimientos for each row execute function public.proteger_rendimiento_vendido();
