alter table public.muestras_peso_boleta
  add column tara_kg numeric(10,3) not null default 0 check (tara_kg>=0),
  add column merma_kg numeric(10,3) not null default 0 check (merma_kg>=0);
drop function public.guardar_boleta_con_muestra(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[]);
create function public.guardar_boleta_con_muestra(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text,
  p_muestra numeric[],p_tara_kg numeric,p_merma_kg numeric
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_finalizada boolean; v_promedio numeric; v_tara numeric:=coalesce(p_tara_kg,0); v_merma numeric:=coalesce(p_merma_kg,0);
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  if v_tara<0 or v_merma<0 then raise exception 'Tara y merma no pueden ser negativas'; end if;
  if p_muestra is null or cardinality(p_muestra) not in (0,10) then raise exception 'Complete los diez pesos de la muestra o deje todas las casillas vacías'; end if;
  if exists(select 1 from unnest(p_muestra) w where w is null or w<=v_tara+v_merma or w>100000) then raise exception 'Cada peso de la muestra debe ser mayor que cero'; end if;
  if cardinality(p_muestra)=10 then
    select round(avg(w)-v_tara-v_merma,3) into v_promedio from unnest(p_muestra) w;
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
  insert into public.muestras_peso_boleta(boleta_id,pesos_kg,tara_kg,merma_kg) values(v_id,p_muestra,v_tara,v_merma)
    on conflict (boleta_id) do update set pesos_kg=excluded.pesos_kg,tara_kg=excluded.tara_kg,merma_kg=excluded.merma_kg;
  return v_id;
end;
$$;
revoke all on function public.guardar_boleta_con_muestra(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[],numeric,numeric) from public,anon;
grant execute on function public.guardar_boleta_con_muestra(uuid,text,uuid,timestamptz,date,timestamptz,timestamptz,text,text,smallint,text,text,text,numeric,text,numeric,text,jsonb,jsonb,text,numeric[],numeric,numeric) to authenticated;
