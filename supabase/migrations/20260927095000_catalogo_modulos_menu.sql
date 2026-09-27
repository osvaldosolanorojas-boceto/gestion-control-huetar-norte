-- Los módulos del borrador de usuarios deben corresponder con las pantallas disponibles.
-- Se conservan etiquetas antiguas para que los borradores existentes sigan editables.
alter table public.usuarios_preparados drop constraint if exists usuarios_preparados_modulos_check;
alter table public.usuarios_preparados add constraint usuarios_preparados_modulos_check check (
  modulos <@ array[
    'Resumen','Órdenes de compra','Órdenes de insumos','Boletas de entrada',
    'Registro de asistencia','Mapa de carga','Saldo de yuca en planta',
    'Segundas y rechazo','Órdenes de venta','Proveedores','Clientes',
    'Colaboradores','Empresas','Inventarios','Finanzas','Efectivo','Bancos',
    'Planilla de planta','Control de costos','Corte semanal','Fincas',
    'Producción y rendimientos','Saldo yuca EE. UU.'
  ]::text[]
);

update public.usuarios_preparados
set modulos=(select coalesce(array_agg(distinct case when m='Saldo yuca EE. UU.' then 'Saldo de yuca en planta' else m end),array[]::text[]) from unnest(modulos) as m where m<>'Producción y rendimientos'),
    actualizado_en=now()
where 'Producción y rendimientos'=any(modulos) or 'Saldo yuca EE. UU.'=any(modulos);
