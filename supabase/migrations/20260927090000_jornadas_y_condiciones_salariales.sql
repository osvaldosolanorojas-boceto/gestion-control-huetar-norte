-- Historial de condiciones: un cambio no altera jornadas anteriores.
create table public.condiciones_salariales (
 id uuid primary key default gen_random_uuid(),
 trabajador_id uuid not null references public.trabajadores(id),
 vigente_desde date not null,
 tipo text not null check(tipo in ('Por horas','Fijo semanal','Fijo mensual')),
 monto numeric(16,2) not null check(monto>0),
 tarifa_nocturna numeric(16,2) check(tarifa_nocturna>0),
 tarifa_mixta numeric(16,2) check(tarifa_mixta>0),
 factor_extra numeric(6,3) not null default 1.5 check(factor_extra>=1),
 factor_feriado numeric(6,3) not null default 2 check(factor_feriado>=1),
 factor_extra_feriado numeric(6,3) not null default 3 check(factor_extra_feriado>=1),
 notas text,
 creado_en timestamptz not null default now(),
 registrado_por uuid not null default auth.uid() references public.perfiles(id),
 unique(trabajador_id,vigente_desde)
);
create index condiciones_salariales_historia on public.condiciones_salariales(trabajador_id,vigente_desde desc);
alter table public.condiciones_salariales enable row level security;
revoke all on public.condiciones_salariales from anon,authenticated;
grant select,insert on public.condiciones_salariales to authenticated;
create policy administracion_condiciones_salariales on public.condiciones_salariales for all to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create table public.jornadas_trabajo (
 id uuid primary key default gen_random_uuid(),
 trabajador_id uuid not null references public.trabajadores(id),
 entrada timestamptz not null,
 salida timestamptz not null check(salida>entrada),
 fecha_labor date not null,
 descanso_minutos integer not null default 0 check(descanso_minutos>=0),
 horas_ordinarias numeric(10,2) not null check(horas_ordinarias>=0),
 horas_extra numeric(10,2) not null default 0 check(horas_extra>=0),
 feriado boolean not null default false,
 tipo_jornada text not null check(tipo_jornada in ('Diurna','Mixta','Nocturna')),
 cuadrilla text not null check(cuadrilla in ('Diurna','Nocturna')),
 minutos_nocturnos integer not null default 0,
 tipo_pago text not null check(tipo_pago in ('Por horas','Fijo semanal','Fijo mensual')),
 tarifa_hora numeric(16,2),
 factor_extra numeric(6,3) not null,
 factor_feriado numeric(6,3) not null,
 factor_extra_feriado numeric(6,3) not null,
 costo_bruto numeric(16,2) not null check(costo_bruto>=0),
 condicion_id uuid references public.condiciones_salariales(id),
 origen text not null default 'manual' check(origen in ('manual','reloj')),
 referencia_externa text,
 observaciones text,
 registrado_por uuid not null default auth.uid() references public.perfiles(id),
 creado_en timestamptz not null default now(),
 actualizado_en timestamptz not null default now(),
 unique(trabajador_id,entrada)
);
create index jornadas_trabajo_fecha on public.jornadas_trabajo(fecha_labor,trabajador_id);
alter table public.jornadas_trabajo enable row level security;
revoke all on public.jornadas_trabajo from anon,authenticated;
grant select on public.jornadas_trabajo to authenticated;
create policy administracion_jornadas on public.jornadas_trabajo for select to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

create function public.guardar_jornada_trabajo(p_trabajador_id uuid,p_entrada timestamptz,p_salida timestamptz,p_descanso_minutos integer,p_horas_extra numeric,p_feriado boolean,p_cuadrilla text,p_observaciones text default null,p_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_cond public.condiciones_salariales%rowtype; v_fecha date; v_horas numeric; v_ordinarias numeric; v_rate numeric; v_cost numeric; v_id uuid; v_old public.jornadas_trabajo%rowtype; v_noct integer; v_tipo text;
begin
 if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Acceso denegado'; end if;
 if p_entrada is null or p_salida is null or p_salida<=p_entrada or p_salida>p_entrada+interval '24 hours' or p_descanso_minutos is null or p_descanso_minutos<0 or p_horas_extra is null or p_horas_extra<0 or p_horas_extra<>round(p_horas_extra,2) then raise exception 'Revise entrada, salida, descanso y horas extra'; end if;
 if p_cuadrilla not in ('Diurna','Nocturna') or p_cuadrilla is null then raise exception 'Seleccione cuadrilla diurna o nocturna'; end if;
 if not exists(select 1 from public.trabajadores where id=p_trabajador_id) then raise exception 'Colaborador no encontrado'; end if;
 v_fecha:=(p_entrada at time zone 'America/Costa_Rica')::date;
 select * into v_cond from public.condiciones_salariales where trabajador_id=p_trabajador_id and vigente_desde<=v_fecha order by vigente_desde desc limit 1;
 if not found then raise exception 'Registre primero la tarifa o salario vigente del colaborador'; end if;
 v_horas:=round(extract(epoch from p_salida-p_entrada)/3600-p_descanso_minutos/60.0,2);
 if v_horas<=0 or p_horas_extra>v_horas then raise exception 'El descanso y las extras superan las horas de la jornada'; end if;
 v_ordinarias:=v_horas-p_horas_extra;
 select count(*)::integer into v_noct from generate_series(p_entrada,p_salida-interval '1 minute',interval '1 minute') m
   where (m at time zone 'America/Costa_Rica')::time>=time '19:00' or (m at time zone 'America/Costa_Rica')::time<time '05:00';
 v_tipo:=case when v_noct=0 then 'Diurna' when v_noct>=210 then 'Nocturna' else 'Mixta' end;
 v_rate:=case when v_cond.tipo<>'Por horas' then null when v_tipo='Nocturna' then coalesce(v_cond.tarifa_nocturna,v_cond.monto) when v_tipo='Mixta' then coalesce(v_cond.tarifa_mixta,v_cond.monto) else v_cond.monto end;
 v_cost:=case when v_cond.tipo='Por horas' then round(v_rate*(v_ordinarias*(case when p_feriado then v_cond.factor_feriado else 1 end)+p_horas_extra*(case when p_feriado then v_cond.factor_extra_feriado else v_cond.factor_extra end)),2) else 0 end;
 if p_id is not null then
   select * into v_old from public.jornadas_trabajo where id=p_id for update;
   if not found or v_old.origen<>'manual' then raise exception 'La jornada no se puede editar manualmente'; end if;
   if v_old.trabajador_id<>p_trabajador_id then raise exception 'No cambie el colaborador de la jornada'; end if;
   update public.jornadas_trabajo set entrada=p_entrada,salida=p_salida,fecha_labor=v_fecha,descanso_minutos=p_descanso_minutos,horas_ordinarias=v_ordinarias,horas_extra=p_horas_extra,feriado=coalesce(p_feriado,false),tipo_jornada=v_tipo,cuadrilla=p_cuadrilla,minutos_nocturnos=v_noct,tipo_pago=v_cond.tipo,tarifa_hora=v_rate,factor_extra=v_cond.factor_extra,factor_feriado=v_cond.factor_feriado,factor_extra_feriado=v_cond.factor_extra_feriado,costo_bruto=v_cost,condicion_id=v_cond.id,observaciones=nullif(trim(p_observaciones),''),actualizado_en=now() where id=p_id returning id into v_id;
 else
   insert into public.jornadas_trabajo(trabajador_id,entrada,salida,fecha_labor,descanso_minutos,horas_ordinarias,horas_extra,feriado,tipo_jornada,cuadrilla,minutos_nocturnos,tipo_pago,tarifa_hora,factor_extra,factor_feriado,factor_extra_feriado,costo_bruto,condicion_id,observaciones)
   values (p_trabajador_id,p_entrada,p_salida,v_fecha,p_descanso_minutos,v_ordinarias,p_horas_extra,coalesce(p_feriado,false),v_tipo,p_cuadrilla,v_noct,v_cond.tipo,v_rate,v_cond.factor_extra,v_cond.factor_feriado,v_cond.factor_extra_feriado,v_cost,v_cond.id,nullif(trim(p_observaciones),'')) returning id into v_id;
 end if;
 return v_id;
end;
$$;
revoke all on function public.guardar_jornada_trabajo(uuid,timestamptz,timestamptz,integer,numeric,boolean,text,text,uuid) from public,anon;
grant execute on function public.guardar_jornada_trabajo(uuid,timestamptz,timestamptz,integer,numeric,boolean,text,text,uuid) to authenticated;

-- Nómina fija por período. La cuota obrera resta al neto; la patronal se suma al costo.
create table public.planillas_fijas (
 id uuid primary key default gen_random_uuid(),
 trabajador_id uuid not null references public.trabajadores(id),
 periodo_inicio date not null,
 periodo_fin date not null check(periodo_fin>=periodo_inicio),
 condicion_id uuid not null references public.condiciones_salariales(id),
 puesto text,
 bruto numeric(16,2) not null check(bruto>0),
 rebajo_ccss numeric(16,2) not null default 0 check(rebajo_ccss>=0),
 otros_rebajos numeric(16,2) not null default 0 check(otros_rebajos>=0),
 cuota_patronal_ccss numeric(16,2) not null default 0 check(cuota_patronal_ccss>=0),
 neto numeric(16,2) generated always as (bruto-rebajo_ccss-otros_rebajos) stored,
 costo_total numeric(16,2) generated always as (bruto+cuota_patronal_ccss) stored,
 observaciones text,
 registrado_por uuid not null default auth.uid() references public.perfiles(id),
 creado_en timestamptz not null default now(),
 actualizado_en timestamptz not null default now(),
 unique(trabajador_id,periodo_inicio,periodo_fin),
 constraint neto_fijo_no_negativo check(bruto>=rebajo_ccss+otros_rebajos)
);
create index planillas_fijas_periodo on public.planillas_fijas(periodo_inicio,periodo_fin);
alter table public.planillas_fijas enable row level security;
revoke all on public.planillas_fijas from anon,authenticated;
grant select,insert,update on public.planillas_fijas to authenticated;
create policy administracion_planillas_fijas on public.planillas_fijas for all to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
