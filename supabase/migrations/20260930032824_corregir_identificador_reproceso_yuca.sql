create or replace function public.reprocesar_saldo_yuca(p_saldo_id uuid,p_fecha date,p_cajas integer,p_partidas jsonb,p_gasto_crc numeric default 0,p_observaciones text default null,p_solicitud uuid default gen_random_uuid()) returns uuid language plpgsql security definer set search_path='' as $$
<<reprocess>>
declare s public.saldos_yuca_eeuu%rowtype; b public.boletas_entrada%rowtype; o public.ordenes_compra%rowtype; line public.ordenes_venta_lineas%rowtype; sale public.ordenes_venta%rowtype;
 item jsonb; n integer; peso numeric; kg numeric; total numeric:=0; cost numeric; disponible integer; be uuid; rid uuid; rp uuid; codigo text; calidad text; lid uuid; posicion smallint; old_setting text;
begin
 if not exists(select 1 from public.perfiles where id=(select auth.uid()) and activo and rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede reprocesar'; end if;
 if p_solicitud is null then raise exception 'Falta identificador de operación'; end if;
 codigo:='RP-'||replace(p_solicitud::text,'-','');
 perform pg_advisory_xact_lock(hashtextextended(codigo,0));
 select id into rp from public.reprocesos_yuca where reprocesos_yuca.codigo=reprocess.codigo;
 if found then return rp; end if;
 if p_fecha is null or p_cajas is null or p_cajas<=0 or p_gasto_crc is null or p_gasto_crc<0 or p_gasto_crc::text in ('NaN','Infinity','-Infinity') or p_gasto_crc<>round(p_gasto_crc,2) then raise exception 'Revise fecha, cajas y gasto'; end if;
 if jsonb_typeof(p_partidas) is distinct from 'array' or jsonb_array_length(p_partidas) not between 1 and 30 then raise exception 'Registre de 1 a 30 resultados'; end if;
 select * into s from public.saldos_yuca_eeuu where id=p_saldo_id for update;
 if not found then raise exception 'Saldo no encontrado'; end if;
 select * into b from public.boletas_entrada where id=s.boleta_id;
 select * into o from public.ordenes_compra where id=b.orden_compra_id;
 if p_fecha<coalesce(b.fecha_labor,(b.fecha_hora at time zone 'America/Costa_Rica')::date) then raise exception 'El reproceso no puede ser anterior al ingreso'; end if;
 select s.cajas_origen-coalesce(sum(cajas),0) into disponible from public.salidas_saldo_yuca_eeuu where saldo_id=s.id;
 if p_cajas>disponible then raise exception 'Solo hay % cajas disponibles',disponible; end if;
 cost:=public.costo_saldo_yuca(s.id);
 -- Lock all target orders in one stable order, shared by concurrent reprocesses.
 perform ov.id from public.ordenes_venta ov where ov.id in(select l.orden_venta_id from public.ordenes_venta_lineas l where l.id in(select nullif(x->>'linea_id','')::uuid from jsonb_array_elements(p_partidas) x)) order by ov.id for update;
 for item in select * from jsonb_array_elements(p_partidas) loop
   calidad:=item->>'calidad'; n:=coalesce((item->>'cajas')::integer,0); peso:=nullif(item->>'peso_kg','')::numeric;
   kg:=case when n>0 then n*peso else nullif(item->>'kg','')::numeric end;
   if calidad is null or calidad not in ('Exportable Europa','Exportable estadounidense','Segunda gruesa','Segunda menuda','Desperdicio') or kg is null or kg<=0 or kg::text in ('NaN','Infinity','-Infinity') or kg<>round(kg,2) or n<0 or (n>0 and (peso is null or peso<=0 or peso::text in ('NaN','Infinity','-Infinity'))) then raise exception 'Revise calidad, cantidad y peso de cada resultado'; end if;
   if calidad like 'Exportable%' and n=0 then raise exception 'La primera se registra en cajas y peso por caja'; end if;
   if calidad='Desperdicio' and n<>0 then raise exception 'La pérdida se registra en kilos'; end if;
   lid:=nullif(item->>'linea_id','')::uuid;
   posicion:=nullif(item->>'posicion','')::smallint;
   if posicion is not null and posicion not between 1 and 22 then raise exception 'Paleta debe ser entre 1 y 22'; end if;
   if lid is not null then
     if calidad not like 'Exportable%' then raise exception 'Solo la primera se asigna al pedido'; end if;
     select * into line from public.ordenes_venta_lineas where id=lid;
     if not found then raise exception 'Línea de pedido no encontrada'; end if;
     select * into sale from public.ordenes_venta where id=line.orden_venta_id;
     if sale.finalizada_en is not null or sale.estado='Anulada' or sale.anulada_en is not null then raise exception 'Seleccione un pedido abierto'; end if;
     if line.producto<>'Yuca' or line.presentacion_kg is distinct from peso then raise exception 'Producto o peso no coincide con el pedido'; end if;
     if (calidad='Exportable Europa' and sale.mercado is distinct from 'Europa') or (calidad='Exportable estadounidense' and sale.mercado is distinct from 'Estados Unidos') then raise exception 'La calidad no coincide con el mercado del pedido'; end if;
     if sale.fecha_salida is null or sale.fecha_salida<p_fecha then raise exception 'El pedido debe salir en la fecha del reproceso o después'; end if;
     if (select coalesce(sum(r.cajas),0) from public.boleta_rendimientos r where r.orden_venta_linea_id=lid)+(select sum((x->>'cajas')::integer) from jsonb_array_elements(p_partidas) x where nullif(x->>'linea_id','')::uuid=lid)>line.cantidad_cajas then raise exception 'Las cajas superan el faltante del pedido'; end if;
   end if;
   total:=total+kg;
 end loop;
 if abs(total-p_cajas*s.kg_por_caja)>0.01 then raise exception 'La clasificación debe sumar % kg; anotó % kg',p_cajas*s.kg_por_caja,total; end if;
 be:=gen_random_uuid();
 insert into public.reprocesos_yuca(codigo,saldo_id,boleta_destino_id,fecha,cajas_entrada,kg_entrada,costo_kg_crc,gasto_crc,observaciones,registrado_por) values(codigo,s.id,be,p_fecha,p_cajas,p_cajas*s.kg_por_caja,cost,p_gasto_crc,p_observaciones,(select auth.uid())) returning id into rp;
 insert into public.boletas_entrada(id,codigo,fecha_hora,fecha_labor,orden_compra_id,proveedor_id,finca_lugar,producto,condicion,cantidad_recipientes,tipo_recipiente,promedio_peso,kg_estimados,linea_proceso,encargado,turno,inicio_proceso,fin_proceso,observaciones)
 values(be,codigo,(p_fecha::text||' 12:00:00 America/Costa_Rica')::timestamptz,p_fecha,b.orden_compra_id,b.proveedor_id,b.finca_lugar,'Yuca','Seco',p_cajas,'Cajas',s.kg_por_caja,p_cajas*s.kg_por_caja,1,b.encargado,'Día',(p_fecha::text||' 12:00:00 America/Costa_Rica')::timestamptz,(p_fecha::text||' 12:00:00 America/Costa_Rica')::timestamptz,'Reproceso de '||s.boleta_codigo||' · '||s.codigo_trazabilidad||'. Compra y costo originales conservados. '||coalesce(p_observaciones,''));
 for item in select * from jsonb_array_elements(p_partidas) loop
   n:=coalesce((item->>'cajas')::integer,0); peso:=nullif(item->>'peso_kg','')::numeric;
   insert into public.boleta_rendimientos(boleta_id,producto,calidad,presentacion_kg,cajas,kg_manual,orden_venta_linea_id,posicion_paleta,codigo_trazabilidad,paga_productor,observaciones)
   values(be,'Yuca',item->>'calidad',case when n>0 then peso else null end,n,case when n=0 then (item->>'kg')::numeric else null end,nullif(item->>'linea_id','')::uuid,nullif(item->>'posicion','')::smallint,s.codigo_trazabilidad,false,'Reproceso de '||s.boleta_codigo) returning id into rid;
   insert into public.reproceso_yuca_partidas values(rid,rp,cost+p_gasto_crc/(p_cajas*s.kg_por_caja));
 end loop;
 -- This is an internal stock movement: no new purchase payable, even for closed original purchases.
 update public.boletas_entrada set finalizada_en=now(),finalizada_por=(select auth.uid()),monto_cxp=0 where id=be;
 insert into public.salidas_saldo_yuca_eeuu(saldo_id,fecha,cajas,destinatario,codigo_salida,detalle,registrado_por) values(s.id,p_fecha,p_cajas,'Reproceso en planta',codigo,'Reclasificación y asignación desde '||s.boleta_codigo,(select auth.uid()));
 if p_gasto_crc>0 then insert into public.costos_operativos(fecha,categoria,concepto,moneda,monto,referencia,observaciones,registrado_por) values(p_fecha,'otros','Reproceso de yuca · '||s.boleta_codigo,'CRC',p_gasto_crc,codigo,p_observaciones,(select auth.uid())); end if;
 return rp;
end $$;
