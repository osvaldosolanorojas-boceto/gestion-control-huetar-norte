-- Datos pactados en campo. El monto a pagar por rendimiento se calcula después
-- de vincular la boleta de entrada y registrar la clasificación de planta.
alter table public.ordenes_compra
  add column if not exists fecha_labor date,
  add column if not exists boleta_campo_referencia text,
  add column if not exists productor_nombre text,
  add column if not exists productor_direccion text,
  add column if not exists productor_telefono text,
  add column if not exists productor_cedula text,
  add column if not exists cantidad_comprada numeric(14,2),
  add column if not exists cantidad_recibida numeric(14,2),
  add column if not exists unidad text,
  add column if not exists precio_campo numeric(14,2),
  add column if not exists precio_en_pie numeric(14,2),
  add column if not exists flete numeric(14,2),
  add column if not exists cuadrilla_arranca numeric(14,2),
  add column if not exists adelanto numeric(14,2),
  add column if not exists chofer text,
  add column if not exists transportista text,
  add column if not exists placa text;
