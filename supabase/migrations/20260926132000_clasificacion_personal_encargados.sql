-- Una ficha por persona; la responsabilidad de planta es independiente del grupo laboral.
alter table public.trabajadores
  add column if not exists categoria text not null default 'Operativo',
  add column if not exists encargado_planta boolean not null default false,
  add column if not exists modalidad_pago text not null default 'Por horas';
alter table public.trabajadores
  add constraint trabajadores_categoria_check check (categoria in ('Operativo','Administrativo')),
  add constraint trabajadores_modalidad_pago_check check (modalidad_pago in ('Por horas','Salario fijo'));

update public.trabajadores set encargado_planta=true
where nombre in ('Andrés Bolaños Araya','Javier Aguilar Beltran') and activo;
update public.trabajadores set categoria='Administrativo', modalidad_pago='Salario fijo', puesto='Socio'
where nombre='Rogelio Solano Delgado';
insert into public.trabajadores(nombre,genero,categoria,modalidad_pago,puesto,observaciones)
select v.nombre,v.genero,'Administrativo','Salario fijo',v.puesto,v.observaciones
from (values
  ('Janet Solano','Mujeres','Gerente general','Completar apellidos y datos de la ficha.'),
  ('Osvaldo Solano Rojas','Hombres','Dirección y compras',null)
) as v(nombre,genero,puesto,observaciones)
where not exists (select 1 from public.trabajadores t where lower(t.nombre)=lower(v.nombre));
update public.trabajadores set activo=false, encargado_planta=false
where nombre='Emilio Solano Murillo';

-- La planta recibe nombres y categorías, sin datos personales ni salarios.
drop function if exists public.colaboradores_para_planta();
create function public.colaboradores_para_planta()
returns table(id uuid,nombre text,genero text,categoria text,encargado_planta boolean)
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then
    raise exception 'Acceso denegado';
  end if;
  return query select t.id,t.nombre,t.genero,t.categoria,t.encargado_planta
    from public.trabajadores t where t.activo and (t.categoria='Operativo' or t.encargado_planta)
    order by t.genero,t.nombre;
end;
$$;
revoke all on function public.colaboradores_para_planta() from public,anon;
grant execute on function public.colaboradores_para_planta() to authenticated;
