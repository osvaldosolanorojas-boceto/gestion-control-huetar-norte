-- La planta puede registrar boletas; las ventas directas requieren administración.
create or replace function public.guardar_boleta_con_ventas_en_pie(
  p_boleta_id uuid,p_codigo text,p_orden_compra_id uuid,p_fecha_hora timestamptz,
  p_fecha_labor date,p_inicio_proceso timestamptz,p_fin_proceso timestamptz,
  p_turno text,p_clima text,p_linea_proceso smallint,p_encargado text,p_encargado_banda text,
  p_condicion text,p_cantidad_recipientes numeric,p_tipo_recipiente text,p_promedio_peso numeric,
  p_observaciones text,p_trabajos jsonb,p_rendimientos jsonb,p_tratamiento_cera text,
  p_muestra numeric[],p_tara_kg numeric,p_merma_kg numeric,p_ventas_directas jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_line jsonb; v_o public.ordenes_compra%rowtype;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
  if p_ventas_directas is null or jsonb_typeof(p_ventas_directas)<>'array' then raise exception 'Ventas directas inválidas'; end if;
  select * into v_o from public.ordenes_compra where id=p_orden_compra_id for update;
  if not found or v_o.tipo_compra<>'En pie' or v_o.producto not in ('Ñampí','Cabeza de ñampí') or v_o.en_pie_finalizada_en is not null then raise exception 'La compra en pie no está abierta'; end if;
  if jsonb_array_length(p_ventas_directas)>0 and not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina registra ventas directas'; end if;
  v_id:=public.guardar_boleta_con_muestra(p_boleta_id,p_codigo,p_orden_compra_id,p_fecha_hora,p_fecha_labor,p_inicio_proceso,p_fin_proceso,
    p_turno,p_clima,p_linea_proceso,p_encargado,p_encargado_banda,p_condicion,p_cantidad_recipientes,p_tipo_recipiente,p_promedio_peso,
    p_observaciones,p_trabajos,p_rendimientos,p_tratamiento_cera,p_muestra,p_tara_kg,p_merma_kg);
  for v_line in select value from pg_catalog.jsonb_array_elements(p_ventas_directas) loop
    insert into public.ventas_externas_en_pie(orden_compra_id,boleta_id,fecha,producto,comprador,cantidad,unidad,peso_saco_kg,precio_unitario,moneda,observaciones)
    values(p_orden_compra_id,v_id,(v_line->>'fecha')::date,v_line->>'producto',pg_catalog.btrim(v_line->>'comprador'),(v_line->>'cantidad')::numeric,
      v_line->>'unidad',nullif(v_line->>'peso_saco_kg','')::numeric,(v_line->>'precio_unitario')::numeric,coalesce(v_line->>'moneda','CRC'),nullif(pg_catalog.btrim(v_line->>'observaciones'),''));
  end loop;
  return v_id;
end;
$$;
