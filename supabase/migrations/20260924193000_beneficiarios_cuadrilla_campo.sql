-- Las cuadrillas pueden tener una ficha propia como beneficiarias de planilla.
alter table public.proveedores drop constraint proveedores_tipo_check;
alter table public.proveedores add constraint proveedores_tipo_check
  check (tipo in ('Agricultor','Intermediario','Propio','Transportista','Cuadrilla'));
