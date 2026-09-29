-- Amplía los destinos de seguimiento durante el ejercicio operativo.
alter table public.seguimiento_ejercicio
  drop constraint if exists seguimiento_ejercicio_modulo_check;
alter table public.seguimiento_ejercicio
  add constraint seguimiento_ejercicio_modulo_check
  check (modulo = any (array[
    'Órdenes de venta','Órdenes de compra','Boletas de entrada',
    'Cuentas por pagar','Cuentas por cobrar','Corte semanal',
    'Segundas y rechazo','Planilla de planta','Control de costos',
    'Efectivo','Inventario de insumos','Órdenes de insumos',
    'Inventario de cartones'
  ]));
