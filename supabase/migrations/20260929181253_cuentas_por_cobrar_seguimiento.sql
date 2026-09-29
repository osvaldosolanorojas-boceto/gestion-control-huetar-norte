alter table public.seguimiento_ejercicio
  drop constraint seguimiento_ejercicio_modulo_check;

alter table public.seguimiento_ejercicio
  add constraint seguimiento_ejercicio_modulo_check
  check (modulo in (
    'Órdenes de venta', 'Órdenes de compra', 'Boletas de entrada',
    'Cuentas por pagar', 'Cuentas por cobrar', 'Corte semanal', 'Segundas y rechazo'
  ));
