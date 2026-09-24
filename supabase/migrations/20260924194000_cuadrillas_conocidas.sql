-- Registrar cuadrillas conocidas sin duplicar fichas existentes.
insert into public.proveedores(nombre,tipo)
select v.nombre,'Cuadrilla'
from (values ('Randall Calvo'),('Santos González')) as v(nombre)
where not exists (select 1 from public.proveedores p where lower(p.nombre)=lower(v.nombre));
