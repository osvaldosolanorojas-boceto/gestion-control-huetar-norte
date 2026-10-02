begin;
select set_config('request.jwt.claim.sub',(select id::text from public.perfiles where activo and rol='administrador' limit 1),true);
set local role authenticated;
do $$
declare r record;i uuid;o uuid;l uuid;lot uuid;cost uuid;cart uuid;person uuid;n numeric;v numeric;base_stock integer;base_total integer;failed boolean;
begin
 for r in select * from (values ('Parafina','kg','caja',25,4,45,'USD',10),
('Cera','kg','caja',25,2,28,'USD',5),
('Aceite hidráulico para perras','litros','bidón',20,2,50000,'CRC',5),
('Cloro al 12%','litros','bidón',20,3,15000,'CRC',8),
('Alcohol en gel','litros','envase',1,12,2500,'CRC',2),
('Desinfectante','litros','bidón',5,4,6000,'CRC',3),
('Esquineros de cartón','unidades','paquete',50,4,10000,'CRC',40),
('Esquineros plásticos','unidades','paquete',50,4,15000,'CRC',30),
('Etiquetas','unidades','rollo',1000,3,12000,'CRC',400),
('Fleje','rollos','rollo',1,6,18000,'CRC',1),
('Grapas para cartón','unidades','caja',2000,2,16000,'CRC',250),
('Grapas para fleje','unidades','caja',1000,2,12000,'CRC',100),
('Guantes','pares','caja',50,2,15000,'CRC',12),
('Jabón en polvo','kg','saco',10,2,14000,'CRC',3),
('Jabón para manos','litros','bidón',5,3,7000,'CRC',2),
('Papel higiénico','rollos','paquete',12,5,6000,'CRC',8),
('Papel para envolver ñame','kg','paquete',10,4,9000,'CRC',5),
('Productos de limpieza de sanitarios','unidades','envase',1,10,3000,'CRC',2)) as t(nombre,unidad,presentacion,factor,cantidad,precio,moneda,uso) loop
  insert into public.insumos(nombre,unidad,categoria,presentacion_compra,unidades_por_presentacion) values('__PRUEBA_'||r.nombre||'_'||gen_random_uuid(),r.unidad,'Otros',r.presentacion,r.factor) returning id into i;
  o:=public.crear_orden_insumos('2026-10-01','SIMULADO · ejemplo de inventarios',null,r.moneda,'PRUEBA',jsonb_build_array(jsonb_build_object('insumo_id',i,'presentacion',r.presentacion,'factor',r.factor,'cantidad',r.cantidad,'precio',r.precio)));
  select id into l from public.ordenes_insumos_lineas where orden_id=o;
  lot:=public.recibir_orden_insumos(l,1,'2026-10-01','PRUEBA');
  if (select estado from public.ordenes_insumos where id=o)<>'Abierta' then raise exception 'Recepción parcial cerró orden %',r.nombre;end if;
  lot:=public.recibir_orden_insumos(l,r.cantidad-1,'2026-10-01','PRUEBA');
  if (select estado from public.ordenes_insumos where id=o)<>'Recibida' then raise exception 'Recepción completa no cerró %',r.nombre;end if;
  select existencia into n from public.insumos where id=i;
  if n<>r.cantidad*r.factor then raise exception 'Conversión incorrecta %',r.nombre;end if;
  perform public.consumir_insumo_operacion(i,r.uso,'2026-10-01',null,'PRUEBA','PRUEBA');
  select existencia into n from public.insumos where id=i;
  if n<>r.cantidad*r.factor-r.uso then raise exception 'Consumo incorrecto %',r.nombre;end if;
  select sum(monto) into v from public.costos_produccion where insumo_id=i;
  if v is distinct from round(r.uso*r.precio::numeric/r.factor,2) then raise exception 'Costo de consumo incorrecto %',r.nombre;end if;
  select sum(monto),count(*) into v,n from public.cxp_operativa where origen='compra_insumos' and origen_id=o;
  if v<>r.cantidad*r.precio or n<>1 then raise exception 'Deuda duplicada o incorrecta %',r.nombre;end if;
  failed:=false;
  begin perform public.recibir_orden_insumos(l,1,'2026-10-01','PRUEBA');exception when others then failed:=true;end;
  if not failed then raise exception 'Aceptó recepción excesiva %',r.nombre;end if;
 end loop;
 insert into public.inventario_cartones(marca,descripcion,presentacion_kg,existencia) values('__PRUEBA_'||gen_random_uuid(),'Cartón 18 kg',18,0) returning id into cart;
 cost:=public.registrar_compra_cartones(cart,1320,'2026-10-01','SIMULADO','USD',2,'PRUEBA',true);
 if (select existencia from public.inventario_cartones where id=cart)<>1320 then raise exception 'Cartón no ingresó';end if;
 if not exists(select 1 from public.cxp_operativa where origen='compra_cartones' and origen_id=cost and monto=2640) then raise exception 'Deuda de cartón incorrecta';end if;
 select disponibles,total into base_stock,base_total from public.control_cajas_plasticas where id=1;
 perform public.registrar_movimiento_cajas('compra',100,null,null,'PRUEBA','PRUEBA');
 perform public.registrar_movimiento_cajas('entrega',30,null,'__PRUEBA_'||gen_random_uuid(),'PRUEBA','PRUEBA');
 select responsable_id into person from public.movimientos_cajas_plasticas where referencia='PRUEBA' and tipo='entrega' order by creado_en desc limit 1;
 perform public.registrar_movimiento_cajas('devolucion',20,person,null,'PRUEBA','PRUEBA');
 if (select pendientes from public.responsables_cajas where id=person)<>10 then raise exception 'Responsable no cuadra';end if;
 if (select disponibles from public.control_cajas_plasticas where id=1)<>base_stock+90 then raise exception 'Planta no cuadra';end if;
 if (select total from public.control_cajas_plasticas where id=1)<>base_total+100 then raise exception 'Total plástico no cuadra';end if;
end $$;
rollback;
