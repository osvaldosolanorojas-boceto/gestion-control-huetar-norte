begin;
alter table public.proveedores drop constraint proveedores_tipo_check;
alter table public.proveedores add constraint proveedores_tipo_check check (tipo in ('Agricultor','Intermediario','Propio','Transportista','Cuadrilla','Insumos'));
insert into public.proveedores(nombre,tipo,activo)
select n,'Insumos',true from unnest(array['El Colono','Discali','Yumac']) n
where not exists(select 1 from public.proveedores p where lower(trim(p.nombre))=lower(n));
update public.ordenes_insumos o set proveedor_id=p.id
from public.proveedores p where o.proveedor_id is null and p.tipo='Insumos' and
(lower(trim(o.proveedor_nombre))=lower(trim(p.nombre)) or (lower(trim(o.proveedor_nombre))='diskali' and p.nombre='Discali'));
commit;
