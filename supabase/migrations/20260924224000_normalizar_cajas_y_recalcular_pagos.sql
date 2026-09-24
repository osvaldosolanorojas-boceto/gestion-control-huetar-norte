-- Reparación de registros anteriores al bloqueo de cajas + kilos manuales.
-- Ajusta únicamente partidas cuyo kg_manual repite exactamente el peso de una caja.
do $$
declare v_boleta record; v_diferencia numeric;
begin
  if exists(select 1 from public.boleta_rendimientos
      where cajas>0 and kg_manual is not null
        and (presentacion_kg is null or kg_manual<>presentacion_kg)) then
    raise exception 'Hay pesos manuales distintos al peso por caja; revise antes de normalizar';
  end if;
  perform set_config('app.corrigiendo_boleta','completa',true);
  for v_boleta in
    select distinct b.id,b.codigo,o.tipo_compra,o.producto,o.campo_promedio_caja_kg,o.precio_europa,o.precio_eeuu,
      o.precio_segunda_gruesa,o.precio_segunda_menuda,o.precio_rechazo,o.precio_campo
    from public.boleta_rendimientos r
    join public.boletas_entrada b on b.id=r.boleta_id
    join public.ordenes_compra o on o.id=b.orden_compra_id
    where r.cajas>0 and r.kg_manual is not null
  loop
    select coalesce(sum(case when r.paga_productor and v_boleta.tipo_compra<>'Puesto en camión'
      and not (v_boleta.tipo_compra='En campo' and v_boleta.campo_promedio_caja_kg is not null)
      and not (v_boleta.tipo_compra='En pie' and v_boleta.producto in ('Ñampí','Cabeza de ñampí'))
      then (r.cajas*r.presentacion_kg-r.kg_manual)/46*
        (case when v_boleta.producto in ('Ñampí','Cabeza de ñampí') then v_boleta.precio_campo
          when r.calidad='Exportable Europa' then v_boleta.precio_europa
          when r.calidad='Exportable estadounidense' then v_boleta.precio_eeuu
          when r.calidad='Segunda gruesa' then v_boleta.precio_segunda_gruesa
          when r.calidad='Segunda menuda' then v_boleta.precio_segunda_menuda
          when r.calidad like 'Rechazo%' then v_boleta.precio_rechazo
          else v_boleta.precio_campo end)
      else 0 end),0) into v_diferencia
    from public.boleta_rendimientos r
    where r.boleta_id=v_boleta.id and r.cajas>0 and r.kg_manual is not null;
    update public.boleta_rendimientos set kg_manual=null
      where boleta_id=v_boleta.id and cajas>0 and kg_manual is not null;
    if v_diferencia<>0 then
      update public.boletas_entrada set monto_cxp=round(coalesce(monto_cxp,0)+v_diferencia,2)
        where id=v_boleta.id and finalizada_en is not null;
    end if;
  end loop;
end;
$$;
alter table public.boleta_rendimientos validate constraint rendimiento_cajas_sin_kg_manual;
