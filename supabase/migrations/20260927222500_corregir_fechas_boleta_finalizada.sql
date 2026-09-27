-- Change chronology without recreating yields already assigned or sold.
create table if not exists public.correcciones_fecha_boleta (
  id uuid primary key default gen_random_uuid(),
  boleta_id uuid not null references public.boletas_entrada(id),
  fecha_hora_anterior timestamptz not null,
  fecha_labor_anterior date,
  fecha_hora_nueva timestamptz not null,
  fecha_labor_nueva date not null,
  motivo text not null,
  creado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now()
);
alter table public.correcciones_fecha_boleta enable row level security;
create policy fecha_boleta_admin on public.correcciones_fecha_boleta
  for select to authenticated using (exists (
    select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'
  ));

create or replace function public.corregir_fechas_boleta_finalizada(
  p_boleta_id uuid,p_fecha_hora timestamptz,p_fecha_labor date,
  p_inicio_proceso timestamptz,p_fin_proceso timestamptz,p_motivo text
) returns void language plpgsql security definer set search_path='' as $$
declare v_b public.boletas_entrada%rowtype; v_compra date; v_salida date;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador') then
    raise exception 'Solo administración puede corregir fechas finalizadas';
  end if;
  select * into v_b from public.boletas_entrada where id=p_boleta_id for update;
  if not found or v_b.finalizada_en is null then raise exception 'Seleccione una boleta finalizada'; end if;
  if length(btrim(coalesce(p_motivo,'')))<15 then raise exception 'Explique la corrección de fechas'; end if;
  select o.fecha into v_compra from public.ordenes_compra o where o.id=v_b.orden_compra_id;
  if p_fecha_hora is null or p_fecha_labor is null or p_inicio_proceso is null or p_fin_proceso is null
     or p_fecha_hora::date<v_compra or p_fecha_hora::date>p_fecha_labor
     or p_inicio_proceso<p_fecha_hora or p_fin_proceso<p_inicio_proceso
     or p_fin_proceso::date>p_fecha_labor then
    raise exception 'Revise la secuencia: compra, ingreso, inicio, fin y fecha de labor';
  end if;
  select min(v.fecha_salida) into v_salida
  from public.boleta_rendimientos r
  join public.ordenes_venta_lineas l on l.id=r.orden_venta_linea_id
  join public.ordenes_venta v on v.id=l.orden_venta_id
  where r.boleta_id=p_boleta_id;
  if v_salida is not null and p_fecha_labor>v_salida then
    raise exception 'El producto se trabajó después de la salida del pedido (%)',v_salida;
  end if;
  perform set_config('app.corrigiendo_boleta','completa',true);
  update public.boletas_entrada set fecha_hora=p_fecha_hora,fecha_labor=p_fecha_labor,
    inicio_proceso=p_inicio_proceso,fin_proceso=p_fin_proceso,
    observaciones=concat_ws(E'\n',nullif(observaciones,''),
      'CORRECCIÓN DE FECHAS: '||btrim(p_motivo))
    where id=p_boleta_id;
  insert into public.correcciones_fecha_boleta
    (boleta_id,fecha_hora_anterior,fecha_labor_anterior,fecha_hora_nueva,fecha_labor_nueva,motivo,creado_por)
    values(p_boleta_id,v_b.fecha_hora,v_b.fecha_labor,p_fecha_hora,p_fecha_labor,btrim(p_motivo),(select auth.uid()));
end;
$$;
revoke all on function public.corregir_fechas_boleta_finalizada(uuid,timestamptz,date,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.corregir_fechas_boleta_finalizada(uuid,timestamptz,date,timestamptz,timestamptz,text) to authenticated;
