-- El adelanto pagado sigue como CxC aunque el productor no entregue ninguna boleta.
-- El castigo documenta la pérdida sin crear un ingreso bancario ficticio.
create table public.castigos_adelantos (
 id uuid primary key default gen_random_uuid(),
 orden_compra_id uuid not null references public.ordenes_compra(id),
 fecha date not null,
 monto numeric(16,2) not null check (monto>0),
 motivo text not null check (length(btrim(motivo))>=10),
 referencia text,
 registrado_por uuid not null default auth.uid(),
 creado_en timestamptz not null default now()
);
create index castigos_adelantos_orden_idx on public.castigos_adelantos(orden_compra_id);
alter table public.castigos_adelantos enable row level security;
revoke all on public.castigos_adelantos from anon,authenticated;
grant select,insert on public.castigos_adelantos to authenticated;
create policy castigos_adelantos_lectura on public.castigos_adelantos for select to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create policy castigos_adelantos_administrador on public.castigos_adelantos for insert to authenticated
 with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'));

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
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric) - COALESCE(cx.monto,0) - COALESCE((SELECT sum(c.monto) FROM public.castigos_adelantos c WHERE c.orden_compra_id=o.id),0))::numeric(16,2) AS monto,
    COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'saldo_productor'::text AND a.origen_id = o.id), 0::numeric)::numeric(16,2) AS aplicado,
    'Adelanto por recuperar'::text AS etapa,
    o.fecha AS fecha_salida,
    o.fecha AS fecha_vencimiento,
    0 AS plazo_pago_dias,
    COALESCE((SELECT sum(c.monto) FROM public.castigos_adelantos c WHERE c.orden_compra_id=o.id),0)::numeric(16,2) AS notas_credito
   FROM ordenes_compra o
     LEFT JOIN cxp_operativa cx ON cx.origen = 'compra_campo'::text AND cx.origen_id = o.id
     LEFT JOIN proveedores p ON p.id = o.proveedor_id
  WHERE (COALESCE(( SELECT sum(ad.monto) AS sum
           FROM adelantos_compra ad
          WHERE ad.orden_compra_id = o.id), 0::numeric) + COALESCE(( SELECT sum(a.monto) AS sum
           FROM aplicaciones_bancarias a
          WHERE a.origen = 'compra_campo'::text AND a.origen_id = o.id), 0::numeric)) > COALESCE(cx.monto,0)
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

create function public.registrar_castigo_adelanto(p_orden_id uuid,p_fecha date,p_monto numeric,p_motivo text,p_referencia text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare v_due numeric; v_id uuid;
begin
 if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador') then raise exception 'Solo el administrador puede registrar una pérdida'; end if;
 if p_fecha is null or p_monto is null or p_monto<=0 or p_monto<>round(p_monto,2) or length(btrim(coalesce(p_motivo,'')))<10 then raise exception 'Ingrese fecha, monto válido y motivo de al menos 10 caracteres'; end if;
 perform 1 from public.ordenes_compra where id=p_orden_id for update;
 if not found then raise exception 'Compra no disponible'; end if;
 select monto-aplicado into v_due from public.cxc_operativa where origen='saldo_productor' and origen_id=p_orden_id;
 if v_due is null or p_monto>v_due then raise exception 'El castigo excede el adelanto pendiente de recuperar'; end if;
 insert into public.castigos_adelantos(orden_compra_id,fecha,monto,motivo,referencia,registrado_por)
 values(p_orden_id,p_fecha,p_monto,btrim(p_motivo),nullif(btrim(p_referencia),''),(select auth.uid())) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.registrar_castigo_adelanto(uuid,date,numeric,text,text) from public,anon;
grant execute on function public.registrar_castigo_adelanto(uuid,date,numeric,text,text) to authenticated;

create function public.validar_castigo_adelanto() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_due numeric;
begin
 perform 1 from public.ordenes_compra where id=new.orden_compra_id for update;
 select monto-aplicado into v_due from public.cxc_operativa where origen='saldo_productor' and origen_id=new.orden_compra_id;
 if v_due is null or new.monto>v_due then raise exception 'El castigo excede el adelanto pendiente de recuperar'; end if;
 new.registrado_por:=(select auth.uid());
 return new;
end $$;
create trigger validar_castigo_adelanto before insert on public.castigos_adelantos
 for each row execute function public.validar_castigo_adelanto();
