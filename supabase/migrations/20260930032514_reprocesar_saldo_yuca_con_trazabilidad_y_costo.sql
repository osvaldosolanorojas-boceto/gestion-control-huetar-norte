create table public.reprocesos_yuca (
 id uuid primary key default gen_random_uuid(), codigo text not null unique,
 saldo_id uuid not null references public.saldos_yuca_eeuu(id),
 boleta_destino_id uuid not null unique references public.boletas_entrada(id) deferrable initially deferred,
 fecha date not null, cajas_entrada integer not null check(cajas_entrada>0),
 kg_entrada numeric not null check(kg_entrada>0), costo_kg_crc numeric not null check(costo_kg_crc>=0),
 gasto_crc numeric not null default 0 check(gasto_crc>=0), observaciones text,
 registrado_por uuid not null references public.perfiles(id), creado_en timestamptz not null default now()
);
create table public.reproceso_yuca_partidas (
 rendimiento_id uuid primary key references public.boleta_rendimientos(id),
 reproceso_id uuid not null references public.reprocesos_yuca(id),
 costo_kg_crc numeric not null check(costo_kg_crc>=0)
);
create index on public.reprocesos_yuca(saldo_id);
create index on public.reproceso_yuca_partidas(reproceso_id);
alter table public.reprocesos_yuca enable row level security;
alter table public.reproceso_yuca_partidas enable row level security;
revoke all on public.reprocesos_yuca,public.reproceso_yuca_partidas from anon,authenticated;
grant select on public.reprocesos_yuca,public.reproceso_yuca_partidas to authenticated;
create policy reproceso_lectura on public.reprocesos_yuca for select to authenticated using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy partidas_lectura on public.reproceso_yuca_partidas for select to authenticated using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create function public.costo_saldo_yuca(p_saldo_id uuid) returns numeric language plpgsql security definer set search_path='' as $$
declare s public.saldos_yuca_eeuu%rowtype; r public.boleta_rendimientos%rowtype; o public.ordenes_compra%rowtype; c numeric; kg numeric;
begin
 if not exists(select 1 from public.perfiles where id=(select auth.uid()) and activo and rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
 select * into s from public.saldos_yuca_eeuu where id=p_saldo_id;
 if not found then raise exception 'Partida no encontrada'; end if;
 select costo_kg_crc into c from public.reproceso_yuca_partidas where rendimiento_id=s.rendimiento_id;
 if found then return c; end if;
 select * into r from public.boleta_rendimientos where id=s.rendimiento_id;
 select oc.* into o from public.ordenes_compra oc join public.boletas_entrada b on b.orden_compra_id=oc.id where b.id=s.boleta_id;
 if o.tipo_compra='A rendimiento' then
   return case when r.paga_productor then coalesce(case s.calidad when 'Europa' then o.precio_europa else o.precio_eeuu end,0)/46 else 0 end;
 end if;
 select sum(br.kg_resultado) into kg from public.boleta_rendimientos br join public.boletas_entrada b on b.id=br.boleta_id where b.orden_compra_id=o.id and b.finalizada_en is not null and not exists(select 1 from public.reprocesos_yuca rp where rp.boleta_destino_id=b.id);
 select monto into c from public.cxp_operativa where origen='compra_campo' and origen_id=o.id;
 return coalesce(c/nullif(kg,0),0);
end $$;
revoke all on function public.costo_saldo_yuca(uuid) from public,anon;
grant execute on function public.costo_saldo_yuca(uuid) to authenticated;

create function public.reprocesar_saldo_yuca(p_saldo_id uuid,p_fecha date,p_cajas integer,p_partidas jsonb,p_gasto_crc numeric default 0,p_observaciones text default null,p_solicitud uuid default gen_random_uuid()) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.saldos_yuca_eeuu%rowtype; b public.boletas_entrada%rowtype; o public.ordenes_compra%rowtype; line public.ordenes_venta_lineas%rowtype; sale public.ordenes_venta%rowtype;
 item jsonb; n integer; peso numeric; kg numeric; total numeric:=0; cost numeric; disponible integer; be uuid; rid uuid; rp uuid; codigo text; calidad text; lid uuid; posicion smallint; old_setting text;
begin
 if not exists(select 1 from public.perfiles where id=(select auth.uid()) and activo and rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede reprocesar'; end if;
 if p_solicitud is null then raise exception 'Falta identificador de operación'; end if;
 codigo:='RP-'||replace(p_solicitud::text,'-','');
 perform pg_advisory_xact_lock(hashtextextended(codigo,0));
 select id into rp from public.reprocesos_yuca where reprocesos_yuca.codigo=reprocesar_saldo_yuca.codigo;
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
revoke all on function public.reprocesar_saldo_yuca(uuid,date,integer,jsonb,numeric,text,uuid) from public,anon;
grant execute on function public.reprocesar_saldo_yuca(uuid,date,integer,jsonb,numeric,text,uuid) to authenticated;

create function public.inventario_arrastre_yuca(p_fecha date) returns numeric language plpgsql security definer set search_path='' as $$
declare total numeric:=0; x record;
begin
 if not exists(select 1 from public.perfiles where id=(select auth.uid()) and activo and rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
 if p_fecha is null then raise exception 'Falta fecha'; end if;
 for x in select s.id,s.kg_por_caja,s.cajas_origen-coalesce((select sum(m.cajas) from public.salidas_saldo_yuca_eeuu m where m.saldo_id=s.id and m.fecha<=p_fecha),0) cajas from public.saldos_yuca_eeuu s join public.boletas_entrada b on b.id=s.boleta_id where coalesce(b.fecha_labor,(b.fecha_hora at time zone 'America/Costa_Rica')::date)<=p_fecha loop
   total:=total+x.cajas*x.kg_por_caja*public.costo_saldo_yuca(x.id);
 end loop;
 -- Output stocks not in the export carry-over table: second grades and reserved first grades awaiting dispatch.
 select total+coalesce(sum(greatest(0,r.kg_resultado-coalesce((select sum(v.kilos) from public.ventas_segundas v where v.rendimiento_id=r.id and v.fecha<=p_fecha),0))*p.costo_kg_crc),0) into total
 from public.reproceso_yuca_partidas p join public.reprocesos_yuca rp on rp.id=p.reproceso_id join public.boleta_rendimientos r on r.id=p.rendimiento_id left join public.ordenes_venta_lineas l on l.id=r.orden_venta_linea_id left join public.ordenes_venta o on o.id=l.orden_venta_id
 where rp.fecha<=p_fecha and r.calidad<>'Desperdicio' and not exists(select 1 from public.saldos_yuca_eeuu s where s.rendimiento_id=r.id) and (r.orden_venta_linea_id is null or o.finalizada_en is null or o.fecha_salida>p_fecha or o.estado='Anulada');
 return round(total,2);
end $$;
revoke all on function public.inventario_arrastre_yuca(date) from public,anon;
grant execute on function public.inventario_arrastre_yuca(date) to authenticated;

create function public.proteger_origen_reproceso_yuca() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' or (to_jsonb(new)-array['observaciones']) is distinct from (to_jsonb(old)-array['observaciones']) then
   if exists(select 1 from public.reproceso_yuca_partidas p where p.rendimiento_id=old.id) or exists(select 1 from public.saldos_yuca_eeuu s join public.reprocesos_yuca rp on rp.saldo_id=s.id where s.rendimiento_id=old.id) then raise exception 'Esta partida tiene reprocesos. Sus cantidades y origen deben conservarse'; end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function public.proteger_origen_reproceso_yuca() from public,anon,authenticated;
create trigger proteger_origen_reproceso before update or delete on public.boleta_rendimientos for each row execute function public.proteger_origen_reproceso_yuca();

create or replace function public.proteger_nuevas_boletas_compra_cerrada() returns trigger language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.reprocesos_yuca rp join public.saldos_yuca_eeuu s on s.id=rp.saldo_id join public.boletas_entrada b on b.id=s.boleta_id where rp.boleta_destino_id=new.id and b.orden_compra_id=new.orden_compra_id) then return new; end if;
 if new.orden_compra_id is not null then
  if exists(select 1 from public.ordenes_compra o where o.id=new.orden_compra_id and o.estado='Anulada') then raise exception 'La orden de compra está anulada; no puede vincular boletas'; end if;
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=new.orden_compra_id and b.finalizada_en is not null) and not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=new.orden_compra_id and b.finalizada_en is null) then raise exception 'La orden de compra está sellada; no puede agregar nuevas boletas'; end if;
 end if;
 return new;
end $$;
create function public.proteger_boleta_reproceso_yuca() returns trigger language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.reprocesos_yuca where boleta_destino_id=old.id) and (new.orden_compra_id is distinct from old.orden_compra_id or coalesce(new.monto_cxp,0)<>0 or new.fecha_labor is distinct from old.fecha_labor or new.codigo is distinct from old.codigo or (old.finalizada_en is not null and new.finalizada_en is null)) then raise exception 'El reproceso conserva fecha, boleta y compra original; no genera una compra nueva'; end if;
 return new;
end $$;
revoke all on function public.proteger_boleta_reproceso_yuca() from public,anon,authenticated;
create trigger proteger_boleta_reproceso before update on public.boletas_entrada for each row execute function public.proteger_boleta_reproceso_yuca();
