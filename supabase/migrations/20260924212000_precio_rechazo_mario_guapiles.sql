-- Precio acordado por el productor para las tres compras de yuca de esos días.
-- Esta corrección administrativa no cambia el pago fijo de compras puestas en camión.
-- La protección de edición de boletas cerradas requiere una sesión de oficina;
-- en esta migración administrativa se suspende solo durante esta corrección.
alter table public.ordenes_compra disable trigger proteger_orden_compra;

update public.ordenes_compra
set precio_rechazo = 2500
where productor_nombre = 'Mario Guapiles'
  and tipo_compra = 'Puesto en camión'
  and fecha between date '2026-09-20' and date '2026-09-22'
  and precio_rechazo is null;

alter table public.ordenes_compra enable trigger proteger_orden_compra;
