create table public.propiedades_finca (
 id uuid primary key default gen_random_uuid(),
 finca_id uuid not null references public.fincas(id),
 nombre text not null check(length(trim(nombre))>0),
 tipo text not null default 'Finca' check(tipo in ('Finca','Lote pequeño')),
 modalidad text not null default 'Pendiente' check(modalidad in ('Pendiente','Alquilada','Propia','Porcentaje sobre ventas brutas')),
 propietario text,
 alquiler_monto numeric(16,2) check(alquiler_monto>=0),
 moneda text not null default 'CRC' check(moneda in ('CRC','USD')),
 frecuencia_pago text,
 forma_pago text,
 contrato_inicio date,
 contrato_vencimiento date,
 porcentaje_propietario numeric(5,2) check(porcentaje_propietario between 0 and 100),
 tierra_mecanizada boolean not null default false,
 obligaciones text,
 observaciones text,
 creado_en timestamptz not null default now(),
 unique(finca_id,nombre), unique(id,finca_id),
 check(contrato_inicio is null or contrato_vencimiento is null or contrato_vencimiento>=contrato_inicio),
 check(modalidad<>'Porcentaje sobre ventas brutas' or porcentaje_propietario is not null)
);
create index propiedades_finca_finca_idx on public.propiedades_finca(finca_id);
alter table public.propiedades_finca enable row level security;
revoke all on public.propiedades_finca from anon,authenticated;
grant select,insert,update on public.propiedades_finca to authenticated;
create policy gestion_oficina on public.propiedades_finca for all to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
alter table public.lotes_finca add column propiedad_id uuid;
alter table public.lotes_finca add constraint lotes_propiedad_misma_finca
 foreign key(propiedad_id,finca_id) references public.propiedades_finca(id,finca_id);
create index lotes_finca_propiedad_idx on public.lotes_finca(propiedad_id);

insert into public.propiedades_finca(finca_id,nombre,modalidad)
 select id,nombre,case when nombre='Copevega' then 'Propia' else 'Alquilada' end
 from public.fincas where nombre in ('La Unión','El Concho','Copevega');
insert into public.propiedades_finca(finca_id,nombre,tipo,modalidad,propietario,porcentaje_propietario,tierra_mecanizada,observaciones)
 select f.id,v.nombre,v.tipo,v.modalidad,v.propietario,v.porcentaje,v.mecanizada,v.notas
 from public.fincas f cross join (values
 ('César Rodríguez','Finca','Porcentaje sobre ventas brutas','César Rodríguez',30::numeric,false,'Agrosolano aporta los gastos. El propietario recibe 30% de las ventas brutas de la producción agrícola.'),
 ('Diego Ulate','Finca','Alquilada','Diego Ulate',null,false,null),
 ('Víctor Carvajal','Finca','Porcentaje sobre ventas brutas','Víctor Carvajal',38::numeric,true,'Nombre del propietario pendiente de precisar. Aporta la tierra mecanizada. Porcentaje pactado: 38%.'),
 ('Exportaciones Norteñas','Finca','Pendiente',null,null,false,null),
 ('Timotea','Finca','Alquilada','Timotea',null,false,null),
 ('Tingo','Lote pequeño','Alquilada',null,null,false,null),
 ('Alonso','Lote pequeño','Alquilada',null,null,false,null),
 ('La Cruz','Lote pequeño','Alquilada',null,null,false,null),
 ('Pelo Yegua','Lote pequeño','Alquilada',null,null,false,null),
 ('Cementerio Tres Esquinas','Lote pequeño','Alquilada',null,null,false,null)
 ) as v(nombre,tipo,modalidad,propietario,porcentaje,mecanizada,notas) where f.nombre='La Fortuna';
update public.lotes_finca l set propiedad_id=p.id from public.propiedades_finca p
 where p.finca_id=l.finca_id and (l.nombre=p.nombre or (p.nombre='Diego Ulate' and l.nombre in ('Diulate','Diego','Diego Ullate')));
update public.lotes_finca l set propiedad_id=p.id from public.propiedades_finca p join public.fincas f on f.id=p.finca_id
 where l.finca_id=p.finca_id and f.nombre in ('La Unión','El Concho','Copevega') and l.propiedad_id is null;
