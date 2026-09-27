-- Captura de asistencia independiente de las tarifas. Puede iniciarse antes de configurarlas.
create table public.asistencias_planta (
 id uuid primary key default gen_random_uuid(),
 trabajador_id uuid not null references public.trabajadores(id),
 entrada timestamptz not null,
 salida timestamptz check(salida is null or salida>entrada),
 descanso_minutos integer not null default 0 check(descanso_minutos>=0),
 horas_extra numeric(10,2) not null default 0 check(horas_extra>=0),
 feriado_pago_doble boolean not null default false,
 cuadrilla text not null check(cuadrilla in ('Diurna','Nocturna')),
 observaciones text,
 origen text not null default 'manual' check(origen in ('manual','reloj')),
 jornada_id uuid unique references public.jornadas_trabajo(id),
 registrado_por uuid not null default auth.uid() references public.perfiles(id),
 salida_registrada_por uuid references public.perfiles(id),
 creado_en timestamptz not null default now(),
 actualizado_en timestamptz not null default now()
);
create unique index asistencia_un_turno_abierto on public.asistencias_planta(trabajador_id) where salida is null;
create index asistencia_planta_fecha on public.asistencias_planta(entrada desc);
alter table public.asistencias_planta enable row level security;
revoke all on public.asistencias_planta from anon,authenticated;
grant select on public.asistencias_planta to authenticated;
create policy administracion_lee_asistencias on public.asistencias_planta for select to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create view public.colaboradores_asistencia with (security_barrier=true) as
 select w.id,w.nombre,w.puesto,w.activo from public.trabajadores w
 where exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta'));
create view public.registro_asistencia_operacion with (security_barrier=true) as
 select a.id,a.trabajador_id,w.nombre,w.puesto,a.entrada,a.salida,a.descanso_minutos,a.horas_extra,a.feriado_pago_doble,a.cuadrilla,a.observaciones,a.origen,a.jornada_id
 from public.asistencias_planta a join public.trabajadores w on w.id=a.trabajador_id
 where exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta'));
revoke all on public.colaboradores_asistencia,public.registro_asistencia_operacion from public,anon;
grant select on public.colaboradores_asistencia,public.registro_asistencia_operacion to authenticated;

create function public.anotar_entrada_planta(p_trabajador_id uuid,p_entrada timestamptz,p_cuadrilla text,p_observaciones text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
 if p_entrada is null or p_cuadrilla not in ('Diurna','Nocturna') or p_cuadrilla is null then raise exception 'Indique entrada y cuadrilla'; end if;
 if not exists(select 1 from public.trabajadores where id=p_trabajador_id and activo) then raise exception 'Colaborador no disponible'; end if;
 insert into public.asistencias_planta(trabajador_id,entrada,cuadrilla,observaciones)
 values(p_trabajador_id,p_entrada,p_cuadrilla,nullif(trim(p_observaciones),'')) returning id into v_id;
 return v_id;
end;
$$;
revoke all on function public.anotar_entrada_planta(uuid,timestamptz,text,text) from public,anon;
grant execute on function public.anotar_entrada_planta(uuid,timestamptz,text,text) to authenticated;

create function public.anotar_salida_planta(p_asistencia_id uuid,p_salida timestamptz,p_descanso_minutos integer,p_horas_extra numeric,p_feriado_pago_doble boolean,p_observaciones text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_asistencia public.asistencias_planta%rowtype; v_horas numeric;
begin
 if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina','planta')) then raise exception 'Acceso denegado'; end if;
 select * into v_asistencia from public.asistencias_planta where id=p_asistencia_id for update;
 if not found or v_asistencia.salida is not null then raise exception 'Entrada abierta no encontrada'; end if;
 if p_salida is null or p_salida<=v_asistencia.entrada or p_salida>v_asistencia.entrada+interval '24 hours' or p_descanso_minutos is null or p_descanso_minutos<0 or p_horas_extra is null or p_horas_extra<0 or p_horas_extra<>round(p_horas_extra,2) then raise exception 'Revise salida, descanso y extras'; end if;
 v_horas:=round(extract(epoch from p_salida-v_asistencia.entrada)/3600-p_descanso_minutos/60.0,2);
 if v_horas<=0 or p_horas_extra>v_horas then raise exception 'Descanso o extras superan la jornada'; end if;
 update public.asistencias_planta set salida=p_salida,descanso_minutos=p_descanso_minutos,horas_extra=p_horas_extra,feriado_pago_doble=coalesce(p_feriado_pago_doble,false),observaciones=coalesce(nullif(trim(p_observaciones),''),observaciones),salida_registrada_por=(select auth.uid()),actualizado_en=now() where id=p_asistencia_id;
 return p_asistencia_id;
end;
$$;
revoke all on function public.anotar_salida_planta(uuid,timestamptz,integer,numeric,boolean,text) from public,anon;
grant execute on function public.anotar_salida_planta(uuid,timestamptz,integer,numeric,boolean,text) to authenticated;

create function public.procesar_asistencia_planilla(p_asistencia_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_a public.asistencias_planta%rowtype; v_j uuid;
begin
 if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
 select * into v_a from public.asistencias_planta where id=p_asistencia_id for update;
 if not found or v_a.salida is null or v_a.jornada_id is not null then raise exception 'La marcación no está lista para calcular'; end if;
 v_j:=public.guardar_jornada_trabajo(v_a.trabajador_id,v_a.entrada,v_a.salida,v_a.descanso_minutos,v_a.horas_extra,v_a.feriado_pago_doble,v_a.cuadrilla,v_a.observaciones,null);
 update public.asistencias_planta set jornada_id=v_j,actualizado_en=now() where id=p_asistencia_id;
 return v_j;
end;
$$;
revoke all on function public.procesar_asistencia_planilla(uuid) from public,anon;
grant execute on function public.procesar_asistencia_planilla(uuid) to authenticated;
