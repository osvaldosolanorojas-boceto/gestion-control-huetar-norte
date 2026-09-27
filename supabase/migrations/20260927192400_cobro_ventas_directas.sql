create or replace view public.cxc_operativa as
SELECT 'venta_exportacion'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    c.nombre AS contraparte,
    o.moneda::text AS moneda,
    GREATEST(0::numeric,
        CASE
            WHEN o.finalizada_en IS NULL THEN COALESCE(( SELECT sum(l.total) AS sum
               FROM ordenes_venta_lineas l
              WHERE l.orden_venta_id = o.id), 0::numeric)
            ELSE COALESCE(o.monto_cxc, 0::numeric)
        END - COALESCE(( SELECT sum(n.monto) AS sum
           FROM notas_credito_ventas n
          WHERE n.orden_venta_id = o.id), 0::numeric))::numeric(16,2) AS monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'venta_exportacion'::text AND a.origen_id = o.id), 0::numeric)::numeric(16,2) AS aplicado,
        CASE
            WHEN o.finalizada_en IS NULL THEN 'Pedido previsto'::text
            ELSE 'Pedido finalizado'::text
        END AS etapa,
    o.fecha_salida,
    COALESCE(o.fecha_salida, o.fecha) + o.plazo_pago_dias AS fecha_vencimiento,
    o.plazo_pago_dias,
    COALESCE(( SELECT sum(n.monto) AS sum
           FROM notas_credito_ventas n
          WHERE n.orden_venta_id = o.id), 0::numeric)::numeric(16,2) AS notas_credito
   FROM ordenes_venta o
     LEFT JOIN clientes c ON c.id = o.cliente_id
  WHERE o.estado IS DISTINCT FROM 'Anulada'::text
UNION ALL
 SELECT 'venta_local'::text AS origen,
    v.id AS origen_id,
    v.codigo,
    v.fecha,
    v.comprador AS contraparte,
    v.moneda,
    (COALESCE(( SELECT sum(s.subtotal) AS sum
           FROM ventas_segundas s
          WHERE s.venta_local_id = v.id), 0::numeric) + COALESCE(( SELECT sum(e.subtotal) AS sum
           FROM ventas_externas_boleta e
          WHERE e.venta_local_id = v.id), 0::numeric))::numeric(16,2) AS monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'venta_local'::text AND a.origen_id = v.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Venta registrada'::text AS etapa,
    v.fecha AS fecha_salida,
    v.fecha AS fecha_vencimiento,
    0 AS plazo_pago_dias,
    0::numeric(16,2) AS notas_credito
   FROM ventas_locales v
UNION ALL
 SELECT 'saldo_productor'::text AS origen,
    o.id AS origen_id,
    o.codigo,
    o.fecha,
    COALESCE(o.productor_nombre, p.nombre, 'Productor'::text) AS contraparte,
    'CRC'::text AS moneda,
    GREATEST(0::numeric, COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric) + COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) - cx.monto)::numeric(16,2) AS monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'saldo_productor'::text AND a.origen_id = o.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Adelanto superior a compra'::text AS etapa,
    o.fecha AS fecha_salida,
    o.fecha AS fecha_vencimiento,
    0 AS plazo_pago_dias,
    0::numeric(16,2) AS notas_credito
   FROM ordenes_compra o
     JOIN cxp_operativa cx ON cx.origen = 'compra_campo'::text AND cx.origen_id = o.id
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE (COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric) + COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric)) > cx.monto
UNION ALL
 SELECT
        CASE
            WHEN m.tipo = 'cobrar'::text THEN 'cuenta_manual_cobrar'::text
            ELSE 'cuenta_manual_pagar'::text
        END AS origen,
    m.id AS origen_id,
    m.codigo,
    m.fecha,
    m.contraparte,
    m.moneda,
    m.monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen =
                CASE
                    WHEN m.tipo = 'cobrar'::text THEN 'cuenta_manual_cobrar'::text
                    ELSE 'cuenta_manual_pagar'::text
                END AND a.origen_id = m.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Registro manual'::text AS etapa,
    m.fecha AS fecha_salida,
    m.fecha_vencimiento,
    0 AS plazo_pago_dias,
    0::numeric(16,2) AS notas_credito
   FROM cuentas_manuales m
  WHERE m.tipo = 'cobrar'::text
UNION ALL
 SELECT 'venta_rechazo_campo'::text AS origen,
    v.id AS origen_id,
    'RC-'::text || "left"(v.id::text, 8) AS codigo,
    v.fecha,
    v.comprador AS contraparte,
    v.moneda,
    v.monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'venta_rechazo_campo'::text AND a.origen_id = v.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Rechazo vendido desde campo'::text AS etapa,
    v.fecha AS fecha_salida,
    v.fecha AS fecha_vencimiento,
    0 AS plazo_pago_dias,
    0::numeric(16,2) AS notas_credito
   FROM ventas_rechazo_campo v
union all
select 'venta_directa_en_pie'::text as origen, v.id as origen_id,
 ('VD-'||left(v.id::text,8))::text as codigo,v.fecha,v.comprador as contraparte,
 v.moneda,(v.cantidad*v.precio_unitario)::numeric(16,2) as monto,
 coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='venta_directa_en_pie' and a.origen_id=v.id),0)::numeric(16,2) as aplicado,
 'Venta directa desde campo'::text as etapa,v.fecha as fecha_salida,v.fecha as fecha_vencimiento,
 0 as plazo_pago_dias,0::numeric(16,2) as notas_credito
from public.ventas_externas_en_pie v;
alter table public.aplicaciones_bancarias drop constraint aplicaciones_bancarias_origen_check;
alter table public.aplicaciones_bancarias add constraint aplicaciones_bancarias_origen_check
 check (origen in ('venta_exportacion','venta_local','venta_rechazo_campo','venta_directa_en_pie','compra_campo','flete_compra','planilla_compra','saldo_productor','cuenta_manual_cobrar','cuenta_manual_pagar','compra_insumos','compra_cartones','planilla_jornada','planilla_fija'));
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
    if v_origen in ('venta_exportacion','venta_local','venta_rechazo_campo','venta_directa_en_pie','saldo_productor','cuenta_manual_cobrar') then
      select moneda,monto-aplicado into v_tipo,v_due from public.cxc_operativa where origen=v_origen and origen_id=v_id and etapa<>'Pedido previsto';
      if p_tipo<>'ingreso' then raise exception 'Un cobro debe ser un ingreso'; end if;
    elsif v_origen in ('compra_campo','flete_compra','planilla_compra','cuenta_manual_pagar','compra_insumos','compra_cartones','planilla_jornada','planilla_fija') then
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
  if new.origen in ('venta_exportacion','venta_local','venta_rechazo_campo','venta_directa_en_pie','saldo_productor','cuenta_manual_cobrar') then
    if v_m.tipo<>'ingreso' then raise exception 'Una venta solo puede aplicarse a un ingreso'; end if;
    select moneda,monto-aplicado into v_origen_moneda,v_due from public.cxc_operativa where origen=new.origen and origen_id=new.origen_id and etapa<>'Pedido previsto';
  elsif new.origen in ('compra_campo','flete_compra','planilla_compra','cuenta_manual_pagar','compra_insumos','compra_cartones','planilla_jornada','planilla_fija') then
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
