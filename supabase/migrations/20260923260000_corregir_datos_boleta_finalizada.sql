-- La corrección autorizada conserva los campos financieros y el cierre.
create or replace function public.bloquear_boleta_finalizada() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_table_name='boletas_entrada' then
    if tg_op='DELETE' and old.finalizada_en is not null then raise exception 'La boleta finalizada no se puede eliminar'; end if;
    if tg_op='UPDATE' and old.finalizada_en is not null then
      if current_setting('app.corrigiendo_boleta',true) is distinct from 'on' or
        (to_jsonb(old) - array['fecha_labor','condicion','cantidad_recipientes','tipo_recipiente','promedio_peso','kg_estimados','inicio_proceso','fin_proceso','turno','clima','linea_proceso','encargado','encargado_banda','observaciones','tratamiento_cera']) is distinct from
        (to_jsonb(new) - array['fecha_labor','condicion','cantidad_recipientes','tipo_recipiente','promedio_peso','kg_estimados','inicio_proceso','fin_proceso','turno','clima','linea_proceso','encargado','encargado_banda','observaciones','tratamiento_cera']) then
        raise exception 'La boleta finalizada solo permite corregir datos de recepción y proceso';
      end if;
    end if;
  elsif exists(select 1 from public.boletas_entrada b where b.id=case when tg_op='DELETE' then old.boleta_id else new.boleta_id end and b.finalizada_en is not null) then
    raise exception 'Los rendimientos de una boleta finalizada no se pueden modificar';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

create function public.corregir_boleta_finalizada(
  p_boleta_id uuid,p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,
  p_promedio_peso numeric,p_fecha_labor date,p_inicio_proceso timestamptz,
  p_fin_proceso timestamptz,p_turno text,p_clima text,p_linea_proceso smallint,
  p_encargado text,p_encargado_banda text,p_observaciones text,p_tratamiento_cera text
) returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.perfiles where id=(select auth.uid()) and activo and rol in ('administrador','oficina')) then
    raise exception 'Solo administración u oficina puede corregir boletas finalizadas';
  end if;
  if p_inicio_proceso is not null and p_fin_proceso is not null and p_fin_proceso<p_inicio_proceso then raise exception 'El fin del proceso debe ser posterior al inicio'; end if;
  if p_cantidad_recipientes<0 or p_promedio_peso<=0 then raise exception 'Revise la cantidad y el peso'; end if;
  perform set_config('app.corrigiendo_boleta','on',true);
  update public.boletas_entrada set fecha_labor=p_fecha_labor,condicion=p_condicion,
    cantidad_recipientes=p_cantidad_recipientes,tipo_recipiente=p_tipo_recipiente,
    promedio_peso=p_promedio_peso,kg_estimados=p_cantidad_recipientes*p_promedio_peso,
    inicio_proceso=p_inicio_proceso,fin_proceso=p_fin_proceso,turno=p_turno,clima=p_clima,
    linea_proceso=p_linea_proceso,encargado=p_encargado,encargado_banda=p_encargado_banda,
    observaciones=p_observaciones,tratamiento_cera=p_tratamiento_cera
  where id=p_boleta_id and finalizada_en is not null;
  if not found then raise exception 'No se encontró la boleta finalizada'; end if;
  perform set_config('app.corrigiendo_boleta','off',true);
end;
$$;
revoke all on function public.corregir_boleta_finalizada(uuid,text,numeric,text,numeric,date,timestamptz,timestamptz,text,text,smallint,text,text,text,text) from public,anon;
grant execute on function public.corregir_boleta_finalizada(uuid,text,numeric,text,numeric,date,timestamptz,timestamptz,text,text,smallint,text,text,text,text) to authenticated;
