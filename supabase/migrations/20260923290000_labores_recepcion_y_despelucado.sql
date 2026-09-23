-- Conserva los nombres anteriores en boletas finalizadas; las nuevas usan los nombres corregidos.
alter table public.boleta_trabajos drop constraint boleta_trabajos_labor_check;
alter table public.boleta_trabajos add constraint boleta_trabajos_labor_check
  check (labor in ('Selección de producto','Pelucado','Recepción de producto','Despelucado','Selección de empaque','Pesaje','Tapado','Flejado'));
