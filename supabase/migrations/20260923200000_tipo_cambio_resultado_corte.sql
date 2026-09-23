-- Tipo de cambio acordado para comparar ventas en USD con el costo en CRC de un lote en pie.
alter table public.ordenes_compra add column tipo_cambio_resultado numeric(14,4) check (tipo_cambio_resultado > 0);
