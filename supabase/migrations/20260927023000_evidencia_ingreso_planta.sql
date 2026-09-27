-- Datos opcionales de proceso y evidencia de ingreso por boleta.
alter table public.boletas_entrada drop constraint if exists boletas_entrada_tratamiento_cera_check;
alter table public.boletas_entrada add constraint boletas_entrada_tratamiento_cera_check
  check (tratamiento_cera is null or tratamiento_cera in ('Sin cera','Cera orgánica','Parafina de candela','Cera','Parafina'));

create table public.detalle_ingreso_planta (
  boleta_id uuid primary key references public.boletas_entrada(id) on delete cascade,
  observaciones_muestreo text,
  temperatura_horno_c numeric(6,2) check (temperatura_horno_c between 0 and 500),
  linea_proceso smallint not null check (linea_proceso in (1,2))
);
alter table public.detalle_ingreso_planta enable row level security;
grant select,insert,update on public.detalle_ingreso_planta to authenticated;
create policy consultar_detalle_ingreso on public.detalle_ingreso_planta for select to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));
create policy registrar_detalle_ingreso on public.detalle_ingreso_planta for insert to authenticated
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));
create policy editar_detalle_ingreso on public.detalle_ingreso_planta for update to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('fotos-ingreso-planta','fotos-ingreso-planta',false,8388608,array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do nothing;
create policy fotos_ingreso_consultar on storage.objects for select to authenticated
  using (bucket_id='fotos-ingreso-planta'
    and exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta'))
    and exists(select 1 from public.boletas_entrada b where b.id::text=split_part(name,'/',1)));
create policy fotos_ingreso_subir on storage.objects for insert to authenticated
  with check (bucket_id='fotos-ingreso-planta'
    and exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta'))
    and exists(select 1 from public.boletas_entrada b where b.id::text=split_part(name,'/',1)));
