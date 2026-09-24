-- Saldos de yuca estadounidense en cajas plásticas; cada partida conserva la boleta de origen.
create table public.saldos_yuca_eeuu (
  id uuid primary key default gen_random_uuid(),
  rendimiento_id uuid not null unique references public.boleta_rendimientos(id),
  boleta_id uuid not null references public.boletas_entrada(id),
  boleta_codigo text not null,
  productor text not null,
  codigo_trazabilidad text not null,
  cajas_origen integer not null check (cajas_origen>0),
  kg_por_caja numeric(8,2) not null check (kg_por_caja>0),
  lunes_destino date not null,
  creado_en timestamptz not null default now()
);
create index saldos_yuca_lunes_idx on public.saldos_yuca_eeuu(lunes_destino);
create table public.salidas_saldo_yuca_eeuu (
  id uuid primary key default gen_random_uuid(),
  saldo_id uuid not null references public.saldos_yuca_eeuu(id),
  fecha date not null,
  cajas integer not null check (cajas>0),
  destinatario text not null check (length(btrim(destinatario))>0),
  codigo_salida text not null check (length(btrim(codigo_salida))>0),
  detalle text,
  registrado_por uuid references auth.users(id),
  creado_en timestamptz not null default now()
);
create index salidas_saldo_yuca_idx on public.salidas_saldo_yuca_eeuu(saldo_id);
alter table public.saldos_yuca_eeuu enable row level security;
alter table public.salidas_saldo_yuca_eeuu enable row level security;
revoke all on public.saldos_yuca_eeuu, public.salidas_saldo_yuca_eeuu from anon, authenticated;
grant select on public.saldos_yuca_eeuu, public.salidas_saldo_yuca_eeuu to authenticated;
create policy saldos_lectura on public.saldos_yuca_eeuu for select to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));
create policy salidas_lectura on public.salidas_saldo_yuca_eeuu for select to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));

create function public.registrar_salida_saldo_yuca_eeuu(p_saldo_id uuid,p_fecha date,p_cajas integer,p_destinatario text,p_codigo_salida text,p_detalle text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_saldo public.saldos_yuca_eeuu%rowtype; v_usadas integer; v_id uuid;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  select * into v_saldo from public.saldos_yuca_eeuu where id=p_saldo_id for update;
  if not found then raise exception 'No se encontró la partida de saldo'; end if;
  select coalesce(sum(cajas),0) into v_usadas from public.salidas_saldo_yuca_eeuu where saldo_id=p_saldo_id;
  if p_cajas is null or p_cajas<=0 or p_cajas>v_saldo.cajas_origen-v_usadas then raise exception 'La cantidad supera las cajas disponibles'; end if;
  if p_fecha is null or nullif(btrim(p_destinatario),'') is null or nullif(btrim(p_codigo_salida),'') is null then raise exception 'Indique fecha, destinatario y código de salida'; end if;
  insert into public.salidas_saldo_yuca_eeuu(saldo_id,fecha,cajas,destinatario,codigo_salida,detalle,registrado_por)
  values(p_saldo_id,p_fecha,p_cajas,btrim(p_destinatario),btrim(p_codigo_salida),nullif(btrim(p_detalle),''),(select auth.uid())) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.registrar_salida_saldo_yuca_eeuu(uuid,date,integer,text,text,text) from public,anon;
grant execute on function public.registrar_salida_saldo_yuca_eeuu(uuid,date,integer,text,text,text) to authenticated;

create function public.crear_saldo_yuca_eeuu_al_finalizar() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.finalizada_en is null and new.finalizada_en is not null then
    insert into public.saldos_yuca_eeuu(rendimiento_id,boleta_id,boleta_codigo,productor,codigo_trazabilidad,cajas_origen,kg_por_caja,lunes_destino)
    select r.id,new.id,new.codigo,coalesce(o.productor_nombre,'Productor'),coalesce(nullif(r.codigo_trazabilidad,''),new.codigo),r.cajas,r.presentacion_kg,
      date_trunc('week',new.finalizada_en at time zone 'America/Costa_Rica')::date+7
    from public.boleta_rendimientos r join public.ordenes_compra o on o.id=new.orden_compra_id
    where r.boleta_id=new.id and r.producto='Yuca' and r.calidad='Exportable estadounidense' and r.cajas>0 and r.orden_venta_linea_id is null
    on conflict (rendimiento_id) do nothing;
  end if;
  return new;
end;
$$;
create trigger saldo_eeuu_al_finalizar after update of finalizada_en on public.boletas_entrada
for each row execute function public.crear_saldo_yuca_eeuu_al_finalizar();
-- También incorpora partidas históricas sin pedido, conservando sus boletas.
insert into public.saldos_yuca_eeuu(rendimiento_id,boleta_id,boleta_codigo,productor,codigo_trazabilidad,cajas_origen,kg_por_caja,lunes_destino)
select r.id,b.id,b.codigo,coalesce(o.productor_nombre,'Productor'),coalesce(nullif(r.codigo_trazabilidad,''),b.codigo),r.cajas,r.presentacion_kg,
  date_trunc('week',b.finalizada_en at time zone 'America/Costa_Rica')::date+7
from public.boleta_rendimientos r join public.boletas_entrada b on b.id=r.boleta_id join public.ordenes_compra o on o.id=b.orden_compra_id
where b.finalizada_en is not null and r.producto='Yuca' and r.calidad='Exportable estadounidense' and r.cajas>0 and r.orden_venta_linea_id is null
on conflict (rendimiento_id) do nothing;
