-- Cuando hay cajas, calcular kilos como cajas por presentación; el peso manual solo aplica sin cajas.
alter table public.boleta_rendimientos add constraint rendimiento_cajas_sin_kg_manual
  check (coalesce(cajas,0)=0 or kg_manual is null) not valid;
