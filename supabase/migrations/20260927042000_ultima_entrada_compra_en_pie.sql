-- La última llegada se decide al preparar la entrada, antes de su boleta de planta.
alter table public.ordenes_compra
  add column ultima_entrada_en_pie integer check (ultima_entrada_en_pie is null or ultima_entrada_en_pie > 0);
