create table public.muestras_peso_boleta (
  boleta_id uuid primary key references public.boletas_entrada(id) on delete cascade,
  pesos_kg numeric(10,3)[] not null,
  check (cardinality(pesos_kg) in (0,10)),
  check (array_position(pesos_kg,null) is null)
);
alter table public.muestras_peso_boleta enable row level security;
revoke all on public.muestras_peso_boleta from public,anon,authenticated;
grant select on public.muestras_peso_boleta to authenticated;
create policy consultar_muestras_peso on public.muestras_peso_boleta for select to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));

create function public.guardar_boleta_con_muestra(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text,
  p_muestra numeric[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_finalizada boolean; v_promedio numeric;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  if p_muestra is null or cardinality(p_muestra) not in (0,10) then raise exception 'Complete los diez pesos de la muestra o deje todas las casillas vacías'; end if;
  if exists(select 1 from unnest(p_muestra) w where w is null or w<=0 or w>100000) then raise exception 'Cada peso de la muestra debe ser mayor que cero'; end if;
  if cardinality(p_muestra)=10 then
    select round(avg(w),3) into v_promedio from unnest(p_muestra) w;
    if p_promedio_peso is distinct from v_promedio then raise exception 'El peso promedio no coincide con la muestra de diez recipientes'; end if;
  end if;
  if p_boleta_id is not null then
    select finalizada_en is not null into v_finalizada from public.boletas_entrada where id=p_boleta_id;
    if not found then raise exception 'No se encontró la boleta'; end if;
  end if;
  if coalesce(v_finalizada,false) then
    v_id:=public.corregir_boleta_finalizada_completa(p_boleta_id,p_codigo,p_orden_compra_id,p_fecha_hora,p_fecha_labor,
      p_inicio_proceso,p_fin_proceso,p_turno,p_clima,p_linea_proceso,p_encargado,p_encargado_banda,p_condicion,
      p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,p_observaciones,p_trabajos,p_rendimientos,p_tratamiento_cera);
  else
    v_id:=private.guardar_boleta_planta(p_boleta_id,p_codigo,p_orden_compra_id,p_fecha_hora,p_fecha_labor,
      p_inicio_proceso,p_fin_proceso,p_turno,p_clima,p_linea_proceso,p_encargado,p_encargado_banda,p_condicion,
      p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,p_observaciones,p_trabajos,p_rendimientos,p_tratamiento_cera);
  end if;
  insert into public.muestras_peso_boleta(boleta_id,pesos_kg) values(v_id,p_muestra)
    on conflict (boleta_id) do update set pesos_kg=excluded.pesos_kg;
  return v_id;
end;
$$;
revoke all on function public.guardar_boleta_con_muestra(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[]) from public,anon;
grant execute on function public.guardar_boleta_con_muestra(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[]) to authenticated;
