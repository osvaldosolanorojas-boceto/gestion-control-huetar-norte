-- Cajas reutilizables: disponibles en planta y pendientes en poder de terceros.
create table public.control_cajas_plasticas (
  id integer primary key default 1 check (id=1),
  disponibles integer not null default 0 check (disponibles>=0),
  total integer not null default 0 check (total>=0)
);
insert into public.control_cajas_plasticas(id) values (1);
create table public.responsables_cajas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(trim(nombre))>0),
  pendientes integer not null default 0 check (pendientes>=0),
  creado_en timestamptz not null default now()
);
create unique index responsables_cajas_nombre_idx on public.responsables_cajas(lower(nombre));
create table public.movimientos_cajas_plasticas (
  id uuid primary key default gen_random_uuid(),
  responsable_id uuid references public.responsables_cajas(id),
  tipo text not null check (tipo in ('entrega','devolucion','compra','baja_planta','perdida_tercero')),
  cantidad integer not null check (cantidad>0),
  referencia text,
  observaciones text,
  registrado_por uuid references public.perfiles(id),
  creado_en timestamptz not null default now(),
  check ((tipo in ('entrega','devolucion','perdida_tercero')) = (responsable_id is not null))
);
create index movimientos_cajas_responsable_idx on public.movimientos_cajas_plasticas(responsable_id,creado_en desc);
do $$ declare t text; begin
  foreach t in array array['control_cajas_plasticas','responsables_cajas','movimientos_cajas_plasticas'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select, insert, update on public.%I to authenticated',t);
    execute format('create policy gestion_oficina on public.%I for all to authenticated using (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in (''administrador'',''oficina''))) with check (exists (select 1 from public.perfiles p where p.id = (select auth.uid()) and p.activo and p.rol in (''administrador'',''oficina'')))',t);
  end loop;
end $$;

create function public.registrar_movimiento_cajas(p_tipo text,p_cantidad integer,p_responsable_id uuid default null,p_nombre text default null,p_referencia text default null,p_observaciones text default null)
returns integer language plpgsql security invoker set search_path = '' as $$
declare v_disponibles integer; v_pendientes integer; v_responsable uuid;
begin
  if p_tipo is null or p_tipo not in ('entrega','devolucion','compra','baja_planta','perdida_tercero') or p_cantidad is null or p_cantidad<=0 then raise exception 'Tipo o cantidad inválidos'; end if;
  -- La fila única serializa todos los movimientos concurrentes.
  select disponibles into v_disponibles from public.control_cajas_plasticas where id=1 for update;
  if v_disponibles is null then raise exception 'Sin permiso para registrar cajas'; end if;
  if p_tipo in ('entrega','devolucion','perdida_tercero') then
    v_responsable:=p_responsable_id;
    if v_responsable is null and nullif(trim(p_nombre),'') is not null and p_tipo='entrega' then
      insert into public.responsables_cajas(nombre) values (trim(p_nombre))
      on conflict (lower(nombre)) do update set nombre=excluded.nombre returning id into v_responsable;
    end if;
    if v_responsable is null then raise exception 'Seleccione el responsable'; end if;
    if not exists (select 1 from public.responsables_cajas where id=v_responsable) then raise exception 'No se encontró el responsable'; end if;
  end if;
  if p_tipo in ('entrega','baja_planta') and v_disponibles<p_cantidad then raise exception 'No hay suficientes cajas disponibles en planta'; end if;
  if p_tipo in ('devolucion','perdida_tercero') then
    select pendientes into v_pendientes from public.responsables_cajas where id=v_responsable for update;
    if v_pendientes is null or v_pendientes<p_cantidad then raise exception 'La cantidad supera las cajas pendientes de este responsable'; end if;
  end if;
  if p_tipo='entrega' then
    update public.control_cajas_plasticas set disponibles=disponibles-p_cantidad where id=1;
    update public.responsables_cajas set pendientes=pendientes+p_cantidad where id=v_responsable;
  elsif p_tipo='devolucion' then
    update public.control_cajas_plasticas set disponibles=disponibles+p_cantidad where id=1;
    update public.responsables_cajas set pendientes=pendientes-p_cantidad where id=v_responsable;
  elsif p_tipo='compra' then
    update public.control_cajas_plasticas set disponibles=disponibles+p_cantidad,total=total+p_cantidad where id=1;
  elsif p_tipo='baja_planta' then
    update public.control_cajas_plasticas set disponibles=disponibles-p_cantidad,total=total-p_cantidad where id=1;
  else
    update public.responsables_cajas set pendientes=pendientes-p_cantidad where id=v_responsable;
    update public.control_cajas_plasticas set total=total-p_cantidad where id=1;
  end if;
  insert into public.movimientos_cajas_plasticas(responsable_id,tipo,cantidad,referencia,observaciones,registrado_por)
  values(v_responsable,p_tipo,p_cantidad,nullif(trim(p_referencia),''),nullif(trim(p_observaciones),''),(select auth.uid()));
  select disponibles into v_disponibles from public.control_cajas_plasticas where id=1;
  return v_disponibles;
end;
$$;
revoke all on function public.registrar_movimiento_cajas(text,integer,uuid,text,text,text) from public, anon;
grant execute on function public.registrar_movimiento_cajas(text,integer,uuid,text,text,text) to authenticated;
