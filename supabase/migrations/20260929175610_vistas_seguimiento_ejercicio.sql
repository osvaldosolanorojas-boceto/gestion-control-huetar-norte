alter table public.seguimiento_ejercicio
  add column historial boolean not null default false;

alter table public.seguimiento_ejercicio
  drop constraint seguimiento_ejercicio_modulo_check;

alter table public.seguimiento_ejercicio
  add constraint seguimiento_ejercicio_modulo_check
  check (modulo in (
    'Órdenes de venta', 'Órdenes de compra', 'Boletas de entrada',
    'Cuentas por pagar', 'Corte semanal', 'Segundas y rechazo'
  ));
