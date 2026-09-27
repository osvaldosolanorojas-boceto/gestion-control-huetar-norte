-- Planilla devengada por trabajador y semana. El gasto del corte es el bruto;
-- las deducciones reducen el neto a entregar, no el costo laboral.
create table public.planillas_planta (
  id uuid primary key default gen_random_uuid(),
  semana_inicio date not null check (extract(dow from semana_inicio)=0),
  trabajador_id uuid not null references public.trabajadores(id),
  modalidad text not null check (modalidad in ('Fijo semanal','Por horas')),
  salario_semanal numeric(16,2) not null default 0 check (salario_semanal>=0),
  horas_ordinarias numeric(10,2) not null default 0 check (horas_ordinarias>=0),
  tarifa_hora numeric(16,2) not null default 0 check (tarifa_hora>=0),
  horas_extra numeric(10,2) not null default 0 check (horas_extra>=0),
  tarifa_extra numeric(16,2) not null default 0 check (tarifa_extra>=0),
  adicionales numeric(16,2) not null default 0 check (adicionales>=0),
  deducciones numeric(16,2) not null default 0 check (deducciones>=0),
  bruto numeric(16,2) generated always as
    (round((case when modalidad='Fijo semanal' then salario_semanal else horas_ordinarias*tarifa_hora end)+horas_extra*tarifa_extra+adicionales,2)) stored,
  neto numeric(16,2) generated always as
    (round((case when modalidad='Fijo semanal' then salario_semanal else horas_ordinarias*tarifa_hora end)+horas_extra*tarifa_extra+adicionales-deducciones,2)) stored,
  observaciones text,
  registrado_por uuid not null default auth.uid() references public.perfiles(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  anulado_en timestamptz,
  constraint planilla_modalidad_valida check
    ((modalidad='Fijo semanal' and salario_semanal>0 and horas_ordinarias=0 and tarifa_hora=0)
     or (modalidad='Por horas' and salario_semanal=0 and horas_ordinarias>0 and tarifa_hora>0)),
  constraint planilla_horas_extra_validas check
    ((horas_extra=0 and tarifa_extra=0) or (horas_extra>0 and tarifa_extra>0)),
  constraint planilla_neto_no_negativo check (neto>=0)
);
create unique index planilla_planta_trabajador_semana_activa
  on public.planillas_planta(trabajador_id,semana_inicio) where anulado_en is null;
create index planilla_planta_semana on public.planillas_planta(semana_inicio) where anulado_en is null;
alter table public.planillas_planta enable row level security;
revoke all on public.planillas_planta from anon,authenticated;
grant select,insert,update on public.planillas_planta to authenticated;
create policy gestion_planilla_planta on public.planillas_planta for all to authenticated
  using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
  with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
create function public.proteger_planilla_planta() returns trigger language plpgsql set search_path='' as $$
begin
  if old.anulado_en is not null then raise exception 'No se puede modificar una planilla anulada'; end if;
  if old.registrado_por<>new.registrado_por or old.creado_en<>new.creado_en then
    raise exception 'No cambie el origen del registro';
  end if;
  if new.anulado_en is not null and new.anulado_en<>old.anulado_en and
    row(new.semana_inicio,new.trabajador_id,new.modalidad,new.salario_semanal,new.horas_ordinarias,new.tarifa_hora,new.horas_extra,new.tarifa_extra,new.adicionales,new.deducciones,new.observaciones)
    is distinct from
    row(old.semana_inicio,old.trabajador_id,old.modalidad,old.salario_semanal,old.horas_ordinarias,old.tarifa_hora,old.horas_extra,old.tarifa_extra,old.adicionales,old.deducciones,old.observaciones)
  then raise exception 'No cambie importes al anular'; end if;
  new.actualizado_en:=now();
  return new;
end;
$$;
create trigger proteger_planilla_planta before update on public.planillas_planta
  for each row execute function public.proteger_planilla_planta();

-- Permite preparar el módulo para usuarios de oficina; planta no recibe acceso a salarios.
alter table public.usuarios_preparados drop constraint if exists usuarios_preparados_modulos_check;
alter table public.usuarios_preparados add constraint usuarios_preparados_modulos_check
  check (modulos <@ array[
    'Resumen','Órdenes de compra','Boletas de entrada','Producción y rendimientos',
    'Mapa de carga','Saldo yuca EE. UU.','Segundas y rechazo','Órdenes de venta',
    'Proveedores','Clientes','Colaboradores','Empresas','Inventarios','Finanzas',
    'Efectivo','Bancos','Planilla de planta','Corte semanal','Fincas'
  ]::text[]);
