begin;
create table public.tipos_tarimas (
 id uuid primary key default gen_random_uuid(),
 insumo_id uuid not null unique references public.insumos(id),
 mercado text not null check(mercado in ('Europa','Estados Unidos')),
 modelo text not null default '',
 largo numeric(8,2) not null check(largo>0),
 ancho numeric(8,2) not null check(ancho>0),
 unidad_medida text not null default 'cm' check(unidad_medida in ('cm','pulgadas')),
 observaciones text,
 creado_en timestamptz not null default now(),
 unique(mercado,modelo,largo,ancho,unidad_medida)
);
alter table public.tipos_tarimas enable row level security;
revoke all on public.tipos_tarimas from public,anon,authenticated;
grant select,insert,update on public.tipos_tarimas to authenticated;
create policy leer_tarimas on public.tipos_tarimas for select to authenticated using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta','bodega')));
create policy crear_tarimas on public.tipos_tarimas for insert to authenticated with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy editar_tarimas on public.tipos_tarimas for update to authenticated using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina'))) with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.guardar_tipo_tarima(p_id uuid,p_mercado text,p_modelo text,p_largo numeric,p_ancho numeric,p_unidad text,p_minimo integer,p_activo boolean,p_observaciones text default null)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_id uuid;v_insumo uuid;v_name text;v_old public.tipos_tarimas%rowtype;
begin
 if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado';end if;
 if p_mercado is null or p_mercado not in ('Europa','Estados Unidos') or p_largo is null or p_largo<=0 or p_largo<>round(p_largo,2) or p_ancho is null or p_ancho<=0 or p_ancho<>round(p_ancho,2) or p_unidad is null or p_unidad not in ('cm','pulgadas') or p_minimo is null or p_minimo<0 or p_activo is null then raise exception 'Revise mercado, medidas y mínimo';end if;
 v_name:=concat('Tarima ',p_mercado,' · ',nullif(trim(p_modelo),''),' ',trim(to_char(p_largo,'999999D99')),' × ',trim(to_char(p_ancho,'999999D99')),' ',p_unidad);
 if p_id is null then
  insert into public.insumos(nombre,categoria,unidad,presentacion_compra,unidades_por_presentacion,minimo,activo,especificacion) values(v_name,'Tarimas','unidades','tarima',1,p_minimo,p_activo,p_observaciones) returning id into v_insumo;
  insert into public.tipos_tarimas(insumo_id,mercado,modelo,largo,ancho,unidad_medida,observaciones) values(v_insumo,p_mercado,coalesce(trim(p_modelo),''),p_largo,p_ancho,p_unidad,p_observaciones) returning id into v_id;
 else
  select * into v_old from public.tipos_tarimas where id=p_id for update;
  if not found then raise exception 'Tarima no encontrada';end if;
  v_insumo:=v_old.insumo_id;
  if (p_mercado,p_largo,p_ancho,p_unidad) is distinct from (v_old.mercado,v_old.largo,v_old.ancho,v_old.unidad_medida) and exists(select 1 from public.movimientos_insumos where insumo_id=v_insumo) then raise exception 'Este tamaño tiene movimientos. Cree otro tipo de tarima para conservar el historial';end if;
  update public.tipos_tarimas set mercado=p_mercado,modelo=coalesce(trim(p_modelo),''),largo=p_largo,ancho=p_ancho,unidad_medida=p_unidad,observaciones=p_observaciones where id=p_id;
  update public.insumos set nombre=v_name,minimo=p_minimo,activo=p_activo,especificacion=p_observaciones where id=v_insumo;
  v_id:=p_id;
 end if;
 return v_id;
end $$;
revoke all on function public.guardar_tipo_tarima(uuid,text,text,numeric,numeric,text,integer,boolean,text) from public,anon;
grant execute on function public.guardar_tipo_tarima(uuid,text,text,numeric,numeric,text,integer,boolean,text) to authenticated;
create function public.validar_tarimas_enteras() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.categoria='Tarimas' and (new.unidad<>'unidades' or new.unidades_por_presentacion is distinct from 1::numeric or new.existencia<>trunc(new.existencia)) then raise exception 'Las tarimas se cuentan por unidades enteras: una tarima por presentación';end if;
 return new;
end $$;
revoke all on function public.validar_tarimas_enteras() from public,anon;
create trigger tarimas_enteras before insert or update on public.insumos for each row execute function public.validar_tarimas_enteras();
commit;
