alter table public.aplicaciones_bancarias drop constraint aplicaciones_bancarias_origen_check;
alter table public.aplicaciones_bancarias add constraint aplicaciones_bancarias_origen_check
  check (origen in ('venta_exportacion','venta_local','compra_campo','flete_compra','planilla_compra','saldo_productor','cuenta_manual_cobrar','cuenta_manual_pagar','compra_insumos'));

create or replace view public.cxp_operativa with (security_invoker=true) as
 SELECT 'compra_campo'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    COALESCE(o.productor_nombre, p.nombre, 'Productor pendiente'::text) AS contraparte,
    'CRC'::text AS moneda,
    GREATEST(0::numeric, COALESCE(sum(b.monto_cxp), 0::numeric) + COALESCE(( SELECT sum(
                CASE
                    WHEN e.unidad = 'Sacos'::text THEN e.cantidad * e.peso_saco_kg
                    ELSE e.cantidad * 46::numeric
                END / 46::numeric * o.precio_campo) AS sum
           FROM ventas_externas_boleta e
             JOIN boletas_entrada be ON be.id = e.boleta_id
          WHERE be.orden_compra_id = o.id), 0::numeric) - o.rebaja_planilla_flete)::numeric(16,2) AS monto,
    LEAST(GREATEST(0::numeric, COALESCE(sum(b.monto_cxp), 0::numeric) + COALESCE(( SELECT sum(
                CASE
                    WHEN e.unidad = 'Sacos'::text THEN e.cantidad * e.peso_saco_kg
                    ELSE e.cantidad * 46::numeric
                END / 46::numeric * o.precio_campo) AS sum
           FROM ventas_externas_boleta e
             JOIN boletas_entrada be ON be.id = e.boleta_id
          WHERE be.orden_compra_id = o.id), 0::numeric) - o.rebaja_planilla_flete), GREATEST(COALESCE(o.adelanto, 0::numeric), COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) + COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric)))::numeric(16,2) AS aplicado,
    'Boleta finalizada'::text AS etapa,
    o.producto
   FROM ordenes_compra o
     LEFT JOIN boletas_entrada b ON b.orden_compra_id = o.id AND b.finalizada_en IS NOT NULL
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND o.tipo_compra IS DISTINCT FROM 'Puesto en camión'::text AND (o.tipo_compra IS DISTINCT FROM 'En campo'::text OR o.campo_promedio_caja_kg IS NULL) AND o.tipo_compra IS DISTINCT FROM 'En pie'::text AND o.tipo_compra IS DISTINCT FROM 'Producto listo'::text AND (o.tipo_compra IS DISTINCT FROM 'En campo'::text OR o.producto = 'Yuca'::text AND o.campo_promedio_caja_kg IS NULL OR o.producto <> 'Yuca'::text AND (o.cantidad_comprada IS NULL OR o.precio_campo IS NULL)) AND (b.id IS NOT NULL OR (EXISTS ( SELECT 1
           FROM ventas_externas_boleta e
             JOIN boletas_entrada be ON be.id = e.boleta_id
          WHERE be.orden_compra_id = o.id)))
  GROUP BY o.id, o.codigo, o.fecha, o.productor_nombre, p.nombre
UNION ALL
 SELECT 'compra_campo'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    COALESCE(o.productor_nombre, p.nombre, 'Productor pendiente'::text) AS contraparte,
    'CRC'::text AS moneda,
    GREATEST(0::numeric, o.precio_en_pie)::numeric(16,2) AS monto,
    LEAST(GREATEST(0::numeric, o.precio_en_pie), GREATEST(COALESCE(o.adelanto, 0::numeric), COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) + COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric)))::numeric(16,2) AS aplicado,
    o.producto || ' en pie · lote abierto'::text AS etapa,
    o.producto
   FROM ordenes_compra o
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND o.tipo_compra = 'En pie'::text AND o.precio_en_pie > 0::numeric
UNION ALL
 SELECT 'compra_campo'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    COALESCE(o.productor_nombre, p.nombre, 'Productor pendiente'::text) AS contraparte,
    'CRC'::text AS moneda,
    GREATEST(0::numeric, round(
        CASE
            WHEN o.producto = 'Yuca'::text AND o.unidad = 'Cajas'::text THEN o.cantidad_comprada * o.peso_caja_camion_kg / 46::numeric
            ELSE o.cantidad_comprada
        END * o.precio_puesto_camion, 2) - o.rebaja_planilla_flete)::numeric(16,2) AS monto,
    LEAST(GREATEST(0::numeric, round(
        CASE
            WHEN o.producto = 'Yuca'::text AND o.unidad = 'Cajas'::text THEN o.cantidad_comprada * o.peso_caja_camion_kg / 46::numeric
            ELSE o.cantidad_comprada
        END * o.precio_puesto_camion, 2) - o.rebaja_planilla_flete), GREATEST(COALESCE(o.adelanto, 0::numeric), COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) + COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric)))::numeric(16,2) AS aplicado,
    'Puesto en camión · precio fijo'::text AS etapa,
    o.producto
   FROM ordenes_compra o
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND o.tipo_compra = 'Puesto en camión'::text
UNION ALL
 SELECT 'compra_campo'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    COALESCE(o.productor_nombre, p.nombre, 'Productor pendiente'::text) AS contraparte,
    'CRC'::text AS moneda,
    GREATEST(0::numeric, round(o.cantidad_comprada * GREATEST(0::numeric, o.campo_promedio_caja_kg - o.campo_tara_caja_kg - o.campo_tierra_caja_kg) / 46::numeric * o.precio_campo + o.campo_sacos::numeric * o.campo_promedio_saco_kg * (1::numeric - o.campo_descuento_rechazo_pct / 100::numeric) / 46::numeric * o.campo_precio_rechazo, 2))::numeric(16,2) AS monto,
    LEAST(GREATEST(0::numeric, round(o.cantidad_comprada * GREATEST(0::numeric, o.campo_promedio_caja_kg - o.campo_tara_caja_kg - o.campo_tierra_caja_kg) / 46::numeric * o.precio_campo + o.campo_sacos::numeric * o.campo_promedio_saco_kg * (1::numeric - o.campo_descuento_rechazo_pct / 100::numeric) / 46::numeric * o.campo_precio_rechazo, 2)), GREATEST(COALESCE(o.adelanto, 0::numeric), COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) + COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric)))::numeric(16,2) AS aplicado,
    'En campo · pesaje pactado'::text AS etapa,
    o.producto
   FROM ordenes_compra o
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND o.tipo_compra = 'En campo'::text AND o.producto = 'Yuca'::text AND o.campo_promedio_caja_kg IS NOT NULL
UNION ALL
 SELECT 'compra_campo'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    COALESCE(o.productor_nombre, p.nombre, 'Productor pendiente'::text) AS contraparte,
    'CRC'::text AS moneda,
    GREATEST(0::numeric, round(o.cantidad_comprada * o.precio_campo, 2) - o.rebaja_planilla_flete)::numeric(16,2) AS monto,
    LEAST(GREATEST(0::numeric, round(o.cantidad_comprada * o.precio_campo, 2) - o.rebaja_planilla_flete), GREATEST(COALESCE(o.adelanto, 0::numeric), COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) + COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric)))::numeric(16,2) AS aplicado,
        CASE
            WHEN o.tipo_compra = 'En campo'::text THEN 'En campo · precio pactado'::text
            ELSE 'Producto listo · precio pactado'::text
        END AS etapa,
    o.producto
   FROM ordenes_compra o
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND (o.tipo_compra = 'En campo'::text AND o.producto <> 'Yuca'::text AND o.cantidad_comprada > 0::numeric AND o.precio_campo > 0::numeric OR o.tipo_compra = 'Producto listo'::text AND o.producto <> 'Yuca'::text)
UNION ALL
 SELECT 'compra_campo'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    COALESCE(o.productor_nombre, p.nombre, 'Productor pendiente'::text) AS contraparte,
    'CRC'::text AS moneda,
    GREATEST(0::numeric, round(o.cantidad_comprada * o.precio_europa, 2) - o.rebaja_planilla_flete)::numeric(16,2) AS monto,
    LEAST(GREATEST(0::numeric, round(o.cantidad_comprada * o.precio_europa, 2) - o.rebaja_planilla_flete), GREATEST(COALESCE(o.adelanto, 0::numeric), COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) + COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric)))::numeric(16,2) AS aplicado,
        CASE
            WHEN o.tipo_compra = 'En campo'::text THEN 'En campo · precio pactado'::text
            ELSE 'Producto listo · precio pactado'::text
        END AS etapa,
    o.producto
   FROM ordenes_compra o
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND o.tipo_compra = 'Producto listo'::text AND o.producto = 'Yuca'::text
UNION ALL
 SELECT 'flete_compra'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    t.nombre AS contraparte,
    'CRC'::text AS moneda,
    o.flete::numeric(16,2) AS monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'flete_compra'::text AND a.origen_id = o.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Flete de compra'::text AS etapa,
    o.producto
   FROM ordenes_compra o
     JOIN proveedores t ON t.id = o.flete_proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND o.flete > 0::numeric
UNION ALL
 SELECT 'planilla_compra'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    p.nombre AS contraparte,
    'CRC'::text AS moneda,
    (COALESCE(o.cuadrilla_arranca, 0::numeric) +
        CASE
            WHEN o.tipo_compra = 'En campo'::text THEN o.campo_encargados + o.campo_otros_costos
            ELSE 0::numeric
        END)::numeric(16,2) AS monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'planilla_compra'::text AND a.origen_id = o.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Planilla de arranca'::text AS etapa,
    o.producto
   FROM ordenes_compra o
     JOIN proveedores p ON p.id = o.planilla_proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND (o.tipo_compra = 'En campo'::text AND (o.producto <> 'Yuca'::text OR o.campo_promedio_caja_kg IS NOT NULL) AND (COALESCE(o.cuadrilla_arranca, 0::numeric) + o.campo_encargados + o.campo_otros_costos) > 0::numeric OR o.tipo_compra = 'En pie'::text AND (o.producto = ANY (ARRAY['Ñampí'::text, 'Cabeza de ñampí'::text])) AND COALESCE(o.cuadrilla_arranca, 0::numeric) > 0::numeric OR o.tipo_compra = 'Cosecha propia'::text AND COALESCE(o.cuadrilla_arranca, 0::numeric) > 0::numeric)
UNION ALL
 SELECT
        CASE
            WHEN c.tipo = 'planilla'::text THEN 'planilla_compra'::text
            ELSE 'flete_compra'::text
        END AS origen,
    c.id AS origen_id,
    (b.codigo || ' · '::text) ||
        CASE
            WHEN c.tipo = 'planilla'::text THEN 'Planilla'::text
            ELSE 'Flete'::text
        END AS codigo,
    (b.fecha_hora AT TIME ZONE 'America/Costa_Rica'::text)::date AS fecha,
    p.nombre AS contraparte,
    'CRC'::text AS moneda,
    c.monto::numeric(16,2) AS monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen =
                CASE
                    WHEN c.tipo = 'planilla'::text THEN 'planilla_compra'::text
                    ELSE 'flete_compra'::text
                END AND a.origen_id = c.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Costo de boleta en pie'::text AS etapa,
    o.producto
   FROM costos_boleta_en_pie c
     JOIN boletas_entrada b ON b.id = c.boleta_id
     JOIN ordenes_compra o ON o.id = b.orden_compra_id
     JOIN proveedores p ON p.id = c.proveedor_id
  WHERE COALESCE(o.estado, ''::text) <> 'Anulada'::text AND c.monto > 0::numeric
UNION ALL
 SELECT 'cuenta_manual_pagar'::text AS origen,
    m.id AS origen_id,
    m.codigo,
    m.fecha,
    m.contraparte,
    m.moneda,
    m.monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'cuenta_manual_pagar'::text AND a.origen_id = m.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Registro manual'::text AS etapa,
    NULL::text AS producto
   FROM cuentas_manuales m
  WHERE m.tipo = 'pagar'::text
union all
select 'compra_insumos'::text,o.id,o.codigo,o.fecha,o.proveedor_nombre,o.moneda::text,
  sum(l.recibido_presentaciones*l.precio_presentacion)::numeric(16,2),
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_insumos' and a.origen_id=o.id),0)::numeric(16,2),
  'Insumos recibidos'::text,null::text as producto
from public.ordenes_insumos o join public.ordenes_insumos_lineas l on l.orden_id=o.id
where l.recibido_presentaciones>0
group by o.id,o.codigo,o.fecha,o.proveedor_nombre,o.moneda;

CREATE OR REPLACE FUNCTION public.registrar_movimiento_bancario(p_cuenta_id uuid, p_fecha date, p_tipo text, p_monto numeric, p_concepto text, p_referencia text, p_aplicaciones jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_moneda text; v_mov uuid; v_app jsonb; v_origen text; v_id uuid; v_amount numeric; v_due numeric; v_used numeric:=0; v_tipo text;
begin
  if p_tipo not in ('ingreso','egreso') or p_monto is null or p_monto<=0 or p_fecha is null or nullif(trim(p_concepto),'') is null then raise exception 'Complete tipo, monto, fecha y concepto'; end if;
  select moneda into v_moneda from public.cuentas_bancarias where id=p_cuenta_id and activo;
  if v_moneda is null then raise exception 'Cuenta bancaria no disponible'; end if;
  if p_aplicaciones is not null and jsonb_typeof(p_aplicaciones)<>'array' then raise exception 'Aplicaciones inválidas'; end if;
  insert into public.movimientos_bancarios(cuenta_id,fecha,tipo,monto,concepto,referencia,registrado_por)
    values(p_cuenta_id,p_fecha,p_tipo,p_monto,trim(p_concepto),nullif(trim(p_referencia),''),(select auth.uid())) returning id into v_mov;
  for v_app in select value from jsonb_array_elements(coalesce(p_aplicaciones,'[]'::jsonb)) loop
    v_origen:=v_app->>'origen';v_id:=(v_app->>'origen_id')::uuid;v_amount:=(v_app->>'monto')::numeric;
    if v_amount is null or v_amount<=0 or v_amount<>round(v_amount,2) then raise exception 'Monto aplicado inválido'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_origen||v_id::text,0));
    if v_origen in ('venta_exportacion','venta_local','saldo_productor','cuenta_manual_cobrar') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxc_operativa where origen=v_origen and origen_id=v_id and etapa<>'Pedido previsto';
      if p_tipo<>'ingreso' then raise exception 'Un cobro debe ser un ingreso'; end if;
    elsif v_origen in ('compra_campo','flete_compra','planilla_compra','cuenta_manual_pagar','compra_insumos') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxp_operativa where origen=v_origen and origen_id=v_id;
      if p_tipo<>'egreso' then raise exception 'Un pago debe ser un egreso'; end if;
    else raise exception 'Origen financiero inválido'; end if;
    if v_tipo is null or v_tipo<>v_moneda or v_amount>v_due then raise exception 'Documento no disponible, moneda distinta o monto superior al saldo'; end if;
    v_used:=v_used+v_amount;
    if v_used>p_monto then raise exception 'Las aplicaciones superan el movimiento bancario'; end if;
    insert into public.aplicaciones_bancarias(movimiento_id,origen,origen_id,monto) values(v_mov,v_origen,v_id,v_amount);
  end loop;
  return v_mov;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.validar_aplicacion_bancaria()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_m public.movimientos_bancarios%rowtype; v_moneda text; v_origen_moneda text; v_due numeric; v_used numeric;
begin
  -- Bloqueos consultivos evitan requerir permiso UPDATE sobre un movimiento ya registrado.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.movimiento_id::text,1));
  select * into v_m from public.movimientos_bancarios where id=new.movimiento_id;
  if not found then raise exception 'Movimiento bancario no disponible'; end if;
  select moneda into v_moneda from public.cuentas_bancarias where id=v_m.cuenta_id;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.origen||new.origen_id::text,0));
  if new.origen in ('venta_exportacion','venta_local','saldo_productor','cuenta_manual_cobrar') then
    if v_m.tipo<>'ingreso' then raise exception 'Una venta solo puede aplicarse a un ingreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxc_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Pedido previsto';
  elsif new.origen in ('compra_campo','flete_compra','planilla_compra','cuenta_manual_pagar','compra_insumos') then
    if v_m.tipo<>'egreso' then raise exception 'Una compra solo puede aplicarse a un egreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxp_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Faltan precios';
  end if;
  if v_origen_moneda is null or v_origen_moneda<>v_moneda or new.monto>v_due then raise exception 'Documento sin saldo suficiente o moneda distinta'; end if;
  select coalesce(sum(monto),0) into v_used from public.aplicaciones_bancarias where movimiento_id=new.movimiento_id;
  if v_used+new.monto>v_m.monto then raise exception 'Aplicaciones superiores al movimiento bancario'; end if;
  return new;
end;
$function$
;
