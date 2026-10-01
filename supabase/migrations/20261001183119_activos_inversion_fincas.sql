create table public.activos_finca (
 id uuid primary key default gen_random_uuid(),
 finca_id uuid not null references public.fincas(id),
 tipo text not null check(tipo in ('Tractor','Implemento agrícola','Insumo disponible')),
 nombre text not null check(length(trim(nombre))>0),
 codigo text,
 marca text,
 modelo text,
 estado text not null default 'Bueno' check(estado in ('Bueno','Regular','En reparación','Fuera de servicio','Retirado')),
 pertenencia text not null default 'Propio' check(pertenencia in ('Propio','Alquilado','De tercero')),
 cantidad numeric(16,3) not null default 1 check(cantidad>=0),
 unidad text not null default 'Unidad',
 costo_unitario_crc numeric(16,2) check(costo_unitario_crc>=0),
 valor_actual_unitario_crc numeric(16,2) check(valor_actual_unitario_crc>=0),
 fecha_adquisicion date,
 fecha_valoracion date not null default current_date,
 caballaje numeric(8,2) check(caballaje>=0),
 llantas text,
 ultimo_mantenimiento date,
 proximo_mantenimiento date,
 frecuencia_mantenimiento text,
 observaciones text,
 creado_en timestamptz not null default now()
);
create index activos_finca_finca_idx on public.activos_finca(finca_id);
alter table public.activos_finca enable row level security;
revoke all on public.activos_finca from anon,authenticated;
grant select,insert,update on public.activos_finca to authenticated;
create policy gestion_oficina on public.activos_finca for all to authenticated
 using(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check(exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
alter table public.lotes_finca add column inversion_en_curso boolean not null default false;
alter table public.costos_finca add column incluir_en_inversion boolean not null default true;
comment on column public.lotes_finca.inversion_en_curso is 'Seleccionar explícitamente cultivos aún en producción; los lotes históricos no se suman por defecto.';
comment on column public.costos_finca.incluir_en_inversion is 'Excluir compras de activos ya valoradas en activos_finca y gastos ya recuperados.';
